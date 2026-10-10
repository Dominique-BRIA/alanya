package com.alanya.telecom

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Person
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.URL

private const val TAG = "AlanyaTelecom"

/// Sonnerie native : RingtoneManager sur le flux SONNERIE (comme le
/// téléphone), en boucle, respectant le mode sonnerie/vibreur/silencieux.
/// Fiable car le processus est LIÉ par Telecom pendant la sonnerie.
object IncomingRinger {
    private var ringtone: Ringtone? = null
    private var vibrator: Vibrator? = null

    fun start(ctx: Context) {
        stop()
        val am = ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager

        // Vibration (sauf mode silencieux)
        if (am.ringerMode != AudioManager.RINGER_MODE_SILENT) {
            try {
                vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    (ctx.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager)
                        .defaultVibrator
                } else {
                    @Suppress("DEPRECATION")
                    ctx.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                }
                vibrator?.vibrate(
                    VibrationEffect.createWaveform(longArrayOf(0, 1000, 800), 0)
                )
            } catch (e: Exception) {
                Log.w(TAG, "vibrator: $e")
            }
        }

        // Sonnerie (uniquement en mode normal)
        if (am.ringerMode == AudioManager.RINGER_MODE_NORMAL) {
            try {
                // Sonnerie CHOISIE par l'utilisateur dans les réglages de
                // l'app (SharedPreferences Flutter, clé `flutter.ringtone`).
                // Nom validé : uniquement [a-z0-9_] (c'est un nom de
                // ressource res/raw, jamais un chemin).
                val chosen = ctx.getSharedPreferences(
                    "FlutterSharedPreferences", Context.MODE_PRIVATE
                ).getString("flutter.ringtone", null)
                    ?.takeIf { it.matches(Regex("^[a-z0-9_]+$")) }
                    ?: "sonnerie_appel"
                val uri = if (chosen == "system_ringtone_default") {
                    RingtoneManager.getActualDefaultRingtoneUri(
                        ctx, RingtoneManager.TYPE_RINGTONE
                    )
                } else {
                    var resId = ctx.resources.getIdentifier(chosen, "raw", ctx.packageName)
                    if (resId == 0) {
                        resId = ctx.resources.getIdentifier(
                            "sonnerie_appel", "raw", ctx.packageName
                        )
                    }
                    if (resId != 0) {
                        Uri.parse("android.resource://${ctx.packageName}/$resId")
                    } else {
                        RingtoneManager.getActualDefaultRingtoneUri(
                            ctx, RingtoneManager.TYPE_RINGTONE
                        )
                    }
                }
                ringtone = RingtoneManager.getRingtone(ctx, uri)?.apply {
                    audioAttributes = AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) isLooping = true
                    play()
                }
                Log.d(TAG, "sonnerie démarrée (uri=$uri)")
            } catch (e: Exception) {
                Log.w(TAG, "ringtone: $e")
            }
        }
    }

    fun stop() {
        try { ringtone?.stop() } catch (_: Exception) {}
        ringtone = null
        try { vibrator?.cancel() } catch (_: Exception) {}
        vibrator = null
    }
}

/// Notification d'appel entrant : CallStyle (Android 12+) avec full-screen
/// intent — le standard système. Le canal est SILENCIEUX : la sonnerie est
/// jouée par IncomingRinger (boucle + arrêt propre au décroché).
object IncomingNotifier {
    const val NOTIF_ID = 4242
    private const val CHANNEL = "alanya_telecom_incoming_v1"
    const val ACTION_ANSWER = "com.alanya.telecom.ANSWER"
    const val ACTION_DECLINE = "com.alanya.telecom.DECLINE"

    fun show(ctx: Context, data: Map<String, String>) {
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                CHANNEL, "Appels entrants (système)", NotificationManager.IMPORTANCE_HIGH
            ).apply {
                setSound(null, null)     // sonnerie portée par IncomingRinger
                enableVibration(false)   // vibration portée par IncomingRinger
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            nm.createNotificationChannel(ch)
        }

        val name = data["callerName"]?.takeIf { it.isNotEmpty() } ?: "Appel entrant"
        val callType = if (data["callType"] == "audio") "audio" else "vidéo"
        // Transfert masqué : sous-titre « … vous transfère l'appel », affiché
        // sous le nom (A) — y compris sur l'écran verrouillé / notification
        // système. Sinon, libellé d'appel entrant standard.
        val transferBy = data["transferBy"]?.takeIf { it.isNotEmpty() }
        val subtitle = if (transferBy != null)
            "$transferBy · transfert d'appel"
        else
            "Appel $callType entrant…"
        val flags = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT

