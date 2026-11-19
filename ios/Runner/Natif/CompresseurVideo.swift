import AVFoundation
import Flutter
import Foundation

/// TRANSCODER UNE VIDÉO AVEC UN DÉBIT IMPOSÉ — portage iOS de
/// `CompresseurVideo.kt` (19/11/2026).
///
/// Même contrat que sur Android (`compression_video.dart`, `_transcoder`) :
/// `compresser { chemin, bordCourt, bordLong, debit }` rend le chemin d'un MP4
/// (H.264 + AAC) qui tient dans bordCourt × bordLong au plus, au débit demandé ;
/// `nil` veut dire « garde l'original », jamais « échoue l'envoi ».
/// L'avancement remonte par `progression` (0 à 1). Une conversion à la fois.
final class CompresseurVideo {
  static let shared = CompresseurVideo()

  weak var canal: FlutterMethodChannel?

  private let file = DispatchQueue(label: "alanya.compression_video", qos: .userInitiated)
  private var occupe = false

  func traiter(_ appel: FlutterMethodCall, _ resultat: @escaping FlutterResult) {
    guard appel.method == "compresser" else { return resultat(FlutterMethodNotImplemented) }
    let a = appel.arguments as? [String: Any] ?? [:]
    guard let chemin = a["chemin"] as? String,
          let bordCourt = (a["bordCourt"] as? NSNumber)?.intValue,
          let bordLong = (a["bordLong"] as? NSNumber)?.intValue,
          let debit = (a["debit"] as? NSNumber)?.intValue,
          !occupe else { return resultat(nil) }
    occupe = true
    let source = chemin.contains("://") ? (URL(string: chemin) ?? URL(fileURLWithPath: chemin)) : URL(fileURLWithPath: chemin)
    let dossier = FileManager.default.temporaryDirectory.appendingPathComponent("compression_video", isDirectory: true)
    try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
    let sortie = dossier.appendingPathComponent("alanya-\(Int(Date().timeIntervalSince1970 * 1000)).mp4")

    file.async {
      let r = self.transcoder(source: source, sortie: sortie, bordCourt: bordCourt, bordLong: bordLong, debit: debit)
      DispatchQueue.main.async {
        self.occupe = false
        resultat(r)
      }
    }
  }

  private func progression(_ v: Double) {
    DispatchQueue.main.async { self.canal?.invokeMethod("progression", arguments: min(1, max(0, v))) }
  }

  /// Dimensions de sortie, dans l'orientation NATURELLE de la piste (la
  /// rotation reste portée par `transform`), paires et dans la limite.
  static func dimensions(naturelle: CGSize, transform: CGAffineTransform, bordCourt: Int, bordLong: Int) -> CGSize {
    let affichee = naturelle.applying(transform)
    let l = abs(affichee.width), h = abs(affichee.height)
    guard l > 0, h > 0 else { return naturelle }
    let limiteL = CGFloat(l >= h ? bordLong : bordCourt)
    let limiteH = CGFloat(l >= h ? bordCourt : bordLong)
    let echelle = min(1, min(limiteL / l, limiteH / h))
    func pair(_ v: CGFloat) -> CGFloat { max(2, (v * echelle / 2).rounded(.down) * 2) }
    let tourne = abs(transform.b) == 1 && abs(transform.c) == 1
    return tourne ? CGSize(width: pair(h), height: pair(l)) : CGSize(width: pair(l), height: pair(h))
  }

