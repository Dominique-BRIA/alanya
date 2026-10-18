package com.alanya237.work

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BlurMaskFilter
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.util.Log
import com.cloudwebrtc.webrtc.video.LocalVideoTrack
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarker
import org.webrtc.JavaI420Buffer
import org.webrtc.VideoFrame
import org.webrtc.YuvHelper
import java.nio.ByteBuffer
import kotlin.math.atan2
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min

/**
 * LES EFFETS DE VISAGE PENDANT UN APPEL VIDÉO (18/10/2026) — 100 % gratuits,
 * 100 % sur le téléphone, comme WhatsApp et Snapchat.
 *
 * Chaque image de la caméra passe ici AVANT d'être envoyée (`flutter_webrtc`
 * l'offre : `LocalVideoTrack.addProcessor`) :
 *  1. réduite à 640 px au plus (WebRTC, en natif) puis convertie en image RGB ;
 *  2. le visage y est repéré par MediaPipe Face Landmarker (Google, licence
 *     Apache 2.0, modèle `assets/face_landmarker.task`, sans réseau) — une image
 *     sur deux, les points sont lissés entre deux détections ;
 *  3. l'effet est dessiné : barbe, moustache ou lunettes posées sur les points
 *     du visage ; grosse tête ou visage fin par un maillage déformé ;
 *  4. l'image repart en I420 (`YuvHelper.ABGRToI420`, natif) vers l'appel —
 *     l'interlocuteur voit l'effet, et notre aperçu aussi.
 *
 * ⚠️ NE CASSE JAMAIS UN APPEL : la moindre erreur rend l'image d'origine, et un
 * détecteur qui ne s'ouvre pas laisse passer la caméra telle quelle.
 *
 * ⚠️ L'IMAGE QU'ON REND est à nous : on la libère à l'image suivante (le temps
 * que WebRTC l'ait prise en charge), ou au retrait de l'effet.
 */
class EffetsVisage(private val contexte: Context) : LocalVideoTrack.ExternalVideoFrameProcessing {

    private companion object {
        const val TAG = "EffetsVisage"
        const val COTE_MAX = 640
        const val COTE_DETECTION = 256f
        const val MAILLE = 24

        // Points du maillage MediaPipe (468 + 10 pour les iris).
        val MACHOIRE = intArrayOf(
            234, 93, 132, 58, 172, 136, 150, 149, 176, 148, 152,
            377, 400, 378, 379, 365, 397, 288, 361, 323, 454,
        )
        val LEVRE_BAS = intArrayOf(291, 375, 321, 405, 314, 17, 84, 181, 91, 146, 61)
        val LEVRE_HAUT = intArrayOf(61, 185, 40, 39, 37, 0, 267, 269, 270, 409, 291)
        const val SOMMET = 10
        const val MENTON = 152
        const val SOUS_NEZ = 2
        const val IRIS_GAUCHE = 468
        const val IRIS_DROIT = 473
        const val OEIL_G_EXT = 33
        const val OEIL_G_INT = 133
        const val OEIL_D_INT = 362
        const val OEIL_D_EXT = 263
        const val JOUE_G = 234
        const val JOUE_D = 454
    }

    /** `aucun`, `barbe`, `moustache`, `lunettes`, `grosse_tete`, `visage_fin`. */
    @Volatile var effet: String = "aucun"

    private val verrou = Any()
    private var detecteur: FaceLandmarker? = null
    private var detecteurImpossible = false
    private var precedente: VideoFrame? = null
    private var points: FloatArray? = null
    private var compteur = 0L
    private var dernierInstant = 0L

    private var source: Bitmap? = null
    private var sortie: Bitmap? = null
    private var pixels: IntArray? = null
    private var tamponRgba: ByteBuffer? = null

