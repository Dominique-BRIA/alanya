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
 * Maintient les ENVOIS et TÉLÉCHARGEMENTS vivants quand l'application n'est plus
 * à l'écran — y compris balayée des tâches récentes.
 *
 * POURQUOI CE SERVICE, ALORS QUE LES NOTIFICATIONS SUFFISAIENT DÉJÀ. Une
 * notification à barre de progression montre où en est un transfert ; elle ne le
 * fait pas avancer. Le transfert, lui, est une requête HTTP portée par l'isolat
 * Dart, donc par le PROCESSUS de l'application. Android suspend puis tue les
 * processus en arrière-plan : jusqu'ici, quitter Alanya pendant l'envoi d'une
 * vidéo de 40 Mo laissait une barre figée sur un transfert mort. Un service de
 * premier plan est le seul moyen officiel de dire au système que ce processus
 * fait quelque chose que l'utilisateur a demandé.
 *
 * Écrit à la main plutôt que confié à `flutter_foreground_task` : ce paquet
 * n'expose QU'UN SEUL service, déjà pris par le relevé de position et déclaré
 * `foregroundServiceType="location"`. Le réutiliser aurait lié les deux — arrêter
 * les transferts aurait arrêté la géolocalisation. Le projet a déjà un service
 * Kotlin écrit à la main pour les appels ([CallForegroundService]) : celui-ci en
 * reprend la structure.
 *
 * ⚠️ **TYPE `dataSync`, et il a un prix.** Depuis Android 15, les services de ce
 * type sont plafonnés à **6 heures par jour** cumulées ; au-delà, le système les
 * arrête. C'est sans effet sur des transferts de fichiers, qui se comptent en
 * minutes — mais ce serait rédhibitoire pour un usage continu.
 *
 * ⚠️ **UN SERVICE `dataSync` NE PEUT PAS ÊTRE DÉMARRÉ DEPUIS L'ARRIÈRE-PLAN**
 * (Android 12+). Ce n'est pas une contrainte ici : un transfert part toujours
 * d'un geste, donc application au premier plan. Mais il ne faudra jamais le
 * démarrer depuis un push ou un minuteur.
 *
 * 🚫 **LIMITE QU'AUCUN CODE NE CORRIGE** : Xiaomi, Huawei, Oppo et Transsion
 * tuent les processus balayés des tâches récentes malgré un service de premier
 * plan, sauf si l'application est exemptée d'optimisation de batterie. Même
 * limite que pour le relevé de position.
 */
class TransferForegroundService : Service() {

    companion object {
        const val ACTION_DEMARRER = "com.alanya237.work.TRANSFERT_DEMARRER"
        const val ACTION_ARRETER = "com.alanya237.work.TRANSFERT_ARRETER"
        const val EXTRA_TEXTE = "texte"

        private const val CANAL = "transferts_actifs"

        /**
         * ⚠️ DISTINCT des identifiants de `PushService.idTransfert` : ce badge-ci
         * n'affiche AUCUNE progression, il ne fait que tenir le processus en vie.
         * Les barres de progression sont posées par Flutter, une par transfert.
         * Partager l'identifiant les ferait s'écraser mutuellement.
         */
        private const val NOTIF_ID = 4343
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
            else -> demarre(intent?.getStringExtra(EXTRA_TEXTE) ?: "Transfert en cours")
        }
        // START_NOT_STICKY : si le système tue quand même le processus, le
        // transfert est perdu de toute façon — le relancer sans requête derrière
        // afficherait un badge éternel sur rien.
        return START_NOT_STICKY
    }

    private fun demarre(texte: String) {
        creeCanal()

        val ouvrir = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val pending = PendingIntent.getActivity(
            this, 0, ouvrir,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification: Notification = Notification.Builder(this, CANAL)
            .setContentTitle("Transferts Alanya")
            .setContentText(texte)
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setOngoing(true)
            .setContentIntent(pending)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIF_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
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
                "alanya:transfert",
            ).apply {
                setReferenceCounted(false)
                // Plafond de sécurité : un verrou oublié viderait la batterie
                // jusqu'au redémarrage. Trente minutes couvrent largement un
                // transfert de fichier, et il est relâché à la fin de toute façon.
                acquire(30 * 60 * 1000L)
            }
        }
        if (wifiLock == null) {
            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            wifiLock = wifi.createWifiLock(
                WifiManager.WIFI_MODE_FULL_HIGH_PERF,
                "alanya:transfert",
            ).apply {
                setReferenceCounted(false)
                acquire()
            }
        }
    }

    private fun arreteTout() {
        // Relâchés AVANT l'arrêt : après, le contexte peut avoir disparu et les
        // verrous resteraient pris jusqu'au redémarrage du téléphone.
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
            "Transferts actifs",
            // LOW : ce badge informe que le processus est tenu en vie. Les
            // barres de progression, elles, vivent sur le canal « Transferts »
            // posé par Flutter.
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Maintient les envois et téléchargements quand l'application est fermée"
            setShowBadge(false)
            enableVibration(false)
            setSound(null, null)
        }
        manager.createNotificationChannel(canal)
    }
}
