package com.alanya.telecom

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.telecom.Connection
import android.telecom.ConnectionRequest
import android.telecom.ConnectionService
import android.telecom.DisconnectCause
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.util.Log
import androidx.annotation.RequiresApi

private const val TAG = "AlanyaTelecom"

/// Le système appelle ce service quand on déclare un appel entrant
/// (addNewIncomingCall). Tant que la Connection vit, Android LIE le
/// processus → sonnerie et appel insensibles au gel de l'app.
@RequiresApi(Build.VERSION_CODES.O)
class AlanyaConnectionService : ConnectionService() {

    override fun onCreateIncomingConnection(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?
    ): Connection {
        val bundle = request?.extras?.getBundle(TelecomManager.EXTRA_INCOMING_CALL_EXTRAS)
            ?: request?.extras ?: Bundle()
        val data = HashMap<String, String>()
        for (k in bundle.keySet()) bundle.getString(k)?.let { data[k] = it }

        Log.d(TAG, "onCreateIncomingConnection (${data["callerName"]})")

        // Écraser un éventuel appel précédent resté ouvert (anti-empilement)
        CallRegistry.endFromApp(false)

        val conn = AlanyaConnection(applicationContext, data)
        conn.connectionProperties = Connection.PROPERTY_SELF_MANAGED
        conn.setCallerDisplayName(
            data["callerName"] ?: "Alanya", TelecomManager.PRESENTATION_ALLOWED
        )
        data["callerPhone"]?.takeIf { it.isNotEmpty() }?.let {
            conn.setAddress(Uri.fromParts("tel", it, null), TelecomManager.PRESENTATION_ALLOWED)
        }
        conn.audioModeIsVoip = true
        conn.setRinging()
        CallRegistry.current = conn
        return conn
    }

    override fun onCreateIncomingConnectionFailed(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?
    ) {
        super.onCreateIncomingConnectionFailed(connectionManagerPhoneAccount, request)
        // Ex. : appel cellulaire en cours qui interdit un 2e appel → informer
        // Dart pour qu'il utilise le fallback notification classique.
        Log.w(TAG, "onCreateIncomingConnectionFailed")
        // La Connection n'a pas été créée : libérer le verrou anti-doublon
        // (sinon le fallback Dart serait lui aussi ignoré comme un doublon).
        val bundle = request?.extras?.getBundle(TelecomManager.EXTRA_INCOMING_CALL_EXTRAS)
            ?: request?.extras
        val data = HashMap<String, String>()
        bundle?.let { b -> for (k in b.keySet()) b.getString(k)?.let { data[k] = it } }
        CallRegistry.clearPending(CallRegistry.keyOf(data))
        AlanyaTelecomPlugin.emit("telecom_failed", HashMap())
    }
}

/// Un appel entrant. Cycle : setRinging → onShowIncomingCallUi (notre notif +
/// sonnerie) → onAnswer (setActive + événement Dart) OU onReject / annulation.
@RequiresApi(Build.VERSION_CODES.O)
class AlanyaConnection(
    private val ctx: Context,
    val data: HashMap<String, String>,
) : Connection() {

    @Volatile var accepted = false
    private val timeoutHandler = Handler(Looper.getMainLooper())
    private val timeoutRunnable = Runnable {
        Log.d(TAG, "timeout 90s → appel manqué")
        AlanyaTelecomPlugin.emit("timeout", data)
        endFromApp(missed = true)
    }

    override fun onShowIncomingCallUi() {
        Log.d(TAG, "onShowIncomingCallUi (${data["callerName"]})")
        IncomingNotifier.show(ctx, data)
        IncomingRinger.start(ctx)
        // Filet local : le serveur émet aussi un timeout (90 s), mais si le
        // réseau est coupé entre-temps la sonnerie s'arrêterait jamais.
        timeoutHandler.postDelayed(timeoutRunnable, 90_000)
    }

    override fun onAnswer(videoState: Int) = onAnswer()

    override fun onAnswer() {
        if (accepted) return
        accepted = true
        Log.d(TAG, "onAnswer")
        cleanupUi()
        setActive()
        // Chip vert « appel en cours » dans la barre d'état. APRÈS `setActive()`
        // : Android 14 n'autorise un service de premier plan `phoneCall` que si
        // un appel est effectivement actif côté Telecom. Voir OngoingCallChip.
        OngoingCallChip.start(ctx, data)
        AlanyaTelecomPlugin.emit("answer", data)
        // Ramener/lancer l'app au premier plan (écran d'appel côté Dart)
        try {
            val launch = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
            launch?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            ctx.startActivity(launch)
        } catch (e: Exception) {
            Log.w(TAG, "launch activity: $e")
        }
    }

    override fun onReject() {
        Log.d(TAG, "onReject")
        cleanupUi()
        AlanyaTelecomPlugin.emit("reject", data)
        // Filet app TUÉE : POST /decline-call natif (token lu dans les
        // SharedPreferences Flutter) — l'appelant est prévenu immédiatement.
        DeclineHttp.declineAsync(ctx, data)
        close(DisconnectCause.REJECTED)
    }

    override fun onDisconnect() {
        Log.d(TAG, "onDisconnect")
        cleanupUi()
        close(DisconnectCause.LOCAL)
    }

    override fun onAbort() {
        cleanupUi()
        close(DisconnectCause.CANCELED)
    }

    /// Bouton volume/power pendant la sonnerie → couper le son, garder l'appel
    override fun onSilence() { IncomingRinger.stop() }

    /// Fin déclenchée par l'app (annulation appelant, fin de com, timeout).
    fun endFromApp(missed: Boolean) {
        cleanupUi()
        close(if (missed) DisconnectCause.MISSED else DisconnectCause.REMOTE)
    }

    private fun cleanupUi() {
        timeoutHandler.removeCallbacks(timeoutRunnable)
        IncomingRinger.stop()
        IncomingNotifier.cancel(ctx)
        // Passage OBLIGÉ de toutes les fins d'appel — refus, raccroché local,
        // raccroché distant, abandon, expiration des 90 s. Poser le retrait ICI
        // plutôt que dans chaque `on…()` garantit qu'aucun chemin ne laisse un
        // chip orphelin dans la barre d'état. Appelé aussi au décroché, juste
        // avant `start()` : sans effet, `stop()` est idempotent.
        OngoingCallChip.stop(ctx)
    }

    private fun close(cause: Int) {
        try { setDisconnected(DisconnectCause(cause)) } catch (_: Exception) {}
        try { destroy() } catch (_: Exception) {}
        if (CallRegistry.current === this) CallRegistry.current = null
        // Libère le verrou anti-doublon (clé callId/roomId) à la fin de l'appel.
        CallRegistry.clearPending(CallRegistry.keyOf(data))
    }
}

