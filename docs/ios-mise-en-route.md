# Alanya Work sur iPhone : mise en route

Le code iOS est sur la branche `feat/ios` (mobile et serveur). Ce document liste ce qui reste à faire à la main, dans l'ordre.

## 1. Compte Apple

1. Ouvrir un compte **Apple Developer Program** (99 $ par an).
   - Compte « organisation » : l'éditeur affiché sera « Alanya ». Il faut un numéro D-U-N-S, gratuit, obtenu en quelques jours.
2. Noter l'**identifiant d'équipe** (Team ID, 10 caractères), visible sur developer.apple.com, rubrique Membership.
3. Dans Certificates, Identifiers & Profiles, onglet Identifiers, créer :
   - l'identifiant `com.alanya237.work`, avec les capacités Push Notifications, Associated Domains, App Groups et Background Modes (Voice over IP) ;
   - l'identifiant `com.alanya237.work.ShareExtension`, avec la capacité App Groups ;
   - le groupe d'applications `group.com.alanya237.work`, rattaché aux deux identifiants.
4. Dans Keys, créer une clé **Apple Push Notifications service (APNs)**.
   - Télécharger le fichier `.p8` : il ne se télécharge qu'une fois.
   - Noter son identifiant (Key ID).

## 2. Firebase (notifications de message)

1. Dans la console Firebase, au même projet qu'Android : ajouter une application iOS avec l'identifiant `com.alanya237.work`.
2. Télécharger `GoogleService-Info.plist` et le déposer dans `ios/Runner/`. La compilation le copie automatiquement ; sans lui, les notifications restent inactives.
3. Dans la console Firebase, Paramètres du projet, onglet Cloud Messaging, application iOS : déposer la **même clé `.p8`**, avec le Key ID et le Team ID.

## 3. Serveur (appels et liens)

À ajouter dans le `.env` de production, puis redéployer la branche serveur :

```
APNS_TEAM_ID=XXXXXXXXXX           # identifiant d'équipe
APNS_KEY_ID=YYYYYYYYYY            # identifiant de la clé .p8
APNS_CLE_P8_CHEMIN=/home/ubuntu/cles/AuthKey_YYYYYYYYYY.p8
# APNS_SANDBOX=1                  # seulement pour une version lancée depuis Xcode
```

- **Appels :** dès ces réglages, les appels vers un iPhone partent par notification VoIP (`apns-voip.mjs`).
- **Liens :** `https://alanyavox.com/.well-known/apple-app-site-association` répond alors avec l'identifiant de l'application ; les liens `/u/`, `/i/` et `/g/` s'ouvrent dans l'application.
- **Contrôle :** le banc `scripts/ios-push-banc.mjs` vérifie toute la chaîne, sur la base de test seulement.

## 4. Compiler, signer, essayer

- **Chaque poussée sur `feat/ios`** lance `.github/workflows/build-ios.yml`, qui compile sans signature pour vérifier que tout compile. Les erreurs apparaissent en annotations.
- **Signer et envoyer sur TestFlight :**
  1. Dans Codemagic, Integrations, Developer Portal, ajouter une clé API App Store Connect nommée « Alanya App Store Connect ».
  2. Dans App Store Connect, créer l'application `com.alanya237.work`.
  3. Lancer à la main le flux `ios-testflight` de `codemagic.yaml`.
- **Essais :** sur un **iPhone réel**, via TestFlight. Les appels (CallKit, PushKit) ne fonctionnent pas sur le simulateur.

## 5. À vérifier sur l'iPhone

1. Un appel reçu application **tuée**, puis écran **verrouillé** : CallKit sonne. Décrocher : le son passe dans les deux sens. Refuser : l'appelant arrête de sonner.
2. Un appel annulé par l'appelant pendant qu'il sonne : l'écran CallKit se ferme.
3. Un appel vidéo, puis la touche Accueil : la fenêtre flottante montre le correspondant.
4. Les sonneries : la sonnerie Alanya, puis celle d'une liste de contacts.
5. Les liens `/u/`, `/i/`, `/g/` ouverts depuis Notes ou Messages.
6. « Partager vers Alanya Work » depuis Photos.
7. Un message à vue unique : capture d'écran (le contenu doit être absent) et enregistrement d'écran (voile noir).
8. Un document sensible téléchargé : signature aux bords (image, PDF, vidéo).
9. Un enregistrement d'appel (compte qui y a droit) : les deux voix dans le fichier mixé.
10. Le suivi de position d'un agent : l'application en arrière-plan continue d'envoyer sa position, avec l'indicateur bleu d'iOS.

## 6. Publication

Les exigences d'Apple sont décrites dans `docs/plan-version-ios.md`, section 7 :
- la fiche « Confidentialité » ;
- les notes à l'examinateur, avec deux comptes de démonstration ;
- la justification de la position « toujours » ;
- la déclaration de chiffrement française (ANSSI), nécessaire pour publier en France.
