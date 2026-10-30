package com.alanya237.work

import android.app.Activity
import android.database.ContentObserver
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.plugin.common.MethodChannel

/**
 * « X A FAIT UNE CAPTURE D'ÉCRAN » (29/10/2026, demande du user) : prévient
 * Dart, par le canal `alanya/capture`, qu'une capture vient d'être prise
 * pendant que l'application est au premier plan. C'est Dart qui sait quelle
 * conversation est ouverte (`DetecteurCapture` côté Dart).
 *
 * 🔴 ANDROID 14 ET PLUS : le rappel officiel du système
 * (`registerScreenCaptureCallback`, permission DETECT_SCREEN_CAPTURE). Il ne
 * se déclenche que pour une capture de NOTRE activité, au premier plan.
 *
 * ⚠️ AVANT ANDROID 14 : aucun moyen officiel. On surveille les nouvelles
 * images de la galerie, et l'on ne retient que celle ajoutée dans les dix
 * dernières secondes dont le nom ou le dossier parle de capture. Sans la
 * permission de lire les photos, la lecture échoue et rien n'est signalé.
 *
 * ⚠️ UN ÉCRAN PROTÉGÉ (FLAG_SECURE : document sensible, vue unique) interdit
 * la capture : rien ne se prend, rien n'est signalé.
 */
class DetecteurCapture(private val activite: Activity, private val canal: MethodChannel) {

    /** `Activity.ScreenCaptureCallback`, gardé en `Any` : la classe n'existe qu'en API 34. */
    private var rappel: Any? = null
    private var observateur: ContentObserver? = null
    private var derniere = 0L

    private fun signaler() {
        val maintenant = System.currentTimeMillis()
        // Le système peut prévenir plusieurs fois pour la même capture.
        if (maintenant - derniere < 2000) return
        derniere = maintenant
        activite.runOnUiThread { canal.invokeMethod("capture", null) }
    }

    fun demarrer() {
        if (Build.VERSION.SDK_INT >= 34) {
            if (rappel != null) return
            val r = Activity.ScreenCaptureCallback { signaler() }
            runCatching { activite.registerScreenCaptureCallback(activite.mainExecutor, r) }
                .onSuccess { rappel = r }
            return
        }
        if (observateur != null) return
        val o = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean, uri: Uri?) {
                if (estCaptureRecente(uri)) signaler()
            }
        }
        runCatching {
            activite.contentResolver.registerContentObserver(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI, true, o,
            )
        }.onSuccess { observateur = o }
    }

    fun arreter() {
        if (Build.VERSION.SDK_INT >= 34) {
            (rappel as? Activity.ScreenCaptureCallback)?.let {
                runCatching { activite.unregisterScreenCaptureCallback(it) }
            }
            rappel = null
        }
        observateur?.let { runCatching { activite.contentResolver.unregisterContentObserver(it) } }
        observateur = null
    }

    @Suppress("DEPRECATION")
    private fun estCaptureRecente(uri: Uri?): Boolean = runCatching {
        val dossier = if (Build.VERSION.SDK_INT >= 29) {
            MediaStore.Images.Media.RELATIVE_PATH
        } else {
            MediaStore.Images.Media.DATA
        }
        val colonnes = arrayOf(
            MediaStore.Images.Media.DISPLAY_NAME,
            MediaStore.Images.Media.DATE_ADDED,
            dossier,
        )
        activite.contentResolver.query(
            uri ?: MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            colonnes,
            null,
            null,
            "${MediaStore.Images.Media.DATE_ADDED} DESC",
        )?.use { c ->
            if (!c.moveToFirst()) return@use false
            val nom = c.getString(0) ?: ""
            val ajout = c.getLong(1)
            val chemin = c.getString(2) ?: ""
            val recente = System.currentTimeMillis() / 1000 - ajout in 0..10
            val texte = "$nom $chemin".lowercase()
            recente && (texte.contains("screenshot") || texte.contains("capture"))
        } ?: false
    }.getOrDefault(false)
}
