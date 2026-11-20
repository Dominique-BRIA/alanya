package com.alanya237.work

import android.content.Context

/**
 * LE CHOIX DE LA CAMÉRA FAIT SUR L'ÉCRAN D'APPEL NATIF (20/11/2026).
 *
 * L'écran natif (activité de flutter_callkit_incoming) sonne application
 * fermée, en arrière-plan ou téléphone verrouillé. Son bouton « Désactiver la
 * vidéo » ([BoutonCameraAppel]) doit valoir pour l'appel décroché ensuite par
 * Flutter, qui démarre parfois APRÈS lui (démarrage à froid) : le choix est
 * donc écrit dans des préférences, et Flutter le relit au décrochage par le
 * canal `com.alanya/call_native` (`choixCameraAppel`).
 *
 * On note aussi que l'écran a été VU pour cet appel. Le « Répondre » de la
 * notification d'appel arrive à Flutter par le même événement que celui de
 * l'écran plein ; seul l'écran plein offre le choix de la caméra. Un appel
 * vidéo décroché depuis la notification — écran jamais vu — rouvre donc
 * l'écran de sonnerie Flutter au lieu de décrocher caméra allumée.
 */
object ChoixCameraAppel {
    private const val FICHIER = "alanya_camera_appel"
    /** Au-delà, une entrée appartient à un appel fini depuis longtemps. */
    private const val DUREE_MS = 6 * 60 * 60 * 1000L

    private fun prefs(ctx: Context) =
        ctx.applicationContext.getSharedPreferences(FICHIER, Context.MODE_PRIVATE)

    fun marquerVu(ctx: Context, callId: String) {
        if (callId.isEmpty()) return
        nettoyer(ctx)
        prefs(ctx).edit()
            .putBoolean("vu_$callId", true)
            .putLong("t_$callId", System.currentTimeMillis())
            .apply()
    }

    fun definirCoupee(ctx: Context, callId: String, coupee: Boolean) {
        if (callId.isEmpty()) return
        prefs(ctx).edit()
            .putBoolean("coupee_$callId", coupee)
            .putLong("t_$callId", System.currentTimeMillis())
            .apply()
    }

    fun estVu(ctx: Context, callId: String): Boolean =
        callId.isNotEmpty() && prefs(ctx).getBoolean("vu_$callId", false)

    fun estCoupee(ctx: Context, callId: String): Boolean =
        callId.isNotEmpty() && prefs(ctx).getBoolean("coupee_$callId", false)

    /** Retire les entrées des appels anciens : le fichier ne grossit jamais. */
    private fun nettoyer(ctx: Context) {
        val p = prefs(ctx)
        val limite = System.currentTimeMillis() - DUREE_MS
        val anciens = p.all.keys
            .filter { it.startsWith("t_") && p.getLong(it, 0L) < limite }
            .map { it.removePrefix("t_") }
        if (anciens.isEmpty()) return
        val e = p.edit()
        anciens.forEach { id ->
            e.remove("t_$id").remove("vu_$id").remove("coupee_$id")
        }
        e.apply()
    }
}
