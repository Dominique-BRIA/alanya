# Analyse du dépôt Alanya — Branche la plus à jour

**Date d'analyse:** 2026-08-01  
**Branche la plus à jour identifiée:** `origin/arena/019fa167-alanya`  
**Commit HEAD:** `7718492` — *Composeur : le smiley entre dans le champ, et le A porte une vraie barre* — 2026-07-31 15:45:40  
**Branche d'analyse courante:** `arena/019fbc55-alanya` (issue de `arena/019f9ff6-alanya` du 27/07) — 201 fichiers  
**Branche à jour:** 215 fichiers, 3932 insertions / 714 suppressions vs 019f9ff6, 22 930 insertions vs main.

---

## 1. Vue d'ensemble

**Alanya / Alanya Work** (`com.alanya237.work`) est une application de messagerie instantanée complète type WhatsApp, développée en Flutter, avec une identité visuelle afro-premium très affirmée (terre cuite, chocolat, sable, teal, vert forêt). 

- **Backend:** Next.js sur `https://alanyavox.com`, WebSocket sur `wss://alanyavox.com/ws` (override possible via `--dart-define API_URL / WS_URL`).
- **Package:** `alanya` v0.1.0+1, SDK `>=3.3.0 <4.0.0`
- **Cibles:** Android (minSdk 21), iOS, Web (partiel), Linux/desktop.
- **Nom:** Renommé récemment **Alanya Work** (commit 3ed5afd), logo bulle téléphone vert `logoVert #098084` relevé sur l'icône.

C'est un **clone WhatsApp avancé** + calls + réunions + IA + status + device management.

---

## 2. Structure du projet

```
lib/
  core/                  # Infra transversal
    api_client.dart      # http + ApiException
    authed_api.dart      # bearer auto via TokenStorage
    server_config.dart   # API_BASE / WS_BASE
    token_storage.dart   # flutter_secure_storage v10
    realtime_client.dart # WebSocket + DNS warmup + ping 20s + backoff DNS vs TCP
    push_service.dart    # FCM + local notifs + full-screen call
    connectivity_service.dart, outbox.dart, message_cache.dart, etc.
    device_registry.dart # NEW (019fa167) : multi-device, cookies_WebID
    whatsapp_format_*    # NEW : *gras* _italique_ ~barré~ ``` code ```
    alanya_id_formatter.dart, ringtone_service.dart, presence_store.dart...
  features/
    auth/                # welcome, login, register, setup, otp, forgot, biometric_lock
    home/                # 5 tabs + OfflineBanner + CallBanner
    chat/                # chat_screen (2665L), gallery, media_gallery_viewer, new_group
    calls/               # call_controller (mesh), webrtc_peer_session, webrtc_group_mesh, dialer, active_call
    contacts/            # sync téléphone (flutter_contacts), add, phone_sync
    group/               # group_info (609L)
    status/              # stories type WhatsApp
    meetings/            # create, detail, room, controller, realtime_meeting_methods
    ai/                  # assistant Alanya, threads
    blocked/, account/, settings/, media/, push/
  models/                # auth_user, conversation, message, call_record, meeting, etc.
  theme/
    alanya_theme.dart    # 1430 lignes sur 019fa167 vs 713 sur main — 4 variantes
    app_theme.dart       # legacy
  widgets/               # avatar_circle, motif_background, alanya_nav_bar, wordmark, glass_card, media/*
  l10n/                  # app_localizations.dart 967 lignes
  main.dart              # MultiProvider (14 providers)
```

**Stats:**
- `origin/main` = 129 fichiers (ancien)
- `arena/019f9ff6` = 201 fichiers, home_screen 1717L, chat_screen 2276L
- `arena/019fa167` = 215 fichiers, alanya_theme 1430L, chat_screen 2665L, home_screen 1751L
- Total lib Dart `14801` lignes sur 019f9ff6, ~18k sur 019fa167

---

## 3. Design System — le chantier majeur de 019fa167

C'est le coeur de la différenciation.

