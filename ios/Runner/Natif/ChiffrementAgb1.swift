import CryptoKit
import Flutter
import Foundation

/// LE FORMAT AGB1, CHIFFRÉ PAR LE PROCESSEUR — portage iOS de
/// `ChiffrementAgb1.kt` (19/11/2026), avec CryptoKit.
///
/// 🔴 MÊMES OCTETS QUE `e2ee_media.dart`, Android et le web : blocs de 64 Kio
/// en clair, chacun chiffré en AES-256-GCM, tag de 128 bits accolé
/// (sortie = chiffré ‖ tag) ; nonce de 12 octets nuls sauf le numéro du bloc
/// en gros-boutiste aux octets 7 à 10 et le drapeau « dernier bloc » à
/// l'octet 11 ; aucune donnée associée. L'empreinte est le SHA-256 du fichier
/// CHIFFRÉ, en Base64.
///
/// Toute erreur autre qu'un fichier invalide fait basculer le Dart sur son
/// propre chemin (`Agb1Natif`) : jamais d'échec pour l'utilisateur.
final class ChiffrementAgb1 {
  static let shared = ChiffrementAgb1()

  weak var canal: FlutterMethodChannel?

  private let bloc = 64 * 1024
  private let tag = 16
  private let file = DispatchQueue(label: "alanya.agb1", qos: .userInitiated)

  private struct Invalide: Error { let message: String }