    override fun onFrame(frame: VideoFrame): VideoFrame = synchronized(verrou) {
        precedente?.release()
        precedente = null
        val e = effet
        if (e == "aucun" || detecteurImpossible) return frame
        try {
            val traitee = traiter(frame, e) ?: return frame
            precedente = traitee
            traitee
        } catch (t: Throwable) {
            Log.e(TAG, "effet « $e » abandonné pour cette image", t)
            frame
        }
    }

    /** Retrait de l'effet (fin d'appel, ou « Aucun ») : tout se libère. */
    fun liberer() = synchronized(verrou) {
        effet = "aucun"
        precedente?.release()
        precedente = null
        points = null
        try { detecteur?.close() } catch (_: Throwable) {}
        detecteur = null
        source?.recycle(); source = null
        sortie?.recycle(); sortie = null
        pixels = null
        tamponRgba = null
    }

    private fun ouvrirDetecteur(): FaceLandmarker? {
        detecteur?.let { return it }
        if (detecteurImpossible) return null
        return try {
            val options = FaceLandmarker.FaceLandmarkerOptions.builder()
                .setBaseOptions(BaseOptions.builder().setModelAssetPath("face_landmarker.task").build())
                .setRunningMode(RunningMode.VIDEO)
                .setNumFaces(1)
                .setMinFaceDetectionConfidence(0.5f)
                .setMinFacePresenceConfidence(0.5f)
                .setMinTrackingConfidence(0.5f)
                .build()
            FaceLandmarker.createFromOptions(contexte, options).also { detecteur = it }
        } catch (t: Throwable) {
            Log.e(TAG, "détecteur de visage indisponible : la caméra passe telle quelle", t)
            detecteurImpossible = true
            null
        }
    }

    private fun traiter(frame: VideoFrame, e: String): VideoFrame? {
        val tampon = frame.buffer
        val w0 = tampon.width
        val h0 = tampon.height
        val echelle = min(1f, COTE_MAX.toFloat() / max(w0, h0))
        val w = ((w0 * echelle).toInt()) and 1.inv()
        val h = ((h0 * echelle).toInt()) and 1.inv()
        if (w < 16 || h < 16) return null

        val reduit = tampon.cropAndScale(0, 0, w0, h0, w, h)
        val i420 = reduit.toI420()
        reduit.release()
        if (i420 == null) return null
        val src = preparer(w, h)
        try {
            versBitmap(i420, w, h, src)
        } finally {
            i420.release()
        }

        val rot = ((frame.rotation % 360) + 360) % 360
        if (compteur++ % 2L == 0L || points == null) detecter(src, w, h, rot, frame.timestampNs)

        val dst = sortie!!
        val canevas = Canvas(dst)
        val versImage = matriceDroitVersImage(rot, w, h)
        val wu = if (rot % 180 == 0) w else h
        val hu = if (rot % 180 == 0) h else w
        val pts = points
        when {
            pts == null -> canevas.drawBitmap(src, 0f, 0f, null)
            e == "grosse_tete" || e == "visage_fin" ->
                deformer(canevas, src, pts, versImage, wu, hu, w, h, e == "grosse_tete")
            else -> {
                canevas.drawBitmap(src, 0f, 0f, null)
                canevas.save()
                canevas.concat(versImage)
                dessinerAccessoire(canevas, e, pts, wu.toFloat(), hu.toFloat())
                canevas.restore()
            }
        }

        val rgba = tamponRgba!!
        rgba.rewind()
        dst.copyPixelsToBuffer(rgba)
        rgba.rewind()
        val dest = JavaI420Buffer.allocate(w, h)
        YuvHelper.ABGRToI420(
            rgba, w * 4,
            dest.dataY, dest.strideY,
            dest.dataU, dest.strideU,
            dest.dataV, dest.strideV,
            w, h,
        )
        return VideoFrame(dest, frame.rotation, frame.timestampNs)
    }

    private fun preparer(w: Int, h: Int): Bitmap {
        val s = source
        if (s != null && s.width == w && s.height == h) return s
        source?.recycle(); sortie?.recycle()
        source = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        sortie = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        pixels = IntArray(w * h)
        tamponRgba = ByteBuffer.allocateDirect(w * h * 4)
        points = null
        return source!!
    }

