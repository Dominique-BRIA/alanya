package com.alanya237.work

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.util.Log
import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
import com.cloudwebrtc.webrtc.audio.LocalAudioTrack
import org.webrtc.AudioTrack
import org.webrtc.AudioTrackSink
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.util.concurrent.LinkedBlockingQueue

/**
 * Enregistre les DEUX voix d'un appel WebRTC en branchant un [AudioTrackSink]
 * sur la piste locale (micro de l'agent) ET sur la piste distante (voix du
 * correspondant), et en encodant chacune en AAC sur l'appareil.
 *
 * 🔴 **POURQUOI PAS `MediaRecorder` DU GREFFON.** `MediaRecorderImpl` du greffon
 * `flutter_webrtc` fait `throw "Audio-only recording not implemented yet"` dès
 * que la piste vidéo est nulle — l'enregistrement audio seul n'existe pas. La
 * voie qui marche (tout public, ni fork ni réflexion) : `getLocalTrack(id)` rend
 * un [LocalAudioTrack] avec `addSink`, `getRemoteTrack(id)` un [AudioTrack] avec
 * `addSink` ; les deux livrent du PCM 16 bits via `onData`.
 *
 * 🔴 **AAC EN FLUX ADTS, PAS UN CONTENEUR MP4.** Un `.m4a` non finalisé (appel
 * coupé net, application tuée) est ILLISIBLE : l'atome `moov` n'est jamais
 * écrit. Un flux ADTS brut, lui, reste lisible jusqu'à la dernière trame
 * complète — exactement ce qu'il faut pour un appel qui se termine brutalement.
 * On préfixe donc chaque trame AAC d'un en-tête ADTS de 7 octets et on écrit un
 * simple `.aac`. Le serveur (`melange-enregistrement.ts`) mixe les deux par
 * ffmpeg, qui lit l'ADTS sans conteneur.
 *
 * ⚠️ **L'ENCODAGE NE TOUCHE JAMAIS LE THREAD AUDIO.** `onData` est appelé sur un
 * thread audio à haute priorité : y faire tourner MediaCodec provoquerait des
 * coupures de son. Le rappel se contente de COPIER les octets et de les mettre
 * en file ; un thread dédié par piste consomme la file, encode et écrit.
 *
 * ⚠️ **TIMING.** La piste locale existe dès le décrochage ; la DISTANTE n'arrive
 * qu'après la négociation. D'où [attacherDistant], appelé séparément quand le
 * flux distant apparaît côté Dart.
 *
 * ⚠️ **AUCUNE ANNONCE** au correspondant — décision explicite du user
 * (20/08/2026). ⚠️ **Singleton** : un enregistrement appartient à un APPEL.
 */
object AppelEnregistreur {
    private const val TAG = "AppelEnregistreur"

    private var callId: String? = null
    private var encodeurAgent: EncodeurAac? = null
    private var encodeurClient: EncodeurAac? = null
    private var sinkAgent: AudioTrackSink? = null
    private var sinkClient: AudioTrackSink? = null
    private var pisteAgent: LocalAudioTrack? = null
    private var pisteClient: AudioTrack? = null

    /**
     * Le plugin WebRTC DU MOTEUR DE L'APPEL, fourni par `MainActivity`.
     *
     * 🔴 **PAS `FlutterWebRTCPlugin.sharedSingleton`.** Ce singleton statique
     * pointe vers le DERNIER moteur Flutter attaché — or l'application en a
     * plusieurs dans le même process (CallKit, tâche de premier plan). Le
     * `getUserMedia` de l'appel inscrit la piste dans la table du moteur de l'UI,
     * mais `sharedSingleton.getLocalTrack` interrogeait la table VIDE d'un moteur
     * secondaire, et rendait toujours « piste introuvable » (constaté au logcat
     * le 20/08/2026). On prend donc le plugin du moteur qui possède notre canal,
     * seul à contenir les pistes de l'appel.
     */
    private var plugin: FlutterWebRTCPlugin? = null

    val enCours: Boolean get() = callId != null

