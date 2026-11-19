import AVFoundation
import Flutter
import ImageIO
import PDFKit
import UIKit
import UniformTypeIdentifiers

/// LA COPIE SIGNÉE D'UN DOCUMENT SENSIBLE — portage iOS de
/// `SignatureDocument.kt` et `SignatureVideo.kt` (19/11/2026).
///
/// Même contrat (`signature_document.dart`) :
///   · `signer { entree, sortie, mime, bords, meta }` → `{ chemin, mime }` ;
///     PDF : le texte de la signature aux quatre bords de chaque page, en
///     rouge, et les métadonnées ; image : les bords (blanc cerclé de noir),
///     puis les métadonnées EXIF ;
///   · `signerVideo { entree, sortie, bords }` → `{ chemin, mime }` : la vidéo
///     réencodée en MP4 avec les bords incrustés.
/// Une erreur rend `ECHEC` : le Dart sort alors la copie sans signature
/// (sauf pour un PDF protégé, qu'il refuse de laisser sortir).
final class SignatureDocument {
  static let shared = SignatureDocument()

  private let file = DispatchQueue(label: "alanya.signature", qos: .userInitiated)
  private let coteMax: CGFloat = 4096
  private let cleApplication = "Application"
  private let cleAlanyaId = "Alanya ID"
  private let cleEmpreinte = "Empreinte numerique"

  func traiter(_ appel: FlutterMethodCall, _ resultat: @escaping FlutterResult) {
    let a = appel.arguments as? [String: Any] ?? [:]
    guard let entree = a["entree"] as? String, let sortie = a["sortie"] as? String else {
      return resultat(FlutterError(code: "ARGUMENTS", message: "entree et sortie sont obligatoires", details: nil))
    }
    let bords = (a["bords"] as? String) ?? ""
    switch appel.method {
    case "signer":
      let mime = (a["mime"] as? String) ?? ""
      let meta = (a["meta"] as? [String: String]) ?? [:]
      file.async {
        do {
          let pdf = mime == "application/pdf" || sortie.lowercased().hasSuffix(".pdf")
          let r = pdf
            ? try self.signerPdf(entree: entree, sortie: sortie, texte: bords, meta: meta)
            : try self.signerImage(entree: entree, sortie: sortie, mime: mime, texte: bords, meta: meta)
          DispatchQueue.main.async { resultat(r) }
        } catch {
          DispatchQueue.main.async {
            resultat(FlutterError(code: "ECHEC", message: error.localizedDescription, details: nil))
          }
        }
      }
    case "signerVideo":
      signerVideo(entree: entree, sortie: sortie, texte: bords, resultat: resultat)
    default:
      resultat(FlutterMethodNotImplemented)
    }
  }

