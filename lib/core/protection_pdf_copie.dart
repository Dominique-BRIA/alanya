import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:syncfusion_flutter_pdf/pdf.dart';
// Le dictionnaire Info d'un PDF n'a pas d'accès public pour des champs
// libres : on passe par l'aide interne de la bibliothèque (voir [_ecrireMeta]).
// ignore: implementation_imports
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/pdf_document/pdf_document_information.dart'
    show PdfDocumentInformationHelper;
// ignore: implementation_imports
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_dictionary.dart'
    show PdfDictionary;

import '../services/e2ee/e2ee_media.dart' show ProtectionPdf;

/// LA COPIE PROTÉGÉE D'UN PDF SENSIBLE (24/10/2026, demande du user).
///
/// Bibliothèque : **Syncfusion Flutter PDF** (`syncfusion_flutter_pdf`),
/// utilisée sous la **Syncfusion Community License**
/// (https://www.syncfusion.com/products/communitylicense). C'est elle qui sait
/// chiffrer un PDF (mot de passe d'ouverture, mot de passe propriétaire,
/// permissions) — PdfBox-Android, qui signe les autres copies, ne le fait pas
/// aussi simplement.
///
/// Ce qu'elle fait de la copie qui sort :
///
/// * AVEC mot de passe : plus de texte aux quatre bords — seulement le numéro
///   Alanya de QUI TÉLÉCHARGE, en chiffres seuls, EN HAUT À DROITE de chaque
///   page ([coin]) ; puis les métadonnées et le chiffrement.
/// * SANS mot de passe mais sans impression : la copie arrive déjà signée aux
///   quatre bords (`SignatureDocument.kt`), on n'y ajoute que la restriction.
///
/// 🔴 LES MÉTADONNÉES RESTENT RECONNAISSABLES. `DetecteurCopieSignee` cherche
/// le NOM de champ « Empreinte#20numerique » dans les octets : un nom de PDF
/// n'est jamais chiffré (seules les chaînes le sont), et la table de
/// références classique garde le dictionnaire Info hors des flux compressés.
///
/// ⚠️ DART PUR CÔTÉ CALCUL : appelée par `compute`, dans un isolat — un PDF de
/// cent pages ne doit pas figer l'écran.
class CopiePdfProtegee {
  CopiePdfProtegee({
    required this.octets,
    required this.protection,
    this.coin,
    this.meta = const {},
  });

  final Uint8List octets;
  final ProtectionPdf protection;

  /// Le texte du coin supérieur droit (le numéro, chiffres seuls), ou `null`
  /// pour ne rien écrire (la copie porte déjà ses quatre bords).
  final String? coin;

  /// Les champs du dictionnaire Info (`SignatureSortie.metadonnees`).
  final Map<String, String> meta;
}

/// Rouge de la signature, le même que les quatre bords (`ROUGE` du natif).
final _rouge = PdfColor(0xE5, 0x39, 0x35);

/// Fabrique la copie protégée. Lève si le PDF est illisible (déjà chiffré par
/// exemple) : l'appelant rend alors la copie telle quelle.
Uint8List protegerPdf(CopiePdfProtegee p) {
  final doc = PdfDocument(inputBytes: p.octets);
  try {
    final coin = p.coin;
    if (coin != null && coin.isNotEmpty) {
      for (var i = 0; i < doc.pages.count; i++) {
        _ecrireCoin(doc.pages[i], coin);
      }
    }
    _ecrireMeta(doc, p.meta);

    // Le dictionnaire Info hors d'un flux compressé (voir plus haut).
    doc.fileStructure
      ..incrementalUpdate = false
      ..crossReferenceType = PdfCrossReferenceType.crossReferenceTable;

    final s = doc.security
      ..algorithm = PdfEncryptionAlgorithm.aesx256BitRevision6
      ..ownerPassword = p.protection.proprietaire
      ..userPassword = p.protection.ouverture ?? '';
    s.permissions.clear();
    s.permissions.addAll([
      // Les lecteurs d'écran gardent l'accès au texte.
      PdfPermissionsFlags.accessibilityCopyContent,
      if (p.protection.imprimer) ...[
        PdfPermissionsFlags.print,
        PdfPermissionsFlags.fullQualityPrint,
      ],
    ]);
    return Uint8List.fromList(doc.saveSync());
  } finally {
    doc.dispose();
  }
}

/// Le numéro en haut à droite de la page, par-dessus le contenu.
///
/// Taille proportionnée à la page comme les quatre bords (entre 7 et 12 pt),
/// un peu plus grande puisqu'il est seul.
void _ecrireCoin(PdfPage page, String texte) {
  final taille = page.getClientSize();
  final court = taille.width < taille.height ? taille.width : taille.height;
  final corps = (court / 50).clamp(7.0, 12.0);
  final police = PdfStandardFont(
    PdfFontFamily.helvetica,
    corps,
    style: PdfFontStyle.bold,
  );
  final mesure = police.measureString(texte);
  final marge = corps * 1.2;
  page.graphics.drawString(
    texte,
    police,
    brush: PdfSolidBrush(_rouge),
    bounds: Rect.fromLTWH(
      taille.width - marge - mesure.width,
      marge,
      mesure.width + 1,
      mesure.height,
    ),
  );
}

/// Les champs libres du dictionnaire Info, sous les noms de `CleMeta`.
void _ecrireMeta(PdfDocument doc, Map<String, String> meta) {
  if (meta.isEmpty) return;
  final info = PdfDocumentInformationHelper.getHelper(
    doc.documentInformation,
  ).element;
  if (info is! PdfDictionary) return;
  meta.forEach(info.setString);
}
