package com.alanya237.work

import android.app.Activity
import android.app.KeyguardManager
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import androidx.core.app.NotificationManagerCompat
import com.hiennv.flutter_callkit_incoming.CallkitConstants
import com.hiennv.flutter_callkit_incoming.CallkitIncomingActivity
import com.hiennv.flutter_callkit_incoming.CallkitIncomingBroadcastReceiver
import com.hiennv.flutter_callkit_incoming.CallkitNotificationManager
import com.hiennv.flutter_callkit_incoming.getDataActiveCalls

/**
 * L'ÉCRAN D'APPEL TOUJOURS AU PREMIER PLAN (07/11/2026).
 *
 * Une notification plein écran (« full-screen intent ») ne suffit pas à
 * garantir qu'un appel s'affiche. Android ne lance son écran que dans un cas
 * précis : téléphone verrouillé ou écran éteint, ET autorisation « plein
 * écran » accordée. Partout ailleurs, il se contente d'une BANNIÈRE :
 *
 * - téléphone déverrouillé, en cours d'utilisation : bannière qui disparaît
 *   après quelques secondes — il faut ensuite dérouler le panneau ;
 * - autorisation « plein écran » refusée (Android 14 et plus, souvent par
 *   défaut) : rien ne s'allume, le téléphone sonne écran noir.
 *
 * Seule l'application peut alors imposer l'écran d'appel, en le lançant
 * elle-même. Android l'autorise depuis l'arrière-plan à une condition :
 * l'utilisateur lui a accordé « Afficher par-dessus les autres applications ».
 * Depuis Android 15, il faut en plus qu'une fenêtre de superposition soit
 * VISIBLE au moment du lancement : on en pose une, d'un pixel et
 * transparente, le temps du lancement.
 *
 * [etat] et [ouvrir] servent l'écran « Fiabilité des appels », qui fait
 * accorder ces autorisations.
 */
object AffichageAppel {
    private const val TAG = "AffichageAppel"
    private val principal = Handler(Looper.getMainLooper())

    // ── Présentation de l'appel ────────────────────────────────────────────

    /**
     * Lance l'écran d'appel CallKit quand la notification seule ne
     * l'afficherait pas. Sans effet quand Android s'en charge lui-même
     * (verrouillé ou éteint, plein écran autorisé) : deux lancements
     * successifs feraient clignoter l'écran.
     */
    fun presenter(context: Context, bundle: Bundle) {
        val ctx = context.applicationContext
        val pm = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
        val km = ctx.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        val allume = pm.isInteractive
        val verrouille = km.isKeyguardLocked
        val pleinEcran = pleinEcranAutorise(ctx)
        val androidLeFait = pleinEcran && (!allume || verrouille)
        if (!Settings.canDrawOverlays(ctx)) {
            if (!androidLeFait) {
                Log.w(TAG, "superposition refusée : l'appel reste en bannière (allumé=$allume pleinEcran=$pleinEcran)")
            }
            return
        }
        if (!androidLeFait) {
            principal.post { lancer(ctx, bundle, allume) }
            return
        }
        // ⚠️ ANDROID DIT QU'IL S'EN CHARGE — ON VÉRIFIE (07/11/2026). Sur TECNO
        // (et d'autres surcouches), l'autorisation plein écran est bien
        // accordée, mais le fabricant bloque le lancement : le téléphone sonne
        // écran éteint, sans rien afficher. Si l'écran d'appel n'est pas à
        // l'écran un instant plus tard alors que l'appel sonne encore, on le
        // lance nous-mêmes.
        val callId = bundle.getString(CallkitConstants.EXTRA_CALLKIT_ID, "")
        principal.postDelayed({
            if (ecranAppelVisible) return@postDelayed
            if (!sonneEncore(ctx, callId)) return@postDelayed
            Log.w(TAG, "plein écran annoncé mais absent (surcouche du fabricant ?) → lancement direct")
            lancer(ctx, bundle, pm.isInteractive)
        }, 1_500)
    }

    /** Vrai tant que l'écran d'appel CallKit est affiché (voir AlanyaApplication). */
    @Volatile var ecranAppelVisible = false

    /** L'appel montré par l'écran d'appel affiché, ou vide. */
    @Volatile private var appelAffiche = ""

    /** Les appels dont l'expiration est programmée ici : une seule fois chacun. */
    private val expirationsProgrammees = HashSet<String>()

