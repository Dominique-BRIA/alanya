package com.alanya237.work

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Typeface
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.exifinterface.media.ExifInterface
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.io.MemoryUsageSetting
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDPage
import com.tom_roush.pdfbox.pdmodel.PDPageContentStream
import com.tom_roush.pdfbox.pdmodel.font.PDFont
import com.tom_roush.pdfbox.pdmodel.font.PDType0Font
import com.tom_roush.pdfbox.pdmodel.font.PDType1Font
import com.tom_roush.pdfbox.pdmodel.graphics.state.PDExtendedGraphicsState
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.text.Normalizer
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.min
import com.tom_roush.pdfbox.util.Matrix as MatricePdf

/**
 * LA COPIE SIGNÉE D'UN DOCUMENT SENSIBLE (22/10/2026), canal `alanya/signature`.
 *
 * Demande du user : un document sensible se télécharge et se partage
 * librement, mais la copie qui sort porte, aux QUATRE BORDS, « Alanya Work ·
 * Alanya <ID> · <appareil> · <date> · <code> », et dans ses MÉTADONNÉES
 * l'Alanya ID, l'appareil, la date, le geste et le code de trace.
 *
 * * PDF : PdfBox-Android (Apache 2.0) écrit le texte aux quatre bords de
 *   chaque page (par-dessus le contenu, rien n'est effacé) et remplit le
 *   dictionnaire Info (Creator, Producer, Subject, Keywords et les champs
 *   « Application », « Alanya ID », « Appareil », « Date Creation »,
 *   « Empreinte numerique »…, visibles dans les propriétés du document).
 * * Images : le texte est peint aux quatre bords (contour blanc : lisible sur
 *   fond clair comme sombre), puis l'EXIF reçoit l'auteur, la description, le
 *   logiciel et le code (`ImageUniqueID`, fait pour 32 caractères).
 *
 * Les vidéos ne passent pas ici : leurs métadonnées s'écrivent en Dart, sans
 * réencodage (`mp4_metadonnees.dart`).
 *
 * Tout tourne hors du fil principal ; une erreur remonte à Dart, qui rend
 * alors la copie telle quelle (le geste n'est jamais refusé).
 */
class SignatureDocument(private val contexte: Context) {

    private companion object {
        const val TAG = "AlanyaSignature"

        /** Au-delà, l'image est réduite : 4096² en ARGB ≈ 64 Mo de mémoire. */
        const val COTE_MAX = 4096

        /** Rouge des documents sensibles (#E53935), comme dans l'application. */
        const val ROUGE = 0xE53935

        /** Noms des champs de métadonnées : les mêmes que `CleMeta` en Dart. */
        const val CLE_APPLICATION = "Application"
        const val CLE_ALANYA_ID = "Alanya ID"
        const val CLE_EMPREINTE = "Empreinte numerique"

        /** Polices du système essayées quand Helvetica ne sait pas écrire le texte. */
        val POLICES_SYSTEME = listOf(
            "/system/fonts/Roboto-Regular.ttf",
            "/system/fonts/RobotoStatic-Regular.ttf",
            "/system/fonts/NotoSans-Regular.ttf",
            "/system/fonts/DroidSans.ttf",
        )
    }

    private val travailleur = Executors.newSingleThreadExecutor()
    private val principal = Handler(Looper.getMainLooper())

    @Volatile
    private var pdfboxPret = false

    /** La signature incrustée d'une vidéo : Media3 Transformer (24/10/2026). */
    private val video by lazy { SignatureVideo(contexte, this) }

    fun traiter(appel: MethodCall, resultat: MethodChannel.Result) {
        if (appel.method == "signerVideo") {
            video.traiter(appel, resultat)
            return
        }
        if (appel.method != "signer") {
            resultat.notImplemented()
            return
        }
        val entree = appel.argument<String>("entree")
        val sortie = appel.argument<String>("sortie")
        val mime = appel.argument<String>("mime") ?: ""
        val bords = appel.argument<String>("bords") ?: ""
        val meta = appel.argument<Map<String, String>>("meta") ?: emptyMap()
        if (entree == null || sortie == null) {
            resultat.error("ARGUMENTS", "entree et sortie sont obligatoires", null)
            return
        }
        travailleur.execute {
            try {
                val r = if (mime == "application/pdf" || sortie.lowercase().endsWith(".pdf")) {
                    signerPdf(entree, sortie, bords, meta)
                } else {
                    signerImage(entree, sortie, mime, bords, meta)
                }
                principal.post { resultat.success(r) }
            } catch (e: Throwable) {
                Log.w(TAG, "Signature impossible : ${e.message}")
                principal.post { resultat.error("ECHEC", e.message, null) }
            }
        }
    }

