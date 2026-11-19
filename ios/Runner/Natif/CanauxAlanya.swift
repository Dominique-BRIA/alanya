import Flutter
import UIKit

/// LES CANAUX NATIFS D'ALANYA SUR iOS (19/11/2026).
///
/// Mêmes noms et mêmes méthodes que sur Android (`MainActivity.kt`) : le Dart
/// ne sait pas sur quelle plateforme il parle. Une méthode qui n'a pas de sens
/// sur iPhone (service de premier plan, écran par-dessus le verrouillage…)
/// répond « fait » sans rien faire : CallKit et iOS s'en chargent.
enum CanauxAlanya {

  /// Le pont vers le Dart propre à iOS (décroché depuis CallKit).
  private(set) static var appelsIos: FlutterMethodChannel?

  private static var canaux: [FlutterMethodChannel] = []
  private static var observateurCapture: NSObjectProtocol?

  static func brancher(moteur: FlutterEngine) {
    let messager = moteur.binaryMessenger

    func canal(_ nom: String, _ traiter: @escaping FlutterMethodCallHandler) -> FlutterMethodChannel {
      let c = FlutterMethodChannel(name: nom, binaryMessenger: messager)
      c.setMethodCallHandler(traiter)
      canaux.append(c)
      return c
    }

    // Marque et modèle (filigrane des documents sensibles).
    _ = canal("alanya/appareil") { appel, resultat in
      guard appel.method == "marqueModele" else { return resultat(FlutterMethodNotImplemented) }
      resultat("Apple \(modeleAppareil())")
    }

    // « X a fait une capture d'écran » : iOS prévient APRÈS la capture.
    let capture = canal("alanya/capture") { _, resultat in resultat(nil) }
    observateurCapture = NotificationCenter.default.addObserver(
      forName: UIApplication.userDidTakeScreenshotNotification, object: nil, queue: .main
    ) { _ in
      capture.invokeMethod("capture", arguments: nil)
    }

    // Écran protégé (message à vue unique).
    _ = canal("alanya/ecran_protege") { appel, resultat in
      switch appel.method {
      case "activer": EcranProtege.shared.activer(); resultat(true)
      case "desactiver": EcranProtege.shared.desactiver(); resultat(true)
      default: resultat(FlutterMethodNotImplemented)
      }
    }

    // Appels et transferts : ce qu'Android confie à ses services.
    _ = canal("alanya/ecran_verrouille") { appel, resultat in
      let args = appel.arguments as? [String: Any] ?? [:]
      let actif = (args["actif"] as? Bool) ?? false
      switch appel.method {
      case "capteurProximite":
        // L'écran s'éteint contre l'oreille pendant un appel audio.
        UIDevice.current.isProximityMonitoringEnabled = actif
        resultat(nil)
      case "ecranAllume":
        UIApplication.shared.isIdleTimerDisabled = actif
        resultat(nil)
      case "demarrerServiceTransferts":
        TacheArrierePlan.transferts.demarrer()
        resultat(nil)
      case "arreterServiceTransferts":
        TacheArrierePlan.transferts.arreter()
        resultat(nil)
      default:
        // afficherParDessusVerrouillage, demarrerServiceAppel, arreterServiceAppel :
        // CallKit garde l'appel vivant et l'affiche sur l'écran verrouillé.
        resultat(nil)
      }
    }

    let pip = canal("alanya/pip") { appel, resultat in FenetrePip.shared.traiter(appel, resultat) }
    FenetrePip.shared.canal = pip

    let chiffrement = canal("alanya/chiffrement") { appel, resultat in ChiffrementAgb1.shared.traiter(appel, resultat) }
    ChiffrementAgb1.shared.canal = chiffrement

    let compression = canal("alanya/compression_video") { appel, resultat in
      CompresseurVideo.shared.traiter(appel, resultat)
    }
    CompresseurVideo.shared.canal = compression

    _ = canal("alanya/signature") { appel, resultat in SignatureDocument.shared.traiter(appel, resultat) }

    _ = canal("alanya/enregistrement") { appel, resultat in EnregistreurAppel.shared.traiter(appel, resultat) }

    _ = canal("alanya/sonneries") { appel, resultat in SonneriesIos.traiter(appel, resultat) }

    appelsIos = canal("alanya/appels_ios") { _, resultat in resultat(nil) }

    // Le Dart prévient avant de retirer lui-même un appel de CallKit : ce
    // retrait ne doit pas partir au serveur comme un refus.
    _ = canal("com.alanya/call_native") { appel, resultat in
      if appel.method == "markProgrammaticDismiss",
         let ids = (appel.arguments as? [String: Any])?["callIds"] as? [String] {
        AppelsVoip.marquerRetraitProgramme(ids)
      }
      resultat(nil)
    }
  }

