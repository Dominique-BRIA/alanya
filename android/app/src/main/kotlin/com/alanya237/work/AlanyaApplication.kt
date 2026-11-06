package com.alanya237.work

import android.app.Application
import android.content.SharedPreferences
import android.util.Log
import com.hiennv.flutter_callkit_incoming.CallkitConstants
import com.hiennv.flutter_callkit_incoming.CallkitEventCallback
import com.hiennv.flutter_callkit_incoming.CallkitNotificationService
import com.hiennv.flutter_callkit_incoming.FlutterCallkitIncomingPlugin
import org.json.JSONArray
import org.json.JSONObject

/**
 * Détecte un refus CallKit même si l'Intent est explicite (plugin) et que
 * Flutter n'est pas booté.
 *
 * Ordre cold-start decline :
 * 1. Application.onCreate → snapshot ACTIVE_CALLS + listener
 * 2. CallkitIncomingBroadcastReceiver → removeCall
 * 3. Listener → appel disparu non accepté → POST du refus
 *
 * Copie de `TalkyApplication` de l'application de référence (06/11/2026),
 * sans sa réparation du stockage chiffré, propre à leur projet. Le refus part
 * sur notre route (voir [CallRejectHelper]).
 */
class AlanyaApplication : Application() {
    companion object {
        private const val TAG = "AlanyaApplication"
        private const val CALLKIT_PREFS = "flutter_callkit_incoming"
        private const val KEY_ACTIVE = "ACTIVE_CALLS"
    }

    /** Référence forte obligatoire (sinon GC du listener). */
    private lateinit var callkitPrefs: SharedPreferences
    private var activeCallsSnapshot: JSONArray = JSONArray()

