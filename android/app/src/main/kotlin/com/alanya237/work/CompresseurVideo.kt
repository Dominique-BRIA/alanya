package com.alanya237.work

import android.content.Context
import android.net.Uri
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
object CompresseurVideo {

    private const val DOSSIER = "compression_video"

    /** Le transcodage en cours, s'il y en a un. Une seule conversion à la fois. */
    private var enCours: Future<Void>? = null

    /** Y a-t-il déjà un transcodage en cours ? */
    fun occupe(): Boolean = enCours?.isDone == false

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
                surFin(resultat)
            }
        }

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