    /** I420 → RGB (BT.601), en entiers. */
    private fun versBitmap(b: VideoFrame.I420Buffer, w: Int, h: Int, cible: Bitmap) {
        val px = pixels!!
        val y = b.dataY; val u = b.dataU; val v = b.dataV
        val sy = b.strideY; val su = b.strideU; val sv = b.strideV
        for (j in 0 until h) {
            val ly = j * sy
            val lu = (j shr 1) * su
            val lv = (j shr 1) * sv
            val ligne = j * w
            for (i in 0 until w) {
                val yy = max((y.get(ly + i).toInt() and 0xff) - 16, 0) * 1192
                val uu = (u.get(lu + (i shr 1)).toInt() and 0xff) - 128
                val vv = (v.get(lv + (i shr 1)).toInt() and 0xff) - 128
                var r = (yy + 1634 * vv) shr 10
                var g = (yy - 833 * vv - 400 * uu) shr 10
                var bl = (yy + 2066 * uu) shr 10
                r = if (r < 0) 0 else if (r > 255) 255 else r
                g = if (g < 0) 0 else if (g > 255) 255 else g
                bl = if (bl < 0) 0 else if (bl > 255) 255 else bl
                px[ligne + i] = (0xff shl 24) or (r shl 16) or (g shl 8) or bl
            }
        }
        cible.setPixels(px, 0, w, 0, 0, w, h)
    }

    /**
     * Repère le visage sur une petite copie REDRESSÉE (la caméra frontale livre
     * souvent ses images couchées : `rotation` 90 ou 270).
     */
    private fun detecter(src: Bitmap, w: Int, h: Int, rot: Int, instantNs: Long) {
        val d = ouvrirDetecteur() ?: return
        val s = COTE_DETECTION / max(w, h)
        val m = Matrix().apply { postScale(s, s); postRotate(rot.toFloat()) }
        val petit = Bitmap.createBitmap(src, 0, 0, w, h, m, true)
        try {
            val instant = max(dernierInstant + 1, instantNs / 1_000_000)
            dernierInstant = instant
            val r = d.detectForVideo(BitmapImageBuilder(petit).build(), instant)
            val visages = r.faceLandmarks()
            if (visages.isEmpty()) {
                points = null
                return
            }
            val v = visages[0]
            val nouveaux = FloatArray(v.size * 2)
            for (k in v.indices) {
                nouveaux[2 * k] = v[k].x()
                nouveaux[2 * k + 1] = v[k].y()
            }
            // Lissage : moins de tremblement entre deux détections.
            val anciens = points
            if (anciens != null && anciens.size == nouveaux.size) {
                for (k in nouveaux.indices) nouveaux[k] = anciens[k] * 0.4f + nouveaux[k] * 0.6f
            }
            points = nouveaux
        } finally {
            petit.recycle()
        }
    }

    /** Coordonnées de l'image redressée (en pixels) → coordonnées de l'image reçue. */
    private fun matriceDroitVersImage(rot: Int, w: Int, h: Int): Matrix {
        val m = Matrix()
        val wf = w.toFloat(); val hf = h.toFloat()
        when (rot) {
            90 -> m.setValues(floatArrayOf(0f, 1f, 0f, -1f, 0f, hf, 0f, 0f, 1f))
            180 -> m.setValues(floatArrayOf(-1f, 0f, wf, 0f, -1f, hf, 0f, 0f, 1f))
            270 -> m.setValues(floatArrayOf(0f, -1f, wf, 1f, 0f, 0f, 0f, 0f, 1f))
        }
        return m
    }

    private fun px(p: FloatArray, k: Int, wu: Float) = p[2 * k] * wu
    private fun py(p: FloatArray, k: Int, hu: Float) = p[2 * k + 1] * hu

