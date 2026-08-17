package com.alanya237.work

import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import com.alanya.telecom.CallRegistry
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

    /**
     * ⚠️ SANS CECI, UN APPEL REÇU ÉCRAN EN VEILLE SONNE SANS QU'ON PUISSE
     * DÉCROCHER.
     *
     * La notification d'appel porte un « full-screen intent » qui lance bien
     * cette activité, mais Android n'allume l'écran que si les drapeaux sont
     * posés AVANT la création de la fenêtre. Après, la décision est prise :
     * l'activité démarre derrière un écran resté noir.
     *
     * Or `LockScreenCall.activer()`, côté Dart, ne peut s'exécuter qu'une fois
     * l'application démarrée et le WebSocket connecté — une dizaine de secondes
     * au démarrage à froid. Beaucoup trop tard.
     *
     * On interroge donc l'état RÉEL du module Telecom, seul à savoir dès la
     * première milliseconde qu'un appel sonne, et on n'allume le comportement
     * que dans ce cas : le verrouillage continue de protéger les conversations
     * le reste du temps, ce qui est précisément la raison pour laquelle
     * `showWhenLocked` n'est pas dans le manifeste.
     */
    override fun onCreate(savedInstanceState: Bundle?) {
        // `runCatching` : on est AVANT super.onCreate, le point le plus fragile
        // du cycle de vie. Une exception ici empêcherait l'application entière
        // de démarrer — un appel qu'on n'arrive pas à décrocher reste
        // infiniment préférable à une application qui ne s'ouvre plus.
        if (unAppelSonne()) runCatching { afficherParDessusVerrouillage(true) }
        super.onCreate(savedInstanceState)
    }

    /**
     * Même situation quand le processus est encore vivant : l'activité existe
     * déjà (`launchMode="singleTask"`), le full-screen intent la ramène au
     * premier plan par ce chemin-ci et non par `onCreate`.
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (unAppelSonne()) runCatching { afficherParDessusVerrouillage(true) }
    }

    /**
     * Un appel Telecom est-il en train de sonner ?
     *
     * Le contrôle de version est indispensable : `CallRegistry` manipule des
     * `Connection`, qui n'existent qu'à partir d'Android 8, alors que
     * l'application descend jusqu'à Android 7 (`minSdk` 24). Y toucher plus bas
     * lèverait une erreur de vérification de classe au chargement.
     */
    private fun unAppelSonne(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            runCatching { CallRegistry.ringingData() != null }.getOrDefault(false)

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
                    // Service de premier plan qui maintient l'appel vivant
                    // quand l'application quitte l'écran. Voir
                    // CallForegroundService pour le détail des verrous.
                    "demarrerServiceAppel" -> {
                        val titre = appel.argument<String>("titre") ?: "Appel en cours"
                        val i = Intent(this, CallForegroundService::class.java).apply {
                            action = CallForegroundService.ACTION_DEMARRER
                            putExtra(CallForegroundService.EXTRA_TITRE, titre)
                        }
                        // startForegroundService à partir d'Android 8 : le
                        // service doit alors appeler startForeground() dans les
                        // 5 s, sinon le système le tue avec une ANR.
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(i)
                        } else {
                            startService(i)
                        }
                        resultat.success(true)
                    }
                    "arreterServiceAppel" -> {
                        startService(
                            Intent(this, CallForegroundService::class.java).apply {
                                action = CallForegroundService.ACTION_ARRETER
                            },
                        )
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
