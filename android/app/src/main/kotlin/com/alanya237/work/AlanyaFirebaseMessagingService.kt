package com.alanya237.work

import android.app.ActivityManager
import android.app.KeyguardManager
import android.content.Context
import android.util.Log
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugins.firebase.messaging.ContextHolder
import io.flutter.plugins.firebase.messaging.FlutterFirebaseTokenLiveData
import java.time.Instant

/**
 * Couche Android propriétaire des APPELS, copiée de `TalkyFirebaseMessagingService`
 * de l'application de référence (06/11/2026).
 *
 * Appel entrant, application hors de l'écran : CallKit plein écran affiché ICI,
 * sans démarrer Flutter ([CallIncomingHelper]). Appel annulé : retiré ici.
 * Tout le reste — messages, réunions… — reste à Flutter.
 *
 * **Ce service ne transmet rien à Flutter, et n'a pas à le faire.** Le plugin
 * `firebase_messaging` déclare son propre `FlutterFirebaseMessagingReceiver`
 * sur `com.google.android.c2dm.intent.RECEIVE` — une diffusion distincte de
 * celle qui nous amène ici. Ce receiver reçoit donc *chaque* message de son
 * côté et fait déjà tout le travail (le handler Dart d'arrière-plan, qui
 * ignore désormais les appels sur Android : ils sont traités ici).
 */
class AlanyaFirebaseMessagingService : FirebaseMessagingService() {

    override fun onMessageReceived(message: RemoteMessage) {
        ensureFlutterContext()

        val data = message.data
        val type = data["type"] ?: return

        when (type) {
            "incoming_call" -> {
                // Réglage de l'application : notifications d'appels coupées.
                val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                if (!prefs.getBoolean("flutter.notif_calls", true)) {
                    Log.d(TAG, "appels désactivés dans les réglages → rien")
                    return
                }
                // Appel PÉRIMÉ : un push en transit peut arriver bien après
                // l'appel (téléphone rallumé, réseau rétabli).
                if (estPerime(data["sentAt"])) {
                    Log.d(TAG, "appel périmé ignoré callId=${data["callId"]}")
                    return
                }
                if (isApplicationForeground(this)) {
                    // Premier plan : Flutter + socket (écran de sonnerie Flutter).
                    Log.d(TAG, "call foreground → Flutter callId=${data["callId"]}")
                } else {
                    Log.d(TAG, "call native show callId=${data["callId"]}")
                    CallIncomingHelper.showIncoming(this, data)
                }
            }
            "call_cancelled" -> {
                val callId = data["callId"].orEmpty()
                Log.d(TAG, "call native end callId=$callId")
                // Noté AVANT : un push d'appel arrivé après son annulation ne
                // sonnera pas (voir CallIncomingHelper.estDejaTermine).
                CallIncomingHelper.marquerTermine(this, callId)
                CallIncomingHelper.endCall(this, data)
            }
            // Tout le reste : rien de natif, le receiver Flutter s'en charge seul.
            else -> Unit
        }
    }

    private fun estPerime(sentAt: String?): Boolean = try {
        if (sentAt.isNullOrBlank()) false
        else System.currentTimeMillis() - Instant.parse(sentAt).toEpochMilli() > 90_000L
    } catch (_: Exception) {
        false
    }

    /**
     * Le jeton a tourné. Il faut le dire à Flutter — personne d'autre ne le fera.
     *
     * Le SDK ne délivre `onNewToken` qu'à UN service `MESSAGING_EVENT`, et
     * c'est désormais celui-ci : le service du plugin est désactivé au
     * manifeste. Or c'est lui, et lui seul, qui alimentait
     * `FlutterFirebaseTokenLiveData` — la source de l'événement
     * `onTokenRefresh` que `PushService` écoute. On repose donc le jeton là où
     * le plugin l'attend.
     */
    override fun onNewToken(token: String) {
        Log.i(TAG, "onNewToken — relais vers Flutter (len=${token.length})")
        ensureFlutterContext()
        try {
            FlutterFirebaseTokenLiveData.getInstance().postToken(token)
        } catch (e: Exception) {
            Log.e(TAG, "relais du jeton échoué", e)
        }
    }

    private fun ensureFlutterContext() {
        if (ContextHolder.getApplicationContext() == null) {
            ContextHolder.setApplicationContext(applicationContext)
        }
    }

    /** Copie de la logique FlutterFirebaseMessagingUtils (classe package-private). */
    private fun isApplicationForeground(context: Context): Boolean {
        val keyguardManager =
            context.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        if (keyguardManager?.isKeyguardLocked == true) return false

        val activityManager =
            context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager ?: return false
        val processes = activityManager.runningAppProcesses ?: return false
        val packageName = context.packageName
        for (process in processes) {
            if (process.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND &&
                process.processName == packageName
            ) {
                return true
            }
        }
        return false
    }

    companion object {
        private const val TAG = "AlanyaFcmService"
    }
}
