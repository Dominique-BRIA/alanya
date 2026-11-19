import CallKit
import Foundation
import UIKit
import flutter_callkit_incoming

/// LES APPELS ENTRANTS iOS (19/11/2026) : notification VoIP → écran CallKit.
///
/// 🔴 LA RÈGLE D'APPLE, SANS EXCEPTION : chaque notification VoIP reçue DOIT
/// déclarer un appel à CallKit, tout de suite, avant tout réseau. Sinon iOS
/// tue l'application et, à force, cesse de lui livrer les appels. D'où :
///   · aucune lecture réseau ici, rien d'asynchrone avant la déclaration ;
///   · un appel périmé ou déjà terminé est quand même DÉCLARÉ, puis fermé
///     aussitôt ;
///   · si le module d'appels n'est pas prêt (ne devrait pas arriver, le
///     moteur est créé au lancement), un fournisseur CallKit de secours
///     déclare puis ferme l'appel.
///
/// Les champs du push sont ceux du serveur (`push.mjs`, `pushIncomingCall`) :
/// les mêmes noms que le push Android, recopiés dans `extra` pour que le Dart
/// (`call_ui_native.dart`, `appelActif`) les lise comme sur Android.
enum AppelsVoip {

  /// Au-delà, le push est arrivé trop tard : l'appel ne sonne plus chez
  /// l'appelant (le serveur le déclare sans réponse à 90 s).
  private static let ageMaximum: TimeInterval = 75

