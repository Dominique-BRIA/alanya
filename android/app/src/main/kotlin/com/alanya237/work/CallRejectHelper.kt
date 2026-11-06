package com.alanya237.work

import android.content.Context
import android.util.Log
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/**
 * Persistance + POST du refus côté natif (app tuée / sans Flutter).
 *
 * Copie de `CallRejectHelper` de l'application de référence (06/11/2026),
 * adaptée à notre serveur :
 *
 * - Route : `POST /api/calls/<callId>/reject` (et non `/calls/reject` avec
 *   l'appelant dans le corps).
 * - File : celle de Flutter (`RefusEnAttente`, clé `refus_appels_en_attente`,
 *   identifiant d'appel → instant du refus). Un seul registre des refus en
 *   attente, quel que soit le côté qui les a pris ; Flutter la rejoue à la
 *   prochaine ouverture.
 * - ⚠️ PAS DE RENOUVELLEMENT DE SESSION ICI. Notre serveur remplace le jeton
 *   de renouvellement à chaque usage (celui de la référence ne le fait pas) :
 *   le consommer côté natif déconnecterait l'application. Un jeton d'accès
 *   expiré (401) laisse le refus en file pour Flutter, qui sait le renouveler.
 */
object CallRejectHelper {
    private const val TAG = "CallRejectHelper"
    private const val FLUTTER_PREFS = "FlutterSharedPreferences"
    private const val KEY_PENDING = "flutter.refus_appels_en_attente"
    private const val KEY_TOKEN = "flutter.jeton_acces_natif"
    private const val KEY_API_BASE = "flutter.api_base_natif"

    private val executor = Executors.newSingleThreadExecutor()

    fun enqueueAndPost(context: Context, callId: String) {
        if (callId.isBlank()) return
        enqueuePending(context, callId)
        executor.execute {
            try {
                postReject(context, callId)
            } catch (e: Exception) {
                Log.e(TAG, "postReject failed", e)
            }
        }
    }

    @Synchronized
    fun enqueuePending(context: Context, callId: String) {
        try {
            val prefs = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            val file = JSONObject(prefs.getString(KEY_PENDING, null) ?: "{}")
            if (!file.has(callId)) file.put(callId, System.currentTimeMillis())
            // `commit()` et non `apply()` : ce chemin s'exécute dans un
            // receiver, et le processus peut être tué dès son retour. Le POST
            // part sur un exécuteur détaché qui n'a rien pour retenir le
            // processus ; si la file n'est pas écrite sur le disque avant, le
            // refus est perdu des deux côtés.
            prefs.edit().putString(KEY_PENDING, file.toString()).commit()
            Log.i(TAG, "enqueue callId=$callId")
        } catch (e: Exception) {
            Log.e(TAG, "enqueuePending failed", e)
        }
    }

    private fun postReject(context: Context, callId: String) {
        val prefs = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
        val token = prefs.getString(KEY_TOKEN, null)
        val apiBase = prefs.getString(KEY_API_BASE, null)
        if (token.isNullOrBlank() || apiBase.isNullOrBlank() || !apiBase.startsWith("https://")) {
            Log.w(TAG, "token/apiBase manquants — refus en file pour Flutter")
            return
        }
        val code = doRejectPost(apiBase, token, callId)
        Log.i(TAG, "POST /api/calls/$callId/reject → HTTP $code")
        // 2xx : refusé. 404/409 : l'appel est déjà clos, il n'y a plus rien à
        // refuser. Tout le reste (réseau, 401, 5xx) reste en file, rejoué par
        // Flutter à la prochaine ouverture.
        if (code in 200..299 || code == 404 || code == 409) {
            removePending(context, callId)
        }
    }

    /** POST avec le token fourni. Retourne le code HTTP (-1 si échec réseau). */
    private fun doRejectPost(apiBase: String, token: String, callId: String): Int {
        val url = URL("${apiBase.trimEnd('/')}/api/calls/$callId/reject")
        val conn = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 8000
            readTimeout = 8000
            doOutput = true
            setRequestProperty("Content-Type", "application/json")
            setRequestProperty("Authorization", "Bearer $token")
        }
        return try {
            conn.outputStream.use { it.write("{}".toByteArray()) }
            conn.responseCode
        } catch (e: Exception) {
            Log.e(TAG, "doRejectPost failed", e)
            -1
        } finally {
            conn.disconnect()
        }
    }

    @Synchronized
    private fun removePending(context: Context, callId: String) {
        try {
            val prefs = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            val file = JSONObject(prefs.getString(KEY_PENDING, null) ?: "{}")
            if (file.remove(callId) == null) return
            prefs.edit().putString(KEY_PENDING, file.toString()).commit()
        } catch (e: Exception) {
            Log.e(TAG, "removePending failed", e)
        }
    }
}
