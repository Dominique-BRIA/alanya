import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as fc;
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../features/contacts/contacts_repository.dart';
import '../models/contact.dart' as modele;
import '../models/message_payload.dart';
import '../theme/alanya_theme.dart';
import 'avatar_circle.dart';

/// Ce que l'écran de discussion doit envoyer après la sélection.
///
/// [photoBytes] n'est renseigné que pour le partage d'UN SEUL contact du
/// répertoire qui a une photo : elle part comme média du message. On ne
/// téléverse pas dix photos pour dix contacts — la carte n'en montrerait
/// aucune, et ce serait dix requêtes pour rien.
class ContactShareResult {
  final List<SharedContact> contacts;
  final Uint8List? photoBytes;
  final String? photoMimeType;

  const ContactShareResult({
    required this.contacts,
    this.photoBytes,
    this.photoMimeType,
  });
}

/// Sélecteur de contact à partager, façon WhatsApp : deux origines, recherche,
/// multi-sélection, et un compteur sur le bouton d'envoi.
///
/// Les deux origines ne sont pas un raffinement : un contact **Alanya** porte un
/// Alanya ID, donc le destinataire pourra lui écrire ou l'appeler dans
/// l'application ; un contact du **répertoire** ne porte qu'un numéro, et la
/// seule action utile est de l'enregistrer. Fusionner les deux listes
/// masquerait cette différence au moment précis où elle se décide.
class ContactShareSheet extends StatefulWidget {
  const ContactShareSheet({super.key});

  static Future<ContactShareResult?> show(BuildContext context) {
    return showModalBottomSheet<ContactShareResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ContactShareSheet(),
    );
  }

  @override
  State<ContactShareSheet> createState() => _ContactShareSheetState();
}

/// Une entrée de la liste, quelle que soit son origine.
class _Entree {
  final String cle;
  final String nom;
  final String? numero;
  final String? alanyaId;
  final String? avatarUrl;

  /// Identifiant du contact du répertoire, pour aller chercher sa photo
  /// seulement s'il est retenu (la charger pour tout le carnet serait lent).
  final String? idTelephone;

  const _Entree({
    required this.cle,
    required this.nom,
    this.numero,
    this.alanyaId,
    this.avatarUrl,
    this.idTelephone,
  });

  SharedContact versCharge() => SharedContact(
        name: nom,
        phones: numero != null ? [numero!] : const [],
        alanyaId: alanyaId,
        avatarUrl: avatarUrl,
      );
}

class _ContactShareSheetState extends State<ContactShareSheet> {
  bool _origineAlanya = true;

  List<_Entree>? _alanya;
  List<_Entree>? _telephone;
  bool _chargement = true;
  bool _permissionRefusee = false;
  String? _erreur;

  final Set<String> _retenus = {};
  final Map<String, _Entree> _parCle = {};
  String _recherche = '';
  bool _envoiEnCours = false;

  /// Plafond aligné sur celui du serveur (10 par charge) : bloquer la sélection
  /// vaut mieux que laisser envoyer puis échouer à l'arrivée.
  static const int _maxContacts = 10;

  @override
  void initState() {
    super.initState();
    _chargeAlanya();
  }