  static func signaler(_ brut: [AnyHashable: Any], completion: @escaping () -> Void) {
    func texte(_ cle: String) -> String {
      if let v = brut[cle] as? String { return v }
      if let v = brut[cle] { return "\(v)" }
      return ""
    }

    var callId = texte("callId")
    // CallKit n'accepte qu'un UUID. Les appels du serveur en sont ; un push
    // malformé doit malgré tout déclarer quelque chose.
    let valide = UUID(uuidString: callId) != nil
    if !valide { callId = UUID().uuidString }

    let video = texte("callType").uppercased() == "VIDEO"
    let groupe = texte("isGroup") == "true"
    let appelant = texte("callerName")
    let nomGroupe = texte("groupName")
    var nom = appelant
    if groupe && !nomGroupe.isEmpty {
      nom = appelant.isEmpty ? nomGroupe : "\(appelant) · \(nomGroupe)"
    }
    if nom.isEmpty { nom = "Alanya Work" }

    let callerId = texte("callerId")
    let data = flutter_callkit_incoming.Data(id: callId, nameCaller: nom, handle: "", type: video ? 1 : 0)
    data.appName = "Alanya Work"
    data.avatar = texte("callerAvatarUrl")
    data.duration = 60000
    data.supportsVideo = true
    data.supportsDTMF = false
    data.supportsHolding = false
    data.supportsGrouping = false
    data.supportsUngrouping = false
    data.iconName = ""
    data.ringtonePath = SonneriesIos.sonPour(appelant: callerId)
    let libelles = libellesNatifs()
    data.missedNotificationSubtitle = libelles["missed_call"] ?? "Appel manqué"
    data.isShowCallback = false
    data.isShowCallingNotification = false
    data.extra = [
      "callId": callId,
      "callerId": callerId,
      "callerName": appelant,
      "callerPhoto": texte("callerAvatarUrl"),
      "isVideo": video,
      "convId": texte("convId"),
      "isGroup": groupe,
      "groupName": nomGroupe,
      "moteur": texte("moteur"),
      "jetonRefus": texte("jetonRefus"),
      "shownAt": Int(Date().timeIntervalSince1970 * 1000),
    ] as NSDictionary

    let perime = !valide || estPerime(texte("sentAt")) || estTermine(callId)

    guard let module = SwiftFlutterCallkitIncomingPlugin.sharedInstance else {
      FournisseurSecours.shared.declarerPuisFermer(callId: callId, nom: nom, video: video, completion: completion)
      return
    }

    module.showCallkitIncoming(data, fromPushKit: true) {
      completion()
      if perime {
        // Déclaré (la règle est tenue), puis retiré : il ne sonne pas pour rien.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
          module.endCall(data)
        }
      }
    }
  }

  /// Envoie le refus au serveur sans Flutter : le jeton de refus du push
  /// d'abord, la session ensuite (même ordre que `CallRejectHelper.kt`).
  /// En cas d'échec réseau, le refus est mis en file pour Flutter
  /// (`refus_appels_en_attente`, relu par `rejouerRefusEnAttente`).
  static func refuser(_ data: flutter_callkit_incoming.Data) {
    let extra = data.extra as? [String: Any] ?? [:]
    let callId = (extra["callId"] as? String) ?? data.uuid
    // Retrait décidé par l'application (l'écran Flutter reprend l'appel,
    // appel terminé ailleurs…) : ce n'est pas un refus.
    if estRetraitProgramme(callId) { return }
    let jetonRefus = (extra["jetonRefus"] as? String) ?? ""
    marquerTermine(callId)
    let prefs = UserDefaults.standard
    let jetonSession = prefs.string(forKey: "flutter.jeton_acces_natif") ?? ""
    var base = prefs.string(forKey: "flutter.api_base_natif") ?? "https://alanyavox.com"
    if !base.hasPrefix("https://") { base = "https://alanyavox.com" }
    while base.hasSuffix("/") { base.removeLast() }

    var tache: UIBackgroundTaskIdentifier = .invalid
    tache = UIApplication.shared.beginBackgroundTask {
      UIApplication.shared.endBackgroundTask(tache)
      tache = .invalid
    }
    func terminer() {
      if tache != .invalid {
        UIApplication.shared.endBackgroundTask(tache)
        tache = .invalid
      }
    }

    func envoyer(_ entete: String, _ valeur: String, ensuite: @escaping (Int) -> Void) {
      guard let url = URL(string: "\(base)/api/calls/\(callId)/reject") else { return ensuite(-1) }
      var requete = URLRequest(url: url, timeoutInterval: 15)
      requete.httpMethod = "POST"
      requete.setValue("application/json", forHTTPHeaderField: "Content-Type")
      requete.setValue(valeur, forHTTPHeaderField: entete)
      requete.httpBody = "{}".data(using: .utf8)
      URLSession.shared.dataTask(with: requete) { _, reponse, _ in
        ensuite((reponse as? HTTPURLResponse)?.statusCode ?? -1)
      }.resume()
    }

    func definitif(_ code: Int) -> Bool { (200..<300).contains(code) || code == 404 || code == 409 }

    func repli(_ code: Int) {
      if definitif(code) { return terminer() }
      if !jetonSession.isEmpty {
        envoyer("Authorization", "Bearer \(jetonSession)") { code2 in
          if !definitif(code2) { mettreEnFile(callId) }
          terminer()
        }
      } else {
        mettreEnFile(callId)
        terminer()
      }
    }

    if !jetonRefus.isEmpty {
      envoyer("X-Jeton-Refus", jetonRefus) { repli($0) }
    } else {
      repli(-1)
    }
  }

  /// Après un décroché depuis CallKit, prévient le Dart : application en
  /// arrière-plan (écran verrouillé), Flutter ne dessine pas d'image et
  /// l'écouteur d'appel peut ne pas être monté. Voir `appels_ios.dart`.
  static func reveillerFlutter() {
    CanauxAlanya.appelsIos?.invokeMethod("decroche", arguments: nil)
  }

  // MARK: - Retraits décidés par l'application

  private static var retraits: [String: Date] = [:]
  private static let verrou = NSLock()

  static func marquerRetraitProgramme(_ ids: [String]) {
    verrou.lock()
    defer { verrou.unlock() }
    let maintenant = Date()
    for id in ids { retraits[id] = maintenant }
    retraits = retraits.filter { maintenant.timeIntervalSince($0.value) < 30 }
  }

  private static func estRetraitProgramme(_ callId: String) -> Bool {
    verrou.lock()
    defer { verrou.unlock() }
    guard let t = retraits[callId] else { return false }
    return Date().timeIntervalSince(t) < 30
  }

  // MARK: - Préférences partagées avec le Dart (SharedPreferences = UserDefaults, préfixe « flutter. »)

  private static func libellesNatifs() -> [String: String] {
    guard let brut = UserDefaults.standard.string(forKey: "flutter.libelles_appel_natif"),
          let d = brut.data(using: .utf8),
          let objet = try? JSONSerialization.jsonObject(with: d) as? [String: String] else { return [:] }
    return objet
  }

  private static func estPerime(_ iso: String) -> Bool {
    guard !iso.isEmpty else { return false }
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    guard let envoi = date else { return false }
    return Date().timeIntervalSince(envoi) > ageMaximum
  }

  /// `AppelsTermines` (Dart) : un objet JSON { callId: horodatage en ms },
  /// gardé dix minutes.
  private static let cleTermines = "flutter.appels_termines"

  private static func lireTermines() -> [String: Any] {
    guard let brut = UserDefaults.standard.string(forKey: cleTermines),
          let d = brut.data(using: .utf8),
          let objet = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [:] }
    return objet
  }

  private static func estTermine(_ callId: String) -> Bool {
    guard let t = lireTermines()[callId] as? NSNumber else { return false }
    return Date().timeIntervalSince1970 * 1000 - t.doubleValue < 10 * 60 * 1000
  }

  /// Même écriture que `AppelsTermines.marquer` : un second push du même appel
  /// ne refera pas sonner.
  private static func marquerTermine(_ callId: String) {
    var liste = lireTermines()
    liste[callId] = Int(Date().timeIntervalSince1970 * 1000)
    if let d = try? JSONSerialization.data(withJSONObject: liste), let s = String(data: d, encoding: .utf8) {
      UserDefaults.standard.set(s, forKey: cleTermines)
    }
  }

  /// Même format que `CallRejectHelper.enqueuePending` : { callId: horodatage }.
  private static func mettreEnFile(_ callId: String) {
    let cle = "flutter.refus_appels_en_attente"
    let prefs = UserDefaults.standard
    var file: [String: Any] = [:]
    if let brut = prefs.string(forKey: cle), let d = brut.data(using: .utf8),
       let objet = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
      file = objet
    }
    if file[callId] == nil { file[callId] = Int(Date().timeIntervalSince1970 * 1000) }
    if let d = try? JSONSerialization.data(withJSONObject: file), let s = String(data: d, encoding: .utf8) {
      prefs.set(s, forKey: cle)
    }
  }
}