    /**
     * Démarre l'enregistrement de la voix de l'agent (piste locale). Rend faux
     * si la piste est introuvable — l'appel se poursuit alors sans trace. Ne
     * lève JAMAIS : un enregistrement raté ne doit pas faire échouer un
     * décrochage.
     */
    @Synchronized
    fun demarrer(
        nouvelAppel: String,
        localTrackId: String,
        dossier: File,
        pluginWebrtc: FlutterWebRTCPlugin?,
    ): Boolean {
        if (callId == nouvelAppel) return true
        if (callId != null) abandonner()
        return try {
            val p = pluginWebrtc
                ?: run { Log.e(TAG, "plugin WebRTC du moteur d'appel absent"); return false }
            val locale = p.getLocalTrack(localTrackId) as? LocalAudioTrack
                ?: run { Log.e(TAG, "piste locale $localTrackId introuvable"); return false }

            val base = File(dossier, "appel-$nouvelAppel").absolutePath
            val agent = EncodeurAac("$base-agent.aac")
            val client = EncodeurAac("$base-client.aac")

            val sa = AudioTrackSink { data, _, rate, ch, _, _ -> pousser(agent, data, rate, ch) }
            locale.addSink(sa)

            encodeurAgent = agent
            encodeurClient = client
            sinkAgent = sa
            pisteAgent = locale
            plugin = p
            callId = nouvelAppel
            Log.i(TAG, "démarré sur $nouvelAppel (agent branché)")
            true
        } catch (e: Throwable) {
            Log.e(TAG, "démarrage impossible : ${e.message}", e)
            abandonner()
            false
        }
    }

    /**
     * Branche la voix du correspondant (piste distante) dès qu'elle est
     * disponible. Idempotent, ne lève jamais.
     */
    @Synchronized
    fun attacherDistant(remoteTrackId: String) {
        if (callId == null || sinkClient != null) return
        try {
            // Le MÊME plugin (moteur de l'appel) que pour la piste locale — voir
            // le champ `plugin`. `sharedSingleton` echouerait de la meme facon.
            val p = plugin ?: return
            val distante = p.getRemoteTrack(remoteTrackId) as? AudioTrack
                ?: run { Log.w(TAG, "piste distante $remoteTrackId introuvable"); return }
            val client = encodeurClient ?: return
            val sc = AudioTrackSink { data, _, rate, ch, _, _ -> pousser(client, data, rate, ch) }
            distante.addSink(sc)
            sinkClient = sc
            pisteClient = distante
            Log.i(TAG, "voix distante branchée ($remoteTrackId)")
        } catch (e: Throwable) {
            Log.e(TAG, "attacherDistant : ${e.message}", e)
        }
    }

    /**
     * Copie le PCM du buffer et le remet à l'encodeur. Fait sur le thread audio,
     * donc réduit au strict minimum : une copie et une mise en file.
     *
     * `duplicate` : plusieurs sinks peuvent partager le même buffer distant ;
     * lire directement en déplacerait la position pour les suivants.
     */
    private fun pousser(encodeur: EncodeurAac, data: ByteBuffer, rate: Int, channels: Int) {
        val vue = data.duplicate()
        val n = vue.remaining()
        if (n <= 0) return
        val octets = ByteArray(n)
        vue.get(octets)
        encodeur.ecrire(octets, rate, channels)
    }

    /**
     * Arrête, ferme les deux flux et rend leurs chemins, ou `null` si l'une des
     * deux voix manque. Attend que les encodeurs aient vidé ce qui reste en file.
     *
     * ⚠️ **LES DEUX VOIX SONT EXIGÉES** : un enregistrement où l'on n'entend
     * qu'un interlocuteur ne prouve rien. Les fichiers partiels sont effacés.
     */
    @Synchronized
    fun arreter(): Map<String, String>? {
        if (callId == null) return null
        detacher()
        val agent = encodeurAgent
        val client = encodeurClient
        encodeurAgent = null
        encodeurClient = null
        callId = null

        val cheminAgent = agent?.fermerEtRendreChemin()
        val cheminClient = client?.fermerEtRendreChemin()
        if (cheminAgent == null || cheminClient == null) {
            Log.w(TAG, "voix manquante — rien à envoyer")
            cheminAgent?.let { File(it).delete() }
            cheminClient?.let { File(it).delete() }
            return null
        }
        return mapOf("agent" to cheminAgent, "client" to cheminClient)
    }