    // ── PDF ────────────────────────────────────────────────────────────────

    private fun signerPdf(
        entree: String,
        sortie: String,
        texte: String,
        meta: Map<String, String>,
    ): Map<String, String> {
        if (!pdfboxPret) {
            PDFBoxResourceLoader.init(contexte.applicationContext)
            pdfboxPret = true
        }
        val memoire = MemoryUsageSetting.setupMixed(48L shl 20).setTempDir(contexte.cacheDir)
        // Un PDF protégé par un mot de passe d'OUVERTURE lève ici
        // (InvalidPasswordException) : on ne sait pas le lire, donc pas le signer.
        PDDocument.load(File(entree), memoire).use { doc ->
            // Protégé seulement contre la modification (mot de passe propriétaire) :
            // on retire la protection, sans quoi l'enregistrement échouerait.
            if (doc.isEncrypted) doc.setAllSecurityToBeRemoved(true)
            val (police, ecrit) = choisirPolice(doc, texte)
            val transparence = PDExtendedGraphicsState().apply { setNonStrokingAlphaConstant(0.85f) }
            for (page in doc.pages) signerPage(doc, page, police, ecrit, transparence)

            val info = doc.documentInformation
            info.creator = meta[CLE_APPLICATION] ?: "Alanya Work"
            info.producer = meta[CLE_APPLICATION] ?: "Alanya Work"
            info.subject = texte
            info.keywords = listOfNotNull(
                meta[CLE_APPLICATION],
                meta[CLE_ALANYA_ID]?.let { "Alanya $it" },
                meta[CLE_EMPREINTE]?.let { "Trace $it" },
            ).joinToString("; ")
            for ((cle, valeur) in meta) info.setCustomMetadataValue(cle, valeur)
            doc.documentInformation = info
            doc.save(File(sortie))
        }
        return mapOf("chemin" to sortie, "mime" to "application/pdf")
    }

    /**
     * Helvetica (sans embarquer de police) quand elle sait écrire le texte — le
     * cas courant : chiffres, noms d'appareil, code. Sinon une police du système
     * embarquée ; en dernier recours Helvetica, caractères inconnus remplacés.
     */
    private fun choisirPolice(doc: PDDocument, texte: String): Pair<PDFont, String> {
        val helvetica = PDType1Font.HELVETICA_BOLD
        if (sait(helvetica, texte)) return helvetica to texte
        for (chemin in POLICES_SYSTEME) {
            val fichier = File(chemin)
            if (!fichier.exists()) continue
            try {
                val police = PDType0Font.load(doc, fichier)
                if (sait(police, texte)) return police to texte
            } catch (e: Exception) {
                Log.w(TAG, "Police $chemin illisible : ${e.message}")
            }
        }
        val propre = buildString {
            for (c in texte) append(if (sait(helvetica, c.toString())) c else '?')
        }
        return helvetica to propre
    }

    private fun sait(police: PDFont, texte: String): Boolean = try {
        police.encode(texte)
        true
    } catch (e: Exception) {
        false
    }

    /** Le texte aux quatre bords de la page, par-dessus le contenu. */
    private fun signerPage(
        doc: PDDocument,
        page: PDPage,
        police: PDFont,
        texte: String,
        transparence: PDExtendedGraphicsState,
    ) {
        val boite = page.cropBox
        val x0 = boite.lowerLeftX
        val y0 = boite.lowerLeftY
        val l = boite.width
        val h = boite.height
        val base = (min(l, h) / 75f).coerceIn(5f, 9f)
        val marge = base * 0.9f
        val unite = police.getStringWidth(texte) / 1000f
        // Réduite si le bord est trop court pour la ligne entière.
        fun taillePour(longueur: Float) = min(base, (longueur - 2 * marge) / unite)
        val tH = taillePour(l)
        val tV = taillePour(h)
        val largeurH = unite * tH
        val largeurV = unite * tV

        PDPageContentStream(doc, page, PDPageContentStream.AppendMode.APPEND, true, true).use { cs ->
            cs.setGraphicsStateParameters(transparence)
            cs.setNonStrokingColor(
                ((ROUGE shr 16) and 0xFF) / 255f,
                ((ROUGE shr 8) and 0xFF) / 255f,
                (ROUGE and 0xFF) / 255f,
            )
            fun ecrire(taille: Float, matrice: MatricePdf) {
                cs.beginText()
                cs.setFont(police, taille)
                cs.setTextMatrix(matrice)
                cs.showText(texte)
                cs.endText()
            }
            // Haut et bas, centrés.
            ecrire(tH, MatricePdf.getTranslateInstance(x0 + (l - largeurH) / 2, y0 + h - marge - tH * 0.75f))
            ecrire(tH, MatricePdf.getTranslateInstance(x0 + (l - largeurH) / 2, y0 + marge + tH * 0.2f))
            // Gauche : lu de bas en haut. Droite : lu de haut en bas.
            ecrire(tV, MatricePdf.getRotateInstance(Math.PI / 2, x0 + marge + tV * 0.75f, y0 + (h - largeurV) / 2))
            ecrire(tV, MatricePdf.getRotateInstance(-Math.PI / 2, x0 + l - marge - tV * 0.75f, y0 + (h + largeurV) / 2))
        }
    }

