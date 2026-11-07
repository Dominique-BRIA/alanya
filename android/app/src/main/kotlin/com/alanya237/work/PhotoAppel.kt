package com.alanya237.work

import android.app.Activity
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.util.Log
import android.view.View
import android.widget.ImageView
import java.lang.ref.WeakReference
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/**
 * LA PHOTO DE L'APPELANT SUR L'ÉCRAN D'APPEL NATIF (07/11/2026).
 *
 * 🐛 CE QU'IL CORRIGE. Application tuée, l'écran d'appel n'affichait jamais la
 * photo. Le chargeur d'images du plugin CallKit avait deux défauts :
 *
 *  - il ajoute l'en-tête `Authorization` reçu à CHAQUE requête, y compris
 *    après la redirection de `/api/avatars/<id>` vers le seau Cloudflare des
 *    photos de profil. Et ce jeton est celui que Flutter a laissé au natif :
 *    expiré 15 minutes après la dernière ouverture. Le chargeur garde en plus
 *    pour toute la vie du processus les en-têtes de son PREMIER appel ;
 *  - il ne lit que des adresses `http(s)` : tout le reste devient
 *    `file:///android_asset/flutter_assets/…`. Une photo en base64, écrite
 *    dans un fichier du cache, n'était donc jamais lue.
 *
 * L'application charge donc la photo ELLE-MÊME, sans jeton (les photos de
 * profil sont publiques depuis le 06/08/2026), et la pose sur l'écran d'appel
 * dès qu'il paraît, puis de nouveau un peu plus tard : si le chargeur du plugin
 * échoue de son côté, il remet son image par défaut par-dessus la nôtre.
 */
object PhotoAppel {
    private const val TAG = "AlanyaPhotoAppel"

    /** Côté de la vignette décodée : l'écran l'affiche en 148 dp. */
    private const val COTE_MAX = 512

    private val photos = ConcurrentHashMap<String, Bitmap>()
    private val executeur = Executors.newSingleThreadExecutor()
    private val principal = Handler(Looper.getMainLooper())

    @Volatile private var ecran: WeakReference<Activity>? = null
    @Volatile private var appelAffiche: String = ""

    /**
     * Charge en arrière-plan la photo de [callId]. [source] : adresse
     * `http(s)` absolue, ou photo `data:` en base64.
     */
    fun preparer(context: Context, callId: String, source: String) {
        if (callId.isBlank() || source.isBlank() || photos.containsKey(callId)) return
        executeur.execute {
            val image = try {
                lire(source)
            } catch (e: Exception) {
                Log.w(TAG, "photo illisible pour $callId : $e")
                null
            } ?: return@execute
            photos[callId] = image
            principal.post { appliquerSiAffiche(callId) }
        }
    }

    /** L'écran d'appel de [callId] vient de paraître. */
    fun ecranAffiche(activite: Activity, callId: String) {
        ecran = WeakReference(activite)
        appelAffiche = callId
        appliquer(activite, callId)
        // Le chargeur du plugin peut finir après nous, et poser son image par
        // défaut s'il a échoué : on repasse derrière lui.
        for (delai in longArrayOf(800L, 2_500L)) {
            principal.postDelayed({ appliquerSiAffiche(callId) }, delai)
        }
    }

    fun ecranQuitte(activite: Activity) {
        if (ecran?.get() === activite) {
            ecran = null
            appelAffiche = ""
        }
    }

    /** L'appel ne sonne plus. Vide = tous. */
    fun oublier(callId: String) {
        if (callId.isBlank()) photos.clear() else photos.remove(callId)
    }

    private fun appliquerSiAffiche(callId: String) {
        val activite = ecran?.get() ?: return
        if (appelAffiche != callId || activite.isFinishing) return
        appliquer(activite, callId)
    }

    private fun appliquer(activite: Activity, callId: String) {
        val image = photos[callId] ?: return
        try {
            val vue = activite.findViewById<ImageView>(R.id.ivAvatar) ?: return
            vue.setImageBitmap(image)
            vue.visibility = View.VISIBLE
        } catch (e: Exception) {
            Log.w(TAG, "pose de la photo impossible : $e")
        }
    }

    private fun lire(source: String): Bitmap? {
        val octets = when {
            source.startsWith("data:") ->
                Base64.decode(source.substringAfter(','), Base64.DEFAULT)
            source.startsWith("http://") || source.startsWith("https://") ->
                telecharger(source)
            else -> null
        } ?: return null
        return decoder(octets)
    }

    /**
     * Téléchargement SANS jeton. Les redirections sont suivies à la main :
     * `HttpURLConnection` refuse de passer de `http` à `https`, et la photo
     * peut être servie par un autre hôte (Cloudflare).
     */
    private fun telecharger(adresse: String): ByteArray? {
        var url = URL(adresse)
        repeat(4) {
            val conn = (url.openConnection() as HttpURLConnection).apply {
                instanceFollowRedirects = false
                connectTimeout = 5_000
                readTimeout = 8_000
            }
            try {
                val code = conn.responseCode
                if (code in 300..399) {
                    val suite = conn.getHeaderField("Location") ?: return null
                    url = URL(url, suite)
                    return@repeat
                }
                if (code !in 200..299) {
                    Log.w(TAG, "photo : HTTP $code ($url)")
                    return null
                }
                return conn.inputStream.use { it.readBytes() }
            } finally {
                conn.disconnect()
            }
        }
        return null
    }

    private fun decoder(octets: ByteArray): Bitmap? {
        val bornes = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(octets, 0, octets.size, bornes)
        var echelle = 1
        while (bornes.outWidth / (echelle * 2) >= COTE_MAX && bornes.outHeight / (echelle * 2) >= COTE_MAX) {
            echelle *= 2
        }
        val options = BitmapFactory.Options().apply { inSampleSize = echelle }
        return BitmapFactory.decodeByteArray(octets, 0, octets.size, options)
    }
}
