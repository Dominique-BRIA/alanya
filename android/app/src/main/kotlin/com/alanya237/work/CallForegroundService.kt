package com.alanya237.work

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * Maintient l'appel vivant quand l'application n'est plus au premier plan.
 *
 * POURQUOI C'EST NÉCESSAIRE. Une fois l'appel établi, ce n'est plus Firebase qui
 * le porte : c'est le processus Flutter et ses connexions WebRTC. Or Android
 * suspend les processus en arrière-plan — écran éteint, changement
 * d'application — et l'audio se coupe alors au bout de quelques secondes, sans
 * que rien ne l'explique à l'utilisateur.
 *
 * Un service de premier plan est le seul moyen officiel de dire au système que
 * ce processus fait quelque chose que l'utilisateur a demandé. Les quatre
 * éléments ci-dessous répondent chacun à une coupure différente :
 *  - le TYPE microphone autorise la capture micro en arrière-plan, obligatoire
 *    depuis Android 10 ;
 *  - le wake lock CPU empêche l'endormissement du processeur écran éteint ;
 *  - le wifi lock empêche la mise en veille de la puce réseau, qui coupe les
 *    connexions WebRTC ;
 *  - la notification persistante est imposée par Android : sans elle, le
 *    système tue le service en quelques secondes.
 *
 * ⚠️ LA VIDÉO N'EST PAS COUVERTE écran éteint : Android interdit l'accès caméra
 * en arrière-plan, quel que soit le service. L'audio continue, l'image se fige.
 * C'est une limite du système, pas de ce code.
 */
class CallForegroundService : Service() {

    companion object {
        const val ACTION_DEMARRER = "com.alanya237.work.APPEL_DEMARRER"
        const val ACTION_ARRETER = "com.alanya237.work.APPEL_ARRETER"
        const val EXTRA_TITRE = "titre"

        private const val CANAL = "appel_en_cours"
        private const val NOTIF_ID = 4242
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_ARRETER -> {
                arreteTout()
                return START_NOT_STICKY
            }
            else -> demarre(intent?.getStringExtra(EXTRA_TITRE) ?: "Appel en cours")
        }
        // START_NOT_STICKY : si le système tue quand même le service, il ne doit
        // PAS le relancer tout seul — l'appel, lui, sera bel et bien terminé, et
        // une notification « Appel en cours » ressuscitée sans appel derrière
        // serait incompréhensible.
        return START_NOT_STICKY
    }

    private fun demarre(titre: String) {
        creeCanal()

        val ouvrir = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val pending = PendingIntent.getActivity(
            this, 0, ouvrir,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification: Notification = Notification.Builder(this, CANAL)
            .setContentTitle(titre)
            .setContentText("Appel Alanya en cours")
            .setSmallIcon(android.R.drawable.stat_sys_phone_call)
            .setOngoing(true)
            .setUsesChronometer(true)
            .setContentIntent(pending)
            .build()

        // Depuis Android 10, un service qui capte le micro doit DÉCLARER ce type,
        // sinon le système refuse la capture en arrière-plan sans message clair.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIF_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
            )
        } else {
            startForeground(NOTIF_ID, notification)
        }

        prendLesVerrous()
    }

    private fun prendLesVerrous() {
        if (wakeLock == null) {
            val power = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = power.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "alanya:appel",
            ).apply {
                setReferenceCounted(false)
                // Plafond de sécurité : un verrou oublié viderait la batterie
                // jusqu'au redémarrage. Deux heures dépassent largement un appel,
                // et le verrou est de toute façon relâché à la fin.
                acquire(2 * 60 * 60 * 1000L)
            }
        }
        if (wifiLock == null) {
            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            wifiLock = wifi.createWifiLock(
                WifiManager.WIFI_MODE_FULL_HIGH_PERF,
                "alanya:appel",
            ).apply {
                setReferenceCounted(false)
                acquire()
            }
        }
    }

    private fun arreteTout() {
        // Relâchés avant l'arrêt du service : après, le contexte peut avoir
        // disparu et les verrous resteraient pris jusqu'au redémarrage.
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (_: Exception) {
        }
        wakeLock = null
        try {
            if (wifiLock?.isHeld == true) wifiLock?.release()
        } catch (_: Exception) {
        }
        wifiLock = null

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    override fun onDestroy() {
        arreteTout()
        super.onDestroy()
    }

    private fun creeCanal() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CANAL) != null) return
        val canal = NotificationChannel(
            CANAL,
            "Appel en cours",
            // LOW et non HIGH : cette notification informe, elle ne doit ni
            // sonner ni vibrer — l'appel s'en charge déjà.
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Maintient l'appel actif quand l'application est en arrière-plan"
            setShowBadge(false)
            enableVibration(false)
            setSound(null, null)
        }
        manager.createNotificationChannel(canal)
    }
}
