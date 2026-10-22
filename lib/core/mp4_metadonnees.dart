import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Écrit des MÉTADONNÉES dans une vidéo MP4 / MOV / 3GP, SANS LA RÉENCODER
/// (22/10/2026, documents sensibles).
///
/// La copie d'un document sensible qui sort de l'application (téléchargée,
/// partagée, transférée) porte de quoi remonter à qui l'a fait sortir. Pour
/// une vidéo, l'image n'est pas touchée (réencoder serait lent et dégraderait
/// la qualité) : seules les métadonnées changent, comme le fait un logiciel
/// de montage quand on remplit « Commentaire » ou « Artiste ».
///
/// COMMENT. Un MP4 est une suite de « boîtes ». Les métadonnées vivent dans
/// `moov/udta/meta/ilst` (format iTunes, lu par ffprobe, VLC, l'explorateur
/// Windows…). On reconstruit la seule boîte `moov` (quelques Ko à quelques
/// Mo) et on recopie le reste octet pour octet.
///
/// ⚠️ LE PIÈGE : si `moov` est AVANT les données (`mdat`), l'agrandir décale
/// tout ce qui suit, et les tables `stco` / `co64` (position de chaque morceau
/// de son et d'image) pointeraient à côté : vidéo illisible. Ces positions
/// sont donc corrigées du même décalage. Une vidéo fragmentée (`moof`) placée
/// après `moov` porte d'autres positions absolues : on refuse plutôt que de
/// la casser ([FormatException]), et l'appelant garde la copie non signée.
class Mp4Metadonnees {
  Mp4Metadonnees._();

  /// L'espace de noms des éléments libres (`----`) écrits par Alanya.
  static const espace = 'com.alanya237.work';

  /// Au-delà, `moov` n'est pas une table d'index plausible : on refuse.
  static const _moovMax = 64 * 1024 * 1024;

  static const _extensions = {'mp4', 'm4v', 'mov', '3gp', '3g2'};
  static const _types = {
    'video/mp4',
    'video/quicktime',
    'video/3gpp',
    'video/3gpp2',
    'video/x-m4v',
  };

  /// Ce fichier est-il un conteneur qu'on sait annoter ?
  static bool prisEnCharge(String mime, String nom) {
    if (_types.contains(mime.toLowerCase())) return true;
    final point = nom.lastIndexOf('.');
    if (point < 0) return false;
    return _extensions.contains(nom.substring(point + 1).toLowerCase());
  }

  /// Copie [entree] dans [sortie] en y écrivant [elements].
  ///
  /// [elements] : les éléments standard (`©cmt`, `©ART`, `©too`, `©day`,
  /// `desc`) et, sous [espace], des éléments libres (`trace`, `alanya_id`…).
  /// Lève [FormatException] si le fichier n'est pas un MP4 qu'on sait
  /// modifier sans risque.
  static Future<void> ecrire(
    File entree,
    File sortie,
    ElementsMp4 elements,
  ) async {
    final source = await entree.open();
    try {
      final longueur = await source.length();
      final boites = await _boitesDuHaut(source, longueur);
      final moovs = boites.where((b) => b.type == 'moov').toList();
      if (moovs.length != 1) {
        throw const FormatException('Pas de boîte moov unique');
      }
      final moov = moovs.single;
      if (moov.taille > _moovMax) {
        throw const FormatException('Boîte moov démesurée');
      }
      await source.setPosition(moov.debut);
      final ancien = await source.read(moov.taille);
      final nouveau = remplacerMoov(Uint8List.fromList(ancien), elements);
      final decalage = nouveau.length - ancien.length;
      final finMoov = moov.debut + moov.taille;
      if (decalage != 0 &&
          boites.any((b) => b.type == 'moof' && b.debut >= finMoov)) {
        throw const FormatException('Vidéo fragmentée : non prise en charge');
      }
      _deplacerPositions(nouveau, finMoov, decalage);

      final cible = await sortie.open(mode: FileMode.write);
      try {
        for (final b in boites) {
          if (identical(b, moov)) {
            await cible.writeFrom(nouveau);
          } else {
            await _recopier(source, cible, b.debut, b.taille);
          }
        }
      } finally {
        await cible.close();
      }
    } finally {
      await source.close();
    }
  }

