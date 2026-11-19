# Alanya Work sur iPhone : plan de réalisation

Préparé le 19/11/2026 à partir du code (mobile `3a2e046`, serveur `255c174`) et de recherches sur les exigences d'Apple.

## 1. En bref

- **Flutter fait l'essentiel.** Les 130 000 lignes de Dart (écrans, chiffrement Signal, discussions, groupes, statuts, appels WebRTC, traduction, cache) tournent telles quelles sur iPhone.
- **Le dépôt n'a pas encore de dossier `ios/`.** Tout le projet Xcode est à créer.
- **Ce qui reste à écrire relève d'Apple, pas de Flutter :**
  - les appels entrants (CallKit et PushKit) ;
  - les notifications (APNs) ;
  - les liens universels ;
  - le partage vers l'application ;
  - une dizaine de petits modules natifs aujourd'hui en Kotlin (4 750 lignes), à refaire en Swift ou à laisser de côté au début.
- **Le serveur doit apprendre à parler à Apple :**
  - envoyer les appels entrants par une notification « VoIP » directement aux serveurs d'Apple ;
  - envoyer les notifications de message sous une forme qu'iOS affiche toujours ;
  - publier le fichier des liens universels.
- **On peut compiler sans Mac** grâce à Codemagic, déjà utilisé pour Android. En revanche, un iPhone réel est indispensable : les appels (CallKit) ne fonctionnent pas sur le simulateur. Un Mac, même loué, rend le travail sur le projet Xcode bien plus sûr.
- **Durée estimée :** environ 8 à 10 semaines pour un développeur, en 5 phases, plus les délais d'Apple (compte, revue). L'estimation est détaillée au §8.

## 2. Ce qui marche déjà sur iPhone sans effort particulier

Ces paquets Flutter gèrent iOS. Il suffit de les configurer : texte d'autorisation dans `Info.plist`, version minimale.

