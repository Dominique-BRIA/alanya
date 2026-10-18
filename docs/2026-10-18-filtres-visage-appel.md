# Filtres de visage pendant un appel vidéo (barbe, forme du visage…)

*Recherche du 18/10/2026, demandée par le patron : « pendant l'appel vidéo, peut-on ajouter la barbe, changer la forme de la tête, comme Snapchat ? »*

## Réponse courte

**Oui, c'est faisable dans Alanya, sans refaire les appels.** La version de `flutter_webrtc` qu'utilise l'application (0.12.12) laisse passer **chaque image de la caméra** par un point d'accroche Android, avant son envoi à l'interlocuteur : `LocalVideoTrack.addProcessor(ExternalVideoFrameProcessing)`. Un moteur de filtres branché là modifie l'image envoyée ; tout le reste (connexion, son, réseau) ne change pas.

Ce qui reste à choisir, c'est **le moteur** qui détecte le visage et dessine la barbe ou déforme la tête.

## Les trois moteurs possibles

| | **Banuba Face AR SDK** (commercial) | **Snap Camera Kit** (Snap) | **MediaPipe** (Google, gratuit) |
|---|---|---|---|
| Ce qu'on obtient | Masques, barbes, maquillage, déformations prêts à l'emploi | Les « Lenses » de Snapchat, ou les nôtres faites dans Lens Studio | Les 478 points du visage ; le dessin est à notre charge |
| Flutter | Paquet officiel `banuba_sdk` sur pub.dev | Pas de paquet Flutter : SDK Android/iOS natif | Bibliothèque Android `tasks-vision` |
| Appels vidéo | Annoncé compatible WebRTC (et Agora, OpenTok) ; Banuba conseille l'intégration native | Non documenté pour les appels | À brancher nous-mêmes sur l'accroche ci-dessus |
| Coût | Licence payante (sur devis) | Accès sur demande, validé par Snap ; gratuit selon une déclaration de Snap de 2023, à vérifier | Gratuit |
| Effort pour nous | Moyen : brancher le SDK sur l'accroche WebRTC | Moyen à fort, et dépend de l'accord de Snap | Fort : il faut dessiner chaque effet (barbe, déformation) et tenir 30 images/s |

DeepAR, autre SDK connu, a un support Flutter tenu par la communauté et a été racheté par Zalando en avril 2025 : avenir incertain, je ne le recommande pas.

## Recommandation

1. **Démo rapide (2 à 3 jours)** : MediaPipe + une barbe dessinée sur les points du menton, branchée sur `addProcessor`. Elle prouve que le circuit marche sur nos téléphones, et mesure la charge sur un appareil d'entrée de gamme.
2. **Pour un vrai catalogue d'effets** (déformer la tête, masques animés) : demander un devis et un essai à **Banuba**, ou un accès **Snap Camera Kit**. Dessiner soi-même des déformations de qualité Snapchat coûterait beaucoup plus cher que la licence.

## Points d'attention

- **Le web** : l'accroche décrite est Android. Sur le navigateur, il faudrait un traitement de la vidéo à part.
- **Les téléphones anciens** : détecter un visage 30 fois par seconde pendant un appel chauffe et consomme. Prévoir de désactiver l'effet sous un certain niveau de performance.
- **L'interlocuteur voit l'effet** : il est appliqué avant l'envoi, comme sur Snapchat.

## Sources

- [Banuba — Face Filters SDK](https://www.banuba.com/facear-sdk/face-filters)
- [Banuba — Best Flutter AR SDKs in 2026](https://www.banuba.com/blog/best-flutter-ar-sdks-in-reviewed-for-production-apps)
- [Banuba — 5 Best Face Filters SDKs (2026 Comparison)](https://www.banuba.com/blog/best-face-filters-sdks-comparison)
- [Banuba — Beauty AR SDK (compatibilité WebRTC)](https://www.banuba.com/facear-sdk/beauty-ar)
- [Communauté Banuba — flutter_webrtc et Face AR SDK](https://community.banuba.com/t/is-it-possible-to-use-flutter-webrtc-sdk-and-face-ar-sdk-on-flutter/146)
- [Snap — Camera Kit (accès et fonctionnement)](https://ar.snap.com/blog/snap-camera-kit-ar-sdk)
- [Snap — FAQ Camera Kit](https://developers.snap.com/camera-kit/faq)
- [Communauté Snap — tarif de Camera Kit (2023)](https://community.snap.com/snapar/discussion/comment/3973)
- [Google — MediaPipe Face Landmarker pour Android](https://developers.google.com/edge/mediapipe/solutions/vision/face_landmarker/android)
- Code de `flutter_webrtc` 0.12.12 : `android/src/main/java/com/cloudwebrtc/webrtc/video/LocalVideoTrack.java` (interface `ExternalVideoFrameProcessing`)