    // ── Images ─────────────────────────────────────────────────────────────

    private fun signerImage(
        entree: String,
        sortie: String,
        mime: String,
        texte: String,
        meta: Map<String, String>,
    ): Map<String, String> {
        val dimensions = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(entree, dimensions)
        if (dimensions.outWidth <= 0 || dimensions.outHeight <= 0) {
            throw IllegalArgumentException("Image illisible")
        }
        var echantillon = 1
        while (max(dimensions.outWidth, dimensions.outHeight) / echantillon > COTE_MAX) echantillon *= 2
        val brute = BitmapFactory.decodeFile(
            entree,
            BitmapFactory.Options().apply {
                inSampleSize = echantillon
                inMutable = true
            },
        ) ?: throw IllegalArgumentException("Image illisible")
        val droite = redresser(brute, entree)
        val toile = if (droite.isMutable) droite else droite.copy(Bitmap.Config.ARGB_8888, true)
        peindreBords(Canvas(toile), toile.width.toFloat(), toile.height.toFloat(), texte)

        // Même format qu'à l'arrivée quand on sait l'écrire ; sinon JPEG
        // (HEIC, BMP…), et l'extension suit.
        val type = mime.lowercase()
        val ext = sortie.substringAfterLast('.', "").lowercase()
        val (format, extension, mimeSortie) = when {
            type == "image/png" || ext == "png" -> Triple(Bitmap.CompressFormat.PNG, "png", "image/png")
            type == "image/webp" || ext == "webp" -> Triple(formatWebp(), "webp", "image/webp")
            else -> Triple(Bitmap.CompressFormat.JPEG, if (ext == "jpeg") "jpeg" else "jpg", "image/jpeg")
        }
        val chemin = if (ext == extension) sortie else "${sortie.substringBeforeLast('.', sortie)}.$extension"
        FileOutputStream(chemin).use { toile.compress(format, 92, it) }
        toile.recycle()
        ecrireExif(chemin, texte, meta)
        return mapOf("chemin" to chemin, "mime" to mimeSortie)
    }

