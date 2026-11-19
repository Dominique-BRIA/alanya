import AVFAudio
import CallKit
import Flutter
import PushKit
import UIKit
import UserNotifications
import WebRTC
import flutter_callkit_incoming

/// LE POINT D'ENTRÉE iOS D'ALANYA WORK (19/11/2026).
///
/// 🔴 LE MOTEUR FLUTTER EST CRÉÉ ICI, DÈS LE LANCEMENT — pas par un storyboard.
/// Un appel entrant application tuée arrive par PushKit : iOS relance
/// l'application EN ARRIÈRE-PLAN, sans scène ni écran. Un moteur créé par la
/// scène n'existerait pas encore, ni donc le module d'appels, alors qu'Apple
/// exige que l'appel soit déclaré à CallKit IMMÉDIATEMENT (sinon l'application
/// est tuée et, à la longue, ne reçoit plus aucun appel).
///
/// Le contrôleur Flutter est posé sur `window` : `FlutterSceneDelegate` le
/// déplace dans la scène quand elle se connecte (comportement prévu par
/// Flutter, voir `FlutterSceneDelegate.mm`).
@main
@objc class AppDelegate: FlutterAppDelegate, PKPushRegistryDelegate, CallkitIncomingAppDelegate {

  /// Le moteur unique de l'application (un seul isolat Dart).
  lazy var moteur = FlutterEngine(name: "alanya")

  private var registreVoip: PKPushRegistry?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    moteur.run()
    GeneratedPluginRegistrant.register(with: moteur)
    CanauxAlanya.brancher(moteur: moteur)

    let fenetre = UIWindow(frame: UIScreen.main.bounds)
    fenetre.rootViewController = FlutterViewController(engine: moteur, nibName: nil, bundle: nil)
    window = fenetre

    // Notifications locales (flutter_local_notifications) et appels manqués.
    UNUserNotificationCenter.current().delegate = self

    // Les appels entrants passent par PushKit (notifications VoIP).
    let registre = PKPushRegistry(queue: DispatchQueue.main)
    registre.delegate = self
    registre.desiredPushTypes = [.voIP]
    registreVoip = registre

    // La sonnerie Alanya par défaut, prête pour CallKit.
    SonneriesIos.preparerSonnerieParDefaut()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - PushKit

  func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType) {
    guard type == .voIP else { return }
    let jeton = credentials.token.map { String(format: "%02x", $0) }.joined()
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(jeton)
  }

  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    guard type == .voIP else { return }
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP("")
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType,
    completion: @escaping () -> Void
  ) {
    guard type == .voIP else {
      completion()
      return
    }
    AppelsVoip.signaler(payload.dictionaryPayload, completion: completion)
  }

  // MARK: - CallKit (flutter_callkit_incoming)

  /// Décroché : l'événement part aussi vers Dart (`CallEventActionCallAccept`),
  /// qui rejoint l'appel. L'action est acceptée tout de suite, comme Android.
  func onAccept(_ call: Call, _ action: CXAnswerCallAction) {
    action.fulfill()
    AppelsVoip.reveillerFlutter()
  }

  /// Refusé : envoyé au serveur PAR LE NATIF, car Flutter peut ne pas tourner
  /// (même principe que `CallRejectHelper.kt`).
  func onDecline(_ call: Call, _ action: CXEndCallAction) {
    AppelsVoip.refuser(call.data)
    action.fulfill()
  }

  func onEnd(_ call: Call, _ action: CXEndCallAction) {
    action.fulfill()
  }

  func onTimeOut(_ call: Call) {}

  /// 🔴 LE SON DE L'APPEL : CallKit active la session audio, WebRTC doit le
  /// savoir — sinon micro et haut-parleur restent muets après un décroché
  /// depuis l'écran verrouillé.
  func didActivateAudioSession(_ audioSession: AVAudioSession) {
    RTCAudioSession.sharedInstance().audioSessionDidActivate(audioSession)
    RTCAudioSession.sharedInstance().isAudioEnabled = true
  }

  func didDeactivateAudioSession(_ audioSession: AVAudioSession) {
    RTCAudioSession.sharedInstance().audioSessionDidDeactivate(audioSession)
  }

  func providerDidReset() {}
}
