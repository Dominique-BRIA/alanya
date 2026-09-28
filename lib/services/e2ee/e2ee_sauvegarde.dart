/// LA SAUVEGARDE CHIFFRÉE, CÔTÉ MOBILE — ticket 4.14.
///
/// 🔴 JUMEAU DE `STAGE-WEB/src/services/e2ee-sauvegarde.ts`. Les deux clients
/// parlent aux mêmes routes et au même format : une archive créée sur le web
/// doit s'ouvrir sur le téléphone, et l'inverse.
///
/// ⚠️ ACTIVÉE PAR DÉFAUT, comme sur le web (décision du user, 23/09/2026).
/// Perdre son historique en changeant d'appareil est un piège que personne ne
/// voit venir : le défaut doit protéger, pas attendre qu'on sache qu'il faut se
/// protéger.
///
/// ⚠️ ET UN REFUS TIENT. Le serveur mémorise « refusée » sur le COMPTE : un
/// téléphone neuf ne doit pas recréer la sauvegarde que quelqu'un vient de
/// supprimer depuis le web.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'e2ee_coffre.dart';
import 'e2ee_serrures.dart';
import '../../core/message_cache.dart';
import '../../models/message.dart';
import 'e2ee_service.dart';

typedef AppelApi = Future<Map<String, dynamic>> Function(
  String methode,
  String chemin,
  Map<String, dynamic>? corps,
);

class E2eeSauvegarde {
  E2eeSauvegarde(this._api);

  final AppelApi _api;

  Uint8List? _maitresse;

  bool get estOuverte => _maitresse != null;

  /* ══════════════ LE COFFRE ══════════════ */

