import 'dart:math';

import 'package:flutter/services.dart';

/// L'EMPREINTE NUMÉRIQUE d'une copie signée, telle qu'on la lit et la saisit
/// (24/10/2026).
///
/// Elle compte 32 caractères hexadécimaux. Écrite d'un bloc, elle est
/// illisible et se recopie mal ; elle s'affiche donc en HUIT BLOCS DE QUATRE,
/// en majuscules — « 3F9A 0C1E 5B7D 2A4C 6E8F 0A1B 2C3D 4E5F » —, comme sur
/// les bords du document.
class Empreinte {
  Empreinte._();

  static const longueur = 32;
  static const taillesBloc = 4;

  /// Les seuls caractères permis, en majuscules (« 0-9 A-F »). Tout le reste
  /// (espaces, tirets, retours à la ligne d'un copier-coller) tombe.
  static String nettoyer(String brut) =>
      brut.toUpperCase().replaceAll(RegExp('[^0-9A-F]'), '');

  /// « 3F9A0C1E… » → « 3F9A 0C1E … ».
  static String enBlocs(String brut) {
    final n = nettoyer(brut);
    return [
      for (var i = 0; i < n.length; i += taillesBloc)
        n.substring(i, min(i + taillesBloc, n.length)),
    ].join(' ');
  }

  /// La forme attendue par le serveur : 32 caractères, minuscules.
  static String? pourServeur(String brut) {
    final n = nettoyer(brut);
    return n.length == longueur ? n.toLowerCase() : null;
  }
}

/// La saisie en blocs : chaque frappe ou collage est nettoyé, mis en
/// majuscules et regroupé par quatre, et le curseur reste derrière le même
/// caractère utile (les espaces ne comptent pas).
class FormateurEmpreinte extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue ancien,
    TextEditingValue nouveau,
  ) {
    final texte = nouveau.text;
    final curseur = nouveau.selection.end.clamp(0, texte.length);
    // Combien de caractères UTILES avant le curseur.
    final utilesAvant = min(
      Empreinte.nettoyer(texte.substring(0, curseur)).length,
      Empreinte.longueur,
    );
    final propre = Empreinte.nettoyer(texte);
    final borne = propre.substring(0, min(propre.length, Empreinte.longueur));
    final formate = Empreinte.enBlocs(borne);
    // Position dans le texte formaté : les utiles, plus une espace par bloc
    // complet déjà franchi.
    var position =
        utilesAvant +
        (utilesAvant == 0 ? 0 : (utilesAvant - 1) ~/ Empreinte.taillesBloc);
    position = min(position, formate.length);
    return TextEditingValue(
      text: formate,
      selection: TextSelection.collapsed(offset: position),
    );
  }
}