| Domaine | Paquets |
|---|---|
| Écrans, logique, chiffrement Signal | tout `lib/` en Dart, `libsignal_protocol_dart`, `pointycastle` |
| Réseau, temps réel | `http`, `web_socket_channel`, `connectivity_plus` |
| Stockage | `sqflite`, `shared_preferences`, `path_provider`, `flutter_secure_storage` (Trousseau d'iOS) |
| Médias | `image_picker`, `photo_manager`, `video_player`, `video_thumbnail`, `video_compress`, `audioplayers`, `record`, `audio_waveforms`, `file_picker`, `open_filex`, `pdfx`, `syncfusion_flutter_pdf` |
| Appels | `flutter_webrtc` (avec un réglage de la session audio, §4) |
| Divers | `local_auth` (Face ID), `mobile_scanner`, `qr_flutter`, `share_plus`, `url_launcher`, `geolocator`, `flutter_local_notifications`, `firebase_messaging`, `background_downloader`, `flutter_timezone`, `gpt_markdown`, `any_link_preview` |
| Traduction sur l'appareil | `google_mlkit_translation` et `google_mlkit_language_id`. Ils exigent **iOS 15.5 au minimum**, et un correctif dans le `Podfile` pour le simulateur des Mac récents. |

**Version minimale retenue : iOS 15.5** (imposée par la traduction). Elle couvre l'iPhone 6s et les modèles suivants.

À noter : sur iPhone, le Trousseau **survit à la désinstallation**, contrairement à Android. Au premier lancement après une réinstallation, il faudra effacer l'ancien coffre ; sinon le chiffrement reprend une identité périmée.

## 3. Ce qu'il faut remplacer ou adapter

### 3.1 Paquets Android seulement

| Paquet | Rôle chez nous | Sur iPhone |
|---|---|---|
| `alanya_telecom` (module maison) | Sonnerie fiable via Telecom | Inutile : CallKit le remplace (§4). |
| `media_store_plus` | Enregistrer dans la galerie | Utiliser `photo_manager` (ou `gal`) pour enregistrer dans Photos. |
| `flutter_foreground_task` | Services de premier plan (position, transferts) | iOS n'a pas de service de premier plan. La position passe par le mode d'arrière-plan « location » ; les transferts passent par la session d'arrière-plan de `background_downloader`. |
| `share_handler` | Recevoir un partage d'une autre appli | Fonctionne sur iOS, mais demande une **extension de partage** (cible Xcode à part) et un groupe d'applications. |
| `app_links` | Liens `/u/`, `/i/`, `/g/` | Fonctionne sur iOS avec les **liens universels** (§5). |

### 3.2 Nos modules natifs Kotlin et leur équivalent iOS

Le code Dart a déjà une solution de repli pour presque tous ces modules. Une première version peut donc sortir sans eux, avec une fonction réduite.

| Canal / fichier Android | Fonction | Équivalent iOS | Priorité |
|---|---|---|---|
| `CallIncomingHelper`, `AffichageAppel`, `CallForegroundService`, `PhotoAppel`, `ApercuCameraAppel`, `CallNativeBridge`, `CallRejectHelper`, `com.alanya/call_native` | Écran d'appel entrant, sonnerie, refus app fermée | **CallKit** : l'écran d'appel du système, y compris téléphone verrouillé. Pas d'écran personnalisé possible (pas d'aperçu caméra avant de décrocher). | Indispensable (phase 2) |
| `CustomRingtonePlayer`, sonneries par liste | Sonnerie par liste de contacts | Un fichier son par configuration CallKit (`ringtoneSound`). Une sonnerie par liste semble faisable en changeant la configuration avant chaque appel ; à vérifier. | Phase 2 |
| `alanya/pip` (`PipBridge`) | Fenêtre flottante pendant un appel vidéo | `AVPictureInPictureController` alimenté image par image (iOS 15+). Avec le mode « voip », la caméra reste active en arrière-plan sans autorisation spéciale si l'application est compilée avec le SDK iOS 18. | Phase 2 |
| `alanya/ecran_verrouille`, proximité | Écran par-dessus le verrouillage, capteur de proximité | Le verrouillage est géré par CallKit. La proximité se règle avec `UIDevice.isProximityMonitoringEnabled`. | Phase 2 |
| `TransferForegroundService` | Finir un envoi lourd application quittée | Session `URLSession` d'arrière-plan (déjà dans `background_downloader`) + `beginBackgroundTask`. | Phase 3 |
| `alanya/capture` (`DetecteurCapture`) | « X a fait une capture d'écran » | `userDidTakeScreenshotNotification` : simple. | Phase 3 |
| `alanya/ecran_protege` | Bloquer captures et enregistrement | Pas d'API officielle. La technique connue (calque de champ sécurisé) est fragile, et Apple pourrait la refuser. On peut toujours **détecter** l'enregistrement d'écran (`UIScreen.isCaptured`) et masquer le contenu. | Phase 3, avec prudence |
| `alanya/chiffrement` (`ChiffrementAgb1`) | Chiffrement AES-GCM accéléré des médias | CryptoKit (`AES.GCM`). Le repli Dart existe déjà : ce n'est qu'une optimisation. Il faut garder le format AGB1 identique, à vérifier sur les vecteurs de test. | Phase 3 |
| `alanya/compression_video` | Compression avec débit imposé | `AVAssetWriter` avec débit cible. En attendant, `video_compress`. | Phase 3 |
| `alanya/signature` (images, documents, vidéos) | Signature incrustée aux quatre bords | Images et PDF : Core Graphics et PDFKit. Vidéo : `AVVideoComposition` + Core Animation. Le repli actuel (`null`) désactive la signature vidéo hors Android. | Phase 3 |
| `alanya/enregistrement` (`AppelEnregistreur`) | Enregistrer les deux voix d'un appel | Le plus risqué : `flutter_webrtc` n'expose pas sur iOS l'équivalent de `AudioTrackSink`. Il faudrait modifier le greffon. Désactivé sur iPhone dans un premier temps (c'est déjà le comportement du code Dart). | Phase 4, à décider |
| `alanya/appareil` | Marque et modèle | Identifiant du modèle d'iPhone (`utsname`). `device_registry.dart` gère déjà iOS (type 2). | Phase 1 |

## 4. Appels et notifications : le cœur du chantier

### 4.1 Appels entrants

Sur iPhone, une application fermée ne peut pas sonner avec une notification ordinaire. Le seul moyen fiable :

1. **Le serveur envoie une notification VoIP (PushKit)** directement aux serveurs d'Apple (APNs), pas par Firebase :
   - en-tête `apns-push-type: voip` ;
   - sujet `<identifiant de l'appli>.voip` ;
   - clé d'authentification `.p8` d'Apple.
2. **L'application déclare l'appel à CallKit immédiatement**, dans le gestionnaire PushKit natif, avant tout réseau ou connexion. `flutter_callkit_incoming` le fait dans l'`AppDelegate`.

🔴 **La règle d'Apple est stricte.** Depuis iOS 13, une notification VoIP qui n'aboutit pas à un appel déclaré fait tuer l'application. Si cela se répète, iOS **cesse de lui livrer les notifications VoIP**. Conséquences pour nous :

- Ne jamais envoyer de VoIP pour autre chose qu'un appel.
- L'annulation d'un appel (`call_cancelled`) doit passer par une notification ordinaire ou par le WebSocket, pas par une notification VoIP. Ce point est à trancher au moment de coder (voir le fil Apple ci-dessous).
- Tester sur un iPhone réel avec une version signée comme en production. Plusieurs développeurs signalent un fonctionnement en débogage et des pannes sur TestFlight.

**Son de l'appel avec WebRTC.** Il faut laisser CallKit activer la session audio, puis allumer l'audio WebRTC seulement à ce moment-là :

- régler `useManualAudio` ;
- activer l'audio de WebRTC dans `didActivate` et le couper dans `didDeactivate`.

Des pannes sont connues depuis iOS 18.4 (CallKit n'active pas toujours la session). Ce point est à surveiller.

**Chine.** Les applications qui utilisent CallKit sont en pratique retirées du magasin chinois : ne pas cocher la Chine à la publication. Je ne l'ai pas revérifié aujourd'hui.

### 4.2 Notifications de message

- **Pas de notifications « données seules » sur iPhone.** iOS les considère comme peu prioritaires et les limite. Il ne les livre pas du tout si l'utilisateur a fermé l'application. Le serveur doit envoyer aux iPhone une notification **visible** : titre et texte, `mutable-content: 1`.
- **Messages chiffrés.** Le serveur ne connaît pas le texte. Deux options :
  - **Version 1 (recommandée) :** « Nouveau message » avec le nom de l'expéditeur, que le serveur connaît.
  - **Plus tard :** une **extension de service de notification** en Swift qui déchiffre le message. Elle a environ 30 secondes et très peu de mémoire, et ne peut pas lancer le moteur Flutter. Il faudrait réimplémenter la lecture Signal en Swift et partager les clés par un groupe de Trousseau. C'est un gros chantier, à garder pour une version ultérieure.
- **Piste A (relève des messages à la notification).** Elle n'est pas fiable sur iPhone. La **piste B** (renvoi par l'expéditeur) et la relève à l'ouverture de l'application prennent le relais. Elles existent déjà.

## 5. Changements côté serveur

1. **`push.mjs` :**
   - Distinguer `android` et `ios` (la colonne `platform` existe déjà dans `PushDevice`).
   - Pour iOS : bloc `apns` avec `alert`, `sound`, `mutable-content` ; jamais de données seules pour les messages.
2. **Envoi VoIP :**
   - Nouveau module qui parle directement à APNs en HTTP/2, avec un jeton JWT ES256 signé par la clé `.p8`.
   - Faisable avec `node:http2` et `node:crypto`, sans nouvelle dépendance.
   - Il faut enregistrer le jeton VoIP de chaque iPhone : nouvelle plateforme `ios_voip` dans `PushDevice`, liée à l'appareil comme les autres jetons.
   - L'appel entrant (aujourd'hui `dataOnly: true`) part par ce chemin pour les iPhone.