  private func erreur(_ message: String) -> NSError {
    NSError(domain: "alanya.signature", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }

  // MARK: - PDF

  private func signerPdf(entree: String, sortie: String, texte: String, meta: [String: String]) throws -> [String: String] {
    guard let doc = PDFDocument(url: URL(fileURLWithPath: entree)) else { throw erreur("PDF illisible") }
    if doc.isLocked && !doc.unlock(withPassword: "") { throw erreur("PDF protégé par un mot de passe") }

    let application = meta[cleApplication] ?? "Alanya Work"
    var motsCles: [String] = [application]
    if let id = meta[cleAlanyaId] { motsCles.append("Alanya \(id)") }
    if let e = meta[cleEmpreinte] { motsCles.append("Trace \(e)") }
    let format = UIGraphicsPDFRendererFormat()
    var info: [String: Any] = [
      kCGPDFContextCreator as String: application,
      kCGPDFContextSubject as String: texte,
      kCGPDFContextKeywords as String: motsCles.joined(separator: "; "),
    ]
    if let titre = doc.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String { info[kCGPDFContextTitle as String] = titre }
    if let id = meta[cleAlanyaId] { info[kCGPDFContextAuthor as String] = "Alanya \(id)" }
    format.documentInfo = info

    let premiere = doc.page(at: 0)?.bounds(for: .cropBox) ?? CGRect(x: 0, y: 0, width: 595, height: 842)
    let rendu = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: premiere.size), format: format)
    try rendu.writePDF(to: URL(fileURLWithPath: sortie)) { contexte in
      for i in 0..<doc.pageCount {
        guard let page = doc.page(at: i) else { continue }
        let boite = page.bounds(for: .cropBox)
        let taille = CGSize(width: boite.width, height: boite.height)
        let tourne = page.rotation % 180 != 0
        let affichee = tourne ? CGSize(width: taille.height, height: taille.width) : taille
        let cadre = CGRect(origin: .zero, size: affichee)
        contexte.beginPage(withBounds: cadre, pageInfo: [:])
        let cg = contexte.cgContext
        cg.saveGState()
        // PDFKit dessine dans un repère PDF (origine en bas) : on retourne.
        cg.translateBy(x: 0, y: affichee.height)
        cg.scaleBy(x: 1, y: -1)
        page.draw(with: .cropBox, to: cg)
        cg.restoreGState()
        dessinerBordsPdf(cg, largeur: affichee.width, hauteur: affichee.height, texte: texte)
      }
    }
    return ["chemin": sortie, "mime": "application/pdf"]
  }

  /// Le texte d'une ligne, en rouge à 85 %, aux quatre bords (repère UIKit).
  private func dessinerBordsPdf(_ cg: CGContext, largeur l: CGFloat, hauteur h: CGFloat, texte: String) {
    guard !texte.isEmpty else { return }
    let base = min(9, max(5, min(l, h) / 75))
    let marge = base * 0.9
    let rouge = UIColor(red: 0xE5 / 255.0, green: 0x39 / 255.0, blue: 0x35 / 255.0, alpha: 0.85)
    func attributs(_ taille: CGFloat) -> [NSAttributedString.Key: Any] {
      [.font: UIFont.boldSystemFont(ofSize: taille), .foregroundColor: rouge]
    }
    let unite = (texte as NSString).size(withAttributes: attributs(base)).width / base
    func taillePour(_ longueur: CGFloat) -> CGFloat { unite <= 0 ? base : min(base, (longueur - 2 * marge) / unite) }
    let tH = taillePour(l), tV = taillePour(h)

    UIGraphicsPushContext(cg)
    defer { UIGraphicsPopContext() }
    func ecrire(_ taille: CGFloat, centreX: CGFloat, centreY: CGFloat, angle: CGFloat) {
      let a = attributs(taille)
      let t = (texte as NSString).size(withAttributes: a)
      cg.saveGState()
      cg.translateBy(x: centreX, y: centreY)
      cg.rotate(by: angle)
      (texte as NSString).draw(at: CGPoint(x: -t.width / 2, y: -t.height / 2), withAttributes: a)
      cg.restoreGState()
    }
    ecrire(tH, centreX: l / 2, centreY: marge + tH * 0.6, angle: 0)
    ecrire(tH, centreX: l / 2, centreY: h - marge - tH * 0.6, angle: 0)
    ecrire(tV, centreX: marge + tV * 0.6, centreY: h / 2, angle: -.pi / 2)
    ecrire(tV, centreX: l - marge - tV * 0.6, centreY: h / 2, angle: .pi / 2)
  }

  // MARK: - Images

  private func signerImage(entree: String, sortie: String, mime: String, texte: String, meta: [String: String]) throws -> [String: String] {
    guard let source = UIImage(contentsOfFile: entree), source.size.width > 0, source.size.height > 0 else {
      throw erreur("Image illisible")
    }
    // `UIImage` applique l'orientation EXIF au dessin : l'image sort redressée.
    let pixels = CGSize(width: source.size.width * source.scale, height: source.size.height * source.scale)
    let echelle = min(1, coteMax / max(pixels.width, pixels.height))
    let taille = CGSize(width: (pixels.width * echelle).rounded(), height: (pixels.height * echelle).rounded())
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = false
    let image = UIGraphicsImageRenderer(size: taille, format: format).image { ctx in
      source.draw(in: CGRect(origin: .zero, size: taille))
      SignatureDocument.peindreBords(ctx.cgContext, largeur: taille.width, hauteur: taille.height, texte: texte)
    }

    let ext = (sortie as NSString).pathExtension.lowercased()
    let png = mime.lowercased() == "image/png" || ext == "png"
    // iOS ne sait pas ÉCRIRE le WebP : une image WebP sort en JPEG.
    let extSortie = png ? "png" : (ext == "jpeg" ? "jpeg" : "jpg")
    let mimeSortie = png ? "image/png" : "image/jpeg"
    let chemin = ext == extSortie ? sortie : (sortie as NSString).deletingPathExtension + "." + extSortie

    guard let cgImage = image.cgImage else { throw erreur("Image non produite") }
    let type = (png ? UTType.png : UTType.jpeg).identifier as CFString
    guard let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: chemin) as CFURL, type, 1, nil) else {
      throw erreur("Écriture impossible")
    }
    CGImageDestinationAddImage(destination, cgImage, proprietes(texte: texte, meta: meta, png: png) as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw erreur("Écriture impossible") }
    return ["chemin": chemin, "mime": mimeSortie]
  }

  private func proprietes(texte: String, meta: [String: String], png: Bool) -> [CFString: Any] {
    let application = ascii(meta[cleApplication] ?? "Alanya Work")
    var tiff: [CFString: Any] = [
      kCGImagePropertyTIFFSoftware: application,
      kCGImagePropertyTIFFImageDescription: ascii(texte.replacingOccurrences(of: "\n", with: " · ")),
      kCGImagePropertyTIFFCopyright: application,
    ]
    if let id = meta[cleAlanyaId] { tiff[kCGImagePropertyTIFFArtist] = ascii("Alanya \(id)") }
    var exif: [CFString: Any] = [
      kCGImagePropertyExifUserComment: ascii(meta.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "; ")),
    ]
    if let e = meta[cleEmpreinte] { exif[kCGImagePropertyExifImageUniqueID] = e }
    var p: [CFString: Any] = [
      kCGImagePropertyOrientation: 1,
      kCGImagePropertyTIFFDictionary: tiff,
      kCGImagePropertyExifDictionary: exif,
    ]
    if !png { p[kCGImageDestinationLossyCompressionQuality] = 0.92 }
    return p
  }

  private func ascii(_ s: String) -> String {
    let sans = s.replacingOccurrences(of: " · ", with: " | ")
      .folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr_FR"))
    return String(sans.unicodeScalars.map { (0x20...0x7E).contains($0.value) ? Character($0) : "?" })
  }

  /// Les bords visuels (image et vidéo) : quatre lignes (haut, bas, gauche,
  /// droite) ou la même partout ; blanc cerclé de noir, comme Android.
  static func peindreBords(_ cg: CGContext, largeur l: CGFloat, hauteur h: CGFloat, texte: String) {
    let lignes = texte.components(separatedBy: "\n")
    let quatre = lignes.count == 4 ? lignes : Array(repeating: texte, count: 4)
    let base = max(16, min(l, h) / 50)
    let marge = base * 0.6
    let coin = marge + base * 1.3
    func police(_ t: CGFloat) -> UIFont { UIFont.boldSystemFont(ofSize: t) }
    func taillePour(_ ligne: String, _ longueur: CGFloat) -> CGFloat {
      let unite = (ligne as NSString).size(withAttributes: [.font: police(base)]).width / base
      return unite <= 0 ? base : min(base, (longueur - 2 * coin) / unite)
    }
    UIGraphicsPushContext(cg)
    defer { UIGraphicsPopContext() }
    func bord(_ ligne: String, _ cx: CGFloat, _ cy: CGFloat, _ angle: CGFloat, _ taille: CGFloat) {
      guard !ligne.trimmingCharacters(in: .whitespaces).isEmpty else { return }
      let contour: [NSAttributedString.Key: Any] = [
        .font: police(taille),
        .strokeColor: UIColor(white: 0, alpha: 230 / 255),
        .strokeWidth: 22, // en % de la taille : contour seul, vers l'extérieur
        .foregroundColor: UIColor.clear,
      ]
      let plein: [NSAttributedString.Key: Any] = [
        .font: police(taille),
        .foregroundColor: UIColor(white: 1, alpha: 240 / 255),
      ]
      let t = (ligne as NSString).size(withAttributes: plein)
      cg.saveGState()
      cg.translateBy(x: cx, y: cy)
      cg.rotate(by: angle)
      let point = CGPoint(x: -t.width / 2, y: -t.height / 2)
      (ligne as NSString).draw(at: point, withAttributes: contour)
      (ligne as NSString).draw(at: point, withAttributes: plein)
      cg.restoreGState()
    }
    let tHaut = taillePour(quatre[0], l), tBas = taillePour(quatre[1], l)
    let tGauche = taillePour(quatre[2], h), tDroite = taillePour(quatre[3], h)
    bord(quatre[0], l / 2, marge + tHaut * 0.6, 0, tHaut)
    bord(quatre[1], l / 2, h - marge - tBas * 0.6, 0, tBas)
    bord(quatre[2], marge + tGauche * 0.6, h / 2, -.pi / 2, tGauche)
    bord(quatre[3], l - marge - tDroite * 0.6, h / 2, .pi / 2, tDroite)
  }

  // MARK: - Vidéo

  private func signerVideo(entree: String, sortie: String, texte: String, resultat: @escaping FlutterResult) {
    let actif = AVURLAsset(url: URL(fileURLWithPath: entree))
    guard actif.tracks(withMediaType: .video).first != nil else {
      return resultat(FlutterError(code: "ECHEC", message: "Vidéo sans image", details: nil))
    }
    let composition = AVMutableVideoComposition(propertiesOf: actif)
    let taille = composition.renderSize
    guard taille.width >= 16, taille.height >= 16 else {
      return resultat(FlutterError(code: "ECHEC", message: "Vidéo sans dimensions lisibles", details: nil))
    }

    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = false
    let calque = UIGraphicsImageRenderer(size: taille, format: format).image { ctx in
      SignatureDocument.peindreBords(ctx.cgContext, largeur: taille.width, hauteur: taille.height, texte: texte)
    }

    let parent = CALayer()
    parent.frame = CGRect(origin: .zero, size: taille)
    parent.isGeometryFlipped = true
    let video = CALayer()
    video.frame = parent.frame
    let bords = CALayer()
    bords.frame = parent.frame
    bords.contents = calque.cgImage
    parent.addSublayer(video)
    parent.addSublayer(bords)
    composition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: video, in: parent)

    guard let export = AVAssetExportSession(asset: actif, presetName: AVAssetExportPresetHighestQuality) else {
      return resultat(FlutterError(code: "ECHEC", message: "Export impossible", details: nil))
    }
    let url = URL(fileURLWithPath: sortie)
    try? FileManager.default.removeItem(at: url)
    export.outputURL = url
    export.outputFileType = .mp4
    export.videoComposition = composition
    export.shouldOptimizeForNetworkUse = true
    export.exportAsynchronously {
      DispatchQueue.main.async {
        if export.status == .completed {
          resultat(["chemin": sortie, "mime": "video/mp4"])
        } else {
          try? FileManager.default.removeItem(at: url)
          resultat(FlutterError(code: "ECHEC", message: export.error?.localizedDescription ?? "Vidéo non signée", details: nil))
        }
      }
    }
  }
}
