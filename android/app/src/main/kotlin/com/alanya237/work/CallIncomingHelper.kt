package com.alanya237.work

import android.content.Context
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import org.json.JSONObject
import com.hiennv.flutter_callkit_incoming.CallkitConstants
import com.hiennv.flutter_callkit_incoming.CallkitNotificationManager
import com.hiennv.flutter_callkit_incoming.CallkitNotificationService
import com.hiennv.flutter_callkit_incoming.CallkitSoundPlayerManager
import com.hiennv.flutter_callkit_incoming.Data
import com.hiennv.flutter_callkit_incoming.addCall
import com.hiennv.flutter_callkit_incoming.getDataActiveCalls
import com.hiennv.flutter_callkit_incoming.removeAllCalls
import com.hiennv.flutter_callkit_incoming.removeCall

/**
 * Affiche CallKit / plein écran sans isolate Flutter (app tuée).
 * Le BroadcastReceiver du plugin exige une instance plugin initialisée ;
 * on instancie directement [CallkitNotificationManager] au démarrage app.
 *
 * Copie de `CallIncomingHelper` de l'application de référence (06/11/2026).
 * Seules diffèrent les clés propres à Alanya Work : champs du push de notre
 * serveur, registre des appels terminés (`appels_termines`), sonneries
 * (`ringtone`, `sonneries_listes_natives`) et en-tête d'autorisation de la
 * photo (notre route des médias est protégée).
 */
object CallIncomingHelper {

    private const val TAG = "AlanyaCallIncoming"
    private const val PREFS = "FlutterSharedPreferences"

    private var notificationManager: CallkitNotificationManager? = null
    private var soundManager: CallkitSoundPlayerManager? = null
    private var lastShownCallId: String? = null

    /** Les données des appels en sonnerie, par identifiant (voir [remettreNotification]). */
    private val bundlesAffiches = HashMap<String, android.os.Bundle>()

    /** L'appel ne sonne plus : ses données ne servent plus. Vide = tous. */
    fun oublier(callId: String) {
        synchronized(bundlesAffiches) {
            if (callId.isBlank()) bundlesAffiches.clear() else bundlesAffiches.remove(callId)
        }
    }

    /** Les données affichées pour [callId], ou null s'il ne sonne plus. */
    fun bundleDe(callId: String): android.os.Bundle? =
        synchronized(bundlesAffiches) { bundlesAffiches[callId] }

    /**
     * Retire la notification d'appel entrant de [callId] — ELLE SEULE : la
     * sonnerie (jouée à part) continue, l'écran d'appel reste ouvert.
     * Identifiant calqué sur le plugin : `EXTRA_CALLKIT_ID.hashCode()`.
     * ⚠️ Pas `clearIncomingNotification`, qui couperait aussi la sonnerie et
     * fermerait l'écran d'appel.
     */
    fun masquerNotification(context: Context, callId: String) {
        if (callId.isBlank()) return
        try {
            NotificationManagerCompat.from(context.applicationContext).cancel(callId.hashCode())
        } catch (e: Exception) {
            Log.w(TAG, "masquerNotification : $e")
        }
    }

    /**
     * Repose la notification d'appel entrant de [callId], telle qu'à son
     * arrivée : nom, photo, boutons Accepter et Refuser. Sans relancer la
     * sonnerie, qui n'a jamais cessé.
     */
    @android.annotation.SuppressLint("MissingPermission")
    fun remettreNotification(context: Context, callId: String) {
        val bundle = bundleDe(callId) ?: return
        if (!notificationsActives(context)) return
        ensureInitialized(context)
        try {
            val n = notificationManager?.getIncomingNotification(bundle) ?: return
            NotificationManagerCompat.from(context.applicationContext).notify(n.id, n.notification)
            Log.d(TAG, "notification remise callId=$callId")
        } catch (e: Exception) {
            Log.e(TAG, "remettreNotification failed", e)
        }
    }

    fun ensureInitialized(context: Context) {
        if (notificationManager != null) return
        val appContext = context.applicationContext
        soundManager = CallkitSoundPlayerManager(appContext)
        notificationManager = CallkitNotificationManager(appContext, soundManager!!)
        Log.d(TAG, "CallkitNotificationManager ready")
    }