        val answerPi = PendingIntent.getBroadcast(
            ctx, 1,
            Intent(ctx, TelecomActionReceiver::class.java).setAction(ACTION_ANSWER),
            flags
        )
        val declinePi = PendingIntent.getBroadcast(
            ctx, 2,
            Intent(ctx, TelecomActionReceiver::class.java).setAction(ACTION_DECLINE),
            flags
        )
        val launch = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
        val fullPi = PendingIntent.getActivity(ctx, 3, launch, flags)

        val builder: Notification.Builder =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val person = Person.Builder().setName(name).setImportant(true).build()
                Notification.Builder(ctx, CHANNEL)
                    .setStyle(Notification.CallStyle.forIncomingCall(person, declinePi, answerPi))
                    .setContentText(subtitle)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(ctx, CHANNEL)
                    .setContentTitle(name)
                    .setContentText(subtitle)
                    .addAction(Notification.Action.Builder(null, "Refuser", declinePi).build())
                    .addAction(Notification.Action.Builder(null, "Décrocher", answerPi).build())
            }

        builder
            .setSmallIcon(ctx.applicationInfo.icon)
            .setCategory(Notification.CATEGORY_CALL)
            .setOngoing(true)
            .setFullScreenIntent(fullPi, true)
            .setContentIntent(fullPi)

        nm.notify(NOTIF_ID, builder.build())
    }

    fun cancel(ctx: Context) {
        (ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .cancel(NOTIF_ID)
    }
}

/// Boutons Décrocher/Refuser de la notification.
class TelecomActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "action notification: ${intent.action}")
        when (intent.action) {
            IncomingNotifier.ACTION_ANSWER -> CallRegistry.answerCurrent()
            IncomingNotifier.ACTION_DECLINE -> CallRegistry.rejectCurrent()
        }
    }
}

/// Refus transmis au serveur DIRECTEMENT en natif — indispensable quand
/// l'app est tuée (aucun isolate Dart pour le faire). Token JWT lu dans les
/// SharedPreferences de Flutter.
///
/// SÉCURITÉ : l'URL de l'API n'est JAMAIS lue du payload d'appel (un payload
/// forgé pourrait sinon exfiltrer le Bearer token vers un hôte attaquant).
/// Elle est configurée une fois par l'app (`configure`), persistée dans des
/// prefs privées, et HTTPS est exigé.
object DeclineHttp {
    private const val PREFS = "alanya_telecom"
    private const val KEY_API = "api_url"

    fun configure(ctx: Context, apiUrl: String) {
        if (!apiUrl.startsWith("https://")) {
            Log.w(TAG, "configure: URL non-HTTPS refusée")
            return
        }
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(KEY_API, apiUrl).apply()
    }

    fun declineAsync(ctx: Context, data: Map<String, String>) {
        val caller = data["callerPhone"]?.takeIf { it.isNotEmpty() } ?: return
        val groupAdd = data["groupAdd"] == "true"
        Thread {
            try {
                val apiUrl = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                    .getString(KEY_API, null) ?: return@Thread
                val url = URL("$apiUrl/decline-call")
                if (url.protocol != "https") return@Thread
                val prefs = ctx.getSharedPreferences(
                    "FlutterSharedPreferences", Context.MODE_PRIVATE
                )
                val token = prefs.getString("flutter.token", null) ?: return@Thread
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = "POST"
                conn.setRequestProperty("Content-Type", "application/json")
                conn.setRequestProperty("Authorization", "Bearer $token")
                conn.connectTimeout = 8000
                conn.readTimeout = 8000
                conn.doOutput = true
                // JSONObject : encodage sûr (pas d'injection via callerName)
                val body = org.json.JSONObject()
                    .put("callerName", caller)
                    .put("groupAdd", groupAdd)
                    .toString()
                conn.outputStream.use { os: OutputStream -> os.write(body.toByteArray()) }
                Log.d(TAG, "decline natif HTTP → ${conn.responseCode}")
                conn.disconnect()
            } catch (e: Exception) {
                Log.w(TAG, "decline natif: $e")
            }
        }.start()
    }
}