**4 variantes dans une enum `VarianteTheme { clair, blanc, nuit, noir }` + `ThemeExtension AlanyaSurfaces`:**

- **Clair (défaut):** `cream #FAF6F0`, `warmWhite`, `terracotta #B85C38`, `forest #2D6A4F`, `gold`.
- **Blanc (NEW 019fa167, 4e variante):** base blanche pure, accent `teal #008B8B`, bulle envoyée `blancEnvoyee #D6ECEC` puis teal plein pour cohérence avec bouton envoi. Terre cuite reste secondaire.
- **Nuit:** `nuit #0B0B18`, `nuit2 #14142A`, `nuit3 #1E1E3D`, `indigo #3B3B7A`, `terracottaNuit`. Motif `motif_nuit_doux/fort`.
- **Noir (NEW):** OLED vrai noir `#000000`, surface `0D0D0D`, teal unique, bulle reçue **blanche à texte noir** pour contraste max, envoyée `tealSombre #00494A`. `avecMotif=false` pour économie batterie.

**Pattern important `themed()`:** `themed(context, light: ..., dark: ...)` — volontairement on ne touche JAMAIS la valeur clair quand on ajoute sombre, pour éviter dérive.

**AlanyaSurfaces** résout 54 couleurs en dur qui posaient problème pour Noir : chaque thème déclare fond/surface/champ/bulleRecue/bulleEnvoyee.

**Wordmark:** `AlanyaWordmark` avec `logoVert`, typographie Inter.

---

## 4. Core / Infra

### Auth & Session
- `AuthController` bootstrap: cache userJson instantané -> tente /me avec access -> si 401 refresh -> si échec clear. Mode offline si cache présent.
- `TokenStorage` via secure storage.
- **Nouveau 019fa167:** `device_registry.dart` — id stable `mob-<24 chars base36>` stocké en SharedPreferences sous clé `cookies_WebID` (même clé que web). `registerIfAuthenticated()` POST `/api/appareils` avec libelle deviné via `Platform.operatingSystemVersion` (samsung/a54...), typeDevice 1=Android 2=iOS. `session_revoked` event WS -> déconnexion immédiate.

### Realtime
- `web_socket_channel`, token en query param.
- DNS warmup: `HttpClient HEAD https://alanyavox.com/ws` avant WSS — contourne cache négatif opérateur Cameroun.
- Ping applicatif 20s contre NAT mobile agressif.
- Backoff différencié: DNS `1,2,3,5,8,15,30s` vs TCP `2,4,8,16,30s`.
- `cancelOnError:false` pour ne pas tuer la sub sur trame louche (fix incoming_call perdu).
- Méthodes: sendMessage, sendMedia, sendMultiMedia, markRead, reaction, delete_message, edit_message, pin_message, set_disappearing, forward, typing, recording, call_ring/signal/state/invite, meeting_join/leave/signal.

### Offline-first
- `MessageCache`, `ConversationCache`, `ContactCache`, `CallCache`, `MediaCache` via sqflite.
- `Outbox` (SQLite `alanya_outbox.db`) file d'attente texte offline, flush auto quand online, max 5 tentatives, survit au kill. Limité à TEXT (médias non rejouables).
- `ConnectivityService` marque succès/échec HTTP pour éviter poll quand offline.
- `ConnectivityService` + `OfflineBanner`.

### Push
- `PushService` singleton, `navigatorKey` global, initialise Firebase + canal Android `messages` + `calls` (max importance, fullScreenIntent, timeout 60s).
- Foreground: pas de notif double pour `incoming_call` (WS prend le relai).
- Background handler `@pragma('vm:entry-point')` gère `call_cancelled` -> cancel notif ciblée par `callId.hashCode`.
- ShowIncomingCall full-screen même écran verrouillé.
- `NotificationSettings` respecté (messagesOn, previewOn, callsEnabledFresh).
- InAppNotifier: bandeau custom glassmorphism groupé par conv, avec reply inline `chat.sendText`.