  func traiter(_ appel: FlutterMethodCall, _ resultat: @escaping FlutterResult) {
    let a = appel.arguments as? [String: Any] ?? [:]
    func octets(_ cle: String) -> Foundation.Data? { (a[cle] as? FlutterStandardTypedData)?.data }
    let jeton = (a["jeton"] as? NSNumber)?.intValue ?? 0

    file.async {
      do {
        switch appel.method {
        case "chiffrerFichier":
          guard let destination = a["destination"] as? String, let cle = octets("cle") else {
            throw NSError(domain: "agb1", code: 1)
          }
          let r = try self.chiffrerFichier(
            source: a["source"] as? String, octets: octets("octets"),
            destination: destination, cle: cle, jeton: jeton)
          DispatchQueue.main.async { resultat(r) }
        case "dechiffrer":
          guard let chiffre = octets("chiffre"), let cle = octets("cle"),
                let empreinte = a["empreinte"] as? String, let taille = (a["taille"] as? NSNumber)?.intValue else {
            throw NSError(domain: "agb1", code: 1)
          }
          let clair = try self.dechiffrer(chiffre: chiffre, cle: cle, empreinte: empreinte, taille: taille)
          DispatchQueue.main.async { resultat(FlutterStandardTypedData(bytes: clair)) }
        case "dechiffrerFichier":
          guard let source = a["source"] as? String, let destination = a["destination"] as? String,
                let cle = octets("cle"), let empreinte = a["empreinte"] as? String,
                let taille = (a["taille"] as? NSNumber)?.int64Value else {
            throw NSError(domain: "agb1", code: 1)
          }
          try self.dechiffrerFichier(source: source, destination: destination, cle: cle,
                                     empreinte: empreinte, taille: taille, jeton: jeton)
          DispatchQueue.main.async { resultat(true) }
        default:
          DispatchQueue.main.async { resultat(FlutterMethodNotImplemented) }
        }
      } catch let e as Invalide {
        DispatchQueue.main.async { resultat(FlutterError(code: "INVALIDE", message: e.message, details: nil)) }
      } catch {
        DispatchQueue.main.async {
          resultat(FlutterError(code: "ECHEC", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  private func nonce(_ index: Int, dernier: Bool) throws -> AES.GCM.Nonce {
    var n = [UInt8](repeating: 0, count: 12)
    n[7] = UInt8((index >> 24) & 0xFF)
    n[8] = UInt8((index >> 16) & 0xFF)
    n[9] = UInt8((index >> 8) & 0xFF)
    n[10] = UInt8(index & 0xFF)
    n[11] = dernier ? 1 : 0
    return try AES.GCM.Nonce(data: n)
  }

  private func progression(_ jeton: Int, _ fraction: Double) {
    DispatchQueue.main.async {
      self.canal?.invokeMethod("progression", arguments: ["jeton": jeton, "fraction": fraction])
    }
  }

  private func chiffrerFichier(
    source: String?, octets: Foundation.Data?, destination: String, cle: Foundation.Data, jeton: Int
  ) throws -> [String: Any] {
    guard (source == nil) != (octets == nil) else { throw NSError(domain: "agb1", code: 2) }
    let cleAes = SymmetricKey(data: cle)
    var sha = SHA256()
    let urlSortie = URL(fileURLWithPath: destination)
    try FileManager.default.createDirectory(at: urlSortie.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: destination, contents: nil)
    guard let sortie = FileHandle(forWritingAtPath: destination) else { throw NSError(domain: "agb1", code: 3) }
    var entree: FileHandle?
    let tailleClair: Int64
    if let s = source {
      entree = FileHandle(forReadingAtPath: s)
      guard entree != nil else { throw NSError(domain: "agb1", code: 4) }
      tailleClair = ((try? FileManager.default.attributesOfItem(atPath: s)[.size]) as? NSNumber)?.int64Value ?? 0
    } else {
      tailleClair = Int64(octets!.count)
    }
    let nbBlocs = max(1, Int((tailleClair + Int64(bloc) - 1) / Int64(bloc)))
    var taille: Int64 = 0
    var reussi = false
    var dernierPourcent = -1
    defer {
      try? entree?.close()
      try? sortie.close()
      if !reussi { try? FileManager.default.removeItem(atPath: destination) }
    }
    for i in 0..<nbBlocs {
      let debut = Int64(i) * Int64(bloc)
      let n = Int(min(Int64(bloc), tailleClair - debut))
      let clair: Foundation.Data
      if let e = entree {
        clair = e.readData(ofLength: n)
        if clair.count != n { throw NSError(domain: "agb1", code: 5, userInfo: [NSLocalizedDescriptionKey: "le fichier a changé pendant le chiffrement"]) }
      } else {
        let d = Int(debut)
        clair = octets!.subdata(in: d..<(d + n))
      }
      let boite = try AES.GCM.seal(clair, using: cleAes, nonce: nonce(i, dernier: i == nbBlocs - 1))
      var chiffre = Foundation.Data(boite.ciphertext)
      chiffre.append(boite.tag)
      sortie.write(chiffre)
      sha.update(data: chiffre)
      taille += Int64(chiffre.count)
      let pourcent = tailleClair == 0 ? 100 : Int((debut + Int64(n)) * 100 / tailleClair)
      if pourcent != dernierPourcent {
        dernierPourcent = pourcent
        progression(jeton, Double(pourcent) / 100)
      }
    }
    reussi = true
    return [
      "taille": NSNumber(value: taille),
      "tailleClair": NSNumber(value: tailleClair),
      "empreinte": FlutterStandardTypedData(bytes: Foundation.Data(sha.finalize())),
    ]
  }

  private func ouvrir(_ morceau: Foundation.Data, cle: SymmetricKey, index: Int, dernier: Bool) throws -> Foundation.Data {
    guard morceau.count >= tag else { throw Invalide(message: "bloc tronqué") }
    do {
      let boite = try AES.GCM.SealedBox(
        nonce: nonce(index, dernier: dernier),
        ciphertext: morceau.prefix(morceau.count - tag),
        tag: morceau.suffix(tag))
      return try AES.GCM.open(boite, using: cle)
    } catch {
      throw Invalide(message: "bloc \(index) refusé : clé fausse, ordre changé ou fichier coupé")
    }
  }

  /// De fichier à fichier, en flux : l'empreinte d'abord, le déchiffrement
  /// ensuite, un seul bloc en mémoire.
  private func dechiffrerFichier(
    source: String, destination: String, cle: Foundation.Data, empreinte: String, taille: Int64, jeton: Int
  ) throws {
    guard let lecture = FileHandle(forReadingAtPath: source) else { throw Invalide(message: "fichier absent") }
    var sha = SHA256()
    while true {
      let d = lecture.readData(ofLength: 1 << 20)
      if d.isEmpty { break }
      sha.update(data: d)
    }
    try? lecture.close()
    if Foundation.Data(sha.finalize()).base64EncodedString() != empreinte {
      throw Invalide(message: "empreinte différente : fichier remplacé ou abîmé")
    }
    if cle.count != 32 { throw Invalide(message: "clé invalide") }
    let blocChiffre = Int64(bloc + tag)
    let tailleChiffre = ((try? FileManager.default.attributesOfItem(atPath: source)[.size]) as? NSNumber)?.int64Value ?? 0
    let nbBlocs = Int((tailleChiffre + blocChiffre - 1) / blocChiffre)
    if nbBlocs == 0 { throw Invalide(message: "fichier vide") }
    let cleAes = SymmetricKey(data: cle)
    let urlSortie = URL(fileURLWithPath: destination)
    try FileManager.default.createDirectory(at: urlSortie.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: destination, contents: nil)
    guard let entree = FileHandle(forReadingAtPath: source),
          let sortie = FileHandle(forWritingAtPath: destination) else { throw NSError(domain: "agb1", code: 3) }
    var ecrits: Int64 = 0
    var reussi = false
    var dernierPourcent = -1
    defer {
      try? entree.close()
      try? sortie.close()
      if !reussi { try? FileManager.default.removeItem(atPath: destination) }
    }
    for i in 0..<nbBlocs {
      let n = Int(min(blocChiffre, tailleChiffre - Int64(i) * blocChiffre))
      let morceau = entree.readData(ofLength: n)
      if morceau.count != n { throw Invalide(message: "bloc tronqué") }
      let clair = try ouvrir(morceau, cle: cleAes, index: i, dernier: i == nbBlocs - 1)
      sortie.write(clair)
      ecrits += Int64(clair.count)
      let pourcent = (i + 1) * 100 / nbBlocs
      if pourcent != dernierPourcent {
        dernierPourcent = pourcent
        progression(jeton, Double(pourcent) / 100)
      }
    }
    if ecrits != taille { throw Invalide(message: "taille différente de celle annoncée") }
    reussi = true
  }

  private func dechiffrer(chiffre: Foundation.Data, cle: Foundation.Data, empreinte: String, taille: Int) throws -> Foundation.Data {
    if Foundation.Data(SHA256.hash(data: chiffre)).base64EncodedString() != empreinte {
      throw Invalide(message: "empreinte différente : fichier remplacé ou abîmé")
    }
    if cle.count != 32 { throw Invalide(message: "clé invalide") }
    let blocChiffre = bloc + tag
    let nbBlocs = (chiffre.count + blocChiffre - 1) / blocChiffre
    if nbBlocs == 0 { throw Invalide(message: "fichier vide") }
    let cleAes = SymmetricKey(data: cle)
    var sortie = Foundation.Data(capacity: max(0, chiffre.count - nbBlocs * tag))
    for i in 0..<nbBlocs {
      let debut = chiffre.startIndex + i * blocChiffre
      let fin = min(debut + blocChiffre, chiffre.endIndex)
      sortie.append(try ouvrir(chiffre.subdata(in: debut..<fin), cle: cleAes, index: i, dernier: i == nbBlocs - 1))
    }
    if sortie.count != taille { throw Invalide(message: "taille différente de celle annoncée") }
    return sortie
  }
}