  /// La boîte `moov` [moov] (en-tête compris), avec les métadonnées
  /// [elements] dans `udta/meta/ilst`. Les positions `stco` / `co64` ne sont
  /// PAS corrigées ici (voir [ecrire]).
  static Uint8List remplacerMoov(Uint8List moov, ElementsMp4 elements) {
    final enTete = _entete(moov, 0);
    if (enTete.type != 'moov')
      throw const FormatException('Pas une boîte moov');
    final enfants = _enfants(moov, enTete.charge, moov.length);
    final morceaux = <List<int>>[];
    var udtaVue = false;
    for (final e in enfants) {
      if (e.type == 'udta' && !udtaVue) {
        udtaVue = true;
        morceaux.add(_remplacerUdta(moov.sublist(e.debut, e.fin), elements));
      } else {
        morceaux.add(moov.sublist(e.debut, e.fin));
      }
    }
    if (!udtaVue) morceaux.add(_boite('udta', _meta(elements, const [])));
    return _boite('moov', morceaux.expand((m) => m).toList());
  }

  // ── udta / meta / ilst ────────────────────────────────────────────────

  static Uint8List _remplacerUdta(Uint8List udta, ElementsMp4 elements) {
    final enTete = _entete(udta, 0);
    final enfants = _enfants(udta, enTete.charge, udta.length);
    final morceaux = <List<int>>[];
    var metaVue = false;
    for (final e in enfants) {
      if (e.type == 'meta' && !metaVue) {
        metaVue = true;
        morceaux.add(_remplacerMeta(udta.sublist(e.debut, e.fin), elements));
      } else {
        morceaux.add(udta.sublist(e.debut, e.fin));
      }
    }
    if (!metaVue) morceaux.add(_meta(elements, const []));
    return _boite('udta', morceaux.expand((m) => m).toList());
  }

  /// Une `meta` iTunes (`hdlr` = `mdir`) garde ses autres éléments ; une
  /// `meta` d'une autre sorte est remplacée (rare : un `udta/meta` porte
  /// presque toujours `mdir`).
  static Uint8List _remplacerMeta(Uint8List meta, ElementsMp4 elements) {
    final enTete = _entete(meta, 0);
    // `meta` est une « full box » en MP4 (4 octets version + drapeaux), pas
    // toujours en QuickTime : une boîte enfant commencerait alors tout de suite.
    final pleine =
        enTete.charge + 8 <= meta.length &&
        !_estTypeDeBoite(meta, enTete.charge + 4);
    final debutEnfants = enTete.charge + (pleine ? 4 : 0);
    final enfants = _enfants(meta, debutEnfants, meta.length);
    final hdlr = enfants.where((e) => e.type == 'hdlr').firstOrNull;
    final mdir =
        hdlr != null &&
        hdlr.charge + 12 <= hdlr.fin &&
        latin1.decode(meta.sublist(hdlr.charge + 8, hdlr.charge + 12)) ==
            'mdir';
    if (!mdir) return _meta(elements, const []);

    final ilst = enfants.where((e) => e.type == 'ilst').firstOrNull;
    final gardes = <List<int>>[];
    if (ilst != null) {
      for (final item in _enfants(meta, ilst.charge, ilst.fin)) {
        final octets = meta.sublist(item.debut, item.fin);
        if (_estAMoi(item, meta, elements)) continue;
        gardes.add(octets);
      }
    }
    final autres = <List<int>>[
      for (final e in enfants)
        if (e.type != 'ilst') meta.sublist(e.debut, e.fin),
    ];
    final ilstNeuve = _boite('ilst', [
      ...gardes.expand((g) => g),
      ..._items(elements),
    ]);
    return _boite('meta', [
      if (pleine) ...meta.sublist(enTete.charge, enTete.charge + 4),
      ...autres.expand((a) => a),
      ...ilstNeuve,
    ]);
  }

