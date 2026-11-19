import AVFoundation
import Flutter
import Foundation

/// ENREGISTRER LES DEUX VOIX D'UN APPEL — portage iOS de
/// `AppelEnregistreur.kt` (19/11/2026).
///
/// Même contrat (`enregistreur_appel.dart`) :
///   · `demarrer { callId, localTrackId }` → vrai si l'enregistrement part ;
///   · `attacherDistant { remoteTrackId }` ;
///   · `arreter` → `{ agent, client }` (les DEUX chemins, sinon rien) ;
///   · `abandonner`.
///
/// Sur iOS, le module WebRTC expose l'audio sans qu'on le modifie
/// (`AudioManager`) : le micro APRÈS traitement (voix de l'agent) et l'audio
/// reçu AVANT la sortie (voix du correspondant). Chaque voix est encodée en
/// AAC, en flux ADTS comme sur Android : un fichier lisible même si
/// l'application est tuée en cours d'appel, que le serveur mixe avec ffmpeg
/// (`melange-enregistrement.ts`).
final class EnregistreurAppel {
  static let shared = EnregistreurAppel()

  private let file = DispatchQueue(label: "alanya.enregistrement")
  private var agent: EncodeurAdts?
  private var client: EncodeurAdts?
  private var renduAgent: RenduAudioAlanya?
  private var renduClient: RenduAudioAlanya?
  private var base: String?

  func traiter(_ appel: FlutterMethodCall, _ resultat: @escaping FlutterResult) {
    let a = appel.arguments as? [String: Any] ?? [:]
    switch appel.method {
    case "demarrer":
      resultat(demarrer(callId: (a["callId"] as? String) ?? "appel"))
    case "attacherDistant":
      attacherDistant()
      resultat(nil)
    case "arreter":
      arreter { resultat($0) }
    case "abandonner":
      abandonner()
      resultat(nil)
    default:
      resultat(FlutterMethodNotImplemented)
    }
  }

  private func demarrer(callId: String) -> Bool {
    abandonner()
    let dossier = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("enregistrements", isDirectory: true)
    try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
    let nom = callId.replacingOccurrences(of: "/", with: "_")
    base = dossier.appendingPathComponent("appel-\(nom)").path
    guard let b = base else { return false }

    agent = EncodeurAdts(chemin: "\(b)-agent.aac", file: file)
    client = EncodeurAdts(chemin: "\(b)-client.aac", file: file)
    let r = RenduAudioAlanya(avecBloc: { [weak self] tampon in self?.agent?.recevoir(tampon) })
    renduAgent = r
    PontWebrtc.brancherMicro(r)
    return true
  }

  /// La voix du correspondant : l'audio reçu, avant la sortie haut-parleur.
  private func attacherDistant() {
    guard renduClient == nil, agent != nil else { return }
    let r = RenduAudioAlanya(avecBloc: { [weak self] tampon in self?.client?.recevoir(tampon) })
    renduClient = r
    PontWebrtc.brancherReception(r)
  }

  private func debrancher() {
    if let r = renduAgent { PontWebrtc.debrancherMicro(r) }
    if let r = renduClient { PontWebrtc.debrancherReception(r) }
    renduAgent = nil
    renduClient = nil
  }

  private func arreter(_ fin: @escaping ([String: String]?) -> Void) {
    debrancher()
    let a = agent, c = client
    agent = nil
    client = nil
    base = nil
    file.async {
      let cheminAgent = a?.fermer()
      let cheminClient = c?.fermer()
      DispatchQueue.main.async {
        // Les DEUX pistes sont exigées : une seule ne prouve rien.
        if let pa = cheminAgent, let pc = cheminClient {
          fin(["agent": pa, "client": pc])
        } else {
          if let pa = cheminAgent { try? FileManager.default.removeItem(atPath: pa) }
          if let pc = cheminClient { try? FileManager.default.removeItem(atPath: pc) }
          fin(nil)
        }
      }
    }
  }

  private func abandonner() {
    debrancher()
    let a = agent, c = client
    agent = nil
    client = nil
    base = nil
    file.async {
      if let p = a?.fermer() { try? FileManager.default.removeItem(atPath: p) }
      if let p = c?.fermer() { try? FileManager.default.removeItem(atPath: p) }
    }
  }
}

