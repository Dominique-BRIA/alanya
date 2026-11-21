package com.alanya237.work

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.FrameDropEffect
import androidx.media3.effect.Presentation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import com.otaliastudios.transcoder.Transcoder
import com.otaliastudios.transcoder.TranscoderListener
import com.otaliastudios.transcoder.source.UriDataSource
import com.otaliastudios.transcoder.strategy.DefaultAudioStrategy
import com.otaliastudios.transcoder.strategy.DefaultVideoStrategy
import java.io.File
import java.util.concurrent.Future

/**
 * TRANSCODER UNE VIDÉO AVEC UN DÉBIT IMPOSÉ — l'alignement du mobile sur le web.
 *
 * 🐛 LE MOBILE RENDAIT DES VIDÉOS DEUX FOIS PLUS LOURDES QUE LE WEB (signalé par
 * le user le 12/10/2026 : une vidéo de plus de 30 Mo sortait à 3,9 Mo sur le
 * web et à 8,9 Mo sur le téléphone). La cause n'était pas le moteur, c'était la
 * CONSIGNE : le paquet `video_compress` ne demande que la TAILLE DE L'IMAGE
 * (`Res1280x720Quality` → `DefaultVideoStrategy.atMost(720, 1280)`) et ne passe
 * AUCUN débit, qu'il ne sait d'ailleurs pas exposer — son API Dart n'a pas de
 * paramètre pour ça. Le moteur choisissait donc lui-même, et il choisissait le
 * double de ce que le web impose.
 *
 * 🔴 ON PARLE DONC AU MOTEUR DIRECTEMENT, SANS CHANGER DE MOTEUR. C'est le même
 * transcodeur que `video_compress` utilise déjà (`com.otaliastudios:transcoder`,
 * même version) : seule la consigne change. Et c'est la voie déjà empruntée
 * dans ce projet par `AppelEnregistreur`, qui s'adresse directement au SDK
 * WebRTC pour la même raison — le greffon n'expose pas ce dont on a besoin.
 *
 * 🔴 LA DÉCISION N'EST PAS ICI, ELLE EST EN DART (`core/compression_video.dart`),
 * et c'est volontaire. Quoi réduire, de combien, et quand s'abstenir : ces
 * règles sont celles du web, écrites une fois, et ce fichier n'en est que le
 * bras. Il reçoit des dimensions et un débit déjà calculés, et il obéit. Sans
 * cela, la règle existerait en deux exemplaires — celui du web et celui du
 * téléphone — et ils divergeraient au premier changement.
 *
 * ⚠️ `atMost(court, long)` ET NON `atMost(720)`. Le raccourci à un seul nombre
 * borne LES DEUX côtés : une vidéo 16/9 en sortirait en 720 × 405, soit du
 * 405p. Avec deux nombres, le petit côté vise le premier et le grand côté le
 * second — c'est ce que `video_compress` fait pour son préréglage 720p, et
 * c'est la seule forme qui donne du vrai 720p.
 *
 * ⚠️ IL NE SUPPRIME JAMAIS LA SOURCE. Le fichier d'entrée est celui de la
 * GALERIE de l'utilisateur ; l'effacer effacerait sa vidéo. C'est le fichier de
 * SORTIE, dans le cache, que Dart retire après l'avoir lu.
 */
/*
 * ⚡ MEDIA3 TRANSFORMER D'ABORD (21/11/2026, « la compression dure trop »).
 *
 * Le moteur de Google, déjà embarqué pour la signature des vidéos
 * (`SignatureVideo`), va plus vite que `transcoder` sur trois points :
 *   · il demande à l'encodeur matériel de tourner AU PLUS VITE (priorité et
 *     cadence de travail), là où `transcoder` le laisse au rythme du temps réel
 *     sur une partie des téléphones ;
 *   · il RECOPIE LE SON tel quel quand le MP4 l'accepte (le cas de toute vidéo
 *     filmée), au lieu de le décoder et le réencoder ;
 *   · sa chaîne décodage → redimensionnement → encodage travaille en parallèle.
 *
 * ⚠️ LA CONSIGNE NE CHANGE PAS : mêmes dimensions, même débit, toujours décidés
 * en Dart. 30 images par seconde au plus, comme `transcoder` le faisait par
 * défaut. Jamais agrandie.
 *
 * ⚠️ UN REPLI, PAS UN REMPLACEMENT : au moindre refus de Media3 (format
 * exotique, encodeur absent, vidéo HDR que le téléphone ne sait pas réduire),
 * `transcoder` reprend la vidéo comme avant. Le pire cas est donc l'ancien.
 */
@OptIn(UnstableApi::class)
object CompresseurVideo {

    private const val DOSSIER = "compression_video"
    private const val TAG = "CompresseurVideo"
    private const val IMAGES_PAR_SECONDE = 30f

    private val principal = Handler(Looper.getMainLooper())

    /** Le transcodage en cours, s'il y en a un. Une seule conversion à la fois. */
    private var enCours: Future<Void>? = null

    /** Une conversion Media3 en cours. */
    private var media3EnCours = false