    fun showIncoming(context: Context, data: Map<String, String>) {
        val callId = (data["callId"] ?: data["roomId"] ?: "").trim()
        if (callId.isNotEmpty() && callId == lastShownCallId) {
            Log.d(TAG, "skip duplicate callId=$callId")
            return
        }

        // ── Cet appel est-il déjà terminé ? ─────────────────────────────────
        //
        // Une annulation peut précéder l'appel qu'elle annule : un push d'appel
        // livré après son ordre de fin ferait sonner en plein écran un appel
        // annulé. Registre écrit par Dart (`AppelsTermines`) et par
        // [endCall] ci-dessous.
        if (callId.isNotEmpty() && estDejaTermine(context, callId)) {
            Log.i(TAG, "appel déjà terminé, on ne sonne pas: $callId")
            return
        }

        // ── L'utilisateur est-il déjà en communication ? ────────────────────
        //
        // On l'affiche quand même, mais en sourdine et sans plein écran :
        // l'information a sa place dans le tiroir, l'intrusion non.
        val enCommunication = estEnCommunication(context)
        if (enCommunication) {
            Log.i(TAG, "communication en cours → entrant en sourdine: $callId")
        }

        if (callId.isNotEmpty()) lastShownCallId = callId

        ensureInitialized(context)

        // Sonnerie que le plugin CallKit ne sait pas jouer (fichier importé, ou
        // son livré dans l'application hors `res/raw`) : on la joue nous-mêmes
        // et on rend CallKit muet (voir [CustomRingtonePlayer]).
        val customPath = resolveListCallRingtone(context, data["callerId"].orEmpty())
        val ringtonePath = if (customPath != null) "silence" else resolveNativeRingtoneName(context)
        val bundle = buildIncomingBundle(
            context,
            data,
            if (enCommunication) "silence" else ringtonePath,
            pleinEcran = !enCommunication,
        )
        try {
            notificationManager?.showIncomingNotification(bundle)
            addCall(context.applicationContext, Data.fromBundle(bundle))
            // Gardé pour pouvoir REPOSER la même notification : elle est retirée
            // tant que l'écran d'appel est affiché (voir AffichageAppel).
            if (callId.isNotEmpty()) synchronized(bundlesAffiches) { bundlesAffiches[callId] = bundle }
            // ── L'écran d'appel au premier plan, partout (07/11/2026) ───────
            //
            // La notification ne lance l'écran d'appel que téléphone verrouillé
            // ou éteint, et seulement si le plein écran est autorisé. Ailleurs
            // ce n'était qu'une bannière fugace, à rechercher ensuite dans le
            // panneau. Voir AffichageAppel. En sourdine (communication en
            // cours), on n'impose rien : la notification suffit.
            if (!enCommunication) AffichageAppel.presenter(context, bundle)
            // ── La notification a-t-elle réellement été postée ? ────────────
            //
            // Le plugin ne joue son son et n'affiche quoi que ce soit que si le
            // canal est actif ; son `notify()` est un no-op silencieux quand
            // POST_NOTIFICATIONS est refusée. Notre lecteur, lui, démarrait sans
            // condition — et en boucle : le téléphone sonnait écran vide, sans
            // bouton pour décrocher ni pour faire taire.
            if (customPath != null && !enCommunication && notificationsActives(context)) {
                CustomRingtonePlayer.start(context, customPath)
            } else if (customPath != null) {
                Log.i(TAG, "sonnerie de liste non démarrée (notification absente ou sourdine)")
            }
            Log.d(TAG, "showIncoming callId=$callId caller=${data["callerId"]} custom=${customPath != null}")
        } catch (e: Exception) {
            Log.e(TAG, "showIncoming failed", e)
        }
    }

    /**
     * L'appel figure-t-il dans le registre des appels terminés ? Écrit par
     * Dart (`AppelsTermines`, clé `appels_termines` : identifiant → instant de
     * la fin), gardé dix minutes.
     */
    private fun estDejaTermine(context: Context, callId: String): Boolean = try {
        val brut = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString("flutter.appels_termines", null)
        if (brut.isNullOrBlank()) {
            false
        } else {
            val fin = JSONObject(brut).optLong(callId, 0L)
            fin > 0L && System.currentTimeMillis() - fin < 10 * 60_000L
        }
    } catch (e: Exception) {
        Log.w(TAG, "lecture du registre des appels terminés: $e")
        false
    }

    /** Marque [callId] terminé dans le registre que lit [estDejaTermine]. */
    fun marquerTermine(context: Context, callId: String) {
        if (callId.isBlank()) return
        try {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val registre = JSONObject(prefs.getString("flutter.appels_termines", null) ?: "{}")
            registre.put(callId, System.currentTimeMillis())
            prefs.edit().putString("flutter.appels_termines", registre.toString()).commit()
        } catch (e: Exception) {
            Log.w(TAG, "écriture du registre des appels terminés: $e")
        }
    }

