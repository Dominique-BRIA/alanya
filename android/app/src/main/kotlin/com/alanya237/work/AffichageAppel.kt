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
import com.hiennv.flutter_callkit_incoming.CallkitIncomingActivity
import com.hiennv.flutter_callkit_incoming.CallkitNotificationManager

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
        if (androidLeFait) {
            Log.d(TAG, "plein écran pris en charge par Android (allumé=$allume verrouillé=$verrouille)")
            return
        }
        if (!Settings.canDrawOverlays(ctx)) {
            Log.w(TAG, "superposition refusée : l'appel reste en bannière (allumé=$allume pleinEcran=$pleinEcran)")
            return
        }
        principal.post { lancer(ctx, bundle, allume) }
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