    private fun dessinerAccessoire(c: Canvas, e: String, p: FloatArray, wu: Float, hu: Float) {
        if (p.size < 2 * 468) return
        when (e) {
            "barbe" -> { dessinerBarbe(c, p, wu, hu); dessinerMoustache(c, p, wu, hu) }
            "moustache" -> dessinerMoustache(c, p, wu, hu)
            "lunettes" -> if (p.size >= 2 * 478) dessinerLunettes(c, p, wu, hu)
        }
    }

    private val pinceauPoils = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(225, 52, 36, 24)
        style = Paint.Style.FILL
    }

    private fun flouPour(taille: Float) = BlurMaskFilter(max(1.5f, taille * 0.035f), BlurMaskFilter.Blur.NORMAL)

    private fun dessinerBarbe(c: Canvas, p: FloatArray, wu: Float, hu: Float) {
        val chemin = Path()
        chemin.moveTo(px(p, MACHOIRE[0], wu), py(p, MACHOIRE[0], hu))
        for (k in MACHOIRE) chemin.lineTo(px(p, k, wu), py(p, k, hu))
        // On remonte par la commissure droite, on longe la lèvre inférieure.
        for (k in LEVRE_BAS) chemin.lineTo(px(p, k, wu), py(p, k, hu))
        chemin.close()
        val visage = hypot(px(p, SOMMET, wu) - px(p, MENTON, wu), py(p, SOMMET, hu) - py(p, MENTON, hu))
        pinceauPoils.maskFilter = flouPour(visage)
        c.drawPath(chemin, pinceauPoils)
    }

    private fun dessinerMoustache(c: Canvas, p: FloatArray, wu: Float, hu: Float) {
        // La bande entre la lèvre supérieure et le dessous du nez.
        val dx = (px(p, SOUS_NEZ, wu) - px(p, 0, wu)) * 0.85f
        val dy = (py(p, SOUS_NEZ, hu) - py(p, 0, hu)) * 0.85f
        val chemin = Path()
        chemin.moveTo(px(p, LEVRE_HAUT[0], wu), py(p, LEVRE_HAUT[0], hu))
        for (k in LEVRE_HAUT) chemin.lineTo(px(p, k, wu), py(p, k, hu))
        for (i in LEVRE_HAUT.indices.reversed()) {
            val k = LEVRE_HAUT[i]
            // Plus épaisse au milieu, effilée aux commissures.
            val milieu = 1f - kotlin.math.abs(i - (LEVRE_HAUT.size - 1) / 2f) / ((LEVRE_HAUT.size - 1) / 2f)
            val f = 0.45f + 0.55f * milieu
            chemin.lineTo(px(p, k, wu) + dx * f, py(p, k, hu) + dy * f)
        }
        chemin.close()
        val largeur = hypot(px(p, 61, wu) - px(p, 291, wu), py(p, 61, hu) - py(p, 291, hu))
        pinceauPoils.maskFilter = flouPour(largeur * 2f)
        c.drawPath(chemin, pinceauPoils)
    }

    private val verre = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(170, 15, 15, 20) }
    private val monture = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(20, 20, 20); style = Paint.Style.STROKE; strokeCap = Paint.Cap.ROUND
    }

    private fun dessinerLunettes(c: Canvas, p: FloatArray, wu: Float, hu: Float) {
        val gx = px(p, IRIS_GAUCHE, wu); val gy = py(p, IRIS_GAUCHE, hu)
        val dx = px(p, IRIS_DROIT, wu); val dy = py(p, IRIS_DROIT, hu)
        val angle = Math.toDegrees(atan2((dy - gy).toDouble(), (dx - gx).toDouble())).toFloat()
        val oeil = max(
            hypot(px(p, OEIL_G_EXT, wu) - px(p, OEIL_G_INT, wu), py(p, OEIL_G_EXT, hu) - py(p, OEIL_G_INT, hu)),
            hypot(px(p, OEIL_D_EXT, wu) - px(p, OEIL_D_INT, wu), py(p, OEIL_D_EXT, hu) - py(p, OEIL_D_INT, hu)),
        )
        val lw = oeil * 1.75f
        val lh = oeil * 1.25f
        monture.strokeWidth = max(2f, oeil * 0.12f)
        for ((cx, cy) in listOf(gx to gy, dx to dy)) {
            c.save()
            c.rotate(angle, cx, cy)
            val r = RectF(cx - lw / 2, cy - lh / 2, cx + lw / 2, cy + lh / 2)
            c.drawRoundRect(r, lh * 0.45f, lh * 0.45f, verre)
            c.drawRoundRect(r, lh * 0.45f, lh * 0.45f, monture)
            c.restore()
        }
        // Le pont sur le nez, et les branches vers les tempes.
        c.drawLine(gx + (dx - gx) * 0.32f, gy + (dy - gy) * 0.32f - lh * 0.15f,
            gx + (dx - gx) * 0.68f, gy + (dy - gy) * 0.68f - lh * 0.15f, monture)
        c.drawLine(gx - (dx - gx) * 0.32f, gy - (dy - gy) * 0.32f, px(p, JOUE_G, wu), py(p, JOUE_G, hu) - lh * 0.4f, monture)
        c.drawLine(dx + (dx - gx) * 0.32f, dy + (dy - gy) * 0.32f, px(p, JOUE_D, wu), py(p, JOUE_D, hu) - lh * 0.4f, monture)
    }

    /**
     * Grosse tête (loupe au centre du visage) ou visage fin (resserré vers
     * l'axe du nez) : la photo est redessinée sur un maillage déformé.
     */
    private fun deformer(
        c: Canvas, src: Bitmap, p: FloatArray, versImage: Matrix,
        wu: Int, hu: Int, w: Int, h: Int, gonfler: Boolean,
    ) {
        val wf = wu.toFloat(); val hf = hu.toFloat()
        val haut = floatArrayOf(px(p, SOMMET, wf), py(p, SOMMET, hf))
        val bas = floatArrayOf(px(p, MENTON, wf), py(p, MENTON, hf))
        val cx = (haut[0] + bas[0]) / 2f
        val cy = (haut[1] + bas[1]) / 2f
        val hauteur = hypot(bas[0] - haut[0], bas[1] - haut[1])
        val rayon = hauteur * if (gonfler) 0.85f else 0.75f
        // L'axe vertical du visage, pour resserrer perpendiculairement à lui.
        val ax = (bas[0] - haut[0]) / max(hauteur, 1f)
        val ay = (bas[1] - haut[1]) / max(hauteur, 1f)

        val versDroit = Matrix().also { versImage.invert(it) }
        val sommets = FloatArray((MAILLE + 1) * (MAILLE + 1) * 2)
        val pt = FloatArray(2)
        var n = 0
        for (j in 0..MAILLE) for (i in 0..MAILLE) {
            pt[0] = w * i / MAILLE.toFloat()
            pt[1] = h * j / MAILLE.toFloat()
            versDroit.mapPoints(pt)
            val ox = pt[0] - cx
            val oy = pt[1] - cy
            val d = hypot(ox, oy) / rayon
            if (d < 1f) {
                if (gonfler) {
                    val f = 1f + 0.5f * (1f - d) * (1f - d)
                    pt[0] = cx + ox * f
                    pt[1] = cy + oy * f
                } else {
                    // Composante perpendiculaire à l'axe du visage, resserrée.
                    val le = ox * ax + oy * ay
                    val px0 = ox - le * ax
                    val py0 = oy - le * ay
                    val f = 1f - 0.22f * (1f - d)
                    pt[0] = cx + le * ax + px0 * f
                    pt[1] = cy + le * ay + py0 * f
                }
            }
            versImage.mapPoints(pt)
            sommets[n++] = pt[0]
            sommets[n++] = pt[1]
        }
        c.drawColor(Color.BLACK)
        c.drawBitmapMesh(src, MAILLE, MAILLE, sommets, 0, null, 0, null)
    }
}
