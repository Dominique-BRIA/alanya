import AVFoundation
import Flutter
import Foundation

/// LES SONNERIES D'APPEL SUR iOS (19/11/2026).
///
/// CallKit ne joue qu'un FICHIER SON (CAF, AIFF ou WAV, 30 s au plus), qu'il
/// cherche par son nom. On convertit donc sur le téléphone, dans
/// `Library/Sounds` :
///   · la sonnerie Alanya, au lancement (`alanya_sonnerie.caf`) ;
///   · la sonnerie de chaque liste de contacts, quand le Dart publie la table
///     « appelant → fichier » (`sonneries_listes.dart`, canal
///     `alanya/sonneries`, méthode `preparer`).
/// Le push VoIP choisit ensuite la sonnerie de l'appelant (`sonPour`), même
/// application tuée. Un son qu'iOS ne sait pas lire (Ogg) garde la sonnerie
/// par défaut.
enum SonneriesIos {

  private static let cleTable = "alanya.sonneries_ios"
  private static let parDefaut = "alanya_sonnerie.caf"
  private static let file = DispatchQueue(label: "alanya.sonneries", qos: .utility)

  private static var dossier: URL {
    let d = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Sounds", isDirectory: true)
    try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
  }

  static func preparerSonnerieParDefaut() {
    file.async {
      if let url = urlAsset("assets/sounds/incoming_ring.mp3") {
        _ = convertir(source: url, nom: parDefaut)
      }
    }
  }

  /// Le nom du son pour [appelant], sinon la sonnerie Alanya, sinon celle du
  /// système.
  static func sonPour(appelant: String) -> String {
    let table = UserDefaults.standard.dictionary(forKey: cleTable) as? [String: String] ?? [:]
    if let nom = table[appelant.lowercased()],
       FileManager.default.fileExists(atPath: dossier.appendingPathComponent(nom).path) {
      return nom
    }
    if FileManager.default.fileExists(atPath: dossier.appendingPathComponent(parDefaut).path) {
      return parDefaut
    }
    return "system_ringtone_default"
  }

  /// `preparer { table: { appelant: source } }` : la source est un chemin de
  /// fichier, ou `asset:<chemin sous assets/>`.
  static func traiter(_ appel: FlutterMethodCall, _ resultat: @escaping FlutterResult) {
    guard appel.method == "preparer" else { return resultat(FlutterMethodNotImplemented) }
    let table = ((appel.arguments as? [String: Any])?["table"] as? [String: String]) ?? [:]
    file.async {
      var noms: [String: String] = [:]
      for (appelant, source) in table {
        let url: URL?
        if source.hasPrefix("asset:") {
          url = urlAsset("assets/" + source.dropFirst("asset:".count))
        } else {
          url = URL(fileURLWithPath: source)
        }
        guard let u = url else { continue }
        let nom = "liste_\(UInt32(truncatingIfNeeded: source.hashValueStable)).caf"
        if convertir(source: u, nom: nom) { noms[appelant.lowercased()] = nom }
      }
      UserDefaults.standard.set(noms, forKey: cleTable)
      DispatchQueue.main.async { resultat(nil) }
    }
  }

  private static func urlAsset(_ cle: String) -> URL? {
    let chemin = FlutterDartProject.lookupKey(forAsset: cle)
    guard let p = Bundle.main.path(forResource: chemin, ofType: nil) else { return nil }
    return URL(fileURLWithPath: p)
  }

  /// Convertit en CAF PCM 16 bits, 29 s au plus. Ne refait pas un fichier
  /// déjà présent.
  @discardableResult
  private static func convertir(source: URL, nom: String) -> Bool {
    let cible = dossier.appendingPathComponent(nom)
    if FileManager.default.fileExists(atPath: cible.path) { return true }
    do {
      let entree = try AVAudioFile(forReading: source)
      let format = entree.processingFormat
      let reglages: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: format.sampleRate,
        AVNumberOfChannelsKey: format.channelCount,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
      ]
      let temporaire = dossier.appendingPathComponent(nom + ".tmp.caf")
      try? FileManager.default.removeItem(at: temporaire)
      do {
        let sortie = try AVAudioFile(forWriting: temporaire, settings: reglages,
                                     commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        let limite = AVAudioFramePosition(29 * format.sampleRate)
        guard let tampon = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192) else { return false }
        while entree.framePosition < min(entree.length, limite) {
          try entree.read(into: tampon)
          if tampon.frameLength == 0 { break }
          try sortie.write(from: tampon)
        }
      }
      try FileManager.default.moveItem(at: temporaire, to: cible)
      return true
    } catch {
      return false
    }
  }
}

private extension String {
  /// Un hachage STABLE d'un lancement à l'autre (`hashValue` ne l'est pas).
  var hashValueStable: UInt64 {
    var h: UInt64 = 1469598103934665603
    for o in utf8 {
      h ^= UInt64(o)
      h = h &* 1099511628211
    }
    return h
  }
}