  private func transcoder(source: URL, sortie: URL, bordCourt: Int, bordLong: Int, debit: Int) -> String? {
    let actif = AVURLAsset(url: source)
    guard let pisteVideo = actif.tracks(withMediaType: .video).first else { return nil }
    let pisteSon = actif.tracks(withMediaType: .audio).first
    let duree = CMTimeGetSeconds(actif.duration)

    do {
      let lecteur = try AVAssetReader(asset: actif)
      let ecrivain = try AVAssetWriter(outputURL: sortie, fileType: .mp4)
      ecrivain.shouldOptimizeForNetworkUse = true

      let taille = Self.dimensions(naturelle: pisteVideo.naturalSize, transform: pisteVideo.preferredTransform,
                                   bordCourt: bordCourt, bordLong: bordLong)
      let sortieVideo = AVAssetReaderTrackOutput(track: pisteVideo, outputSettings: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
      ])
      sortieVideo.alwaysCopiesSampleData = false
      guard lecteur.canAdd(sortieVideo) else { return nil }
      lecteur.add(sortieVideo)

      let entreeVideo = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: taille.width,
        AVVideoHeightKey: taille.height,
        AVVideoScalingModeKey: AVVideoScalingModeResizeAspect,
        AVVideoCompressionPropertiesKey: [
          AVVideoAverageBitRateKey: debit,
          AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
          AVVideoMaxKeyFrameIntervalDurationKey: 2,
        ],
      ])
      entreeVideo.transform = pisteVideo.preferredTransform
      entreeVideo.expectsMediaDataInRealTime = false
      guard ecrivain.canAdd(entreeVideo) else { return nil }
      ecrivain.add(entreeVideo)

      var sortieSon: AVAssetReaderTrackOutput?
      var entreeSon: AVAssetWriterInput?
      if let son = pisteSon {
        let o = AVAssetReaderTrackOutput(track: son, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
        if lecteur.canAdd(o) {
          lecteur.add(o)
          var canaux = 2
          var frequence = 44100.0
          if let desc = son.formatDescriptions.first,
             let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc as! CMAudioFormatDescription)?.pointee {
            canaux = max(1, min(2, Int(asbd.mChannelsPerFrame)))
            frequence = asbd.mSampleRate > 0 ? min(48000, asbd.mSampleRate) : 44100
          }
          let e = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: canaux,
            AVSampleRateKey: frequence,
            AVEncoderBitRateKey: canaux == 1 ? 64000 : 128000,
          ])
          e.expectsMediaDataInRealTime = false
          if ecrivain.canAdd(e) {
            ecrivain.add(e)
            sortieSon = o
            entreeSon = e
          }
        }
      }

      guard lecteur.startReading(), ecrivain.startWriting() else { return nil }
      ecrivain.startSession(atSourceTime: .zero)

      let groupe = DispatchGroup()
      let fileVideo = DispatchQueue(label: "alanya.compression.video")
      let fileSon = DispatchQueue(label: "alanya.compression.son")

      groupe.enter()
      entreeVideo.requestMediaDataWhenReady(on: fileVideo) {
        while entreeVideo.isReadyForMoreMediaData {
          guard let echantillon = sortieVideo.copyNextSampleBuffer() else {
            entreeVideo.markAsFinished()
            groupe.leave()
            return
          }
          if duree > 0 {
            let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(echantillon))
            self.progression(t / duree)
          }
          if !entreeVideo.append(echantillon) {
            entreeVideo.markAsFinished()
            groupe.leave()
            return
          }
        }
      }

      if let o = sortieSon, let e = entreeSon {
        groupe.enter()
        e.requestMediaDataWhenReady(on: fileSon) {
          while e.isReadyForMoreMediaData {
            guard let echantillon = o.copyNextSampleBuffer(), e.append(echantillon) else {
              e.markAsFinished()
              groupe.leave()
              return
            }
          }
        }
      }

      groupe.wait()
      if lecteur.status == .failed {
        ecrivain.cancelWriting()
        try? FileManager.default.removeItem(at: sortie)
        return nil
      }
      let fin = DispatchSemaphore(value: 0)
      ecrivain.finishWriting { fin.signal() }
      fin.wait()
      guard ecrivain.status == .completed else {
        try? FileManager.default.removeItem(at: sortie)
        return nil
      }
      progression(1)
      return sortie.path
    } catch {
      try? FileManager.default.removeItem(at: sortie)
      return nil
    }
  }
}
