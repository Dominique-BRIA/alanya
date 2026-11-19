import AVKit
import Flutter
import UIKit
import WebRTC

/// LA FENÊTRE FLOTTANTE PENDANT UN APPEL VIDÉO — portage iOS de `PipBridge.kt`
/// (19/11/2026).
///
/// Même contrat (`fenetre_video.dart`) :
///   · `setEligible { eligible }` : un appel vidéo est en cours ;
///   · `enterNow` → vrai si la fenêtre s'ouvre ;
///   · vers le Dart : `onPipModeChanged` (vrai / faux).
///
/// iOS (15 et plus) a une fenêtre flottante prévue pour les appels vidéo
/// (`AVPictureInPictureVideoCallViewController`). Elle s'ouvre toute seule
/// quand on quitte l'application pendant l'appel, et affiche la vidéo du
/// correspondant, rendue directement depuis WebRTC (`PontWebrtc`). Avec le
/// mode d'arrière-plan « voip », notre caméra continue de filmer.
final class FenetrePip: NSObject, AVPictureInPictureControllerDelegate {
  static let shared = FenetrePip()

  weak var canal: FlutterMethodChannel?

  private var controleur: AVPictureInPictureController?
  private var vueSource: UIView?
  private var rendu: RTCMTLVideoView?

  func traiter(_ appel: FlutterMethodCall, _ resultat: @escaping FlutterResult) {
    switch appel.method {
    case "setEligible":
      let eligible = ((appel.arguments as? [String: Any])?["eligible"] as? Bool) ?? false
      if eligible { installer() } else { retirer() }
      resultat(nil)
    case "enterNow":
      guard let c = controleur, c.isPictureInPicturePossible else { return resultat(false) }
      c.startPictureInPicture()
      resultat(true)
    default:
      resultat(FlutterMethodNotImplemented)
    }
  }

  private var fenetre: UIWindow? {
    for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
      if let f = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first { return f }
    }
    return UIApplication.shared.delegate?.window ?? nil
  }

  private func installer() {
    guard controleur == nil, AVPictureInPictureController.isPictureInPictureSupported(),
          let racine = fenetre?.rootViewController?.view else { return }

    // La « source » : une vue minuscule de l'application, d'où la fenêtre
    // semble sortir quand on quitte l'application.
    let source = UIView(frame: CGRect(x: 0, y: 0, width: 2, height: 2))
    source.isUserInteractionEnabled = false
    source.alpha = 0.01
    racine.addSubview(source)

    let contenu = AVPictureInPictureVideoCallViewController()
    contenu.preferredContentSize = CGSize(width: 720, height: 1280)
    let vue = RTCMTLVideoView(frame: contenu.view.bounds)
    vue.videoContentMode = .scaleAspectFill
    vue.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    contenu.view.addSubview(vue)
    contenu.view.backgroundColor = .black

    let c = AVPictureInPictureController(
      contentSource: AVPictureInPictureController.ContentSource(
        activeVideoCallSourceView: source, contentViewController: contenu))
    c.canStartPictureInPictureAutomaticallyFromInline = true
    c.delegate = self

    PontWebrtc.autoriserCameraMultitache()
    controleur = c
    vueSource = source
    rendu = vue
  }

  private func retirer() {
    if let c = controleur, c.isPictureInPictureActive { c.stopPictureInPicture() }
    if let v = rendu { PontWebrtc.detacherVideo(v) }
    vueSource?.removeFromSuperview()
    controleur = nil
    vueSource = nil
    rendu = nil
  }

  // MARK: - AVPictureInPictureControllerDelegate

  func pictureInPictureControllerWillStartPictureInPicture(_ controleur: AVPictureInPictureController) {
    if let v = rendu { _ = PontWebrtc.attacherVideoDistante(v) }
    canal?.invokeMethod("onPipModeChanged", arguments: true)
  }

  func pictureInPictureControllerDidStopPictureInPicture(_ controleur: AVPictureInPictureController) {
    if let v = rendu { PontWebrtc.detacherVideo(v) }
    canal?.invokeMethod("onPipModeChanged", arguments: false)
  }

  func pictureInPictureController(
    _ controleur: AVPictureInPictureController,
    failedToStartPictureInPictureWithError error: Error
  ) {
    if let v = rendu { PontWebrtc.detacherVideo(v) }
    canal?.invokeMethod("onPipModeChanged", arguments: false)
  }
}