### Calls
- **Mesh WebRTC:** `WebrtcGroupMesh` = N PeerConnection (1 par participant). `WebrtcPeerSession`.
- `CallController`: état complet (incoming, activeCallId, role outgoing/incoming/ongoing, isGroupCall, isCallInitiator, muted, speaker, video, remoteRinging, callScreenVisible, connectedSince, pendingTransfer).
- Features: toggle mute/speaker/video/switchCamera, inviteToCall, transferCall supervisé (invite puis leave auto quand cible rejoint), `joinedParticipantIds`, `invitedParticipantIds`, `_initialMemberIds` pour taguer "(invité)".
- Ring timeout 60s.
- `RingtoneService`: sons locaux `incoming_ring.mp3`, `outgoing_ring.mp3`, cue discret pour typing.
- `CallBanner` global overlay dans `MaterialApp.builder` (Lot 2b) + `CallListener`.
- **Nouveau dialer 019fa167 (570L):** compose Alanya ID (6 ou 8 chiffres, formatage `formatAlanyaId`), recherche auto debounce 450ms dès longueur valide, via `ContactsRepository.searchByNumber`, puis `createDirect` + `startOutgoing`. Actions: call AUDIO/VIDEO, add contact, search, haptic feedback.
- ICE: fallback hardcodé + chargement backend `/api/calls/ice` (évolution vers dynamique dans 8355cb3).

---

## 5. Fonctionnalités métier

### Chats (2665L sur 019fa167)
- WhatsApp-like complet: reply (swipe), edit (même par WS), delete me/everyone, forward multi-conv, pin/unpin partagé, star, réactions emoji flottantes avec overlay animé, agrégation emoji + compteur, search dans conversation avec index `pos/total`, date separators, system messages timer, disappearing messages (0/24h/7j/90j), présence live via `PresenceStore`.
- Typing/recording indicators avec timeout (6s typing, 12s recording) + cue sonore throttlé 4s.
- Scroll infini: `cursor` = first message id, preserve position visuelle après prepend.
- Media: `media_picker_sheet` (photo, video, doc, audio, contact), multi-media grid (2+ médias = `MediaGrid`), `ImageBubble`, `VideoBubble` avec thumbnail `video_thumbnail`, `DocumentBubble` (PDF vs doc), `AudioBubble` avec player intégré, `LinkBubble` via `any_link_preview`, reply preview media, download via MediaStore.
- Gallery: `_galleryItems()` collecte tous médias image/vidéo du fil pour viewer navigable swipe.
- Traduction inline: `TranslateService`, tap pour traduire vers `LocaleController.languageCode`.
- Voice: `VoiceRecorder` IO/Web, lock en swipe up (-60px), timer, annulation.
- Poll fallback 3s si WS déconnecté, mais skip si `loadedOlder` ou `loadingOlder` pour ne pas écraser historique.

### ConversationsTab (Home)
- Cache d'abord, sync après. Badge unread terre cuite, pin icon, archived section WhatsApp-style bottom sheet draggable, filtres Tous/Non lues/Groupes, recherche dans titre + publicNumber + dernier message, multi-select mixin delete, long-press menu pin/archive/delete.
- Banner user avec Alanya ID formaté.

### Contacts & Groups
- `flutter_contacts` lecture répertoire natif, `phone_sync_screen` + `phone_sync_service`.
- `group_info_screen` 609L.

### Meetings, Status, AI
- Meetings: CRUD, meeting_room_screen 492L avec WebRTC.
- Status: create, viewer avec progress.
- AI: threads, messages, `AiRepository`, onglet Discussion / Mes Conversations, share/copy/delete, scroll to bottom.

### Settings (019fa167 ajoute)
- `devices_screen.dart` 271L : liste appareils, isOnline, lastLogin, icône type, bouton déconnexion distante, current device badge.
- `login_history_screen.dart` 205L : historique connexions mobile.
- notification_settings, privacy, blocked_users.
- `theme_controller.dart` refacto complet (195L vs 60L) pour gérer 4 variantes + persistence.

---

## 6. Nouveautés spécifiques de la branche la plus à jour (019fa167)

