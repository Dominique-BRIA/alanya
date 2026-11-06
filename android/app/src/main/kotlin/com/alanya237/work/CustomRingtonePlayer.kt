package com.alanya237.work

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.util.Log
import java.io.File

/**
 * Joue une sonnerie *importée par l'utilisateur* (fichier arbitraire hors
 * `res/raw`) pour un appel entrant quand l'app est en arrière-plan / tuée.
 *
 * Nécessaire parce que `flutter_callkit_incoming`
 * ([com.hiennv.flutter_callkit_incoming.CallkitSoundPlayerManager]) ne sait
 * jouer qu'une ressource `res/raw` compilée ou la sonnerie système par
 * défaut — jamais un chemin de fichier. On rend donc CallKit muet (ressource
 * `res/raw/silence`) et on joue nous-mêmes le fichier ici.
 *
 * Appartient à un objet unique (scope application) pour garantir un seul son
 * actif et un [stop] fiable depuis n'importe quel chemin de fin d'appel
 * (accept / decline / timeout / ended), voir [TalkyApplication] et
 * [CallIncomingHelper].
 */
object CustomRingtonePlayer {

    private const val TAG = "TalkyCustomRingtone"

    private var player: MediaPlayer? = null

    /** Préfixe d'un son LIVRÉ dans l'application (asset Flutter), voir [start]. */
    private const val PREFIXE_ASSET = "asset:"

    /**
     * [filePath] est un fichier sur le disque — ou, ajout d'Alanya Work, un son
     * livré dans l'application sous la forme `asset:<chemin>` : nos sonneries
     * de liste (`liste-bureau.mp3`…) sont des assets Flutter, pas des fichiers
     * importés. Elles ne sont pas dans `res/raw`, donc CallKit ne saurait pas
     * les jouer : même traitement qu'un fichier importé.
     */
    @Synchronized
    fun start(context: Context, filePath: String) {
        val asset = filePath.startsWith(PREFIXE_ASSET)
        val file = File(filePath)
        if (!asset && !file.exists()) {
            Log.w(TAG, "start ignoré, fichier absent: $filePath")
            return
        }
        // Un appel entrant déjà en train de sonner : on ne relance pas.
        if (player != null) {
            Log.d(TAG, "start ignoré, déjà en lecture")
            return
        }
        try {
            player = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                        .setLegacyStreamType(AudioManager.STREAM_RING)
                        .build(),
                )
                if (asset) {
                    // Les assets Flutter vivent sous `flutter_assets/` dans le
                    // paquet, et l'mp3 n'y est pas compressé.
                    context.assets.openFd("flutter_assets/" + filePath.removePrefix(PREFIXE_ASSET)).use {
                        setDataSource(it.fileDescriptor, it.startOffset, it.length)
                    }
                } else {
                    setDataSource(filePath)
                }
                isLooping = true
                setOnPreparedListener { it.start() }
                setOnErrorListener { mp, what, extra ->
                    // L'erreur était consommée sans rien libérer : `player`
                    // restait non nul, et le `start()` suivant sortait sur
                    // « déjà en lecture ». L'appel entrant d'après était donc
                    // silencieux, jusqu'au prochain stop().
                    Log.e(TAG, "MediaPlayer error what=$what extra=$extra — libération")
                    if (player === mp) {
                        player = null
                    }
                    try {
                        mp.release()
                    } catch (e: Exception) {
                        Log.w(TAG, "release après erreur: ${e.message}")
                    }
                    true
                }
                prepareAsync()
            }
            Log.d(TAG, "start $filePath")
        } catch (e: Exception) {
            Log.e(TAG, "start failed", e)
            releaseQuietly()
        }
    }

    @Synchronized
    fun stop() {
        val p = player ?: return
        player = null
        try {
            if (p.isPlaying) p.stop()
        } catch (_: Exception) {
        } finally {
            try {
                p.release()
            } catch (_: Exception) {
            }
        }
        Log.d(TAG, "stop")
    }

    fun isActive(): Boolean = player != null

    private fun releaseQuietly() {
        try {
            player?.release()
        } catch (_: Exception) {
        }
        player = null
    }
}