  /// Un élément que cette écriture remplace : même clé standard, ou élément
  /// libre de [espace] (une copie re-signée ne cumule pas deux traces).
  static bool _estAMoi(_Boite item, Uint8List d, ElementsMp4 elements) {
    if (elements.standard.containsKey(item.type)) return true;
    if (item.type != '----') return false;
    for (final e in _enfants(d, item.charge, item.fin)) {
      if (e.type == 'mean' && e.charge + 4 <= e.fin) {
        return utf8.decode(
              d.sublist(e.charge + 4, e.fin),
              allowMalformed: true,
            ) ==
            espace;
      }
    }
    return false;
  }

  static Uint8List _meta(ElementsMp4 elements, List<int> gardes) {
    // hdlr iTunes : version/drapeaux, pre_defined, « mdir », « appl », 0, 0, nom vide.
    final hdlr = _boite('hdlr', [
      0, 0, 0, 0, //
      0, 0, 0, 0,
      ...latin1.encode('mdir'),
      ...latin1.encode('appl'),
      0, 0, 0, 0, //
      0, 0, 0, 0,
      0,
    ]);
    return _boite('meta', [
      0, 0, 0, 0, // version + drapeaux
      ...hdlr,
      ..._boite('ilst', [...gardes, ..._items(elements)]),
    ]);
  }

  static List<int> _items(ElementsMp4 elements) => [
    for (final e in elements.standard.entries)
      ..._boite(e.key, _donnee(e.value)),
    for (final e in elements.libres.entries)
      ..._boite('----', [
        ..._boite('mean', [0, 0, 0, 0, ...utf8.encode(espace)]),
        ..._boite('name', [0, 0, 0, 0, ...utf8.encode(e.key)]),
        ..._donnee(e.value),
      ]),
  ];

  /// Une boîte `data` de texte UTF-8 (type 1, langue 0).
  static Uint8List _donnee(String texte) =>
      _boite('data', [0, 0, 0, 1, 0, 0, 0, 0, ...utf8.encode(texte)]);

  // ── positions des morceaux (stco / co64) ───────────────────────────────

  static const _conteneurs = {'trak', 'mdia', 'minf', 'stbl', 'edts'};

  /// Ajoute [decalage] à toute position `stco` / `co64` située à partir de
  /// [seuil] (fin de l'ancienne `moov`) : ce qui était après elle a bougé.
  static void _deplacerPositions(Uint8List moov, int seuil, int decalage) {
    if (decalage == 0) return;
    final vue = ByteData.sublistView(moov);
    void parcourir(int debut, int fin) {
      for (final e in _enfants(moov, debut, fin)) {
        if (_conteneurs.contains(e.type)) {
          parcourir(e.charge, e.fin);
        } else if (e.type == 'stco') {
          final n = vue.getUint32(e.charge + 4);
          for (var i = 0; i < n; i++) {
            final p = e.charge + 8 + i * 4;
            final v = vue.getUint32(p);
            if (v < seuil) continue;
            final neuf = v + decalage;
            if (neuf > 0xFFFFFFFF) {
              throw const FormatException('Position hors de stco');
            }
            vue.setUint32(p, neuf);
          }
        } else if (e.type == 'co64') {
          final n = vue.getUint32(e.charge + 4);
          for (var i = 0; i < n; i++) {
            final p = e.charge + 8 + i * 8;
            final v = vue.getUint64(p);
            if (v >= seuil) vue.setUint64(p, v + decalage);
          }
        }
      }
    }

    final enTete = _entete(moov, 0);
    parcourir(enTete.charge, moov.length);
  }

  // ── lecture et écriture des boîtes ────────────────────────────────────