    /** Referme sans rien rendre : raccroché avant l'heure, ou changement d'appel. */
    @Synchronized
    fun abandonner() {
        detacher()
        encodeurAgent?.fermerEtRendreChemin()?.let { File(it).delete() }
        encodeurClient?.fermerEtRendreChemin()?.let { File(it).delete() }
        encodeurAgent = null
        encodeurClient = null
        callId = null
    }

    private fun detacher() {
        try { sinkAgent?.let { pisteAgent?.removeSink(it) } } catch (_: Throwable) {}
        try { sinkClient?.let { pisteClient?.removeSink(it) } } catch (_: Throwable) {}
        sinkAgent = null
        sinkClient = null
        pisteAgent = null
        pisteClient = null
        plugin = null
    }
}

/**
 * Encode un flux PCM 16 bits entrant en AAC-LC et l'écrit en trames ADTS.
 *
 * Le format (fréquence, canaux) n'est connu qu'au PREMIER paquet : l'encodeur
 * est donc créé paresseusement, sur son propre thread, à la première écriture.
 * Le thread audio ne fait qu'empiler des octets ; ce thread-ci les encode.
 */
private class EncodeurAac(private val chemin: String) {
    private companion object {
        const val TAG = "EncodeurAac"
        // Table des fréquences d'échantillonnage MPEG-4, pour l'en-tête ADTS.
        val FREQUENCES = intArrayOf(
            96000, 88200, 64000, 48000, 44100, 32000, 24000,
            22050, 16000, 12000, 11025, 8000, 7350,
        )
    }

    private val flux = BufferedOutputStream(FileOutputStream(chemin))
    private val file = LinkedBlockingQueue<ByteArray>()
    private val fin = ByteArray(0) // sentinelle de fin de flux

    @Volatile private var thread: Thread? = null
    private var rate = 0
    private var canaux = 0
    private var demarre = false

    @Volatile private var closed = false
    @Volatile private var octetsEcrits = 0L

    /** Empile un paquet PCM. Le premier fixe le format et démarre l'encodeur. */
    fun ecrire(pcm: ByteArray, sampleRate: Int, channels: Int) {
        if (closed) return
        if (!demarre) {
            demarre = true
            rate = sampleRate
            canaux = channels
            // Le thread est démarré APRÈS l'affectation de rate/canaux : il les
            // lit sans course (le démarrage d'un thread établit un happens-before).
            val t = Thread({ boucle() }, "aac-${File(chemin).name}")
            thread = t
            t.start()
        }
        file.offer(pcm)
    }

    /**
     * Ferme le flux et rend le chemin, ou `null` si rien n'a été encodé. Attend
     * que l'encodeur ait vidé la file (borné) : sans cette attente, l'appelant
     * lirait un fichier incomplet.
     */
    fun fermerEtRendreChemin(): String? {
        if (closed) return if (octetsEcrits > 0) chemin else null
        closed = true
        val t = thread
        if (t == null) {
            // Aucun PCM n'est jamais arrivé : rien à encoder.
            try { flux.close() } catch (_: Throwable) {}
            return null
        }
        file.offer(fin)
        try { t.join(3000) } catch (_: InterruptedException) {}
        return if (octetsEcrits > 0) chemin else null
    }