    /**
     * Une entrée CallKit acceptée signifie une communication en cours — de
     * même qu'un appel ou une réunion démarrés depuis l'application
     * (`CommunicationEnCours` côté Dart : marque au numéro de CE processus).
     */
    private fun estEnCommunication(context: Context): Boolean {
        val callkit = try {
            getDataActiveCalls(context.applicationContext).any { it.isAccepted }
        } catch (e: Exception) {
            Log.w(TAG, "lecture ACTIVE_CALLS: $e")
            false
        }
        if (callkit) return true
        return try {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getString("flutter.communication_en_cours_pid", null) ==
                android.os.Process.myPid().toString()
        } catch (_: Exception) {
            false
        }
    }

    /** Une notification postée maintenant serait-elle visible ? */
    private fun notificationsActives(context: Context): Boolean = try {
        NotificationManagerCompat.from(context.applicationContext)
            .areNotificationsEnabled()
    } catch (e: Exception) {
        Log.w(TAG, "areNotificationsEnabled: $e")
        true
    }

    /**
     * Sonnerie de la liste prioritaire de l'appelant : `asset:<chemin>` (son
     * livré) ou chemin d'un fichier importé déjà téléchargé. L'arbitrage entre
     * listes est fait côté Dart (`SonneriesDeListes`, table
     * `sonneries_listes_natives`) ; ici on ne fait que lire la réponse.
     */
    private fun resolveListCallRingtone(context: Context, callerId: String): String? {
        if (callerId.isBlank()) return null
        return try {
            val brut = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getString("flutter.sonneries_listes_natives", null) ?: return null
            val choix = JSONObject(brut).optString(callerId.lowercase(), "")
            when {
                choix.startsWith("asset:") -> choix
                choix.startsWith("file:") -> choix.removePrefix("file:")
                    .takeIf { java.io.File(it).exists() }
                else -> null
            }
        } catch (e: Exception) {
            Log.e(TAG, "resolveListCallRingtone failed", e)
            null
        }
    }

    /**
     * Nom de ressource `res/raw` que CallKit doit jouer pour la sonnerie
     * choisie dans les réglages (écrit par Flutter, clé `ringtone`).
     * Défaut : la sonnerie d'Alanya.
     */
    private fun resolveNativeRingtoneName(context: Context): String {
        return try {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getString("flutter.ringtone", null)
                ?.trim()
                ?.takeIf { it.matches(Regex("^[a-z0-9_]+$")) }
                ?: "sonnerie_appel"
        } catch (e: Exception) {
            Log.e(TAG, "resolveNativeRingtoneName failed", e)
            "sonnerie_appel"
        }
    }

    fun dismissIncomingSilently(context: Context, callId: String) {
        val id = callId.trim()
        if (id.isEmpty()) return
        CallDismissRegistry.markProgrammaticDismiss(id)
        endCall(context, mapOf("callId" to id))
    }

    /**
     * Coupe la sonnerie native jouée par CETTE instance (soundManager propre).
     * Nécessaire car le BroadcastReceiver du plugin arrête le soundManager du
     * plugin (ou rien si l'app est tuée : FlutterCallkitIncomingPlugin.getInstance()
     * est null), jamais celui-ci → sinon la sonnerie continue après refus/accept.
     */
    fun stopSound() {
        try {
            soundManager?.stop()
        } catch (e: Exception) {
            Log.e(TAG, "stopSound failed", e)
        }
    }

    /**
     * Annule explicitement la notification d'appel EN COURS d'un [callId] (id
     * calqué sur le plugin : `("ongoing_$callId").hashCode()`). Complète
     * stopService : sur certains OEM la notif de service au premier plan ne
     * disparaît pas toujours à l'arrêt du service.
     */
    fun cancelOngoingNotification(context: Context, callId: String) {
        val id = callId.trim()
        if (id.isEmpty()) return
        try {
            NotificationManagerCompat.from(context.applicationContext)
                .cancel("ongoing_$id".hashCode())
        } catch (e: Exception) {
            Log.e(TAG, "cancelOngoingNotification failed", e)
        }
    }