/// Le fournisseur CallKit de SECOURS : ne sert que si le module d'appels n'est
/// pas encore prêt quand une notification VoIP arrive. Il déclare l'appel (la
/// règle d'Apple est tenue), puis le ferme : mieux vaut un appel manqué qu'une
/// application tuée et privée d'appels.
final class FournisseurSecours: NSObject, CXProviderDelegate {
  static let shared = FournisseurSecours()

  private lazy var fournisseur: CXProvider = {
    let configuration = CXProviderConfiguration()
    configuration.supportsVideo = true
    configuration.maximumCallsPerCallGroup = 1
    configuration.supportedHandleTypes = [.generic]
    let p = CXProvider(configuration: configuration)
    p.setDelegate(self, queue: nil)
    return p
  }()

  func declarerPuisFermer(callId: String, nom: String, video: Bool, completion: @escaping () -> Void) {
    let uuid = UUID(uuidString: callId) ?? UUID()
    let maj = CXCallUpdate()
    maj.remoteHandle = CXHandle(type: .generic, value: nom)
    maj.localizedCallerName = nom
    maj.hasVideo = video
    fournisseur.reportNewIncomingCall(with: uuid, update: maj) { [weak self] _ in
      completion()
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        self?.fournisseur.reportCall(with: uuid, endedAt: Date(), reason: .failed)
      }
    }
  }

  func providerDidReset(_ provider: CXProvider) {}
}
