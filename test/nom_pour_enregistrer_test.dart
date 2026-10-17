// LE NOM D'UN MÉDIA CHIFFRÉ ENREGISTRÉ DEPUIS LA GALERIE.
//
// Le fichier du serveur s'appelle « chiffre.bin » : on garde le nom d'origine
// quand le descripteur le porte, sinon on en fabrique un avec la bonne
// extension.

import 'package:alanya/features/chat/screens/media_gallery_viewer.dart';
import 'package:alanya/services/e2ee/e2ee_media.dart';
import 'package:flutter_test/flutter_test.dart';

DescripteurMedia _d(String mime, {String? nom}) => DescripteurMedia(
    id: 'm', cle: 'k', empreinte: 'e', taille: 1, mime: mime, nom: nom);

void main() {
  final t = DateTime(2026, 10, 6, 9, 5, 7);

  test("le nom d'origine est gardé", () {
    expect(nomPourEnregistrer(_d('application/pdf', nom: 'devis.pdf')), 'devis.pdf');
  });

  test('sans nom : daté, avec l’extension du vrai type', () {
    expect(nomPourEnregistrer(_d('image/jpeg'), maintenant: t), 'Alanya_20261006_090507.jpg');
    expect(nomPourEnregistrer(_d('video/mp4'), maintenant: t), 'Alanya_20261006_090507.mp4');
  });

  test('type inconnu : .bin plutôt qu’une extension inventée', () {
    expect(nomPourEnregistrer(_d('application/x-truc'), maintenant: t), 'Alanya_20261006_090507.bin');
  });
}