/// Registre du call courant (un seul appel entrant à la fois — le serveur
/// signale « occupé » aux autres). Consulté par Dart au démarrage à froid.
object CallRegistry {
    @Volatile var current: AlanyaConnection? = null

    // ── Anti-doublon (idempotence par appel) ──────────────────────────────
    // Un même appel arrive par DEUX canaux quasi simultanés : le signal socket
    // 'incoming_call' ET le push FCM (le serveur envoie les deux quand le
    // socket est actif). Sans garde, chaque canal déclare l'appel au système →
    // deux Connections → la 2e écrase la 1re (sonnerie coupée puis relancée) :
    // l'appel « se lance deux fois ». On déduplique sur l'IDENTIFIANT D'APPEL :
    // le serveur génère un `callId` UNIQUE et l'envoie à l'identique dans les
    // deux canaux (même principe que le UUID de CallKit côté iOS). Deux appels
    // successifs entre les mêmes personnes ont des callId différents → un
    // rappel immédiat n'est jamais pris pour un doublon. Repli sur `roomId` si
    // le callId est absent (ex. ancien serveur pas encore redéployé).
    @Volatile private var pendingKey: String? = null
    @Volatile private var pendingAt: Long = 0L

    /// Clé d'identité de l'appel : `callId` unique en priorité, sinon `roomId`.
    fun keyOf(data: Map<String, String>): String? {
        data["callId"]?.takeIf { it.isNotEmpty() }?.let { return it }
        return data["roomId"]?.takeIf { it.isNotEmpty() }
    }

    /// true si [key] correspond à un appel DÉJÀ déclaré : soit une Connection
    /// vivante (sonne ou décrochée), soit une déclaration récente (< 5 s) par
    /// un autre canal dont la Connection n'est pas encore créée (la fenêtre ne
    /// sert qu'à couvrir cette course socket/FCM, pas à distinguer les appels).
    fun isDuplicateReport(key: String?): Boolean {
        if (key.isNullOrEmpty()) return false
        if (current?.let { keyOf(it.data) } == key) return true
        return pendingKey == key &&
            (System.currentTimeMillis() - pendingAt) < 5_000
    }

    /// Marque [key] comme déclaré (appelé juste avant addNewIncomingCall).
    fun markReport(key: String?) {
        pendingKey = key
        pendingAt = System.currentTimeMillis()
    }

    /// Libère le verrou pour [key] (fin d'appel / échec de création).
    fun clearPending(key: String?) {
        if (key == null || pendingKey == key) pendingKey = null
    }

    fun ringingData(): Map<String, String>? =
        current?.takeIf { !it.accepted }?.data

    fun acceptedData(): Map<String, String>? =
        current?.takeIf { it.accepted }?.data

    fun endFromApp(missed: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) current?.endFromApp(missed)
    }

    fun answerCurrent() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) current?.onAnswer()
    }

    fun rejectCurrent() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) current?.onReject()
    }

    fun setSpeaker(speakerOn: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val route = if (speakerOn) android.telecom.CallAudioState.ROUTE_SPEAKER else android.telecom.CallAudioState.ROUTE_EARPIECE
            current?.setAudioRoute(route)
        }
    }
}