Commits entre 27/07 et 31/07:
- `Composeur: le smiley entre dans le champ, et le A porte une vraie barre`
- `Composeur: disposition de la maquette, et le micro devient l'envoi`
- `Theme Blanc`, `Theme Noir (2/2)`, `Theme Noir (1/2)`
- `Clavier d'appel : composer un Alanya ID et appeler vraiment`
- `Appareils : le mobile s'inscrit et son écran Appareils connectés`
- `Historique de connexion`
- `Déconnexion immédiate : session_revoked`
- `Logo et icône : fonds corrigés, recentrage`

Fichiers nouveaux:
- `device_registry.dart`, `devices_screen.dart`, `login_history_screen.dart`
- `whatsapp_format_input.dart`, `whatsapp_format_logic.dart`, `whatsapp_text.dart`, `whatsapp_text_parser.dart`
- `ic_launcher.xml` adaptive icon fond blanc, foreground, background
- `test/alanya_id_formatter_test.dart`

Améliorations:
- `alanya_id_formatter.dart` 99L de plus, formattage WhatsApp.
- `dialer_screen.dart` réécriture complète 518 insertions.
- `chat_screen.dart` +518 lignes : formatage gras/italique au doigt, micro qui grossit à l'appui, bouton A dans champ, smiley intégré.
- `theme_controller.dart` +187L: passage de 2 à 4 thèmes sans casser clair/nuit.
- `profile_screen`, `setup_screen`, `add_contact_screen` polishing.
- MinSdk verrouillé à 21 avec raison.
- Package `com.alanya237.work`.

---

## 7. Points forts

- **Vision produit claire:** identité forte, UX WhatsApp familière mais avec twists (teal, oasis, motif).
- **Offline-first sérieux:** caches SQLite + outbox persistant + connectivity awareness.
- **Realtime robuste:** DNS warmup Afrique, ping NAT, backoff intelligent, debug overlay.
- **Calls avancés:** group mesh, invite, transfert supervisé, full-screen push, banner global, ringtone service.
- **Thématisation exemplaire:** commentaire `themed()` qui protège le mode clair, ThemeExtension pour Noir/Blanc sans dérive.
- **Sécurité mobile:** adhérence permissions, biometric_gate, copie offline purge à logout.
- **L10n:** 9 locales supportées, `app_localizations` central.
- **Media complet:** image, video, pdf intégré, audio, doc, link preview.

---

## 8. Dettes techniques & risques

**Critiques:**
- **Fichiers monolithes:** `chat_screen.dart` 2665L, `home_screen.dart` 1751L, `theme` 1430L, `contact_info_screen` 700L+. Maintenabilité faible, violation SRP.
- **Fichiers bak:** `chat_screen.dart.bak` (2481L, 86k) commité — doit être `.gitignore`.
- **Token en query param:** WS `?token=` + media `?token=` + push `?token=` → fuite dans logs Nginx, historique, etc. Mieux header ou cookie HttpOnly.
- **HttpClient dans realtime_client.dart `import dart:io`** : casse build Web (pas de HttpClient). Devrait être conditional import.
- **Upload en mémoire:** `Uint8List.fromList(f.bytes)` pour chaque média, O(n) RAM, OOM sur vidéo 100Mo. Devrait streamer.
- **Double PDF:** `pdfx` + `flutter_pdfview` + `microsoft_viewer` — 3 libs PDF lourdes pour même usage.
- **Timeouts absents:** `ApiClient` http sans `timeout` → UI freeze potentiel. `MessageCache.putConv` delete+batch sans transaction.
- **Migrations SQLite absentes:** version 1 partout, pas de onUpgrade → crash si schema change.
- **google-services.json commité:** secret FCM exposé, risque abus. Mettre en secret Codemagic.
- **Secure storage non clair à l'uninstall?** Cache user json en clair dans secure storage? Vérifié.
- **Tests:** seul `alanya_id_formatter_test.dart` et `widget_test.dart` vide. Pas de tests pour call_controller, outbox, realtime.
- **Poids assets:** `app_icon.png` 620Ko, `dark-bg.png` 1.6Mo (non optimisé), sons 800Ko.
- **Duplication:** `alanya_android.iml` commité (IDE), `.gradle/` 8.11.1 commité (binaire) — `.gitignore` incomplet.
- **ProGuard:** rules ajoutées OK, mais build.gradle.kts hardcode.
- **Thread-safety:** `PresenceStore` lit `RealtimeClient` sans sync, `myUserId` bind post-frame dans HomeScreen peut rater 1er incoming_call.