    private val activeCallsListener =
        SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
            if (key == KEY_ACTIVE) onActiveCallsChanged()
        }

    /**
     * Distingue un refus d'une expiration — voir [CallDeclineRegistry].
     *
     * Le registre du plugin ne garde que des références faibles : ce champ est
     * la référence forte obligatoire, comme pour [activeCallsListener].
     */
    private val callkitEventCallback = object : CallkitEventCallback {
        override fun onCallEvent(
            event: CallkitEventCallback.CallEvent,
            callData: android.os.Bundle,
        ) {
            if (event != CallkitEventCallback.CallEvent.DECLINE) return
            // Lecture directe de la clé plutôt que `Data.fromBundle` : celui-ci
            // déréférence `extra` sans garde de nullité et lèverait sur un
            // bundle incomplet.
            val id = callData.getString(CallkitConstants.EXTRA_CALLKIT_ID, "").trim()
            if (id.isEmpty()) return
            Log.i(TAG, "refus utilisateur explicite id=$id")
            CallDeclineRegistry.markDeclined(id)
        }
    }

    override fun onCreate() {
        super.onCreate()
        callkitPrefs = getSharedPreferences(CALLKIT_PREFS, MODE_PRIVATE)
        activeCallsSnapshot = readActiveCalls()
        callkitPrefs.registerOnSharedPreferenceChangeListener(activeCallsListener)
        Log.i(TAG, "CallKit ACTIVE_CALLS listener armé (snapshot=${activeCallsSnapshot.length()})")
        CallIncomingHelper.ensureInitialized(this)
        // Avant tout affichage : c'est ce rappel qui permettra de ne pas
        // confondre un refus avec une notification expirée.
        FlutterCallkitIncomingPlugin.registerEventCallback(callkitEventCallback)
    }

    private fun onActiveCallsChanged() {
        val before = activeCallsSnapshot
        val after = readActiveCalls()
        activeCallsSnapshot = after

        // La sonnerie native (soundManager de CallIncomingHelper) ne doit sonner
        // que tant qu'un entrant NON accepté est présent. Dès qu'un appel est
        // accepté (isAccepted=true) OU retiré (refus/timeout/dismiss), on la coupe.
        // Le receiver du plugin ne le fait pas pour cette instance (il utilise
        // celle du plugin, ou rien quand l'app est tuée) → sinon la sonnerie
        // continue après un appui sur la notification (décrocher ET raccrocher).
        val hasRingingIncoming = (0 until after.length()).any { j ->
            val c = after.optJSONObject(j)
            c != null && !c.optBoolean("isAccepted", false)
        }
        if (!hasRingingIncoming) {
            CallIncomingHelper.stopSound()
            // Même condition que la sonnerie native : couper aussi la sonnerie
            // de liste jouée nativement (accept / decline / timeout / ended, y
            // compris depuis la notification CallKit).
            CustomRingtonePlayer.stop()
        }
        // Appel passé à isAccepted : retirer la notification entrante. La branche
        // ACCEPT du service plugin ne peut pas le faire quand l'app était tuée
        // (manager null), et avec EXTRA_CALLKIT_CALLING_SHOW=false elle fait
        // stopSelf() sans rien nettoyer.
        for (i in 0 until after.length()) {
            val cur = after.optJSONObject(i) ?: continue
            if (!cur.optBoolean("isAccepted", false)) continue
            val id = cur.optString("id", "")
            if (id.isEmpty()) continue
            val wasAcceptedBefore = (0 until before.length()).any { j ->
                val p = before.optJSONObject(j)
                p?.optString("id") == id && p.optBoolean("isAccepted", false)
            }
            if (!wasAcceptedBefore) {
                CallIncomingHelper.clearIncomingNotification(this, id)
            }
        }
        // Plus AUCUN appel actif → couper aussi le service d'appel en cours
        // (notification chronomètre + raccrocher). Le plugin ne le fait pas quand
        // getInstance() est null (app tuée), d'où une notification fantôme qui
        // persiste après l'appel avec des boutons morts.
        if (after.length() == 0) {
            try {
                CallkitNotificationService.stopService(this)
            } catch (e: Exception) {
                Log.e(TAG, "stopService (ACTIVE_CALLS vide) failed", e)
            }
        }

        for (i in 0 until before.length()) {
            val prev = before.optJSONObject(i) ?: continue
            val id = prev.optString("id", "")
            if (id.isEmpty()) continue
            val stillThere = (0 until after.length()).any { j ->
                after.optJSONObject(j)?.optString("id") == id
            }
            if (stillThere) continue

            // Appel retiré : annuler ses DEUX notifications possibles.
            //
            // `cancelOngoingNotification` vise `("ongoing_$id").hashCode()` —
            // l'appel en cours. La notification d'appel ENTRANT, elle, porte
            // `id.hashCode()`, et personne ne l'annulait sur ce chemin :
            // `CallkitIncomingBroadcastReceiver` s'en remet au gestionnaire du
            // plugin, qui est nul tant qu'aucun moteur Flutter n'existe. Elle
            // survivait donc au refus, et retaper « Accepter » relançait toute
            // la chaîne d'acceptation d'un appel que l'on venait de refuser.
            CallIncomingHelper.cancelOngoingNotification(this, id)
            CallIncomingHelper.clearIncomingNotification(this, id)

            if (CallDismissRegistry.consumeIfProgrammatic(id)) {
                Log.i(TAG, "ACTIVE_CALLS: dismiss programmatique id=$id (pas de reject)")
                continue
            }

            val callerId = extractCallerId(prev)
            val callId = extractCallId(prev)
            val wasAccepted = prev.optBoolean("isAccepted", false)

            if (wasAccepted) {
                Log.i(TAG, "ACTIVE_CALLS: raccrochage notif id=$id callId=$callId")
                CallNativeBridge.notifyCallEnded(callId, callerId)
                continue
            }

            // Refus explicite ou notification expirée ? Les deux se présentent
            // ici à l'identique — une entrée a disparu. Une expiration n'a rien
            // à signaler : le minuteur du serveur la classe correctement, et lui
            // seul sait le faire. Seul un refus se signale.
            if (CallDeclineRegistry.consumeIfDeclined(id)) {
                if (callId.isNullOrBlank()) {
                    Log.w(TAG, "ACTIVE_CALLS: refus sans callId id=$id")
                } else {
                    Log.i(TAG, "ACTIVE_CALLS: refus utilisateur caller=$callerId callId=$callId")
                    CallRejectHelper.enqueueAndPost(this, callId)
                }
            } else {
                Log.i(
                    TAG,
                    "ACTIVE_CALLS: entrée expirée callId=$callId — " +
                        "aucun refus posté, le minuteur serveur tranche",
                )
            }
            CallNativeBridge.notifyCallEnded(callId, callerId)
        }
    }

    private fun readActiveCalls(): JSONArray {
        return try {
            val raw = callkitPrefs.getString(KEY_ACTIVE, "[]") ?: "[]"
            JSONArray(raw)
        } catch (e: Exception) {
            Log.e(TAG, "readActiveCalls failed", e)
            JSONArray()
        }
    }

    private fun extractCallerId(call: JSONObject): String? {
        val extra = call.optJSONObject("extra")
        val fromExtra = extra?.optString("callerId")?.trim()
        if (!fromExtra.isNullOrEmpty()) return fromExtra
        // Parfois extra est sérialisé différemment ; handle = callerId.
        val handle = call.optString("handle", "").trim()
        return handle.ifEmpty { null }
    }

    private fun extractCallId(call: JSONObject): String? {
        val extra = call.optJSONObject("extra")
        val fromExtra = extra?.optString("callId")?.trim()
        if (!fromExtra.isNullOrEmpty()) return fromExtra
        val id = call.optString("id", "").trim()
        return id.ifEmpty { null }
    }
}
