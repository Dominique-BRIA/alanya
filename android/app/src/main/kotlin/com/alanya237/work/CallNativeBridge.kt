package com.alanya237.work

import android.content.Context
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/**
 * Pont natif ↔ Flutter pour les actions CallKit (raccrochage / refus depuis
 * la notification quand l'événement plugin n'atteint pas Dart).
 *
 * Copie de `CallNativeBridge` de l'application de référence (06/11/2026). Le
 * passage par-dessus le verrouillage est confié à [MainActivity] (notre
 * équivalent de leur `LockScreenBridge`), reçu à l'attache.
 */
object CallNativeBridge {
    private const val CHANNEL = "com.alanya/call_native"

    private var channel: MethodChannel? = null
    private var appContext: Context? = null
    private var ready = false
    private var verrouillage: ((Boolean) -> Unit)? = null

    fun attach(
        binaryMessenger: io.flutter.plugin.common.BinaryMessenger,
        context: Context,
        afficherParDessusVerrouillage: (Boolean) -> Unit,
    ) {
        appContext = context.applicationContext
        verrouillage = afficherParDessusVerrouillage
        channel = MethodChannel(binaryMessenger, CHANNEL).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "dismissIncomingSilently" -> {
                        val callId = call.argument<String>("callId")?.trim() ?: ""
                        dismissIncomingSilently(callId)
                        result.success(null)
                    }
                    // Flutter s'apprête à retirer ces appels de CallKit
                    // (endCall/endAllCalls) : les marquer AVANT le retrait pour
                    // qu'AlanyaApplication ne les prenne pas pour des refus
                    // utilisateur (sinon refus « fratricide »).
                    "markProgrammaticDismiss" -> {
                        val ids = call.argument<List<String>>("callIds") ?: emptyList()
                        ids.forEach { CallDismissRegistry.markProgrammaticDismiss(it) }
                        result.success(null)
                    }
                    // Affichage de l'appel entrant par le natif, quand Dart le
                    // reçoit par le socket application en arrière-plan : UN seul
                    // chemin d'affichage, avec ses gardes (doublon, appel
                    // terminé, communication en cours, sonnerie).
                    "showIncoming" -> {
                        val ctx = appContext
                        @Suppress("UNCHECKED_CAST")
                        val brut = call.arguments as? Map<Any?, Any?> ?: emptyMap<Any?, Any?>()
                        val data = HashMap<String, String>()
                        brut.forEach { (k, v) -> if (k != null) data[k.toString()] = v?.toString() ?: "" }
                        if (ctx != null) CallIncomingHelper.showIncoming(ctx, data)
                        result.success(null)
                    }
                    // Mode de sonnerie du téléphone : 0 silencieux, 1 vibreur,
                    // 2 normal.
                    "getRingerMode" -> {
                        val am = appContext?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                        result.success(am?.ringerMode ?: AudioManager.RINGER_MODE_NORMAL)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        ready = true
    }

    fun dismissIncomingSilently(callId: String) {
        val ctx = appContext ?: return
        if (callId.isEmpty()) return
        CallIncomingHelper.dismissIncomingSilently(ctx, callId)
    }

    fun notifyCallEnded(callId: String?, callerId: String?) {
        // Filet : l'appel est fini côté CallKit, même si Flutter n'a pas pu
        // jouer sa clôture — l'app ne doit plus passer par-dessus le verrou.
        try { verrouillage?.invoke(false) } catch (_: Exception) {}
        if (!ready) return
        Handler(Looper.getMainLooper()).post {
            channel?.invokeMethod(
                "onCallEnded",
                mapOf(
                    "callId" to (callId ?: ""),
                    "callerId" to (callerId ?: ""),
                ),
            )
        }
    }
}