  static Future<List<_Boite>> _boitesDuHaut(
    RandomAccessFile f,
    int longueur,
  ) async {
    final boites = <_Boite>[];
    var pos = 0;
    while (pos < longueur) {
      if (longueur - pos < 8) throw const FormatException('En-tête tronqué');
      await f.setPosition(pos);
      final h = ByteData.sublistView(Uint8List.fromList(await f.read(16)));
      var taille = h.getUint32(0);
      final type = latin1.decode([
        h.getUint8(4),
        h.getUint8(5),
        h.getUint8(6),
        h.getUint8(7),
      ]);
      var entete = 8;
      if (taille == 1) {
        if (h.lengthInBytes < 16)
          throw const FormatException('Taille tronquée');
        taille = h.getUint64(8);
        entete = 16;
      } else if (taille == 0) {
        taille = longueur - pos;
      }
      if (taille < entete || pos + taille > longueur) {
        throw FormatException('Boîte $type mal formée');
      }
      boites.add(_Boite(type, pos, pos + entete, pos + taille));
      pos += taille;
    }
    if (boites.isEmpty ||
        !_estTypeDeBoite(latin1.encode(boites.first.type), 0)) {
      throw const FormatException('Pas un fichier MP4');
    }
    return boites;
  }

  static Future<void> _recopier(
    RandomAccessFile de,
    RandomAccessFile vers,
    int debut,
    int taille,
  ) async {
    const bloc = 1 << 20;
    await de.setPosition(debut);
    var reste = taille;
    while (reste > 0) {
      final lu = await de.read(reste < bloc ? reste : bloc);
      if (lu.isEmpty) throw const FormatException('Fichier tronqué');
      await vers.writeFrom(lu);
      reste -= lu.length;
    }
  }

  static _Boite _entete(Uint8List d, int debut) {
    if (debut + 8 > d.length) throw const FormatException('En-tête tronqué');
    final vue = ByteData.sublistView(d);
    var taille = vue.getUint32(debut);
    final type = latin1.decode(d.sublist(debut + 4, debut + 8));
    var entete = 8;
    if (taille == 1) {
      if (debut + 16 > d.length) throw const FormatException('Taille tronquée');
      taille = vue.getUint64(debut + 8);
      entete = 16;
    } else if (taille == 0) {
      taille = d.length - debut;
    }
    if (taille < entete || debut + taille > d.length) {
      throw FormatException('Boîte $type mal formée');
    }
    return _Boite(type, debut, debut + entete, debut + taille);
  }

  static List<_Boite> _enfants(Uint8List d, int debut, int fin) {
    final enfants = <_Boite>[];
    var pos = debut;
    while (pos + 8 <= fin) {
      final b = _entete(d, pos);
      if (b.fin > fin) throw FormatException('Boîte ${b.type} déborde');
      enfants.add(b);
      pos = b.fin;
    }
    return enfants;
  }

  /// Quatre octets imprimables (ou ©) : un type de boîte plausible.
  static bool _estTypeDeBoite(List<int> d, int debut) {
    if (debut + 4 > d.length) return false;
    for (var i = debut; i < debut + 4; i++) {
      final c = d[i];
      if (c != 0xA9 && (c < 0x20 || c > 0x7E)) return false;
    }
    return true;
  }

  static Uint8List _boite(String type, List<int> charge) {
    final taille = 8 + charge.length;
    final b = BytesBuilder(copy: false)
      ..add((ByteData(4)..setUint32(0, taille)).buffer.asUint8List())
      ..add(latin1.encode(type))
      ..add(charge);
    return b.toBytes();
  }
}

/// Les métadonnées à écrire : éléments standard par clé à quatre caractères
/// (`©cmt`, `©ART`…), et éléments libres sous [Mp4Metadonnees.espace].
class ElementsMp4 {
  const ElementsMp4({required this.standard, required this.libres});

  final Map<String, String> standard;
  final Map<String, String> libres;
}

class _Boite {
  _Boite(this.type, this.debut, this.charge, this.fin);

  final String type;
  final int debut;

  /// Début du contenu (après l'en-tête).
  final int charge;
  final int fin;

  int get taille => fin - debut;
}