    /*
     * UN SEUL AFFICHAGE À LA FOIS : L'ÉCRAN OU LA NOTIFICATION (07/11/2026).
     *
     * La notification d'appel est posée à l'arrivée de l'appel ; l'écran
     * d'appel s'ouvre ensuite. Quand c'est NOUS qui l'ouvrons (téléphone
     * déverrouillé, ou plein écran bloqué par le fabricant), Android affichait
     * en même temps la notification en bannière, par-dessus l'écran.
     *
     * - L'écran est affiché → la notification est retirée. Retirée encore un
     *   peu plus tard : le plugin la repose quand la photo de l'appelant finit
     *   de charger.
     * - L'utilisateur QUITTE l'écran sans répondre, alors que ça sonne encore
     *   → la même notification est remise (Accepter / Refuser, et un toucher
     *   rouvre l'écran), sinon il entendrait sonner sans moyen de répondre.
     *   Pas écran éteint : la remettre relancerait le plein écran et
     *   rallumerait le téléphone ; au rallumage l'écran d'appel revient de
     *   lui-même.
     *
     * La sonnerie ne dépend pas de la notification : elle continue.
     */
    fun ecranAffiche(context: Context, callId: String) {
        if (callId.isEmpty()) return
        val ctx = context.applicationContext
        appelAffiche = callId
        CallIncomingHelper.masquerNotification(ctx, callId)
        for (delai in longArrayOf(800, 2_000, 4_000)) {
            principal.postDelayed({
                if (ecranAppelVisible && appelAffiche == callId) {
                    CallIncomingHelper.masquerNotification(ctx, callId)
                }
            }, delai)
        }
        programmerExpiration(ctx, callId)
    }

    fun ecranQuitte(context: Context, callId: String, fermeture: Boolean) {
        if (callId.isEmpty()) return
        val ctx = context.applicationContext
        if (appelAffiche == callId) appelAffiche = ""
        // Écran fermé (décroché, refusé, expiré, annulé) : rien à remettre.
        if (fermeture) return
        principal.postDelayed({
            if (ecranAppelVisible) return@postDelayed // revenu entre-temps
            val pm = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
            if (!pm.isInteractive) return@postDelayed
            if (!sonneEncore(ctx, callId)) return@postDelayed
            CallIncomingHelper.remettreNotification(ctx, callId)
        }, 600)
    }

    /**
     * ⚠️ L'EXPIRATION DE LA SONNERIE ÉTAIT PORTÉE PAR LA NOTIFICATION. Le
     * plugin la déclenche quand sa notification arrive au bout de son délai
     * (arrêt du son, appel manqué, retrait de l'appel) ; l'écran d'appel, lui,
     * se ferme seulement. Notification retirée, plus rien n'expirait : la
     * sonnerie aurait continué indéfiniment. On envoie donc nous-mêmes, au
     * même instant, l'ordre d'expiration du plugin — sans effet si l'appel ne
     * sonne plus.
     */
    private fun programmerExpiration(ctx: Context, callId: String) {
        synchronized(expirationsProgrammees) {
            if (!expirationsProgrammees.add(callId)) return
        }
        val bundle = CallIncomingHelper.bundleDe(callId) ?: return
        val duree = bundle.getLong(CallkitConstants.EXTRA_CALLKIT_DURATION, 0L)
        if (duree <= 0L) return
        val debut = bundle.getLong(CallkitNotificationManager.EXTRA_TIME_START_CALL, System.currentTimeMillis())
        val reste = (debut + duree - System.currentTimeMillis()).coerceAtLeast(0L)
        principal.postDelayed({
            synchronized(expirationsProgrammees) { expirationsProgrammees.remove(callId) }
            if (!sonneEncore(ctx, callId)) return@postDelayed
            Log.i(TAG, "expiration de la sonnerie (notification retirée) callId=$callId")
            try {
                ctx.sendBroadcast(CallkitIncomingBroadcastReceiver.getIntentTimeout(ctx, bundle))
            } catch (e: Exception) {
                Log.e(TAG, "expiration non envoyée", e)
            }
        }, reste)
    }

    private fun sonneEncore(ctx: Context, callId: String): Boolean = try {
        getDataActiveCalls(ctx).any { it.id == callId && !it.isAccepted }
    } catch (_: Exception) {
        false
    }