  Future<void> _chargeAlanya() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final contacts = await context.read<ContactsRepository>().list();
      if (!mounted) return;
      final entrees = contacts
          .where((c) => !c.isBlocked)
          .map((modele.Contact c) => _Entree(
                cle: 'alanya:${c.publicNumber}',
                nom: c.displayName,
                numero: c.publicNumber,
                alanyaId: c.publicNumber,
                avatarUrl: c.avatarUrl,
              ))
          .toList()
        ..sort((a, b) => a.nom.toLowerCase().compareTo(b.nom.toLowerCase()));
      for (final e in entrees) {
        _parCle[e.cle] = e;
      }
      setState(() {
        _alanya = entrees;
        _chargement = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _chargement = false;
        _erreur = "Impossible de charger les contacts Alanya";
      });
    }
  }

  Future<void> _chargeTelephone() async {
    if (_telephone != null) return;
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    final statut = await Permission.contacts.request();
    if (!mounted) return;
    if (!statut.isGranted) {
      setState(() {
        _chargement = false;
        _permissionRefusee = true;
      });
      return;
    }
    try {
      // `withPhoto: false` : la photo d'un carnet de 800 contacts ferait
      // plusieurs mégaoctets et rendrait l'ouverture de la feuille inutilisable.
      // Celle du contact RETENU est chargée à l'envoi.
      final brut = await fc.FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: false,
      );
      if (!mounted) return;
      final entrees = <_Entree>[];
      for (final c in brut) {
        final nom = c.displayName.trim();
        final numero =
            c.phones.isNotEmpty ? c.phones.first.number.trim() : null;
        if (nom.isEmpty && (numero == null || numero.isEmpty)) continue;
        entrees.add(_Entree(
          cle: 'tel:${c.id}',
          nom: nom.isNotEmpty ? nom : numero!,
          numero: (numero != null && numero.isNotEmpty) ? numero : null,
          idTelephone: c.id,
        ));
      }
      entrees
          .sort((a, b) => a.nom.toLowerCase().compareTo(b.nom.toLowerCase()));
      for (final e in entrees) {
        _parCle[e.cle] = e;
      }
      setState(() {
        _telephone = entrees;
        _chargement = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _chargement = false;
        _erreur = "Impossible de lire le répertoire";
      });
    }
  }

  void _bascule(_Entree e) {
    setState(() {
      if (_retenus.contains(e.cle)) {
        _retenus.remove(e.cle);
      } else {
        if (_retenus.length >= _maxContacts) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("10 contacts au maximum par message")),
          );
          return;
        }
        _retenus.add(e.cle);
      }
    });
  }

  Future<void> _envoyer() async {
    if (_retenus.isEmpty || _envoiEnCours) return;
    setState(() => _envoiEnCours = true);

    final entrees =
        _retenus.map((cle) => _parCle[cle]).whereType<_Entree>().toList();
    Uint8List? photo;
    String? mime;

    // Photo seulement pour un partage unique venu du répertoire : c'est le seul
    // cas où la carte peut l'afficher, un compte Alanya ayant déjà son avatar.
    if (entrees.length == 1 && entrees.first.idTelephone != null) {
      try {
        final complet = await fc.FlutterContacts.getContact(
          entrees.first.idTelephone!,
          withPhoto: true,
          withThumbnail: true,
        );
        final octets = complet?.photo ?? complet?.thumbnail;
        if (octets != null && octets.isNotEmpty) {
          photo = octets;
          // Les photos de contact d'Android sont des JPEG ; le serveur n'accepte
          // de toute façon que des types connus, et se fie à celui annoncé.
          mime = 'image/jpeg';
        }
      } catch (_) {
        // Une photo illisible ne doit pas empêcher le partage du contact.
      }
    }

    if (!mounted) return;
    Navigator.of(context).pop(ContactShareResult(
      contacts: entrees.map((e) => e.versCharge()).toList(),
      photoBytes: photo,
      photoMimeType: mime,
    ));
  }

  List<_Entree> get _liste {
    final source = (_origineAlanya ? _alanya : _telephone) ?? const <_Entree>[];
    if (_recherche.isEmpty) return source;
    final q = _recherche.toLowerCase();
    return source
        .where((e) =>
            e.nom.toLowerCase().contains(q) ||
            (e.numero?.toLowerCase().contains(q) ?? false))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final surfaces = surfacesOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fond = dark ? surfaces.surface : Colors.white;
    final onSub = dark ? AlanyaColors.craie2 : Colors.black54;

    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          margin: const EdgeInsets.only(top: 12, bottom: 8),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: AlanyaColors.grey300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const Text("Partager un contact",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),

        // Origine : deux sources qui n'offrent pas les mêmes actions au
        // destinataire (voir l'en-tête de la classe).
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                  value: true,
                  label: Text("Alanya"),
                  icon: Icon(Icons.chat_bubble_outline_rounded, size: 16)),
              ButtonSegment(
                  value: false,
                  label: Text("Téléphone"),
                  icon: Icon(Icons.contacts_outlined, size: 16)),
            ],
            selected: {_origineAlanya},
            showSelectedIcon: false,
            onSelectionChanged: (s) {
              final alanya = s.first;
              setState(() {
                _origineAlanya = alanya;
                _permissionRefusee = false;
              });
              if (!alanya) _chargeTelephone();
            },
          ),
        ),
        const SizedBox(height: 10),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            onChanged: (v) => setState(() => _recherche = v.trim()),
            decoration: InputDecoration(
              isDense: true,
              hintText: "Rechercher",
              prefixIcon: const Icon(Icons.search, size: 20),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AlanyaColors.grey300)),
            ),
          ),
        ),
        const SizedBox(height: 6),

        Flexible(child: _corps(onSub)),

        if (_retenus.isNotEmpty)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _envoiEnCours ? null : _envoyer,
                  icon: _envoiEnCours
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send, size: 18),
                  label: Text("Envoyer (${_retenus.length})"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentOf(context),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _corps(Color onSub) {
    if (_chargement) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child:
            Center(child: CircularProgressIndicator(color: accentOf(context))),
      );
    }
    if (_permissionRefusee) {
      return _message(
        icone: Icons.contacts_outlined,
        texte: "Accès au répertoire refusé",
        action: const TextButton(
          onPressed: openAppSettings,
          child: Text("Ouvrir les paramètres"),
        ),
        onSub: onSub,
      );
    }
    if (_erreur != null) {
      return _message(
        icone: Icons.cloud_off_rounded,
        texte: _erreur!,
        action: TextButton(
          onPressed: _origineAlanya
              ? _chargeAlanya
              : () {
                  _telephone = null;
                  _chargeTelephone();
                },
          child: const Text("Réessayer"),
        ),
        onSub: onSub,
      );
    }

    final liste = _liste;
    if (liste.isEmpty) {
      return _message(
        icone: Icons.person_search_outlined,
        texte: _recherche.isEmpty ? "Aucun contact" : "Aucun résultat",
        onSub: onSub,
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      itemCount: liste.length,
      itemBuilder: (_, i) {
        final e = liste[i];
        final choisi = _retenus.contains(e.cle);
        return ListTile(
          onTap: () => _bascule(e),
          leading:
              AvatarCircle(name: e.nom, avatarUrl: e.avatarUrl, radius: 20),
          title: Text(e.nom, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: e.numero != null
              ? Text(e.numero!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: onSub))
              : null,
          trailing: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: choisi ? accentOf(context) : Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(
                  color: choisi ? accentOf(context) : AlanyaColors.grey400,
                  width: 1.5),
            ),
            child: choisi
                ? const Icon(Icons.check, size: 14, color: Colors.white)
                : null,
          ),
        );
      },
    );
  }

  Widget _message({
    required IconData icone,
    required String texte,
    required Color onSub,
    Widget? action,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icone, size: 44, color: AlanyaColors.grey400),
        const SizedBox(height: 10),
        Text(texte,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: onSub)),
        if (action != null) ...[const SizedBox(height: 4), action],
      ]),
    );
  }
}