    private fun boucle() {
        var codec: MediaCodec? = null
        try {
            val format = MediaFormat.createAudioFormat(
                MediaFormat.MIMETYPE_AUDIO_AAC, rate, canaux,
            ).apply {
                setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
                setInteger(MediaFormat.KEY_BIT_RATE, if (canaux >= 2) 64000 else 32000)
                setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16384)
            }
            val c = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
            c.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            c.start()
            codec = c

            val info = MediaCodec.BufferInfo()
            var echantillons = 0L
            var termine = false
            while (!termine) {
                val pcm = file.take() // bloque jusqu'au prochain paquet
                if (pcm.isEmpty()) {
                    // Fin de flux : pousser un buffer d'entrée EOS, en réessayant
                    // jusqu'à en obtenir un — sinon le codec ne produirait jamais
                    // sa fin et le drain tournerait sans fin.
                    var envoye = false
                    while (!envoye) {
                        val idxIn = c.dequeueInputBuffer(10000)
                        if (idxIn >= 0) {
                            val pts = if (rate > 0) echantillons * 1_000_000L / rate else 0L
                            c.queueInputBuffer(idxIn, 0, 0, pts, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            envoye = true
                        } else {
                            drainer(c, info) // libère des buffers de sortie
                        }
                    }
                    while (!termine) termine = drainer(c, info)
                } else {
                    var offset = 0
                    while (offset < pcm.size) {
                        val idxIn = c.dequeueInputBuffer(10000)
                        if (idxIn >= 0) {
                            val entree = c.getInputBuffer(idxIn)!!
                            entree.clear()
                            val n = minOf(pcm.size - offset, entree.capacity())
                            entree.put(pcm, offset, n)
                            val pts = if (rate > 0) echantillons * 1_000_000L / rate else 0L
                            c.queueInputBuffer(idxIn, 0, n, pts, 0)
                            offset += n
                            if (canaux > 0) echantillons += (n / 2 / canaux).toLong()
                        }
                        drainer(c, info)
                    }
                }
            }
        } catch (e: Throwable) {
            Log.e(TAG, "encodage $chemin : ${e.message}", e)
        } finally {
            try { codec?.stop() } catch (_: Throwable) {}
            try { codec?.release() } catch (_: Throwable) {}
            try { flux.flush(); flux.close() } catch (_: Throwable) {}
        }
    }

    /** Vide ce que le codec a produit ; rend vrai à la fin de flux. */
    private fun drainer(c: MediaCodec, info: MediaCodec.BufferInfo): Boolean {
        while (true) {
            val idxOut = c.dequeueOutputBuffer(info, 0)
            if (idxOut == MediaCodec.INFO_TRY_AGAIN_LATER) return false
            if (idxOut == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED ||
                idxOut == MediaCodec.INFO_OUTPUT_BUFFERS_CHANGED
            ) {
                continue
            }
            if (idxOut < 0) return false
            // La trame de configuration du codec n'est pas de l'audio : ADTS la
            // porte dans son propre en-tête, on ne l'écrit pas.
            val config = info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
            if (!config && info.size > 0) {
                val sortie = c.getOutputBuffer(idxOut)!!
                val paquet = ByteArray(7 + info.size)
                enteteAdts(paquet, 7 + info.size)
                sortie.position(info.offset)
                sortie.get(paquet, 7, info.size)
                flux.write(paquet)
                octetsEcrits += paquet.size
            }
            c.releaseOutputBuffer(idxOut, false)
            if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return true
        }
    }

    /** En-tête ADTS de 7 octets (AAC-LC, sans CRC) pour une trame donnée. */
    private fun enteteAdts(paquet: ByteArray, longueur: Int) {
        val profil = 2 // AAC-LC
        var idxFreq = FREQUENCES.indexOf(rate)
        if (idxFreq < 0) idxFreq = 3 // repli 48 kHz (fréquences WebRTC standard)
        val cfgCanaux = canaux
        paquet[0] = 0xFF.toByte()
        paquet[1] = 0xF1.toByte() // MPEG-4, couche 0, sans CRC
        paquet[2] = (((profil - 1) shl 6) or (idxFreq shl 2) or (cfgCanaux shr 2)).toByte()
        paquet[3] = (((cfgCanaux and 3) shl 6) or (longueur shr 11)).toByte()
        paquet[4] = ((longueur and 0x7FF) shr 3).toByte()
        paquet[5] = (((longueur and 7) shl 5) or 0x1F).toByte()
        paquet[6] = 0xFC.toByte()
    }
}