/// Encode du PCM en AAC-LC et l'écrit en flux ADTS (un en-tête de 7 octets
/// devant chaque paquet). Tout le travail passe par la file série donnée : le
/// fil audio de WebRTC ne fait que déposer les tampons.
final class EncodeurAdts {
  private let chemin: String
  private let file: DispatchQueue
  private var sortie: FileHandle?
  private var convertisseur: AVAudioConverter?
  private var formatAac: AVAudioFormat?
  private var indexFrequence: UInt8 = 3
  private var canaux: UInt8 = 1
  private var octetsEcrits = 0
  private var horsService = false

  private static let frequences: [Double] = [96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350]

  init(chemin: String, file: DispatchQueue) {
    self.chemin = chemin
    self.file = file
  }

  /// Appelé sur le fil audio : on ne fait que passer la main.
  func recevoir(_ tampon: AVAudioPCMBuffer) {
    file.async { self.encoder(tampon) }
  }

  private func preparer(_ format: AVAudioFormat) -> Bool {
    guard let index = Self.frequences.firstIndex(of: format.sampleRate) else { return false }
    let nbCanaux = max(1, min(2, Int(format.channelCount)))
    guard let aac = AVAudioFormat(settings: [
      AVFormatIDKey: kAudioFormatMPEG4AAC,
      AVSampleRateKey: format.sampleRate,
      AVNumberOfChannelsKey: nbCanaux,
    ]), let c = AVAudioConverter(from: format, to: aac) else { return false }
    c.bitRate = nbCanaux == 1 ? 64000 : 96000
    FileManager.default.createFile(atPath: chemin, contents: nil)
    guard let h = FileHandle(forWritingAtPath: chemin) else { return false }
    sortie = h
    convertisseur = c
    formatAac = aac
    indexFrequence = UInt8(index)
    canaux = UInt8(nbCanaux)
    return true
  }

  private func encoder(_ tampon: AVAudioPCMBuffer, finDeFlux: Bool = false) {
    if horsService { return }
    if convertisseur == nil {
      if finDeFlux { return }
      if !preparer(tampon.format) {
        horsService = true
        return
      }
    }
    guard let c = convertisseur, let aac = formatAac else { return }
    // Un tampon d'un autre format (changement de périphérique) est ignoré.
    if !finDeFlux && tampon.format != c.inputFormat { return }
    var fourni = false
    while true {
      let paquets = AVAudioCompressedBuffer(format: aac, packetCapacity: 16, maximumPacketSize: max(c.maximumOutputPacketSize, 1536))
      var erreur: NSError?
      let statut = c.convert(to: paquets, error: &erreur) { _, etat in
        if fourni {
          etat.pointee = finDeFlux ? .endOfStream : .noDataNow
          return nil
        }
        fourni = true
        if finDeFlux {
          etat.pointee = .endOfStream
          return nil
        }
        etat.pointee = .haveData
        return tampon
      }
      ecrire(paquets)
      if statut != .haveData || erreur != nil { break }
    }
  }

  private func ecrire(_ paquets: AVAudioCompressedBuffer) {
    guard let h = sortie, let descriptions = paquets.packetDescriptions, paquets.packetCount > 0 else { return }
    let octets = paquets.data.assumingMemoryBound(to: UInt8.self)
    var bloc = Data()
    for i in 0..<Int(paquets.packetCount) {
      let d = descriptions[i]
      let taille = Int(d.mDataByteSize)
      guard taille > 0 else { continue }
      bloc.append(contentsOf: entete(taille))
      bloc.append(octets.advanced(by: Int(d.mStartOffset)), count: taille)
    }
    if !bloc.isEmpty {
      h.write(bloc)
      octetsEcrits += bloc.count
    }
  }

  /// En-tête ADTS d'un paquet AAC-LC de [taille] octets.
  private func entete(_ taille: Int) -> [UInt8] {
    let total = taille + 7
    let profil: UInt8 = 1 // AAC-LC (objet 2) moins 1
    return [
      0xFF,
      0xF1,
      (profil << 6) | (indexFrequence << 2) | (canaux >> 2),
      ((canaux & 3) << 6) | UInt8((total >> 11) & 0x03),
      UInt8((total >> 3) & 0xFF),
      UInt8(((total & 7) << 5) | 0x1F),
      0xFC,
    ]
  }

  /// Vide l'encodeur et ferme le fichier ; rend son chemin s'il contient du
  /// son. À appeler sur la file série.
  func fermer() -> String? {
    if let c = convertisseur, let vide = AVAudioPCMBuffer(pcmFormat: c.inputFormat, frameCapacity: 1) {
      encoder(vide, finDeFlux: true)
    }
    try? sortie?.close()
    sortie = nil
    convertisseur = nil
    return octetsEcrits > 0 ? chemin : nil
  }
}