3. **Liens universels :**
   - Ajouter `public/.well-known/apple-app-site-association`, à côté de `assetlinks.json`.
   - Contenu : l'identifiant `ÉQUIPE.com.alanya237.work` et les chemins `/u/*`, `/i/*`, `/g/*`.
   - Il doit être servi en `application/json`, sans redirection.
4. **Firebase :**
   - Déclarer l'application iOS dans Firebase et récupérer `GoogleService-Info.plist`.
   - Déposer la clé APNs `.p8` dans Firebase, pour les notifications ordinaires.
5. **Console :** rien d'obligatoire. On pourrait plus tard afficher la plateforme des appareils.

## 6. Compiler et publier sans Mac

| Besoin | Solution proposée |
|---|---|
| Compte Apple | **Apple Developer Program, 99 $/an.** Un compte **organisation** affiche « Alanya » comme éditeur, mais exige un numéro **D-U-N-S** (gratuit, quelques jours à deux semaines). |
| Créer le dossier `ios/` | `flutter create --platforms=ios --org com.alanya237 .` fonctionne sous Windows. Ensuite il faut éditer `Info.plist`, les droits (entitlements), le `Podfile` (iOS 15.5) et l'`AppDelegate.swift`. |
| Extensions (partage, plus tard notifications) | Ajouter une cible au projet Xcode sans Xcode est risqué. **Un Mac loué quelques heures** (MacinCloud ou similaire) ou un Mac mini d'occasion règle le problème. |
| Compilation et signature | **Codemagic** (déjà configuré pour Android) : machines Mac, signature automatique avec une clé API App Store Connect, envoi automatique sur TestFlight. Ajouter un flux `ios-build` à `codemagic.yaml`. Autre possibilité : GitHub Actions sur macOS avec les outils Codemagic. |
| Essais | **Un iPhone réel est obligatoire** (CallKit et PushKit ne marchent pas sur simulateur). Distribution des essais par **TestFlight**. |
| Mises à jour à distance | Shorebird gère iOS, si on veut le même mécanisme qu'ailleurs. |