    @Suppress("DEPRECATION")
    private fun formatWebp(): Bitmap.CompressFormat =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) Bitmap.CompressFormat.WEBP_LOSSY
        else Bitmap.CompressFormat.WEBP

    /** Applique l'orientation EXIF : la copie s'affiche droite partout. */
    private fun redresser(image: Bitmap, chemin: String): Bitmap {
        val exif = try {
            ExifInterface(chemin)
        } catch (e: Exception) {
            return image
        }
        val degres = exif.rotationDegrees
        val miroir = exif.isFlipped
        if (degres == 0 && !miroir) return image
        val m = Matrix()
        if (miroir) m.postScale(-1f, 1f)
        if (degres != 0) m.postRotate(degres.toFloat())
        val tournee = Bitmap.createBitmap(image, 0, 0, image.width, image.height, m, true)
        if (tournee !== image) image.recycle()
        return tournee
    }

    /**
     * Le texte de la signature le long des quatre bords — images, et chaque
     * image d'une vidéo (`SignatureVideo`, sur un calque transparent).
     *
     * 🐛 LES COINS SE CHEVAUCHAIENT (capture du user, 24/10/2026) : sur une image
     * presque carrée, chaque ligne occupait tout son bord et mordait sur la
     * colonne voisine. Chaque ligne laisse maintenant libre, à ses deux bouts,
     * la bande du texte perpendiculaire. Même règle que le web.
     *
     * 🔴 UN CHAMP PAR BORD (25/10/2026, recommandation retenue par le patron) :
     * [texte] porte quatre lignes séparées par « \n » — haut, bas, gauche,
     * droite. Plus courte qu'une chaîne complète, chaque ligne garde sa pleine
     * taille au lieu d'être réduite pour tenir sur le bord. Une seule ligne
     * (ancien appel) est répétée sur les quatre bords.
     */
    internal fun peindreBords(toile: Canvas, l: Float, h: Float, texte: String) {
        val lignes = texte.split('\n')
        val (haut, bas, gauche, droite) = if (lignes.size == 4) lignes else List(4) { texte }
        // 16 px au moins (25/10/2026, demande du patron), davantage sur une
        // grande image : la ligne garde sa taille lisible une fois l'image
        // réduite par WhatsApp.
        val base = max(16f, min(l, h) / 50f)
        // 🔴 BLANC CERNÉ DE NOIR (25/10/2026) : le rouge sur blanc devenait
        // illisible quand WhatsApp recompressait la photo ou la vidéo — la
        // compression bave sur les couleurs, pas sur un fort contraste.
        val remplissage = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(240, 255, 255, 255)
            typeface = Typeface.DEFAULT_BOLD
            textSize = base
        }
        val contour = Paint(remplissage).apply {
            style = Paint.Style.STROKE
            strokeJoin = Paint.Join.ROUND
            color = Color.argb(230, 0, 0, 0)
        }
        val marge = base * 0.6f
        // La bande du texte perpendiculaire : sa marge, plus sa hauteur de ligne.
        val coin = marge + base * 1.3f
        // Réduite seulement si la ligne ne tient pas sur son bord.
        fun taillePour(ligne: String, longueur: Float): Float {
            remplissage.textSize = base
            val unite = remplissage.measureText(ligne) / base
            return if (unite <= 0f) base else min(base, (longueur - 2 * coin) / unite)
        }

        fun bord(ligne: String, cx: Float, cy: Float, angle: Float, taille: Float) {
            if (ligne.isBlank()) return
            remplissage.textSize = taille
            contour.textSize = taille
            contour.strokeWidth = taille * 0.22f
            val largeur = remplissage.measureText(ligne)
            val m = remplissage.fontMetrics
            val y = -(m.ascent + m.descent) / 2
            toile.save()
            toile.translate(cx, cy)
            toile.rotate(angle)
            toile.drawText(ligne, -largeur / 2, y, contour)
            toile.drawText(ligne, -largeur / 2, y, remplissage)
            toile.restore()
        }

        val tHaut = taillePour(haut, l)
        val tBas = taillePour(bas, l)
        val tGauche = taillePour(gauche, h)
        val tDroite = taillePour(droite, h)
        bord(haut, l / 2, marge + tHaut * 0.6f, 0f, tHaut)
        bord(bas, l / 2, h - marge - tBas * 0.6f, 0f, tBas)
        // Gauche : lu de bas en haut. Droite : lu de haut en bas.
        bord(gauche, marge + tGauche * 0.6f, h / 2, -90f, tGauche)
        bord(droite, l - marge - tDroite * 0.6f, h / 2, 90f, tDroite)
    }

    /**
     * Les métadonnées dans l'EXIF (JPEG, PNG et WebP savent les porter). Un
     * échec ici laisse l'image signée aux bords : on ne jette pas la copie.
     */
    private fun ecrireExif(chemin: String, texte: String, meta: Map<String, String>) {
        try {
            val exif = ExifInterface(chemin)
            val application = ascii(meta[CLE_APPLICATION] ?: "Alanya Work")
            exif.setAttribute(ExifInterface.TAG_SOFTWARE, application)
            meta[CLE_ALANYA_ID]?.let { exif.setAttribute(ExifInterface.TAG_ARTIST, ascii("Alanya $it")) }
            // Les quatre lignes des bords, sur une seule ligne de description.
            exif.setAttribute(ExifInterface.TAG_IMAGE_DESCRIPTION, ascii(texte.replace("\n", " · ")))
            exif.setAttribute(ExifInterface.TAG_COPYRIGHT, application)
            exif.setAttribute(
                ExifInterface.TAG_USER_COMMENT,
                ascii(meta.entries.joinToString("; ") { "${it.key}=${it.value}" }),
            )
            meta[CLE_EMPREINTE]?.let { exif.setAttribute(ExifInterface.TAG_IMAGE_UNIQUE_ID, it) }
            // Les pixels ont déjà été redressés.
            exif.setAttribute(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL.toString())
            exif.saveAttributes()
        } catch (e: Exception) {
            Log.w(TAG, "EXIF non écrit : ${e.message}")
        }
    }

    /**
     * Les champs texte de l'EXIF sont de l'ASCII : ExifInterface y remplace
     * « · » ou un accent par « ? ». Le séparateur devient « | », les accents
     * tombent, le reste devient « ? » — même règle que le web.
     */
    private fun ascii(s: String): String =
        Normalizer.normalize(s.replace(" · ", " | "), Normalizer.Form.NFD)
            .replace(Regex("\\p{M}+"), "")
            .replace(Regex("[^\\x20-\\x7E]"), "?")
}