    /**
     * Arrête la conversion en cours (21/11/2026, « Annuler » sur la bulle
     * « Compression… »). Nul quand rien ne tourne.
     */
    private var annulation: (() -> Unit)? = null

    /**
     * Annule la conversion en cours : le moteur s'arrête, le fichier partiel
     * est effacé, et Dart reçoit `null` — jamais le repli sur l'autre moteur.
     */
    fun annuler() {
        annulation?.invoke()
    }

    /** Y a-t-il déjà un transcodage en cours ? */
    fun occupe(): Boolean = media3EnCours || enCours?.isDone == false

    /**
     * Transcode [chemin] en une vidéo de [bordCourt] × [bordLong] au plus, à
     * [debit] bits par seconde, puis rend le chemin du fichier produit.
     *
     * Ne lève pas : chaque issue passe par [surFin], avec `null` quand rien n'a
     * pu être produit. Côté Dart, `null` veut dire « garde l'original », jamais
     * « échoue l'envoi ».
     *
     * [surProgression] reçoit une valeur de 0 à 1, et [surFin] le chemin du
     * fichier produit ou `null`. Les deux sont appelés sur le fil où cette
     * méthode a été appelée (le fil principal, depuis le canal Flutter).
     */
    fun compresser(
        contexte: Context,
        chemin: String,
        bordCourt: Int,
        bordLong: Int,
        debit: Long,
        surProgression: (Double) -> Unit,
        surFin: (String?) -> Unit,
    ) {
        if (occupe()) {
            surFin(null)
            return
        }

        val sortie = try {
            val dossier = File(contexte.cacheDir, DOSSIER).apply { mkdirs() }
            File(dossier, "alanya-${System.currentTimeMillis()}.mp4")
        } catch (_: Throwable) {
            surFin(null)
            return
        }

        /*
         * ⚠️ UNE SEULE RÉPONSE, QUOI QU'IL ARRIVE. `onTranscodeCompleted` et
         * `onTranscodeFailed` ne peuvent pas se produire tous les deux, mais une
         * exception levée à la construction passerait par le `catch` du bas
         * APRÈS qu'un auditeur ait déjà répondu. Deux réponses sur un canal
         * Flutter font tomber l'application.
         */
        var repondu = false
        val repondre = { resultat: String? ->
            if (!repondu) {
                repondu = true
                annulation = null
                surFin(resultat)
            }
        }

        var annule = false
        var transformer: Transformer? = null
        annulation = {
            annule = true
            try { transformer?.cancel() } catch (_: Throwable) {}
            try { enCours?.cancel(true) } catch (_: Throwable) {}
            media3EnCours = false
            sortie.delete()
            repondre(null)
        }

        transformer = try {
            parMedia3(contexte, chemin, sortie, bordCourt, bordLong, debit, surProgression) { reussi ->
                if (annule) return@parMedia3
                if (reussi) {
                    repondre(sortie.absolutePath)
                } else {
                    sortie.delete()
                    parTranscoder(contexte, chemin, sortie, bordCourt, bordLong, debit, surProgression, repondre)
                }
            }
        } catch (e: Throwable) {
            Log.w(TAG, "Media3 indisponible, repli : ${e.message}")
            media3EnCours = false
            null
        }
        if (transformer == null && !annule) {
            parTranscoder(contexte, chemin, sortie, bordCourt, bordLong, debit, surProgression, repondre)
        }
    }

    /**
     * La conversion par Media3. [surFin] reçoit `true` si [sortie] est prête,
     * `false` pour laisser la main au repli. Lève si elle ne peut même pas
     * démarrer (l'appelant passe alors au repli).
     */
    private fun parMedia3(
        contexte: Context,
        chemin: String,
        sortie: File,
        bordCourt: Int,
        bordLong: Int,
        debit: Long,
        surProgression: (Double) -> Unit,
        surFin: (Boolean) -> Unit,
    ): Transformer {
        val source = if (chemin.contains("://")) Uri.parse(chemin) else Uri.fromFile(File(chemin))
        val (largeur, hauteur) = dimensionsEcran(contexte, source)
        // Le grand côté de la consigne suit le grand côté de l'IMAGE AFFICHÉE
        // (rotation comprise) ; jamais au-delà de la source.
        val couchee = largeur >= hauteur
        val boiteL = if (couchee) bordLong else bordCourt
        val boiteH = if (couchee) bordCourt else bordLong
        val echelle = minOf(1.0, boiteL.toDouble() / largeur, boiteH.toDouble() / hauteur)
        val cibleL = pair(largeur * echelle)
        val cibleH = pair(hauteur * echelle)

        val effets = Effects(
            emptyList(),
            listOf(
                FrameDropEffect.createDefaultFrameDropEffect(IMAGES_PAR_SECONDE),
                Presentation.createForWidthAndHeight(cibleL, cibleH, Presentation.LAYOUT_SCALE_TO_FIT),
            ),
        )
        val element = EditedMediaItem.Builder(MediaItem.fromUri(source))
            .setEffects(effets)
            .build()
        val encodeurs = DefaultEncoderFactory.Builder(contexte)
            .setRequestedVideoEncoderSettings(
                VideoEncoderSettings.Builder()
                    .setBitrate(debit.coerceAtMost(Int.MAX_VALUE.toLong()).toInt())
                    .build(),
            )
            .setEnableFallback(true)
            .build()

        var fini = false
        val transformer = Transformer.Builder(contexte)
            .setVideoMimeType(MimeTypes.VIDEO_H264)
            .setEncoderFactory(encodeurs)
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    if (fini) return
                    fini = true
                    media3EnCours = false
                    surProgression(1.0)
                    surFin(sortie.exists() && sortie.length() > 0)
                }