## 7. Exigences d'Apple pour la publication

| Exigence | État chez nous |
|---|---|
| Suppression du compte **dans l'application** (règle 5.1.1(v)) | ✅ existe (`delete_account_screen.dart`) |
| Contenu des utilisateurs (règle 1.2) : signaler, bloquer, contact publié, filtrage | ✅ signaler et bloquer (18/11) ; contact dans les pages légales. ⚠️ « filtrage » : dans un fil chiffré, le serveur ne peut rien filtrer. Il faudra l'expliquer dans les notes à l'examinateur (signalement et modération). |
| Acceptation des conditions | ✅ `MentionAcceptation` à l'inscription. Ajouter notre contrat de licence dans App Store Connect. |
| Textes d'autorisation (`Info.plist`) | À écrire : caméra, micro, photos (lecture et ajout), position (en utilisation et toujours), Face ID, réseau local si nécessaire. Ils doivent dire précisément à quoi sert chaque accès. |
| Modes d'arrière-plan (règle 2.5.4) | `voip`, `audio`, `location`, `remote-notification`, chacun pour son vrai usage. |
| Position « toujours » | Réservée aux comptes d'entreprise (suivi des agents). L'écran d'information avant la demande existe ; Apple a déjà refusé des pré-écrans avec « Pas maintenant ». Un seul bouton « Continuer » qui mène à la demande du système. |
| Manifeste de confidentialité (`PrivacyInfo.xcprivacy`) | À créer : données collectées, API « à raison déclarée » (`UserDefaults`, dates de fichiers…). |
| Fiche « Confidentialité » d'App Store Connect | À remplir (proche du formulaire Sécurité des données de Google). |
| Chiffrement (conformité à l'export) | Nous utilisons nos propres algorithmes standards (Signal, AES-GCM), pas seulement ceux d'iOS. Pour **distribuer en France**, Apple demande la **déclaration de chiffrement française (ANSSI)**, examinée en un mois environ. Sinon, publier d'abord hors de France. |
| Connexion avec Apple | Pas exigée : nous n'avons pas de connexion par Google, Facebook, etc. |
| Compte de démonstration | À fournir à l'examinateur, avec un second compte pour tester un appel. |

## 8. Les phases

| Phase | Contenu | Durée estimée |
|---|---|---|
| **0. Préparation** | Compte Apple (D-U-N-S si organisation), iPhone de test, accès à un Mac, application iOS dans Firebase et clé APNs, flux Codemagic. | 1 à 2 semaines de calendrier (attente d'Apple), peu de code |
| **1. Socle** | Dossier `ios/`, `Podfile`, `Info.plist`, autorisations. Première version sur TestFlight : connexion, discussions, chiffrement, médias, groupes, statuts, notifications de message (texte générique), liens universels, enregistrement dans Photos. | 2 semaines |
| **2. Appels** | Serveur VoIP (APNs direct, jetons `ios_voip`), PushKit et CallKit, session audio WebRTC, appels audio puis vidéo, groupes et réunions, fenêtre flottante, proximité, sonneries. | 2 à 3 semaines |
| **3. Fonctions natives** | Extension de partage, capture d'écran signalée, protection d'écran (prudente), signature des images, documents et vidéos, compression vidéo, chiffrement CryptoKit, suivi de position en arrière-plan, transferts en arrière-plan. | 2 à 3 semaines |
| **4. Publication** | Manifeste de confidentialité, fiches et captures d'écran, notes à l'examinateur, déclaration ANSSI, corrections après la revue. Décision sur l'enregistrement d'appel. | 1 à 2 semaines + délais d'Apple |

**Total : environ 8 à 10 semaines de travail** pour une personne, auxquelles s'ajoutent l'attente du compte Apple, de la revue et de l'ANSSI. Chaque phase se termine par une version TestFlight essayée sur iPhone réel.

## 9. Risques

1. **Notifications VoIP mal utilisées :** application tuée, puis plus d'appels. C'est la règle la plus dangereuse ; le §4.1 la cadre.
2. **Son des appels :** les bogues connus de CallKit depuis iOS 18.4 imposent des essais sur plusieurs versions d'iOS.
3. **Protection d'écran :** la technique non officielle peut être refusée par Apple ou casser à une mise à jour d'iOS.
4. **Enregistrement des appels :** il faut modifier le greffon WebRTC. Il y a aussi des enjeux légaux.
5. **Suivi de position :** risque de refus si les textes et l'usage ne sont pas impeccables.
6. **Pas de Mac :** les extensions et le débogage natif sont pénibles sans Mac. Prévoir au moins une location.
7. **France :** pas de publication en France tant que la déclaration ANSSI n'est pas faite.

## 10. Décisions à prendre (toi ou le patron)

1. Compte Apple **organisation** (nom « Alanya », D-U-N-S) ou **individuel** (plus rapide, ton nom affiché) ?
2. **Mac :** location à l'heure, ou achat d'un Mac mini d'occasion ? Et quel **iPhone de test** ?
3. **Texte des notifications de message en version 1 :** « Nouveau message » avec le nom de l'expéditeur. D'accord ?
4. **France :** déposer la déclaration ANSSI dès maintenant, ou publier d'abord hors de France ?
5. **Fonctions réduites sur iPhone au départ :** enregistrement d'appel, protection d'écran, sonnerie par liste. Les accepte-t-on pour la première version ?

## Sources

- Rapport immédiat à CallKit et coupure des notifications VoIP : [Apple Developer Forums](https://developer.apple.com/forums/thread/775144), [fil 801446](https://developer.apple.com/forums/thread/801446), [débogage/TestFlight](https://developer.apple.com/forums/thread/799977), [VoIP pour terminer un appel](https://developer.apple.com/forums/thread/818104)
- `flutter_callkit_incoming` et PushKit : [documentation](https://www.mintlify.com/hiennguyen92/flutter_callkit_incoming/setup/pushkit), [dépannage](https://www.mintlify.com/hiennguyen92/flutter_callkit_incoming/troubleshooting)
- Session audio CallKit avec WebRTC : [fil iOS 18.4.1](https://developer.apple.com/forums/thread/783870?page=3), [LiveSwitch](https://developer.liveswitch.io/liveswitch-cloud/guides/ios-audio-session-management.html)
- Caméra en fenêtre flottante : [Stream](https://getstream.io/video/docs/ios/advanced/picture-in-picture/), [Agora](https://docs.agora.io/en/api-reference/faq/integration/multitasking)
- Notifications « données seules » sur iOS : [FlutterFire #9381](https://github.com/firebase/flutterfire/issues/9381), [Apple Developer Forums](https://developer.apple.com/forums/thread/677597)
- Extension de service de notification : [Apple](https://developer.apple.com/documentation/usernotifications/unnotificationserviceextension), [Kodeco](https://www.kodeco.com:443/books/push-notifications-by-tutorials/v4.0/chapters/10-modifying-the-payload)
- Envoi VoIP depuis un serveur : [guide APNs PushKit](https://cdn.jsdelivr.net/npm/@cometchat/skills@4.4.1/skills/cometchat-ios-calls/references/server-apns-pushkit.md), [archives Apple](https://developer-mdn.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/CommunicatingwithAPNs.html)
- Traduction ML Kit sur iOS : [pub.dev](https://pub.dev/documentation/google_mlkit_translation/latest/), [google_mlkit_commons](https://pub.dev/documentation/google_mlkit_commons/latest/)
- Protection d'écran : [Apple Developer Forums](https://developer.apple.com/forums/thread/838583), [screen_guard](https://pub.dev/packages/screen_guard)
- Règles de l'App Store : [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/), [règle 1.2](https://developer.apple.com/forums/thread/807358), [textes d'autorisation](https://developer.apple.com/help/app-review/guideline-reference/5-1-1-purpose-strings), [position « toujours »](https://developer.apple.com/documentation/bundleresources/choosing-the-location-services-authorization-to-request), [pré-écran refusé](https://developer.apple.com/forums/thread/817672)
- Chiffrement et France : [Apple – export compliance](https://developer.apple.com/help/app-store-connect/reference/export-compliance-documentation-for-encryption), [Cryptomator](https://cryptomator.org/blog/2016/06/16/indepth-french-app-store/)
- Codemagic et iOS : [première version signée](https://docs.codemagic.io/yaml-quick-start/first-signed-build/), [signature en ligne de commande](https://blog.codemagic.io/ios-code-signing-with-cli-tools)
