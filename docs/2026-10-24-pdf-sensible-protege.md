# PDF sensible protégé (mot de passe, impression)

*Fonction du 24/10/2026, demandée par le patron. Mobile d'abord ; le web suivra.*

## Ce que fait la fonction

À l'envoi d'un **PDF sensible**, l'expéditeur règle une fois, pour tous les PDF sensibles de l'envoi :

- **autoriser l'impression** ou non ;
- **protéger par mot de passe** ou non. S'il en met un, il en saisit deux :
  - le mot de passe **d'ouverture**, pour ouvrir la copie téléchargée ;
  - le mot de passe **propriétaire**, qui lève les restrictions (l'impression).

  Seule règle : 4 caractères au moins chacun, chiffres ou lettres. Les deux peuvent être identiques ; dans ce cas, celui qui ouvre la copie avec ce mot de passe a aussi les droits du propriétaire, impression comprise.

Sous le message PDF :

- **chez l'expéditeur**, les deux mots de passe sont affichés en clair ;
- **chez le destinataire**, seul le mot de passe d'ouverture est affiché, **une seule fois** (bouton « Voir le mot de passe (une seule fois) »). Le mot de passe propriétaire ne lui est jamais montré.

La copie **téléchargée** :

- **avec mot de passe** : plus de texte aux quatre bords. Seule l'**empreinte numérique** de la personne qui télécharge est écrite, **en haut à droite** de chaque page (le numéro Alanya jusqu'au 25/10/2026 ; il reste dans les métadonnées). Le fichier est chiffré en AES-256, avec l'impression interdite si l'expéditeur l'a choisi ;
- **sans mot de passe, impression interdite** : la signature habituelle aux quatre bords, plus l'interdiction d'imprimer. Le mot de passe propriétaire est alors tiré au hasard et personne ne le voit.

Dans Alanya, le document reste lisible dans la visionneuse protégée, comme avant. Les métadonnées (empreinte numérique, Alanya ID, appareil…) sont toujours écrites, et une copie téléchargée reste reconnue si on essaie de la renvoyer en document sensible.

Si la protection échoue, le téléchargement échoue. Rien ne sort sans la protection que l'expéditeur a demandée.

## Où sont les mots de passe

Ils voyagent **dans l'enveloppe chiffrée** du message (champ `protection` du descripteur de média), jamais en clair : **le serveur ne les voit pas**. La vue unique est retenue sur l'appareil du destinataire.

## Bibliothèque : Syncfusion Flutter PDF

Le chiffrement et le dessin de l'empreinte passent par **[Syncfusion Flutter PDF](https://pub.dev/packages/syncfusion_flutter_pdf)** (`syncfusion_flutter_pdf`), utilisée sous la **[Syncfusion Community License](https://www.syncfusion.com/products/communitylicense)**.

⚠️ Cette licence gratuite a des conditions : l'entreprise doit rester sous des plafonds de chiffre d'affaires, de développeurs et de salariés fixés par Syncfusion. Les vérifier sur la page de la licence et s'inscrire au programme Community avec le compte de l'entreprise. Au-delà de ces plafonds, une licence payante est nécessaire.

## Fichiers (mobile)

| Rôle | Fichier |
|---|---|
| Format (descripteur chiffré) | `lib/services/e2ee/e2ee_media.dart` — `ProtectionPdf` |
| Copie protégée (Syncfusion) | `lib/core/protection_pdf_copie.dart` |
| Branchement au téléchargement | `lib/core/signature_document.dart` — `_signerProtege` |
| Dialogue à l'envoi | `lib/widgets/dialogue_protection_pdf.dart` |
| Affichage sous le message | `lib/features/chat/widgets/infos_protection_pdf.dart` |
| Tests | `test/protection_pdf_test.dart`, `test/protection_pdf_ui_test.dart` |

## Reste à faire

- **Le web** : le même format (`protection` dans le descripteur), le dialogue, l'affichage et la copie protégée avec une bibliothèque JavaScript équivalente. En attendant, un PDF protégé envoyé du mobile s'ouvre normalement sur le web, mais sa copie téléchargée depuis le web ne sera pas encore protégée.
