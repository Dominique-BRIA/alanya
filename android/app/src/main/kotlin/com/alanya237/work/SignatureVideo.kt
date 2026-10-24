package com.alanya237.work

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.Presentation
import androidx.media3.effect.TextureOverlay
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import com.google.common.collect.ImmutableList
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * LA SIGNATURE INCRUSTÉE AUX QUATRE BORDS D'UNE VIDÉO (24/10/2026), méthode
 * `signerVideo` du canal `alanya/signature`.
 *
 * Demande du user : comme pour une image, le texte de la signature court aux
 * quatre bords d'une vidéo sensible téléchargée. Il survit à WhatsApp, qui
 * réencode la vidéo et efface les métadonnées.
 *
 * Media3 Transformer (même version 1.9.2 que la lecture vidéo de `video_player`)
 * décode la vidéo, pose sur chaque image un CALQUE transparent où les bords
 * sont peints une fois pour toutes (`BitmapOverlay`), et réencode en H.264 /
 * AAC. La rotation d'origine est appliquée avant les effets : le calque est
 * donc fait aux dimensions À L'ÉCRAN, et `Presentation` fixe ces dimensions.
 *
 * Les métadonnées (huit champs, empreinte) sont écrites ensuite, en Dart, sur
 * le MP4 produit (`mp4_metadonnees.dart`). Un échec ici remonte à Dart, qui
 * retombe sur la copie aux seules métadonnées : jamais pire qu'avant.
 *
 * ⚠️ `@OptIn(UnstableApi::class)` : les effets de Media3 sont marqués instables
 * par Google, et le contrôle d'Android (lint) refuse sinon la construction.
 */
@OptIn(UnstableApi::class)
class SignatureVideo(
    private val contexte: Context,
    private val signature: SignatureDocument,
) {

    private companion object {
        const val TAG = "AlanyaSignatureVideo"
    }

    /** Transformer veut un fil qui a une boucle de messages : le fil principal. */
    private val principal = Handler(Looper.getMainLooper())

    fun traiter(appel: MethodCall, resultat: MethodChannel.Result) {
        val entree = appel.argument<String>("entree")
        val sortie = appel.argument<String>("sortie")
        val bords = appel.argument<String>("bords") ?: ""
        if (entree == null || sortie == null) {
            resultat.error("ARGUMENTS", "entree et sortie sont obligatoires", null)
            return
        }
        principal.post { demarrer(entree, sortie, bords, resultat) }
    }

    private fun demarrer(entree: String, sortie: String, texte: String, resultat: MethodChannel.Result) {
        val calque: Bitmap
        val transformer: Transformer
        try {
            val (l, h) = dimensionsEcran(entree)
            calque = Bitmap.createBitmap(l, h, Bitmap.Config.ARGB_8888)
            signature.peindreBords(Canvas(calque), l.toFloat(), h.toFloat(), texte)
            val effets = Effects(
                emptyList(),
                listOf(
                    Presentation.createForWidthAndHeight(l, h, Presentation.LAYOUT_SCALE_TO_FIT),
                    // Type explicite : la liste Java attendue est invariante.
                    OverlayEffect(
                        ImmutableList.of<TextureOverlay>(BitmapOverlay.createStaticBitmapOverlay(calque)),
                    ),
                ),
            )
            val element = EditedMediaItem.Builder(MediaItem.fromUri(Uri.fromFile(File(entree))))
                .setEffects(effets)
                .build()
            transformer = Transformer.Builder(contexte)
                .setVideoMimeType(MimeTypes.VIDEO_H264)
                .setAudioMimeType(MimeTypes.AUDIO_AAC)
                .addListener(object : Transformer.Listener {
                    override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                        calque.recycle()
                        resultat.success(mapOf("chemin" to sortie, "mime" to "video/mp4"))
                    }

                    override fun onError(
                        composition: Composition,
                        exportResult: ExportResult,
                        exportException: ExportException,
                    ) {
                        calque.recycle()
                        File(sortie).delete()
                        Log.w(TAG, "Vidéo non signée : ${exportException.message}")
                        resultat.error("ECHEC", exportException.message, null)
                    }
                })
                .build()
            transformer.start(element, sortie)
        } catch (e: Throwable) {
            Log.w(TAG, "Vidéo non signée : ${e.message}")
            resultat.error("ECHEC", e.message, null)
        }
    }

    /** Largeur et hauteur À L'ÉCRAN (rotation comprise), paires pour l'encodeur. */
    private fun dimensionsEcran(chemin: String): Pair<Int, Int> {
        val lecteur = MediaMetadataRetriever()
        try {
            lecteur.setDataSource(chemin)
            val l = lecteur.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull()
            val h = lecteur.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull()
            val rotation = lecteur.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                ?.toIntOrNull() ?: 0
            if (l == null || h == null || l < 16 || h < 16) {
                throw IllegalArgumentException("Vidéo sans dimensions lisibles")
            }
            val couchee = rotation % 180 != 0
            val ecranL = if (couchee) h else l
            val ecranH = if (couchee) l else h
            return Pair(ecranL - ecranL % 2, ecranH - ecranH % 2)
        } finally {
            lecteur.release()
        }
    }
}
