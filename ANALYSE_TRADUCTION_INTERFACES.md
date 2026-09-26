# Analyse et traduction des interfaces — Alanya (Flutter)

> Suite de la demande : « analyse les interfaces puis continue la traduction dans
> toutes les langues ». Ce document fait le bilan de ce qui a été câblé, des
> conventions retenues, et de ce qui reste volontairement hors périmètre.

## 1. Le catalogue

**`lib/l10n/app_localizations.dart`** — **1 085 clés × 9 langues**
(`fr`, `en`, `es`, `de`, `pt`, `ru`, `zh`, `sv`, `no`), parité vérifiée après
chaque injection (mêmes clés dans les 9 blocs, `_one`/`_many` appariés).

Deux helpers publics :

| Helper | Rôle |
|---|---|
| `tr(context, clé, {params})` | traduit une clé, remplace `{param}` par sa valeur |
| `trN(context, clé, n, {params})` | choisit `clé_one` / `clé_many` et fournit `{n}` |

Conventions :
- une clé par ligne, `'clé': 'valeur',` (les 541 clés historiques du plan
  initial sont restées en `"double quotes"` ; toutes les nouvelles injections
  utilisent des `'simple quotes'` — les deux formes cohabitent, le test de
  parité lit les deux) ;
- pluriels : suffixes `_one` / `_many` (jamais `_other`) ; le `_none` reste
  facultatif, traité par les écrans ;
- le chinois n'a qu'une forme (les deux entrées y sont identiques) ; le russe
  a trois formes réelles, sa forme `_many` est approximative sur les petits
  nombres (limite documentée dans le fichier) ;
- `tr()` **retombe silencieusement sur le français** si la clé manque — d'où le
  test `test/l10n_parite_test.dart` qui relit le fichier source.

## 2. Ce qui a été câblé (68 fichiers Dart)

Toutes les chaînes visibles passent par `tr()` / `trN()` :

- **Auth & compte** : login, otp, setup, forgot_password, biometric_lock,
  profile, change_password, delete_account.
- **Appels** : active_call, dialer, calls, abandoned_clients, call_banner,
  ivr_panel, plainte_recorder, queue_status_sheet, call_rating_sheet,
  in_app_notifier (bouton Refuser), full_screen_permission, contact_bubble,
  document_bubble, image_bubble, location_bubble, cached_media.
- **Appels — lot « interfaces dynamiques »** (demande user du 12/09/2026) :
  `call_controller` (26 sites : `lastError`, titres de notification
  `CallForegroundService.demarrer` et `AlanyaTelecom.chipDemarrer`, replis de
  noms « Appel »/« Membre »/« Standard »/« Contact », `_inviteErrorText`,
  raisons `cancelTransfer`, « Service {n} » du menu IVR), `_statusText`
  d'active_call (« En train de sonner… », « Sonnerie du groupe… »…),
  lookup 404/erreur du dialer, « Lecture en cours »/« Mise en relation »/
  « Service plainte » de l'ivr_panel, « · Groupe » et titre « Clavier ».
  Deux helpers sans `BuildContext` (même logique que
  `CallUiNative._libelle` : `PushService.navigatorKey.currentContext`, repli
  FR si non monté) : `_trAppel` (contrôleur) et
  `CallStatusFormalisme._traduire` (formalisme des statuts).
  Les libellés `preciseStatus`/`detail` formulés par le serveur en français
  passent par la table `_clesServeur` (libellé FR → clé l10n, libellé inconnu
  affiché tel quel) : traduction d'affichage, le formalisme reste au serveur.
- **Chat** : chat_screen (~60 remplacements : messages éphémères, épinglés,
  sélection, infos, réponses, traduction auto, menu édition…), gallery,
  image/video/pdf viewers, starred, new_group, media_caption,
  media_gallery_picker/viewer, location_share, activity_indicator,
  sending_media_bubble, offline_banner, multi_select_mixin, contact /
  media_picker_sheet, back_app_bar.
- **Statuts** : create_status, status_viewer, editeur_media_statut,
  audience_statuts, choix_emoji (libellés de familles), horodatage_statut
  (refactoré avec `BuildContext`).
- **Groupes** : group_info (nom/avatar, ajout/retrait de membres, promotion
  administrateur, départ), new_group (validations).
- **Réunions** : meetings (onglets, suppression), create_meeting (formulaire
  complet), meeting_detail (dialogues, demandes, statuts participant),
  meeting_room (contrôles, menu organisateur, exclusion, chat de salle, mains
  levées, minuteur), tuile_demande, meeting_banner.
- **Géolocalisation / entreprises** : geo_disclosure (textes longs),
  entreprises_tab (tooltip, fallback « Pays ») ; les libellés de services/
  centres viennent du serveur.
- **Widgets transverses** : auth_network_image (« Image indisponible »).

### Refactors notables (BuildContext injecté dans les helpers)

