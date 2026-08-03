package com.alanya237.work

import android.app.KeyguardManager
import android.content.Context
import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Affichage de l'écran d'appel PAR-DESSUS L'ÉCRAN VERROUILLÉ.
 *
 * C'est ce qui manquait pour reproduire le comportement de WhatsApp : la
 * notification plein écran lance bien l'application, mais sans ces réglages
 * Android la place derrière le verrouillage. L'utilisateur doit alors
 * déverrouiller pour découvrir l'appel, souvent trop tard.
 *
 * ⚠️ ACTIVÉ À LA DEMANDE, JAMAIS EN PERMANENCE. Poser `showWhenLocked` dans le
 * manifeste rendrait TOUTE l'application accessible sans déverrouiller — donc
 * les conversations, les médias et les réglages. Ici Flutter n'allume le
 * comportement que le temps d'un appel entrant et l'éteint juste après, si bien
 * que le verrouillage protège l'application le reste du temps.
 */
class MainActivity : FlutterActivity() {

    private companion object {
        const val CANAL = "alanya/ecran_verrouille"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CANAL)
            .setMethodCallHandler { appel, resultat ->
                when (appel.method) {
                    "afficherParDessusVerrouillage" -> {
                        val actif = appel.argument<Boolean>("actif") ?: false
                        afficherParDessusVerrouillage(actif)
                        resultat.success(true)
                    }
                    else -> resultat.notImplemented()
                }
            }
    }

    private fun afficherParDessusVerrouillage(actif: Boolean) {
        runOnUiThread {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                setShowWhenLocked(actif)
                setTurnScreenOn(actif)
                if (actif) {
                    // Écarte l'écran de verrouillage quand il n'a pas de code.
                    // Avec un code, Android le laisse en place : on ne contourne
                    // pas une protection, on se contente de s'afficher par-dessus.
                    val keyguard = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
                    keyguard?.requestDismissKeyguard(this, null)
                }
            } else {
                // Avant Android 8.1, les mêmes effets passent par des drapeaux de
                // fenêtre. Ils sont dépréciés depuis, d'où les deux chemins.
                @Suppress("DEPRECATION")
                val drapeaux = WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
                if (actif) {
                    window.addFlags(drapeaux)
                } else {
                    window.clearFlags(drapeaux)
                }
            }
        }
    }
}
