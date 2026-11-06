package com.alanya237.work

import android.app.Activity
import android.app.PictureInPictureParams
import android.os.Build
import android.util.Log
import android.util.Rational
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * FENETRE FLOTTANTE DU SYSTEME pendant un appel video (06/11/2026), comme
 * WhatsApp : on quitte l'application, l'image du correspondant reste a l'ecran
 * dans une petite fenetre au-dessus des autres applications.
 * Canal : `alanya/pip`.
 *
 * Flutter -> natif : `setEligible` dit si un appel video est en cours, donc si
 * quitter l'application doit ouvrir la fenetre. `enterNow` l'ouvre tout de suite.
 *
 * Natif -> Flutter : `onPipModeChanged` previent des deux transitions. Elle est
 * indispensable : dans la fenetre, l'activite est EN PAUSE TOUT EN RESTANT
 * VISIBLE, si bien que Flutter ne peut pas le deduire du cycle de vie. C'est ce
 * qui fait passer l'ecran a la disposition reduite (l'image seule).
 *
 * La fenetre demande l'API 26 ; l'application accepte l'API 23. En dessous,
 * tout ici est inerte et l'appel se comporte comme avant.
 */
object PipBridge {
    private const val TAG = "AlanyaPip"
    private const val CANAL = "alanya/pip"

    private var canal: MethodChannel? = null
    private var activite: Activity? = null

    /** Un appel video est en cours : quitter l'application ouvre la fenetre. */
    private var eligible = false

    private val supporte: Boolean
        get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O

    /** L'entree automatique, qui couvre tous les chemins de sortie, demande l'API 31. */
    private val entreeAutoSupportee: Boolean
        get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S

    fun attach(messenger: BinaryMessenger, activity: Activity) {
        activite = activity
        canal = MethodChannel(messenger, CANAL).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "setEligible" -> {
                        eligible = call.argument<Boolean>("eligible") ?: false
                        appliquerParametres()
                        result.success(supporte)
                    }
                    "enterNow" -> result.success(entrer(activity))
                    else -> result.notImplemented()
                }
            }
        }
    }

    fun detach() {
        canal?.setMethodCallHandler(null)
        canal = null
        activite = null
        eligible = false
    }

    /**
     * L'entree automatique (API 31+) : c'est le systeme qui ouvre la fenetre
     * des que l'activite passerait en arriere-plan, quel que soit le chemin —
     * Accueil, geste, applications recentes. En dessous, `onUserLeaveHint`
     * couvre l'Accueil et Flutter rattrape le retour arriere.
     */
    private fun appliquerParametres() {
        if (!entreeAutoSupportee) return
        val act = activite ?: return
        try {
            act.setPictureInPictureParams(parametres())
        } catch (e: IllegalStateException) {
            Log.w(TAG, "entree automatique refusee: ${e.message}")
        } catch (e: IllegalArgumentException) {
            Log.w(TAG, "parametres refuses: ${e.message}")
        }
    }

    private fun parametres(): PictureInPictureParams {
        // Portrait 9:16 : l'image d'un telephone tenu droit.
        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(Rational(9, 16))
        if (entreeAutoSupportee) builder.setAutoEnterEnabled(eligible)
        return builder.build()
    }

    /** Bouton Accueil : le seul moment ou Android accepte encore la fenetre sans entree automatique. */
    fun onUserLeaveHint(activity: Activity) {
        if (!eligible) return
        entrer(activity)
    }

    private fun entrer(activity: Activity): Boolean {
        if (!supporte) return false
        if (activity.isInPictureInPictureMode) return true
        return try {
            activity.enterPictureInPictureMode(parametres())
        } catch (e: IllegalStateException) {
            // Fenetre desactivee dans les reglages, activite deja en pause :
            // l'appel continue, sans fenetre.
            Log.w(TAG, "entree refusee: ${e.message}")
            false
        } catch (e: IllegalArgumentException) {
            Log.w(TAG, "parametres refuses: ${e.message}")
            false
        }
    }

    fun notifierChangement(enFenetre: Boolean) {
        canal?.invokeMethod("onPipModeChanged", enFenetre)
    }
}