| Fonction | Avant | Après |
|---|---|---|
| `messageErreurAppel(e, {messageSi404})` | phrases FR en dur | `{..., required BuildContext context}` → `call_err_*` |
| `messageMediasEcartes(noms)` | phrases FR en dur | `{required BuildContext context}` → `media_skipped_one/_many` |
| `MeetingRefus.texteCourt` (controller) | phrase FR composée dans le contrôleur | supprimé ; composé dans `meeting_banner` via `tr('meet_room_full_short', …)`, le message serveur passe tel quel |
| `horodatageStatut(date)` | fonction libre, FR en dur | `(date, BuildContext context)` → `status_now` / `ago_min|hour|day` |

Le message du serveur (ApiException) passe **toujours tel quel** dans ces
helpers : c'est lui qui distingue les cas que le client ne peut pas deviner.

### Réutilisations assumées (libellé FR légèrement différent, écart accepté)

- `chat_open_failed` (« Impossible d'ouvrir la discussion ») pour l'ancien
  « Impossible d'ouvrir la conversation » ;
- `finish`/`decline`/`save`/`edit`/`delete`/`ok`/`retry`/`remove`/`validate`…
  comme boutons génériques ;
- `status_add_caption` pour la légende de média ; `meet_stat_invited`/`guest`
  pour « Invité » ; `meet_participant` comme fallback « Participant ».

## 3. Hors périmètre — volontairement non traduit

| Fichier | Raison |
|---|---|
| `core/push_service.dart`, `core/call_foreground_service.dart`, `core/geo_service.dart`, `core/geo_background*.dart` | notifications système / service Android, sans `BuildContext` au moment de la construction (les titres passés par `call_controller` sont désormais traduits) |
| `core/realtime_client.dart`, `core/ringtone_service.dart`, `core/enregistreur_appel.dart`, `calls/call_controller.dart` (journaux seuls), `calls/call_listener.dart`, `calls/enregistrements_repository.dart` | journaux de debug et messages techniques internes |
| `core/biometric_service.dart` | titre d'authentification biométrique exposé par le plugin, hors écran |
| `core/authed_api.dart` | « Session expirée » : erreur technique, message serveur en pratique |
| `features/auth/auth_controller.dart` | « Votre compte a été ouvert sur un autre appareil » : signal serveur (déconnexion multi-appareils) |
| `core/centre_transferts.dart`, `features/status/publication_statuts.dart` (titres), `features/chat/envoi_media_store.dart` | notifications de progression de téléchargement/envoi — singleton sans contexte ; travail restant (voir §4) |
| `core/sonneries_livrees.dart` | noms propres de sonneries (« Tonalité Alanya », « Éclosion ») |
| `features/calls/call_ui_native.dart` | écran d'appel natif (Kotlin/Swift), documenté à part |
| `lib/models/contact.dart`, `conversation.dart`, `message.dart`, `message_payload.dart` | getters/fonctions de prévisualisation sans `BuildContext` (« en ligne », « vu à l'instant », « 📍 Position », « 📷 Photo »…) — travail restant (voir §4) |
| `main.dart` (« Alanya »), `choix_pays_screen.dart` (alphabet de normalisation Unicode) | nom d'app / données techniques |
| Chemins API, messages serveur, `ApiException.message` | source de vérité = serveur |

## 4. Travail restant identifié (non bloquant)

1. **Prévisualisations des modèles** (`contact.onlineStatus`,
   `conversation.onlineStatus`, `message.apercu`, `message_payload`) :
   transformer les getters en méthodes prenant un `BuildContext` et passer
   `presence_online` / `presence_just_now` / `presence_min|hour|day` /
   `media_photo` / `video` / `voice_message` / `file`… Les clés existent déjà
   pour la plupart. Les écrans appelants ont tous un contexte.
2. **Progression des transferts** (`centre_transferts`) : fournir des libellés
   localisés au `demarrer(titre:)` (déjà le cas côté appelants pour les
   statuts) et traduire « Téléchargement impossible / en cours » dans les
   notifications (exigerait un contexte ou des libellés fournis par l'appelant).
3. Le test `test/l10n_parite_test.dart` doit tourner via `flutter test`
   (indisponible dans l'environnement d'analyse) ; la parité a été vérifiée de
   façon équivalente par script (mêmes clés × 9, `_one`/`_many` appariés).

## 5. Méthode

1. Scan systématique (`Text("…")`, tooltips, labels, hints, snackbars,
   ternaires, affectations `_erreur =`, patterns multi-lignes) — heuristique
   sur les accents et mots français, y compris les formes que le premier scan
   de patterns avait manquées.
2. Injection des clés manquantes **par bloc de langue** (insertion en fin de
   bloc, regex ancrée, itération inversée pour préserver les offsets), avec
   assertion anti-doublon et contrôle de parité à chaque passe.
3. Câblage par patches scriptés à comptage strict (`remplace(path,
   [(old, new, attendu)])`) — échec explicite si le nombre d'occurrences
   diffère, aucun remplacement à l'aveugle.
4. Vérifications après chaque fichier : tokenizer Dart (délimiteurs équilibrés,
   chaînes refermées) + détection de `const` englobant un `tr()` (interdit par
   le compilateur), dé-const manuel avec re-`const` des sous-expressions.
5. Re-scan final : **0 chaîne française codée en dur** dans les écrans (hors
   périmètre documenté ci-dessus).
