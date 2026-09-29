import 'alanya_id_formatter.dart';

/// LES LIENS ALANYA — ce que contient un QR code, et comment le relire.
///
/// Un QR qui ne contient que le numéro (`82312187`) ne fait RIEN quand on le
/// scanne avec l'appareil photo du téléphone : il s'affiche comme du texte.
/// Un lien `https://alanyavox.com/u/82312187`, lui, est ouvert par le
/// téléphone — dans l'application si elle est installée (liens d'application
/// Android), sur la page web sinon.
///
/// Deux formes, et deux seulement :
///   · `/u/<Alanya ID>` — le QR PERMANENT de l'écran Profil ;
///   · `/i/<jeton>`     — l'invitation à usage unique (15 min), où l'Alanya ID
///                        n'apparaît pas : le serveur seul sait à qui il mène.
///
/// ⚠️ La fabrication et la lecture vivent dans le MÊME fichier : deux endroits
/// qui décrivent un format finissent toujours par ne plus être d'accord, et
/// l'écart ne se voit qu'au moment où un QR n'est plus reconnu.
///
/// Ce fichier n'importe rien de Flutter, pour rester exécutable par un test
/// seul (voir `test/lien_alanya_test.dart`).

/// L'hôte des liens. Écrit en dur, et non tiré de `ServerConfig.apiBase` :
/// le manifeste Android déclare ce même hôte pour ouvrir l'application, et un
/// `--dart-define=API_URL` de test produirait sinon des QR que le téléphone
/// ne reconnaît plus.
const String hoteLiensAlanya = 'alanyavox.com';

/// Le lien du QR permanent d'un compte.
String lienProfil(String publicNumber) =>
    'https://$hoteLiensAlanya/u/${stripAlanyaId(publicNumber)}';

/// Le lien d'une invitation à usage unique.
String lienInvitation(String jeton) => 'https://$hoteLiensAlanya/i/$jeton';

/// Ce vers quoi mène un code scanné ou un lien ouvert.
sealed class CibleLien {
  const CibleLien();
}

/// Un compte, désigné par son Alanya ID.
class CibleProfil extends CibleLien {
  final String publicNumber;
  const CibleProfil(this.publicNumber);

  @override
  bool operator ==(Object other) =>
      other is CibleProfil && other.publicNumber == publicNumber;
  @override
  int get hashCode => publicNumber.hashCode;
  @override
  String toString() => 'CibleProfil($publicNumber)';
}

/// Une invitation à usage unique, désignée par son jeton.
class CibleInvitation extends CibleLien {
  final String jeton;
  const CibleInvitation(this.jeton);

  @override
  bool operator ==(Object other) =>
      other is CibleInvitation && other.jeton == jeton;
  @override
  int get hashCode => jeton.hashCode;
  @override
  String toString() => 'CibleInvitation($jeton)';
}

/// Un jeton est du base64url (alphabet `A-Z a-z 0-9 - _`). Bornes larges :
/// le serveur en émet de 22 caractères (128 bits), et c'est lui qui juge de
/// sa validité — ce contrôle écarte seulement ce qui ne peut pas en être un.
final _formeJeton = RegExp(r'^[A-Za-z0-9_-]{16,64}$');

/// Relit le contenu d'un QR code ou d'un lien ouvert.
///
/// Renvoie nul pour tout ce qui n'est pas à nous : un QR de site web, de wifi,
/// un lien d'un autre domaine. Accepte aussi le NUMÉRO SEUL, qui est ce que
/// contenaient les QR du profil avant les liens — ils sont encore affichés
/// sur des téléphones qui n'ont pas été mis à jour.
CibleLien? analyserLienAlanya(String brut) {
  final texte = brut.trim();
  if (texte.isEmpty) return null;

  // Ancien format : des chiffres, éventuellement groupés par des espaces.
  // ⚠️ Pas `stripAlanyaId` sur n'importe quoi : « abc123 » en tirerait
  // « 123 », un Alanya ID valide qu'on n'a jamais scanné.
  if (RegExp(r'^[\d\s]+$').hasMatch(texte)) {
    return estAlanyaIdValide(texte) ? CibleProfil(stripAlanyaId(texte)) : null;
  }

  final uri = Uri.tryParse(texte);
  if (uri == null) return null;
  if (uri.scheme != 'https' && uri.scheme != 'http') return null;
  final hote = uri.host.toLowerCase();
  if (hote != hoteLiensAlanya && hote != 'www.$hoteLiensAlanya') return null;

  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.length != 2) return null;
  final valeur = segments[1];

  switch (segments[0]) {
    case 'u':
      return RegExp(r'^\d+$').hasMatch(valeur) && estAlanyaIdValide(valeur)
          ? CibleProfil(valeur)
          : null;
    case 'i':
      return _formeJeton.hasMatch(valeur) ? CibleInvitation(valeur) : null;
    default:
      return null;
  }
}