    private fun lancer(ctx: Context, bundle: Bundle, allume: Boolean) {
        // Écran éteint : on l'allume, l'écran d'appel prend ensuite le relais
        // (il pose lui-même l'allumage et le passage sur le verrouillage).
        if (!allume) {
            try {
                val pm = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
                @Suppress("DEPRECATION")
                pm.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                    "Alanya:AppelEntrant",
                ).acquire(5_000)
            } catch (e: Exception) {
                Log.w(TAG, "réveil de l'écran : $e")
            }
        }
        val fenetre = poserFenetreTemoin(ctx)
        try {
            ctx.startActivity(CallkitIncomingActivity.getIntent(ctx, bundle))
            Log.i(TAG, "écran d'appel lancé au premier plan")
        } catch (e: Exception) {
            Log.e(TAG, "lancement de l'écran d'appel refusé", e)
        }
        // Retirée après coup : le lancement est décidé, l'écran d'appel est là.
        if (fenetre != null) principal.postDelayed({ retirer(ctx, fenetre) }, 2_000)
    }

    /** Fenêtre de superposition d'un pixel, exigée par Android 15. */
    private fun poserFenetreTemoin(ctx: Context): View? = try {
        val wm = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val vue = View(ctx)
        @Suppress("DEPRECATION")
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else WindowManager.LayoutParams.TYPE_PHONE
        val lp = WindowManager.LayoutParams(
            1, 1, type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply { gravity = Gravity.TOP or Gravity.START }
        wm.addView(vue, lp)
        vue
    } catch (e: Exception) {
        Log.w(TAG, "fenêtre témoin : $e")
        null
    }

    private fun retirer(ctx: Context, vue: View) {
        try {
            (ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager).removeView(vue)
        } catch (_: Exception) {}
    }

    // ── État des autorisations ─────────────────────────────────────────────

    private fun pleinEcranAutorise(ctx: Context): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            (ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .canUseFullScreenIntent()
        } else true

    /** Le canal des appels sonne-t-il ET s'affiche-t-il à l'écran ? */
    private fun canalAppelsActif(ctx: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val canal = nm.getNotificationChannel(CallkitNotificationManager.NOTIFICATION_CHANNEL_ID_INCOMING)
            ?: return true // pas encore créé : il le sera à l'importance haute
        return canal.importance >= NotificationManager.IMPORTANCE_HIGH
    }

    fun etat(ctx: Context): Map<String, Any> {
        val pm = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
        return mapOf(
            "notifications" to NotificationManagerCompat.from(ctx).areNotificationsEnabled(),
            "canalAppels" to canalAppelsActif(ctx),
            "pleinEcran" to pleinEcranAutorise(ctx),
            "superposition" to Settings.canDrawOverlays(ctx),
            "batterie" to pm.isIgnoringBatteryOptimizations(ctx.packageName),
            "fabricant" to Build.MANUFACTURER.lowercase(),
        )
    }

    // ── Ouverture des réglages ─────────────────────────────────────────────

    /** Ouvre la page de réglages qui accorde [quoi]. Faux si aucune n'existe. */
    fun ouvrir(activity: Activity, quoi: String): Boolean {
        val pkg = activity.packageName
        val paquet = Uri.fromParts("package", pkg, null)
        val candidats: List<Intent> = when (quoi) {
            "notifications" -> listOf(
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, pkg),
            )
            "canalAppels" -> listOf(
                Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, pkg)
                    .putExtra(Settings.EXTRA_CHANNEL_ID, CallkitNotificationManager.NOTIFICATION_CHANNEL_ID_INCOMING),
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, pkg),
            )
            "pleinEcran" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                listOf(Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, paquet))
            } else emptyList()
            "superposition" -> listOf(
                Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, paquet),
            )
            "batterie" -> listOf(
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, paquet),
                Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS),
            )
            // Réglages propres au fabricant (démarrage automatique, affichage
            // sur l'écran de verrouillage, fenêtres en arrière-plan) : aucune
            // API commune, on essaie les pages connues, puis la fiche de
            // l'application.
            "fabricant" -> listOf(
                Intent().setComponent(ComponentName(
                    "com.miui.securitycenter",
                    "com.miui.permcenter.permissions.PermissionsEditorActivity",
                )).putExtra("extra_pkgname", pkg),
                Intent().setComponent(ComponentName(
                    "com.transsion.phonemaster",
                    "com.cyin.himgr.autostart.AutoStartActivity",
                )),
                Intent().setComponent(ComponentName(
                    "com.coloros.safecenter",
                    "com.coloros.safecenter.permission.startup.StartupAppListActivity",
                )),
                Intent().setComponent(ComponentName(
                    "com.huawei.systemmanager",
                    "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
                )),
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, paquet),
            )
            else -> listOf(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, paquet))
        }
        for (intent in candidats) {
            try {
                activity.startActivity(intent)
                return true
            } catch (_: Exception) {
                // Page absente sur ce téléphone : la suivante.
            }
        }
        return false
    }
}
