package com.alanya.telecom

import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.telecom.PhoneAccount
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CopyOnWriteArrayList

/// Pont Flutter ↔ Telecom. Enregistré par GeneratedPluginRegistrant sur TOUS
/// les moteurs (main + isolate FCM background) → reportIncomingCall marche
/// même app tuée. Les événements (answer/reject/timeout) sont diffusés à tous
/// les moteurs attachés.
class AlanyaTelecomPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var context: Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "alanya_telecom").also {
            it.setMethodCallHandler(this)
            channels.add(it)
        }
        TelecomHelper.ensureAccount(binding.applicationContext)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.let { channels.remove(it); it.setMethodCallHandler(null) }
        channel = null
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val ctx = context
        if (ctx == null) { result.success(false); return }
        when (call.method) {
            "configure" -> {
                call.argument<String>("apiUrl")?.let { DeclineHttp.configure(ctx, it) }
                result.success(true)
            }
            "reportIncomingCall" -> {
                @Suppress("UNCHECKED_CAST")
                val raw = call.arguments as? Map<Any?, Any?> ?: emptyMap<Any?, Any?>()
                val data = HashMap<String, String>()
                raw.forEach { (k, v) -> if (k != null) data[k.toString()] = v?.toString() ?: "" }
                result.success(TelecomHelper.reportIncoming(ctx, data))
            }
            "endCall" -> {
                CallRegistry.endFromApp(call.argument<Boolean>("missed") ?: false)
                result.success(true)
            }
            "silenceRinger" -> { IncomingRinger.stop(); result.success(true) }
            "answerRinging" -> {
                mainHandler.post { CallRegistry.answerCurrent() }
                result.success(true)
            }
            "rejectRinging" -> {
                mainHandler.post { CallRegistry.rejectCurrent() }
                result.success(true)
            }
            "setSpeaker" -> {
                val on = call.argument<Boolean>("speakerOn") ?: false
                CallRegistry.setSpeaker(on)
                result.success(true)
            }
            "getRingingCall" -> result.success(CallRegistry.ringingData())
            "getAcceptedCall" -> result.success(CallRegistry.acceptedData())
            else -> result.notImplemented()
        }
    }

    companion object {
        private const val TAG = "AlanyaTelecom"
        private val channels = CopyOnWriteArrayList<MethodChannel>()
        private val mainHandler = Handler(Looper.getMainLooper())

        /// Diffuse un événement à tous les moteurs Flutter attachés.
        fun emit(event: String, data: Map<String, String>) {
            mainHandler.post {
                Log.d(TAG, "emit $event → ${channels.size} moteur(s)")
                channels.forEach { ch ->
                    try { ch.invokeMethod(event, data) } catch (_: Exception) {}
                }
            }
        }
    }
}

object TelecomHelper {
    private const val TAG = "AlanyaTelecom"
    const val ACCOUNT_ID = "alanya_self_managed"

    fun canUseTelecom(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O

    fun handle(context: Context): PhoneAccountHandle = PhoneAccountHandle(
        ComponentName(context, AlanyaConnectionService::class.java), ACCOUNT_ID
    )

    fun ensureAccount(context: Context) {
        if (!canUseTelecom()) return
        try {
            val tm = context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
            val account = PhoneAccount.builder(handle(context), "Alanya")
                .setCapabilities(PhoneAccount.CAPABILITY_SELF_MANAGED)
                .build()
            tm.registerPhoneAccount(account)
        } catch (e: Exception) {
            Log.w(TAG, "registerPhoneAccount: $e")
        }
    }

    /// Déclare l'appel entrant au système. false → l'appelant Dart doit
    /// utiliser le fallback (flutter_callkit_incoming).
    fun reportIncoming(context: Context, data: HashMap<String, String>): Boolean {
        if (!canUseTelecom()) return false
        // Idempotence : le même appel arrive par 2 canaux (socket + FCM). On
        // déduplique sur l'identifiant d'appel (callId unique fourni par le
        // serveur, repli roomId). Si on vient déjà de le déclarer, on considère
        // l'appel « pris en charge » (true) sans créer une 2e Connection.
        val key = CallRegistry.keyOf(data)
        if (CallRegistry.isDuplicateReport(key)) {
            Log.d(TAG, "reportIncoming ignoré — doublon key=$key (${data["callerName"]})")
            return true
        }
        return try {
            ensureAccount(context)
            val tm = context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
            val callExtras = Bundle().apply { data.forEach { (k, v) -> putString(k, v) } }
            val extras = Bundle().apply {
                putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, handle(context))
                putBundle(TelecomManager.EXTRA_INCOMING_CALL_EXTRAS, callExtras)
            }
            // Verrou posé AVANT la déclaration : ferme la fenêtre de course où
            // le 2e canal appellerait addNewIncomingCall avant que le système
            // n'ait créé la Connection.
            CallRegistry.markReport(key)
            tm.addNewIncomingCall(handle(context), extras)
            Log.d(TAG, "addNewIncomingCall OK (${data["callerName"]})")
            true
        } catch (e: Exception) {
            // SecurityException (compte refusé par l'OEM…) → fallback Dart.
            // La Connection n'existe pas : libérer le verrou pour que le
            // fallback (flutter_callkit_incoming) ne soit pas pris pour un doublon.
            CallRegistry.clearPending(key)
            Log.w(TAG, "addNewIncomingCall ÉCHEC: $e")
            false
        }
    }
}