**Moyens:**
- `build-android.yml` workflow existe mais pas iOS.
- `translation_service` appelle probablement API externe non cachée.
- `whatsapp_format_*` parseur custom — risque RegExp ReDoS si mal throttlé.
- `call_controller` fallback ICE hardcodé vs dynamic loading commit 8355cb3 — incohérence.
- `alanya_id_formatter` formaté à la saisie mais pas de validation Luhn.

---

## 9. Sécurité

- JWT secure storage OK (v10 fix clang Linux).
- `api_client` décode erreur `{ error: { message, code } }`.
- Logout: unregister FCM + clear MessageCache + ConversationCache + CallCache + ContactCache + disconnect WS.
- Mais: token in URL, google-services.json public, no cert pinning, no root detection, media URLs guessable via id.
- `session_revoked` bien géré en 019fa167: écoute event et déconnexion immédiate.

---

## 10. Recommandations (priorisées)

**P0 — Nettoyage:**
1. Supprimer `chat_screen.dart.bak`, `chat_screen_patch.dart`, ajouter `*.bak` au `.gitignore`.
2. Retirer `android/.gradle/` et `*.iml` du repo, optimiser `.gitignore`.
3. Extraire `google-services.json` vers secret env / Codemagic, mettre `google-services.json.example`.

**P1 — Archi:**
4. Split `chat_screen.dart` en mixins existants + widgets (`composer.dart`, `bubble.dart`, `search_bar.dart`) et services.
5. Split `home_screen.dart` : `conversations_tab.dart`, `status_tab.dart`, `ai_tab.dart` séparés.
6. Passer `ApiClient` à `http.Client` avec timeout + retry + interceptor auth.
7. Migrer token query param vers header `Authorization: Bearer` pour WS via sous-protocole ou cookie, et pour media via header signé.
8. Ajouter migrations sqflite v2, v3.

**P2 — Perf/fiabilité:**
9. Streaming upload multipart, pas `fromList`.
10. Fix `realtime_client` web: conditional `_warmupDns` ou `kIsWeb` guard.
11. Ajouter `flutter_driver` / integration tests pour call flow et offline.
12. Linter strict: `flutter_lints` → activer `avoid_print`, `prefer_const`, `unawaited_futures`.
13. Optimiser assets: app_icon 620Ko → 100Ko webp, dark-bg 1.6Mo → motif vectoriel.

**P3 — Produit:**
14. Documenter 4 thèmes dans Storybook Widgetbook.
15. Finir `dialer_screen` → ajouter DTMF sons, T9 search.
16. Ajouter E2E encryption (Signal lib) — actuellement messages en clair serveur.
17. Compléter `devices_screen` avec renommage et last activity map.

---

## 11. Conclusion

La branche `arena/019fa167-alanya` du 31/07 est **de loin la plus avancée**: passage de 3 à 4 thèmes sans régression (exploit via ThemeExtension), dialer clavier Alanya ID fonctionnel, multi-device avec registre et déconnexion distante, composer WhatsApp-style avec formatage et micro interactif. Le socle WhatsApp (chat, calls mesh, offline, push full-screen) était déjà solide en `019f9ff6`, la dernière branche le porte au niveau produit **Alanya Work**.

Reste à adresser la dette monolithe + sécurité tokens + assets lourds pour passer en production stable.

**Prochaine étape suggérée:** merger `019fa167` dans `main` (ou `arena/019fbc55-alanya`), nettoyer `.bak` et `.gradle`, publier test APK Codemagic.

---
*Généré automatiquement par analyse statique du repo et diff inter-branches.*
