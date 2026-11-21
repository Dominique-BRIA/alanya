package com.alanya237.work

import android.content.Context
import android.os.Build
import android.util.Log
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * LE JOURNAL DES CRASHS (21/11/2026).
 *
 * Quand l'application se fermait brutalement, rien n'en restait : on ne
 * pouvait que deviner. Toute erreur non rattrapée du code natif (fil principal,
 * service, tâche de fond) est désormais écrite ici avant que le système ne
 * ferme l'application, puis montrée par Flutter au lancement suivant, avec de
 * quoi la partager (`crash_journal.dart`).
 *
 * Le gestionnaire d'origine est TOUJOURS rappelé ensuite : le système ferme
 * l'application comme avant — on note, on ne masque rien.
 *
 * Seul le DERNIER crash est gardé : c'est lui qu'on veut voir, et le fichier
 * ne grossit jamais. Aucune donnée de l'utilisateur n'y entre, seulement la
 * pile d'appels, la version et le modèle du téléphone.
 */
object JournalCrash {
    private const val FICHIER = "dernier_crash.txt"
    private const val TAG = "JournalCrash"

    fun installer(context: Context) {
        val ctx = context.applicationContext
        val precedent = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { fil, erreur ->
            try {
                noter(ctx, fil, erreur)
            } catch (_: Throwable) {
                // Ne jamais empêcher la fermeture normale.
            }
            precedent?.uncaughtException(fil, erreur)
        }
    }

    private fun noter(ctx: Context, fil: Thread, erreur: Throwable) {
        val version = try {
            ctx.packageManager.getPackageInfo(ctx.packageName, 0).versionName ?: "?"
        } catch (_: Exception) {
            "?"
        }
        val date = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date())
        val texte = buildString {
            append("Date : ").append(date).append('\n')
            append("Version : ").append(version).append('\n')
            append("Android : ").append(Build.VERSION.RELEASE)
                .append(" (API ").append(Build.VERSION.SDK_INT).append(")\n")
            append("Téléphone : ").append(Build.MANUFACTURER).append(' ').append(Build.MODEL).append('\n')
            append("Fil : ").append(fil.name).append("\n\n")
            append(Log.getStackTraceString(erreur))
        }
        File(ctx.filesDir, FICHIER).writeText(texte.take(20_000))
        Log.e(TAG, "crash noté", erreur)
    }

    /** Le dernier crash noté, ou null. */
    fun lire(ctx: Context): String? = try {
        File(ctx.filesDir, FICHIER).takeIf { it.exists() }?.readText()
    } catch (_: Exception) {
        null
    }

    fun effacer(ctx: Context) {
        try {
            File(ctx.filesDir, FICHIER).delete()
        } catch (_: Exception) {
        }
    }
}
