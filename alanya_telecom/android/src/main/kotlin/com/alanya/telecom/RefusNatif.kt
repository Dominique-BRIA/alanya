package com.alanya.telecom

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

private const val TAG = "AlanyaTelecom"

/**
 * Le refus d'un appel, envoyé par le NATIF, sans attendre Flutter (06/11/2026).
 *
 * Même principe que l'application de référence (`CallRejectHelper`) :
 *
 * 1. Le refus est d'abord ÉCRIT dans la file, avec `commit()` et non
 *    `apply()` : ce chemin part d'un bouton de notification ou de l'écran
 *    natif, et le processus peut être tué dès le geste traité. Une file non
 *    écrite sur le disque, c'est un refus perdu des deux côtés.
 * 2. Puis il part au serveur, sur un fil à part, avec le jeton d'accès que
 *    l'application recopie pour le natif (`jeton_acces_natif`).
 * 3. Réussi ou définitivement inutile (appel déjà clos), il sort de la file.
 *    Sinon il y reste, réessayé quelques fois tant que l'appel peut encore
 *    sonner, puis rejoué par Flutter à la prochaine ouverture.
 *
 * ⚠️ LA FILE EST CELLE DE FLUTTER (`RefusEnAttente`, clé
 * `refus_appels_en_attente`) : un seul registre des refus en attente, quel
 * que soit le côté qui les a pris. Chaque côté vérifie que le refus y est
 * encore avant de l'envoyer : un refus parti n'est jamais renvoyé.
 *
 * ⚠️ PAS DE RENOUVELLEMENT DE SESSION ICI, contrairement à la référence.
 * Notre serveur remplace le jeton de renouvellement à chaque usage : le
 * consommer côté natif déconnecterait l'application. Un jeton d'accès
 * expiré (401) laisse donc le refus en file pour Flutter, qui sait le
 * renouveler.
 */
object RefusNatif {
    private const val PREFS = "FlutterSharedPreferences"
    private const val CLE_FILE = "flutter.refus_appels_en_attente"
    private const val CLE_JETON = "flutter.jeton_acces_natif"
    private const val CLE_API = "flutter.api_base_natif"
    private val DELAIS_MS = longArrayOf(0, 4_000, 8_000, 15_000, 25_000, 35_000)

    private val executeur = Executors.newSingleThreadExecutor()
    private val principal = Handler(Looper.getMainLooper())

    fun refuser(ctx: Context, callId: String?) {
        if (callId.isNullOrEmpty()) return
        val app = ctx.applicationContext
        enfiler(app, callId)
        essayer(app, callId, 0)
    }

    private fun essayer(ctx: Context, callId: String, tentative: Int) {
        if (tentative >= DELAIS_MS.size) return
        principal.postDelayed({
            executeur.execute {
                if (!enFile(ctx, callId)) return@execute
                when (envoyer(ctx, callId)) {
                    Issue.FAIT -> retirer(ctx, callId)
                    Issue.A_REFAIRE -> essayer(ctx, callId, tentative + 1)
                    Issue.POUR_FLUTTER -> Unit
                }
            }
        }, DELAIS_MS[tentative])
    }

    private enum class Issue { FAIT, A_REFAIRE, POUR_FLUTTER }

    private fun envoyer(ctx: Context, callId: String): Issue {
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val jeton = prefs.getString(CLE_JETON, null)
        val base = prefs.getString(CLE_API, null)
        if (jeton.isNullOrEmpty() || base.isNullOrEmpty() || !base.startsWith("https://")) {
            Log.w(TAG, "refus natif : jeton ou adresse absents → laissé à Flutter")
            return Issue.POUR_FLUTTER
        }
        val c = URL("${base.trimEnd('/')}/api/calls/$callId/reject")
            .openConnection() as HttpURLConnection
        return try {
            c.requestMethod = "POST"
            c.connectTimeout = 8000
            c.readTimeout = 8000
            c.doOutput = true
            c.setRequestProperty("Content-Type", "application/json")
            c.setRequestProperty("Authorization", "Bearer $jeton")
            c.outputStream.use { it.write("{}".toByteArray()) }
            val code = c.responseCode
            Log.d(TAG, "refus natif POST → $code")
            when {
                code == 401 -> Issue.POUR_FLUTTER
                code >= 500 || code == 408 || code == 429 -> Issue.A_REFAIRE
                // 2xx, ou 404/409 : l'appel est refusé, ou déjà clos.
                else -> Issue.FAIT
            }
        } catch (e: Exception) {
            Log.w(TAG, "refus natif (réseau) : $e")
            Issue.A_REFAIRE
        } finally {
            c.disconnect()
        }
    }

    @Synchronized
    private fun lire(ctx: Context): JSONObject = try {
        JSONObject(
            ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(CLE_FILE, null) ?: "{}"
        )
    } catch (_: Exception) {
        JSONObject()
    }

    @Synchronized
    private fun enfiler(ctx: Context, callId: String) {
        val file = lire(ctx)
        if (!file.has(callId)) file.put(callId, System.currentTimeMillis())
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(CLE_FILE, file.toString()).commit()
    }

    @Synchronized
    private fun retirer(ctx: Context, callId: String) {
        val file = lire(ctx)
        if (file.remove(callId) == null) return
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(CLE_FILE, file.toString()).commit()
    }

    private fun enFile(ctx: Context, callId: String): Boolean = lire(ctx).has(callId)
}