                override fun onError(
                    composition: Composition,
                    exportResult: ExportResult,
                    exportException: ExportException,
                ) {
                    if (fini) return
                    fini = true
                    media3EnCours = false
                    Log.w(TAG, "Media3 a refusé la vidéo, repli : ${exportException.message}")
                    surFin(false)
                }
            })
            .build()
        media3EnCours = true
        transformer.start(element, sortie.absolutePath)

        // Media3 ne pousse pas son avancement : on le relit quatre fois par
        // seconde, sur le fil principal où il tourne.
        val prise = ProgressHolder()
        principal.postDelayed(object : Runnable {
            override fun run() {
                if (fini) return
                val etat = try {
                    transformer.getProgress(prise)
                } catch (_: Throwable) {
                    Transformer.PROGRESS_STATE_NOT_STARTED
                }
                // Plus rien ne tourne (annulée, ou finie) : on cesse de relire.
                if (etat == Transformer.PROGRESS_STATE_NOT_STARTED) return
                if (etat == Transformer.PROGRESS_STATE_AVAILABLE) {
                    surProgression((prise.progress / 100.0).coerceIn(0.0, 1.0))
                }
                principal.postDelayed(this, 250)
            }
        }, 250)
        return transformer
    }

    /** Largeur et hauteur de l'image AFFICHÉE (rotation appliquée). */
    private fun dimensionsEcran(contexte: Context, source: Uri): Pair<Int, Int> {
        val lecteur = MediaMetadataRetriever()
        try {
            lecteur.setDataSource(contexte, source)
            val l = lecteur.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull()
            val h = lecteur.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull()
            val rotation = lecteur.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                ?.toIntOrNull() ?: 0
            if (l == null || h == null || l < 16 || h < 16) {
                throw IllegalArgumentException("Vidéo sans dimensions lisibles")
            }
            return if (rotation % 180 != 0) Pair(h, l) else Pair(l, h)
        } finally {
            lecteur.release()
        }
    }

    private fun pair(n: Double): Int = maxOf(2, 2 * Math.round(n / 2).toInt())

    /** L'ancien moteur, `transcoder` : le repli. */
    private fun parTranscoder(
        contexte: Context,
        chemin: String,
        sortie: File,
        bordCourt: Int,
        bordLong: Int,
        debit: Long,
        surProgression: (Double) -> Unit,
        repondre: (String?) -> Unit,
    ) {
        try {
            // Un chemin nu n'est pas une URI : `Uri.parse("/storage/…")` ne
            // porte aucun schéma et ne s'ouvre pas. On le convertit.
            val source = if (chemin.contains("://")) Uri.parse(chemin) else Uri.fromFile(File(chemin))

            val imageStrategy = DefaultVideoStrategy.atMost(bordCourt, bordLong)
                .bitRate(debit)
                .build()

            /*
             * Le son est RÉ-ENCODÉ au format d'entrée (mêmes canaux, même
             * fréquence) plutôt que recopié tel quel. Le web, lui, recopie ses
             * paquets — mais ici le transcodeur s'en charge, et un son recopié
             * depuis un conteneur exotique est la première chose qui casse. Son
             * poids est négligeable devant celui de l'image.
             */
            val sonStrategy = DefaultAudioStrategy.builder()
                .channels(DefaultAudioStrategy.CHANNELS_AS_INPUT)
                .sampleRate(DefaultAudioStrategy.SAMPLE_RATE_AS_INPUT)
                .build()

            enCours = Transcoder.into(sortie.absolutePath)
                .addDataSource(UriDataSource(contexte, source))
                .setVideoTrackStrategy(imageStrategy)
                .setAudioTrackStrategy(sonStrategy)
                .setListener(object : TranscoderListener {
                    override fun onTranscodeProgress(progress: Double) {
                        surProgression(progress.coerceIn(0.0, 1.0))
                    }

                    override fun onTranscodeCompleted(successCode: Int) {
                        surProgression(1.0)
                        repondre(sortie.absolutePath)
                    }

                    override fun onTranscodeCanceled() {
                        sortie.delete()
                        repondre(null)
                    }

                    override fun onTranscodeFailed(exception: Throwable) {
                        // Un format que le téléphone ne sait pas relire, une
                        // piste exotique, un disque plein : la vidéo partira
                        // intacte, ce qui est le repli voulu.
                        sortie.delete()
                        repondre(null)
                    }
                })
                .transcode()
        } catch (_: Throwable) {
            sortie.delete()
            repondre(null)
        }
    }
}