  /// L'identifiant du modèle (« iPhone15,2 »), comme `Build.MODEL` sur Android.
  private static func modeleAppareil() -> String {
    var info = utsname()
    uname(&info)
    let octets = Mirror(reflecting: info.machine).children.compactMap { $0.value as? Int8 }
    let modele = String(decoding: octets.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    return modele.isEmpty ? UIDevice.current.model : modele
  }
}

/// Garder l'application en vie le temps d'un envoi lancé par l'utilisateur
/// (l'équivalent, borné par iOS, du service de transferts d'Android).
final class TacheArrierePlan {
  static let transferts = TacheArrierePlan(nom: "alanya.transferts")

  private let nom: String
  private var tache: UIBackgroundTaskIdentifier = .invalid

  private init(nom: String) { self.nom = nom }

  func demarrer() {
    DispatchQueue.main.async {
      guard self.tache == .invalid else { return }
      self.tache = UIApplication.shared.beginBackgroundTask(withName: self.nom) { [weak self] in
        self?.arreter()
      }
    }
  }

  func arreter() {
    DispatchQueue.main.async {
      guard self.tache != .invalid else { return }
      UIApplication.shared.endBackgroundTask(self.tache)
      self.tache = .invalid
    }
  }
}

/// ÉCRAN PROTÉGÉ (vue unique) : iOS n'a pas l'équivalent officiel de
/// `FLAG_SECURE`. Deux protections :
///   · la fenêtre de l'application est placée, UNE FOIS, dans le calque d'un
///     champ de saisie ; quand ce champ passe en mode « sécurisé », iOS retire
///     son contenu des captures et des enregistrements (technique répandue,
///     non documentée par Apple). Activer et désactiver ne font ensuite que
///     basculer ce mode : on ne redéplace jamais les calques ;
///   · si l'écran est enregistré ou recopié (`isCaptured`), un voile noir
///     couvre l'application tant que la protection est active.
final class EcranProtege {
  static let shared = EcranProtege()

  private var actif = false
  private var champ: UITextField?
  private var voile: UIView?
  private var observateur: NSObjectProtocol?

  private var fenetre: UIWindow? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    for scene in scenes {
      if let f = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first { return f }
    }
    return UIApplication.shared.delegate?.window ?? nil
  }

  func activer() {
    DispatchQueue.main.async {
      guard !self.actif, let fenetre = self.fenetre else { return }
      self.actif = true
      self.installer(dans: fenetre)
      self.champ?.isSecureTextEntry = true
      self.observateur = NotificationCenter.default.addObserver(
        forName: UIScreen.capturedDidChangeNotification, object: nil, queue: .main
      ) { [weak self] _ in self?.majVoile() }
      self.majVoile()
    }
  }

  func desactiver() {
    DispatchQueue.main.async {
      guard self.actif else { return }
      self.actif = false
      self.champ?.isSecureTextEntry = false
      if let o = self.observateur { NotificationCenter.default.removeObserver(o) }
      self.observateur = nil
      self.voile?.removeFromSuperview()
      self.voile = nil
    }
  }

  private func installer(dans fenetre: UIWindow) {
    guard champ == nil, let parent = fenetre.layer.superlayer else { return }
    let c = UITextField()
    c.isSecureTextEntry = false
    c.isUserInteractionEnabled = false
    fenetre.addSubview(c)
    parent.addSublayer(c.layer)
    let calqueSecurise = c.layer.sublayers?.last ?? c.layer.sublayers?.first
    calqueSecurise?.addSublayer(fenetre.layer)
    champ = c
  }

  private func majVoile() {
    guard actif, let fenetre = fenetre else { return }
    if UIScreen.main.isCaptured {
      if voile == nil {
        let v = UIView(frame: fenetre.bounds)
        v.backgroundColor = .black
        v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        fenetre.addSubview(v)
        voile = v
      }
    } else {
      voile?.removeFromSuperview()
      voile = nil
    }
  }
}
