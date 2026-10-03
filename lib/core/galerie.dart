import 'package:photo_manager/photo_manager.dart';

/// ACCÈS À LA GALERIE DU TÉLÉPHONE — la permission, et l'ordre des médias.
///
/// Ces deux règles vivent ici parce que **les deux sélecteurs doivent les
/// partager** : la feuille d'envoi (`widgets/media/media_picker_sheet.dart`) et
/// le sélecteur plein écran (`features/chat/screens/media_gallery_picker_screen.dart`).
/// Chacun portait la sienne, et chacun s'est trompé de la même façon.

/// Les médias du **plus RÉCENT au plus ancien**.
///
/// 🔴 SANS CET ORDRE EXPLICITE, LA GALERIE REMONTE À L'ENVERS (constaté sur
/// device le 30/08/2026 : « les fichiers sont classés des plus anciens aux plus
/// récents »).
///
/// Les deux sélecteurs appelaient `getAssetPathList` **sans `filterOption`** :
/// aucun ordre n'était alors demandé, et Android rend les médias dans l'ordre
/// naturel de `MediaStore`, c'est-à-dire par identifiant croissant — donc la
/// plus vieille photo du téléphone en premier. Un ordre par défaut existe dans
/// `OrderOption`, mais il ne s'applique QUE si l'on fournit un
/// `FilterOptionGroup` ; ne rien passer ne prend pas ce défaut, ça ne demande
/// rien.
///
/// ⚠️ L'ordre se pose sur l'ALBUM, pas sur la page : c'est
/// `getAssetPathList(filterOption:)` qui le porte, et `getAssetListPaged` s'en
/// sert ensuite. Le passer à la pagination ne servirait à rien.
///
/// `createDate` et non `modifiedDate` : une photo retouchée ou recopiée
/// remonterait en tête alors qu'elle est ancienne, et la date de prise de vue
/// est celle que l'utilisateur a en tête quand il cherche « la photo de tout à
/// l'heure ».
final FilterOptionGroup ordreRecentDAbord = FilterOptionGroup(
  orders: const [
    OrderOption(type: OrderOptionType.createDate, asc: false),
  ],
);

/// L'application peut-elle lire la galerie ?
///
/// 🔴 « PARTIEL » COMPTE COMME UN OUI, et c'est tout l'objet de cette fonction.
///
/// Les deux sélecteurs testaient `permission.isAuth`, qui n'est vrai que pour
/// l'accès **complet**. Or depuis Android 14, la boîte de dialogue propose
/// « Sélectionner des photos » — un accès **partiel**, que beaucoup
/// d'utilisateurs choisissent parce qu'il est présenté en premier. Ce choix rend
/// `PermissionState.limited`, donc `isAuth == false`, donc nos sélecteurs se
/// croyaient REFUSÉS et retombaient sur le sélecteur de fichiers du système.
///
/// C'est ce repli qui expliquait les quatre défauts constatés le 30/08/2026 :
/// l'ordre du plus ancien au plus récent, l'absence de bouton d'envoi, la
/// fenêtre où il faut sélectionner une seconde fois, et la réouverture à
/// l'endroit de la dernière sélection — quatre comportements du sélecteur
/// SYSTÈME, dont aucun ne vient de notre code.
///
/// Le greffon expose exactement la bonne question sous le nom `hasAccess`
/// (complet **ou** partiel) : c'est elle qu'il fallait poser.
bool accesUtilisable(PermissionState etat) => etat.hasAccess;

/// L'accès est-il PARTIEL ? Le cas échéant, l'utilisateur ne voit qu'une partie
/// de sa galerie, et il faut lui offrir d'en ajouter — sans quoi il cherchera
/// une photo que l'application n'a tout simplement pas le droit de lui montrer.
bool accesPartiel(PermissionState etat) => etat.isLimited;
