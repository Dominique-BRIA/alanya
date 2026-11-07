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

    /**
     * [jetonRefus] : le jeton porté par le push d'appel (07/11/2026). Il ne vaut
     * que pour refuser CET appel, mais il est valable pendant toute la sonnerie,
     * là où le jeton d'accès laissé par Flutter expire 15 minutes après la
     * dernière ouverture de l'application. Sans lui, application fermée depuis
     * plus longtemps, le refus recevait un 401 et l'appelant sonnait jusqu'au
     * bout.
     */
    fun enqueueAndPost(context: Context, callId: String, jetonRefus: String = "") {
        if (callId.isBlank()) return
        enqueuePending(context, callId)
        executor.execute {
            try {
                postReject(context, callId, jetonRefus)
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

    /** 2xx : refusé. 404/409 : l'appel est déjà clos, plus rien à refuser. */
    private fun estDefinitif(code: Int) = code in 200..299 || code == 404 || code == 409

    private fun postReject(context: Context, callId: String, jetonRefus: String) {
        val prefs = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
        val token = prefs.getString(KEY_TOKEN, null)
        val apiBase = prefs.getString(KEY_API_BASE, null)
        if (apiBase.isNullOrBlank() || !apiBase.startsWith("https://")) {
            Log.w(TAG, "apiBase manquante — refus en file pour Flutter")
            return
        }
        if (jetonRefus.isBlank() && token.isNullOrBlank()) {
            Log.w(TAG, "aucun jeton — refus en file pour Flutter")
            return
        }
        // Quelques tentatives rapprochées : le refus n'a de sens que pendant la
        // sonnerie, et Flutter ne rejouera la file qu'à la prochaine ouverture.
        val delais = longArrayOf(0L, 2_000L, 5_000L)
        for (delai in delais) {
            if (delai > 0) Thread.sleep(delai)
            val code = tenter(apiBase, callId, jetonRefus, token)
            Log.i(TAG, "POST /api/calls/$callId/reject → HTTP $code")
            if (estDefinitif(code)) {
                removePending(context, callId)
                return
            }
            // 401/403 : aucun des deux jetons n'est accepté, réessayer n'y
            // changera rien. Flutter, qui sait renouveler la session, reprendra.
            if (code == 401 || code == 403) return
        }
    }

    /**
     * Le jeton de refus d'abord, la session ensuite : un serveur antérieur au
     * jeton de refus l'ignore et répond 401, la session prend alors le relais.
     */
    private fun tenter(apiBase: String, callId: String, jetonRefus: String, token: String?): Int {
        var code = -1
        if (jetonRefus.isNotBlank()) {
            code = doRejectPost(apiBase, callId, "X-Jeton-Refus", jetonRefus)
            if (estDefinitif(code) || code == -1 || code >= 500) return code
        }
        if (!token.isNullOrBlank()) {
            code = doRejectPost(apiBase, callId, "Authorization", "Bearer $token")
        }
        return code
    }

    /** POST avec l'en-tête d'identification fourni. Code HTTP, ou -1 si échec réseau. */
    private fun doRejectPost(apiBase: String, callId: String, entete: String, valeur: String): Int {
        val url = URL("${apiBase.trimEnd('/')}/api/calls/$callId/reject")
        val conn = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 8000
            readTimeout = 8000
            doOutput = true
            setRequestProperty("Content-Type", "application/json")
            setRequestProperty(entete, valeur)
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