    fun endCall(context: Context, data: Map<String, String>) {
        ensureInitialized(context)
        lastShownCallId = null
        // Couper la sonnerie importée jouée nativement (voir CustomRingtonePlayer).
        CustomRingtonePlayer.stop()
        // Coupe aussi le service/notification d'appel EN COURS (chronomètre +
        // raccrocher). Le plugin ne le fait pas quand getInstance() est null
        // (app tuée) → sinon notification fantôme aux boutons morts après l'appel.
        try {
            CallkitNotificationService.stopService(context.applicationContext)
        } catch (e: Exception) {
            Log.e(TAG, "stopService (endCall) failed", e)
        }
        val callId = (data["callId"] ?: "").trim()
        oublier(callId)
        // Retrait piloté par le serveur (push call_cancelled) ou par Flutter —
        // pas un refus utilisateur : marquer AVANT removeCall pour que le
        // listener ACTIVE_CALLS d'AlanyaApplication ne POST pas le refus.
        try {
            if (callId.isNotEmpty()) {
                CallDismissRegistry.markProgrammaticDismiss(callId)
            } else {
                getDataActiveCalls(context.applicationContext).forEach {
                    CallDismissRegistry.markProgrammaticDismiss(it.id)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "markProgrammaticDismiss (endCall) failed", e)
        }
        try {
            if (callId.isEmpty()) {
                soundManager?.stop()
                removeAllCalls(context.applicationContext)
                Log.d(TAG, "endCall all")
                return
            }
            cancelOngoingNotification(context, callId)
            val bundle = Data(hashMapOf<String, Any?>("id" to callId)).toBundle()
            notificationManager?.clearIncomingNotification(bundle, false)
            removeCall(context.applicationContext, Data.fromBundle(bundle))
            Log.d(TAG, "endCall callId=$callId")
        } catch (e: Exception) {
            Log.e(TAG, "endCall failed", e)
        }
    }

    /** Couleur du texte de l'écran plein écran, au format `Color.parseColor`. */
    private fun couleurTexte(context: Context): String =
        String.format(
            java.util.Locale.US,
            "#%08X",
            context.getColor(R.color.callkit_on_background),
        )

    /** Libellé traduit, écrit par l'application (`libelles_appel_natif`). */
    private fun libelle(context: Context, cle: String, repli: String): String = try {
        JSONObject(
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getString("flutter.libelles_appel_natif", null) ?: "{}"
        ).optString(cle, "").ifEmpty { repli }
    } catch (_: Exception) {
        repli
    }

    /**
     * Photo de l'appelant : URL complète, le serveur rendant souvent un chemin
     * relatif. L'image se charge par le plugin, avec l'en-tête d'autorisation
     * passé dans `headers` (notre route des médias est protégée).
     */
    private fun photoComplete(context: Context, brut: String): String {
        val v = brut.trim()
        if (v.isEmpty() || v.startsWith("http")) return v
        // Photo enregistrée en base64 (« data: ») : le chargeur d'images du
        // plugin (Coil) ne sait pas la lire, mais il lit un fichier. On
        // l'écrit donc dans le cache, une fois par photo (07/11/2026).
        if (v.startsWith("data:")) return photoEnFichier(context, v)
        val base = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString("flutter.api_base_natif", null)?.trimEnd('/') ?: return ""
        return base + (if (v.startsWith("/")) v else "/$v")
    }

    private fun photoEnFichier(context: Context, dataUri: String): String = try {
        val dossier = java.io.File(context.cacheDir, "photos_appel").apply { mkdirs() }
        val fichier = java.io.File(dossier, "${dataUri.hashCode() and 0x7fffffff}.img")
        if (!fichier.exists() || fichier.length() == 0L) {
            val octets = android.util.Base64.decode(dataUri.substringAfter(','), android.util.Base64.DEFAULT)
            fichier.writeBytes(octets)
        }
        fichier.absolutePath
    } catch (e: Exception) {
        Log.w(TAG, "photo base64 illisible : $e")
        ""
    }

    private fun buildIncomingBundle(
        context: Context,
        data: Map<String, String>,
        ringtonePath: String = "sonnerie_appel",
        pleinEcran: Boolean = true,
    ): android.os.Bundle {
        val callId = (data["callId"] ?: data["roomId"] ?: "").trim()
        val callerId = data["callerId"] ?: ""
        val isGroup = data["isGroup"] == "true"
        val groupName = data["groupName"].orEmpty()
        val callerName = (if (isGroup && groupName.isNotBlank()) groupName else null)
            ?: data["callerName"] ?: data["title"] ?: "Alanya"
        // Push du serveur : `callType` = "VIDEO" ; chemin Dart : `isVideo`.
        val isVideo = data["isVideo"] == "true" || data["callType"] == "VIDEO"
        val photoBrute = data["callerAvatarUrl"] ?: data["photo"] ?: ""
        val photo = photoComplete(context, photoBrute)
        val jeton = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString("flutter.jeton_acces_natif", null).orEmpty()

        val extra = hashMapOf<String, Any?>(
            "callId" to callId,
            "callerId" to callerId,
            "callerName" to (data["callerName"] ?: callerName),
            // La valeur du serveur, telle quelle : c'est Flutter qui la relit
            // (AvatarSource), pas le chargeur du plugin.
            "callerPhoto" to photoBrute,
            "isVideo" to isVideo,
            "convId" to data["convId"].orEmpty(),
            "isGroup" to isGroup,
            "groupName" to groupName,
            // Fraîcheur pour le cold start Flutter : une entrée ACTIVE_CALLS
            // résiduelle d'un essai précédent ne doit jamais déclencher une
            // auto-réponse ou un écran entrant fantôme.
            "shownAt" to System.currentTimeMillis(),
        )

        val args = hashMapOf<String, Any?>(
            "id" to callId,
            "nameCaller" to callerName,
            "appName" to "Alanya Work",
            "handle" to callerId,
            "avatar" to photo,
            "type" to if (isVideo) 1 else 0,
            // Durée de sonnerie alignée sur celle de l'appelant (60 s) : un
            // écran qui sonnerait plus longtemps afficherait un appel que plus
            // personne ne passe.
            "duration" to 60000L,
            "extra" to extra,
            "headers" to (if (jeton.isNotEmpty()) hashMapOf("Authorization" to "Bearer $jeton") else hashMapOf<String, Any?>()),
            "android" to hashMapOf(
                "isCustomNotification" to true,
                "isShowLogo" to false,
                // Depuis la 3.x, `Data` lit ces libellés dans `android` et non
                // plus à la racine.
                "textAccept" to libelle(context, "accept", "Accepter"),
                "textDecline" to libelle(context, "decline", "Refuser"),
                // Nom de ressource res/raw compilée, ou 'silence' quand on joue
                // nous-mêmes la sonnerie (voir CustomRingtonePlayer).
                // NB : passer "" ne rend PAS muet — le plugin retombe alors sur
                // la sonnerie système.
                "ringtonePath" to ringtonePath,
                // Transparent : le dégradé de l'écran plein écran appartient au
                // layout (res/layout/callkit_incoming_content.xml), que cet
                // aplat recouvrirait.
                "backgroundColor" to "#00000000",
                "textColor" to couleurTexte(context),
                "actionColor" to "#2D6A4F",
                "incomingCallNotificationChannelName" to libelle(context, "incoming_calls", "Appels entrants"),
                "missedCallNotificationChannelName" to libelle(context, "missed_calls", "Appels manqués"),
                "isShowFullLockedScreen" to pleinEcran,
            ),
        )
        val bundle = Data(args).toBundle()
        // CRUCIAL — quand l'app est tuée, le tap « Accepter » déclenche
        // ContextCompat.startForegroundService(CallkitNotificationService) alors
        // que le service ne peut PAS appeler startForeground() : son
        // CallkitNotificationManager vient de FlutterCallkitIncomingPlugin
        // .getInstance(), null tant qu'aucun engine Flutter n'est attaché →
        // ForegroundServiceDidNotStartInTimeException ~10 s après l'acceptation,
        // le process meurt en plein appel. Avec ce flag à false, l'accept passe
        // par startService + stopSelf (aucun contrat startForeground) ; le
        // service de premier plan légitime est démarré ensuite par Dart
        // (CallForegroundService) une fois l'engine prêt.
        bundle.putBoolean(CallkitConstants.EXTRA_CALLKIT_CALLING_SHOW, false)
        return bundle
    }

    /**
     * Efface la notification d'appel ENTRANT d'un [callId] (sonnerie comprise).
     * Utilisé par AlanyaApplication quand l'appel passe à isAccepted : la
     * branche ACCEPT du service plugin ne peut pas le faire (manager null app
     * tuée), et avec EXTRA_CALLKIT_CALLING_SHOW=false elle fait stopSelf()
     * immédiatement.
     */
    fun clearIncomingNotification(context: Context, callId: String) {
        val id = callId.trim()
        if (id.isEmpty()) return
        ensureInitialized(context)
        try {
            val bundle = Data(hashMapOf<String, Any?>("id" to id)).toBundle()
            notificationManager?.clearIncomingNotification(bundle, true)
        } catch (e: Exception) {
            Log.e(TAG, "clearIncomingNotification failed", e)
        }
    }
}
