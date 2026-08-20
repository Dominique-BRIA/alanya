import 'centre_transferts.dart';
import 'downloader.dart';

/// Télécharge un fichier **en l'annonçant** au centre de transferts.
///
/// POURQUOI UN ENROBAGE. Cinq écrans téléchargent (image, vidéo, PDF, galerie,
/// fil de discussion). Y recopier la déclaration, l'avancement, la réussite et
/// l'échec, ce serait cinq fois la même comptabilité — et la certitude qu'un
/// des cinq oublierait de refermer sa notification, la laissant à vie.
///
/// ⚠️ **L'identité du transfert ne peut pas être l'URL** : elle porte un jeton
/// d'accès, qui change à chaque rafraîchissement. Deux téléchargements du même
/// fichier auraient alors deux notifications. On la bâtit sur le nom du fichier
/// et l'instant du clic, fourni par l'appelant.
Future<String?> telechargerEnSuivant(
  String url,
  String nomFichier, {
  required String idTransfert,
  bool ouvrirEnsuite = false,
}) async {
  CentreTransferts.instance.demarrer(
    id: idTransfert,
    sorte: SorteTransfert.telechargement,
    titre: nomFichier,
  );
  try {
    final chemin = ouvrirEnsuite
        ? await downloadUrl(
            url,
            nomFichier,
            surProgression: (f) =>
                CentreTransferts.instance.avancer(idTransfert, f),
          )
        : await downloadOnly(
            url,
            nomFichier,
            surProgression: (f) =>
                CentreTransferts.instance.avancer(idTransfert, f),
          );
    // `null` n'est pas une exception ici : le téléchargeur signale ses échecs
    // par un retour nul. Les traiter comme un succès laisserait la notification
    // disparaître alors que rien n'a été enregistré.
    if (chemin == null) {
      CentreTransferts.instance.echouer(idTransfert);
    } else {
      CentreTransferts.instance.reussir(idTransfert);
    }
    return chemin;
  } catch (_) {
    CentreTransferts.instance.echouer(idTransfert);
    return null;
  }
}