  /// Les serrures posées sur ce compte, et si la sauvegarde a été REFUSÉE.
  ///
  /// ⚠️ « PAS ENCORE ACTIVÉE » ET « REFUSÉE » NE SE CONFONDENT PAS : la première
  /// appelle une activation, la seconde l'interdit. Les traiter pareil ferait
  /// réapparaître la sauvegarde chez quelqu'un qui vient de la supprimer.
  Future<({List<Serrure> serrures, bool refusee})> lireCoffre() async {
    try {
      final r = await _api('GET', '/api/e2ee/coffre', null);
      final liste = (r['serrures'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(Serrure.depuisJson)
          .toList();
      return (serrures: liste, refusee: r['refusee'] == true);
    } catch (_) {
      /*
       * ⚠️ UN ÉCHEC RÉSEAU VAUT « REFUSÉE », PAS « À ACTIVER ». Dans le doute on
       * ne crée rien : activer par erreur envoie l'historique sur nos serveurs
       * sans que personne l'ait demandé, et c'est irréversible.
       */
      return (serrures: <Serrure>[], refusee: true);
    }
  }

  Future<void> _poser(Serrure s) =>
      _api('PUT', '/api/e2ee/coffre', s.enJson());

  /* ══════════════ ACTIVER / OUVRIR ══════════════ */

  /// À la connexion : ouvre l'archive, complète ses serrures, et restaure.
  ///
  /// 🔴 TROIS CHOSES, ET L'ORDRE COMPTE.
  ///
  ///   ① OUVRIR — par la clé maîtresse gardée sur l'appareil si elle y est,
  ///      sinon par la serrure « mot de passe ». La première voie est celle qui
  ///      permet d'ouvrir une archive créée avec la SEULE clé de récupération :
  ///      sans elle, cette archive resterait fermée pour toujours sur cet
  ///      appareil, et les nouveaux messages cesseraient d'être sauvegardés.
  ///
  ///   ② COMPLÉTER — si l'archive s'ouvre mais n'a pas de serrure « mot de
  ///      passe », on en pose une MAINTENANT. C'est le seul moment du cycle de
  ///      vie où ce secret existe, et poser une serrure ne demande que la clé
  ///      maîtresse, qu'on vient d'obtenir.
  ///
  ///   ③ RESTAURER — l'historique revient tout seul. Sans cette étape, un
  ///      téléphone neuf reste vide alors que l'archive est là : elle serait
  ///      alimentée sans jamais être relue.
  ///
  /// ⚠️ NE LÈVE JAMAIS ET NE BLOQUE PAS LA CONNEXION : empêcher quelqu'un
  /// d'entrer parce qu'une sauvegarde a échoué serait bien pire que l'absence
  /// d'historique.
  ///
  /// ⚠️ LE MOT DE PASSE N'EST GARDÉ NULLE PART. Il traverse cette fonction et
  /// en sort.
  Future<({int restaures, int illisibles})> aLaConnexion(
    String motDePasse,
    CoffreE2ee coffre,
  ) async {
    try {
      final etat = await lireCoffre();

      /* ── ① OUVRIR ────────────────────────────────────────────────── */
      if (etat.serrures.isEmpty) {
        if (etat.refusee) return (restaures: 0, illisibles: 0);
        final a = creerArchive({TypeSerrure.motdepasse: motDePasse});
        for (final s in a.serrures) {
          await _poser(s);
        }
        _maitresse = a.maitresse;
        await coffre.rangerMaitresse(a.maitresse);
        return (restaures: 0, illisibles: 0);
      }

      _maitresse = await coffre.lireMaitresse();

      if (_maitresse == null) {
        final mdp = etat.serrures.where((s) => s.type == 'motdepasse');
        if (mdp.isEmpty) {
          /*
           * ⚠️ ARCHIVE FERMÉE, ET ON NE PEUT RIEN FAIRE DE PLUS ICI. Elle n'a
           * qu'une clé de récupération, et cet appareil ne l'a jamais eue.
           * L'écran des réglages doit la demander — c'est la seule sortie, et
           * elle appartient à l'utilisateur.
           */
          return (restaures: 0, illisibles: 0);
        }
        _maitresse = ouvrirArchive(motDePasse, mdp.first);
        await coffre.rangerMaitresse(_maitresse!);
      }

      /* ── ② COMPLÉTER LES SERRURES ────────────────────────────────── */
      if (!etat.serrures.any((s) => s.type == 'motdepasse')) {
        await _poser(poserSerrure(_maitresse!, TypeSerrure.motdepasse, motDePasse));
      }

      /* ── ③ RESTAURER ─────────────────────────────────────────────── */
      final r = await restaurer();
      /*
       * 🔴 ET ON LES ÉCRIT. C'EST TOUT CE QUI MANQUAIT, ET C'ÉTAIT TOUT.
       *
       * 🐛 L'archive était ouverte, déchiffrée, ses messages rendus — puis
       * JETÉS. Cette fonction n'en gardait que le NOMBRE. Aucune ligne, dans
       * tout le mobile, n'écrivait le contenu restauré quelque part.
       *
       * ⚠️ LE SYMPTÔME ÉTAIT SPECTACULAIRE ET LA CAUSE MINUSCULE : sur un
       * second appareil du même compte, toutes les bulles chiffrées restaient
       * vides alors que le web affichait la conversation entière. Le
       * chiffrement marchait ; c'est la dernière ligne du parcours qui
       * manquait.
       *
       * ⚠️ `upsert`, PAS `putConv` : le second REMPLACE une conversation
       * entière, et effacerait les messages en clair d'avant le chiffrement.
       * On ajoute, on ne substitue pas.
       */
      return (restaures: r.messages.length, illisibles: r.illisibles);
    } catch (_) {
      /*
       * ⚠️ UN ÉCHEC ICI VEUT DIRE « MAUVAIS MOT DE PASSE », et rien d'autre :
       * AES-GCM authentifie. Le cas arrive quand le mot de passe du COMPTE a
       * changé sans que la serrure suive.
       */
      _maitresse = null;
      return (restaures: 0, illisibles: 0);
    }
  }

  /// Ouvre l'archive avec la clé de récupération, et pose la serrure manquante.
  ///
  /// 🔴 LA SEULE SORTIE quand une archive n'a QUE sa clé de récupération et que
  /// l'appareil ne l'a jamais eue. C'est à l'utilisateur de la fournir : nous ne
  /// l'avons jamais eue non plus, et c'est tout l'intérêt.
  Future<bool> ouvrirParRecuperation(
    String saisie,
    CoffreE2ee coffre, {
    String? motDePasse,
  }) async {
    try {
      final etat = await lireCoffre();
      final rec = etat.serrures.where((s) => s.type == 'recuperation');
      if (rec.isEmpty) return false;

      final cle = ouvrirArchive(normaliserCleRecuperation(saisie), rec.first);
      _maitresse = cle;
      await coffre.rangerMaitresse(cle);

      /*
       * ⚠️ ON EN PROFITE POUR POSER LA SERRURE DU MOT DE PASSE si on l'a : sans
       * elle, la prochaine connexion sur un AUTRE appareil redemanderait les
       * douze mots.
       */
      if (motDePasse != null &&
          motDePasse.isNotEmpty &&
          !etat.serrures.any((s) => s.type == 'motdepasse')) {
        await _poser(poserSerrure(cle, TypeSerrure.motdepasse, motDePasse));
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Ajoute une clé de récupération à une archive déjà ouverte.
  ///
  /// ⚠️ RIEN N'EST RECHIFFRÉ : on ré-enveloppe 32 octets. Une archive de cent
  /// mégaoctets gagne une serrure en quelques millisecondes.
  Future<String?> ajouterCleRecuperation() async {
    final cle = _maitresse;
    if (cle == null) return null;
    final mots = tirerCleRecuperation();
    await _poser(poserSerrure(cle, TypeSerrure.recuperation, mots));
    return mots;
  }


  /// Crée l'archive avec SES DEUX SERRURES, et rend la clé de récupération.
  ///
  /// 🔴 DEUX SERRURES D'UN COUP. Le mot de passe rouvre l'archive à chaque
  /// connexion sans rien demander ; la clé de récupération la rouvre sur un
  /// appareil neuf, ou si le mot de passe est oublié. Avec une seule des deux,
  /// il resterait toujours un cas où l'archive se referme pour de bon.
  ///
  /// ⚠️ LA CLÉ MAÎTRESSE EST AUSSI RANGÉE SUR L'APPAREIL : c'est ce qui permet
  /// d'ajouter une serrure plus tard sans redemander quoi que ce soit.
  ///
  /// ⚠️ SI UNE ARCHIVE EXISTE DÉJÀ, ON N'EN CRÉE PAS UNE SECONDE — on poserait
  /// une archive orpheline, et l'ancienne deviendrait illisible. On rend alors
  /// `null` : il n'y a pas de nouvelle clé à montrer.
  Future<String?> activerAvecDeuxSerrures(
    String motDePasse,
    CoffreE2ee coffre,
  ) async {
    final etat = await lireCoffre();
    if (etat.serrures.isNotEmpty) {
      /*
       * 🔴 UNE ARCHIVE EXISTE : ON L'OUVRE. On ne la remplace pas, mais sortir
       * sans rien faire était tout aussi mauvais.
       *
       * 🐛 C'ÉTAIT UN `return null` SEC, et voici ce qu'il coûtait. Quelqu'un
       * qui avait déjà une archive — créée depuis le web — activait le
       * chiffrement sur son téléphone, tapait son mot de passe... et la clé
       * maîtresse n'était JAMAIS rangée sur l'appareil.
       *
       * Conséquence exacte, observée le 27/09 : les messages REÇUS revenaient
       * (ils passent par les enveloppes) mais pas ceux qu'on avait ENVOYÉS, ni
       * aucune conversation menée d'un navigateur à l'autre — tout ce qui
       * dépend de l'archive, et rien d'autre.
       *
       * ⚠️ LE MOT DE PASSE VIENT D'ÊTRE TAPÉ, ET C'EST TOUT L'INTÉRÊT DE SA
       * SERRURE. La demander puis ne pas s'en servir était le pire des deux
       * mondes : on dérange la personne et on n'ouvre rien.
       *
       * ⚠️ ON REND TOUJOURS `null` : il n'y a pas de NOUVELLE clé de
       * récupération à montrer, celle de l'archie d'origine reste la bonne.
       */
      final mdp = etat.serrures.where((s) => s.type == 'motdepasse');
      if (mdp.isNotEmpty && _maitresse == null) {
        try {
          _maitresse = ouvrirArchive(motDePasse, mdp.first);
          await coffre.rangerMaitresse(_maitresse!);
        } catch (_) {
          /*
           * ⚠️ MOT DE PASSE QUI NE CORRESPOND PAS À LA SERRURE — le cas
           * arrive quand il a changé depuis. Le chiffrement de la conversation
           * s'active quand même : il ne dépend pas de l'archive. C'est
           * l'historique qui restera fermé, et la clé de récupération est là
           * pour ça.
           */
        }
      }
      return null;
    }

    final cle = tirerCleRecuperation();
    final a = creerArchive({
      TypeSerrure.motdepasse: motDePasse,
      TypeSerrure.recuperation: cle,
    });
    for (final s in a.serrures) {
      await _poser(s);
    }
    _maitresse = a.maitresse;
    await coffre.rangerMaitresse(a.maitresse);
    return cle;
  }

  /// Ré-enveloppe la serrure « mot de passe » avec le nouveau.
  ///
  /// 🐛 SANS CECI, CHANGER DE MOT DE PASSE CASSE LA SAUVEGARDE EN SILENCE : la
  /// serrure garde l'ANCIEN, et l'ouverture automatique échoue à la connexion
  /// suivante. L'utilisateur le découvre au pire moment — en changeant
  /// d'appareil.
  ///
  /// ⚠️ RIEN N'EST RECHIFFRÉ : on ré-enveloppe 32 octets.
  ///
  /// ⚠️ IL FAUT QUE L'ARCHIVE SOIT OUVERTE. Elle l'est si cet appareil a déjà
  /// sa clé maîtresse — c'est le cas normal après une connexion réussie.
  ///
  /// ⚠️ NE LÈVE JAMAIS : le mot de passe du compte a DÉJÀ changé quand on
  /// arrive ici. Échouer bruyamment laisserait croire que le changement n'a pas
  /// eu lieu.
  Future<bool> suivreChangementMotDePasse(String nouveau) async {
    final cle = _maitresse;
    if (cle == null) return false;
    try {
      await _poser(poserSerrure(cle, TypeSerrure.motdepasse, nouveau));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Pose la serrure « trousseau » de cet appareil.
  ///
  /// ⚠️ ELLE EST PAR APPAREIL, pas par compte : le serveur l'exige, et c'est ce
  /// qui permet au téléphone et au navigateur d'en avoir chacun une. Sans cette
  /// distinction, poser la sienne effacerait celle de l'autre.
  Future<bool> poserTrousseau(String secret, String appareil) async {
    final cle = _maitresse;
    if (cle == null) return false;
    try {
      await _poser(poserSerrure(cle, TypeSerrure.trousseau, secret,
          appareil: appareil));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Ouvre l'archive par le trousseau de cet appareil.
  Future<bool> ouvrirParTrousseau(
    String secret,
    String appareil,
    CoffreE2ee coffre,
  ) async {
    try {
      final etat = await lireCoffre();
      /*
       * ⚠️ ON CHERCHE LA SERRURE DE CET APPAREIL, pas « la » serrure trousseau.
       * Celle du téléphone n'ouvre rien depuis la tablette, et essayer avec le
       * mauvais secret échouerait sans qu'on sache pourquoi.
       */
      final sienne = etat.serrures.where(
        (s) => s.type == 'trousseau' && s.appareil == appareil,
      );
      if (sienne.isEmpty) return false;

      final cle = ouvrirArchive(secret, sienne.first);
      _maitresse = cle;
      await coffre.rangerMaitresse(cle);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Referme — déconnexion, ou changement de compte.
  void refermer() => _maitresse = null;

  /* ══════════════ DÉPOSER ══════════════ */

  /// Dépose un lot de messages dans l'archive.
  ///
  /// ⚠️ PAR LOTS, PAS PAR MESSAGE. Un bloc par message ferait une requête réseau
  /// par message, et 200 octets de chiffré pour 30 de texte — l'en-tête AES-GCM
  /// et le JSON pèsent plus que la charge.
  Future<bool> deposer(List<Map<String, dynamic>> messages) async {
    final cle = _maitresse;
    if (cle == null || messages.isEmpty) return false;

    try {
      final clair = Uint8List.fromList(
        utf8.encode(jsonEncode({'v': 1, 'messages': messages})),
      );
      final iv = ivNeuf();
      await _api('POST', '/api/e2ee/archive', {
        'iv': base64.encode(iv),
        'contenu': base64.encode(chiffrerAvec(cle, iv, clair)),
        'nbMessages': messages.length,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Relit toute l'archive.
  ///
  /// ⚠️ UN BLOC ILLISIBLE NE BLOQUE PAS LES AUTRES : on le compte et on continue.
  /// Une restauration silencieusement partielle est pire qu'un échec net, donc
  /// le nombre remonte à l'appelant.
  /// Tous les blocs de l'archive, page après page.
  ///
  /// 🐛 ON NE LISAIT QUE LA PREMIÈRE PAGE. Le serveur rend au plus 2 000 blocs
  /// par appel et donne `suivant` quand il en reste : au-delà, les messages
  /// les plus RÉCENTS manquaient à la restauration, en silence. Prouvé côté
  /// serveur (`e2ee-archive-banc.mjs` ⑧) et ici par
  /// `test/e2ee_archive_pages_test.dart`.
  ///
  /// ⚠️ 50 TOURS AU PLUS : un serveur qui rendrait toujours le même `suivant`
  /// ferait tourner la boucle sans fin. 50 pages = 100 000 blocs.
  Future<List<Map<String, dynamic>>> lireTousLesBlocs() async {
    final blocs = <Map<String, dynamic>>[];
    String? suivant;
    for (var tour = 0; tour < 50; tour++) {
      final r = await _api(
        'GET',
        suivant == null
            ? '/api/e2ee/archive'
            : '/api/e2ee/archive?apres=${Uri.encodeQueryComponent(suivant)}',
        null,
      );
      blocs.addAll((r['blocs'] as List? ?? const []).cast<Map<String, dynamic>>());
      suivant = r['suivant'] as String?;
      if (suivant == null) break;
    }
    return blocs;
  }

  Future<({List<Map<String, dynamic>> messages, int illisibles})> restaurer() async {
    final cle = _maitresse;
    if (cle == null) return (messages: <Map<String, dynamic>>[], illisibles: 0);

    final blocs = await lireTousLesBlocs();

    final vus = <String, Map<String, dynamic>>{};
    var illisibles = 0;

    for (final b in blocs) {
      try {
        final clair = dechiffrerAvec(
          cle,
          Uint8List.fromList(base64.decode(b['iv'] as String)),
          Uint8List.fromList(base64.decode(b['contenu'] as String)),
        );
        final charge = jsonDecode(utf8.decode(clair)) as Map<String, dynamic>;
        /*
         * ⚠️ LA VERSION SE VÉRIFIE ET ON S'ARRÊTE SI ELLE EST INCONNUE. Un
         * client ancien rendrait sinon des messages tronqués sans le dire.
         */
        if (charge['v'] != 1) {
          illisibles++;
          continue;
        }
        for (final m in listeDe(charge, 'messages')) {
          // Du plus ancien au plus récent : une correction déposée plus tard
          // l'emporte sur la version d'origine.
          vus[m['id'] as String] = m;
        }
      } catch (_) {
        illisibles++;
      }
    }
    /*
     * 🔴 ON ÉCRIT ICI, ET NON CHEZ CHAQUE APPELANT.
     *
     * 🐛 L'écriture vivait dans `aLaConnexion`. L'écran de sauvegarde, lui,
     * appelle `restaurer()` directement — pour la clé de récupération comme
     * pour le trousseau. Il annonçait « 42 message(s) restauré(s) » et n'en
     * rangeait AUCUN : deux chemins sur trois jetaient ce qu'ils venaient de
     * déchiffrer.
     *
     * ⚠️ UNE OPÉRATION QUI N'EST COMPLÈTE QU'À CONDITION QUE L'APPELANT AJOUTE
     * UNE LIGNE finira par rencontrer un appelant qui l'oublie. La remonter ici
     * supprime la question.
     */
    final messages = vus.values.toList();
    await _ecrireDansLeCache(messages);
    return (messages: messages, illisibles: illisibles);
  }

  /// Supprime tout — blocs ET serrures — et mémorise le refus.
  Future<void> toutEffacer() async {
    await _api('DELETE', '/api/e2ee/archive', null);
    refermer();
  }
  /// Range dans le cache local ce que l'archive vient de rendre.
  ///
  /// ⚠️ UN MESSAGE MAL FORMÉ N'ARRÊTE PAS LES AUTRES. Une archive écrite par un
  /// client plus ancien peut porter un champ de moins ; refuser le lot entier
  /// pour une ligne ferait perdre toute une conversation.
  ///
  /// ⚠️ ON NE SAIT PAS TOUJOURS QUI A ÉCRIT. Les archives posées avant que
  /// l'expéditeur ne soit enregistré n'ont pas ce champ : la bulle s'affichera
  /// alors du côté des messages reçus. Mieux vaut un message du mauvais côté
  /// qu'un message absent.
  Future<void> _ecrireDansLeCache(List<Map<String, dynamic>> messages) async {
    for (final m in messages) {
      try {
        final id = m['id'] as String?;
        final convId = m['convId'] as String?;
        final texte = m['texte'] as String?;
        if (id == null || convId == null || texte == null) continue;

        /*
         * 🔴 DEUX FORMATS COEXISTENT DANS L'ARCHIVE, ET IL FAUT LES DEUX.
         *
         * Le web écrit `quand` en MILLISECONDES depuis 1970 ; d'anciens blocs
         * peuvent porter une date ISO. Ne lire que l'une des deux ferait
         * retomber l'autre sur « maintenant » — et toute une conversation
         * restaurée se serait empilée à la date du jour, dans le désordre.
         *
         * ⚠️ L'ORDRE COMPTE : on essaie le nombre d'abord. `DateTime.tryParse`
         * accepte certaines suites de chiffres et rendrait une date absurde.
         */
        final brut = m['quand'];
        final quand = brut is num
            ? DateTime.fromMillisecondsSinceEpoch(brut.toInt())
            : DateTime.tryParse('$brut') ?? DateTime.now();
        await MessageCache.upsert(
          Message(
            id: id,
            convId: convId,
            senderId: (m['expediteurId'] as String?) ?? '',
            content: texte,
            type: 'TEXT',
            status: 'SENT',
            replyToId: null,
            media: const [],
            createdAt: quand,
          ),
          convId,
        );
      } catch (_) {
        // Ligne illisible : on passe à la suivante.
      }
    }
  }

  /// Reprend l'archive au démarrage, sans rien demander.
  ///
  /// 🔴 `aLaConnexion` NE TOURNE QU'À LA CONNEXION, et c'était le trou.
  /// Quelqu'un qui reste connecté — le cas normal — ne repasse jamais par cet
  /// écran. Les messages arrivés entre-temps sur un AUTRE appareil restaient
  /// donc dans l'archive, intacts, sans que rien n'aille les chercher.
  ///
  /// ⚠️ LE MOT DE PASSE N'EST PAS NÉCESSAIRE ICI : la clé maîtresse est déjà
  /// dans le coffre sécurisé depuis la première ouverture. C'est ce qui permet
  /// de le faire à chaque lancement, en silence.
  ///
  /// ⚠️ ON NE REFAIT RIEN SI L'ARCHIVE N'A PAS GROSSI. Déchiffrer deux mille
  /// blocs à chaque lancement coûterait cher pour rien ; on retient le nombre
  /// de blocs déjà repris. Les écritures étant de toute façon idempotentes,
  /// se tromper ici ne coûte qu'un tour de travail, jamais une donnée.
  ///
  /// ⚠️ NE LÈVE JAMAIS : c'est un rattrapage de fond, pas un préalable.
  Future<int> reprendreAuDemarrage(CoffreE2ee coffre, {bool force = false}) async {
    try {
      _maitresse ??= await coffre.lireMaitresse();
      if (_maitresse == null) return 0;

      final r = await _api('GET', '/api/e2ee/archive', null);
      final blocs = (r['blocs'] as List? ?? const []).length;
      if (blocs == 0) return 0;

      /*
       * ⚠️ `force` CONTOURNE CE RACCOURCI, ET IL LE FAUT. Le compte de blocs
       * dit si l'ARCHIVE a bougé ; il ne dit rien du cache LOCAL, qui peut
       * avoir été vidé, remplacé par les lignes sans texte du serveur, ou
       * n'avoir jamais reçu ce que l'archive contient.
       *
       * 🔴 UN RACCOURCI QUI SUPPOSE L'ÉTAT DE L'AUTRE CÔTÉ finit par se
       * tromper. Celui-ci économise un déchiffrement au démarrage ; il ne doit
       * pas pouvoir empêcher une conversation ouverte de se remplir.
       */
      final dejaVus = int.tryParse(await coffre.lireBlocsRepris() ?? '') ?? -1;
      if (!force && blocs == dejaVus) return 0;

      final restaure = await restaurer();
      await coffre.noterBlocsRepris(blocs);
      return restaure.messages.length;
    } catch (_) {
      // Réseau coupé, archive fermée : on réessaiera au lancement suivant.
      return 0;
    }
  }

  /// Rouvre l'archive avec le mot de passe du compte.
  ///
  /// 🔴 IL MANQUAIT, ET C'ÉTAIT LA SORTIE LA PLUS ÉVIDENTE. L'écran ne
  /// proposait que les douze mots — qui sont sur un papier, quelque part — et
  /// le trousseau, lié à un appareil qu'on n'a peut-être plus. Le mot de passe,
  /// lui, est dans la tête de la personne, et sa serrure existe déjà.
  ///
  /// ⚠️ REND `false` SUR UN MAUVAIS MOT DE PASSE, sans autre explication :
  /// AES-GCM authentifie, il n'y a pas de cas où la clé serait bonne et
  /// l'ouverture échouerait.
  Future<bool> ouvrirParMotDePasse(String motDePasse, CoffreE2ee coffre) async {
    try {
      final etat = await lireCoffre();
      final mdp = etat.serrures.where((s) => s.type == 'motdepasse');
      if (mdp.isEmpty) return false;

      final cle = ouvrirArchive(motDePasse, mdp.first);
      _maitresse = cle;
      await coffre.rangerMaitresse(cle);
      return true;
    } catch (_) {
      return false;
    }
  }

}
