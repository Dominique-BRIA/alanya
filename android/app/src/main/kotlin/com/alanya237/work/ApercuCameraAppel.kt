package com.alanya237.work

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Matrix
import android.graphics.SurfaceTexture
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CameraMetadata
import android.os.Handler
import android.os.HandlerThread
import android.util.AttributeSet
import android.util.Log
import android.util.Size
import android.view.Surface
import android.view.TextureView
import android.view.View
import android.widget.FrameLayout
import com.hiennv.flutter_callkit_incoming.CallkitConstants

/**
 * L'APERÇU DE LA CAMÉRA sur l'écran d'appel natif, pour un appel vidéo
 * (07/11/2026) — on se voit avant de décrocher, comme sur WhatsApp et comme
 * sur l'écran de sonnerie Flutter.
 *
 * L'écran d'appel natif est l'activité de flutter_callkit_incoming : on ne
 * peut pas la modifier. Elle construit en revanche son écran à partir de NOTRE
 * maquette (`callkit_incoming_content.xml`), et une maquette peut contenir une
 * vue à nous. Celle-ci se met donc en route toute seule à l'affichage :
 * - appel vidéo (type CallKit > 0, lu dans l'intent de l'activité) ;
 * - caméra déjà autorisée — jamais de demande d'autorisation ici, une boîte
 *   système par-dessus la sonnerie gênerait le décrochage.
 * Sinon elle reste invisible et l'écran garde son dégradé.
 *
 * ⚠️ LA CAMÉRA EST RENDUE DÈS QUE L'ÉCRAN SE FERME (décroché, refusé,
 * annulé) : l'application va l'ouvrir pour l'appel, et une caméra encore tenue
 * ici la lui refuserait.
 *
 * Camera2 nu, sans dépendance. Le miroir de la caméra frontale est appliqué
 * par le système sur les flux d'aperçu ; l'écran d'appel est en portrait sur
 * téléphone, il ne reste donc que le rognage au centre.
 */
class ApercuCameraAppel @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : FrameLayout(context, attrs), TextureView.SurfaceTextureListener {

    private val vue = TextureView(context)

    /** L'aperçu en cours, ou null. Chaque démarrage a le SIEN — voir [Execution]. */
    private var courante: Execution? = null

    init {
        addView(vue, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        // Voile sombre : le nom et les boutons restent lisibles sur l'image.
        addView(View(context).apply { setBackgroundColor(0x59000000) },
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        visibility = GONE
    }

    private fun estAppelVideo(): Boolean = try {
        val data = (context as? Activity)?.intent
            ?.getBundleExtra(CallkitConstants.EXTRA_CALLKIT_INCOMING_DATA)
        (data?.getInt(CallkitConstants.EXTRA_CALLKIT_TYPE, 0) ?: 0) > 0
    } catch (_: Exception) {
        false
    }

    private fun cameraAutorisee(): Boolean =
        context.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        if (!estAppelVideo() || !cameraAutorisee()) return
        visibility = VISIBLE
        demarrer()
    }

    override fun onDetachedFromWindow() {
        arreter()
        super.onDetachedFromWindow()
    }

    override fun onWindowVisibilityChanged(visibility: Int) {
        super.onWindowVisibilityChanged(visibility)
        // Écran quitté sans être fermé : la caméra se rend, et revient au retour.
        if (visibility != VISIBLE) arreter()
        else if (this.visibility == VISIBLE) demarrer()
    }

    private fun demarrer() {
        if (courante != null) return
        courante = Execution().also {
            if (vue.isAvailable) it.ouvrir() else vue.surfaceTextureListener = this
        }
    }

    private fun arreter() {
        courante?.arreter()
        courante = null
    }

    override fun onSurfaceTextureAvailable(st: SurfaceTexture, w: Int, h: Int) {
        courante?.ouvrir()
    }
    override fun onSurfaceTextureSizeChanged(st: SurfaceTexture, w: Int, h: Int) {}
    override fun onSurfaceTextureDestroyed(st: SurfaceTexture): Boolean = true
    override fun onSurfaceTextureUpdated(st: SurfaceTexture) {}

    /** Rogne au centre : en portrait, l'image du capteur est couchée. */
    private fun rognerAuCentre(taille: Size) {
        val l = vue.width.toFloat()
        val h = vue.height.toFloat()
        if (l == 0f || h == 0f) return
        val largeurImage = taille.height.toFloat()
        val hauteurImage = taille.width.toFloat()
        val echelle = maxOf(l / largeurImage, h / hauteurImage)
        vue.setTransform(Matrix().apply {
            setScale(largeurImage * echelle / l, hauteurImage * echelle / h, l / 2f, h / 2f)
        })
    }

    /**
     * UN aperçu : son fil, sa caméra, sa session. Un aperçu arrêté puis relancé
     * aussitôt (écran masqué puis rendu) en crée un autre : les rappels tardifs
     * de l'ancien ne touchent que l'ancien, jamais la caméra du nouveau.
     *
     * ⚠️ Le fil ne s'arrête pas pendant une ouverture : la réponse du système
     * serait perdue, et la caméra ouverte entre-temps jamais rendue.
     */
    private inner class Execution {
        private val fil = HandlerThread("alanya-apercu-appel").also { it.start() }
        private val gestionnaire = Handler(fil.looper)
        @Volatile private var arretee = false
        @Volatile private var enOuverture = false
        private var camera: CameraDevice? = null
        private var session: CameraCaptureSession? = null

        @SuppressLint("MissingPermission")
        fun ouvrir() {
            if (arretee || !cameraAutorisee()) return
            try {
                val cm = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
                val id = cm.cameraIdList.firstOrNull {
                    cm.getCameraCharacteristics(it).get(CameraCharacteristics.LENS_FACING) ==
                        CameraMetadata.LENS_FACING_FRONT
                } ?: cm.cameraIdList.firstOrNull() ?: return
                val carte = cm.getCameraCharacteristics(id)
                    .get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP) ?: return
                val tailles = carte.getOutputSizes(SurfaceTexture::class.java) ?: return
                val taille = tailles.filter { it.width <= 1280 && it.height <= 1280 }
                    .maxByOrNull { it.width * it.height } ?: tailles.first()
                enOuverture = true
                cm.openCamera(id, object : CameraDevice.StateCallback() {
                    override fun onOpened(d: CameraDevice) {
                        enOuverture = false
                        camera = d
                        if (arretee) liberer() else demarrerSession(d, taille)
                    }
                    override fun onDisconnected(d: CameraDevice) {
                        enOuverture = false
                        d.close(); camera = null
                        if (arretee) liberer()
                    }
                    override fun onError(d: CameraDevice, e: Int) {
                        enOuverture = false
                        d.close(); camera = null
                        if (arretee) liberer()
                    }
                }, gestionnaire)
            } catch (e: Exception) {
                enOuverture = false
                Log.w(TAG, "aperçu caméra : $e")
            }
        }

        private fun demarrerSession(d: CameraDevice, taille: Size) {
            try {
                val st = vue.surfaceTexture ?: return
                st.setDefaultBufferSize(taille.width, taille.height)
                val surface = Surface(st)
                post { rognerAuCentre(taille) }
                @Suppress("DEPRECATION")
                d.createCaptureSession(listOf(surface), object : CameraCaptureSession.StateCallback() {
                    override fun onConfigured(s: CameraCaptureSession) {
                        if (arretee) { s.close(); return }
                        session = s
                        try {
                            val requete = d.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
                                .apply { addTarget(surface) }
                            s.setRepeatingRequest(requete.build(), null, gestionnaire)
                        } catch (e: Exception) {
                            Log.w(TAG, "aperçu caméra (requête) : $e")
                        }
                    }
                    override fun onConfigureFailed(s: CameraCaptureSession) {
                        Log.w(TAG, "aperçu caméra : session refusée")
                    }
                }, gestionnaire)
            } catch (e: Exception) {
                Log.w(TAG, "aperçu caméra (session) : $e")
            }
        }

        fun arreter() {
            if (arretee) return
            arretee = true
            gestionnaire.post { liberer() }
        }

        /** Sur le fil de la caméra. */
        private fun liberer() {
            try { session?.close() } catch (_: Exception) {}
            session = null
            try { camera?.close() } catch (_: Exception) {}
            camera = null
            if (!enOuverture) fil.quitSafely()
        }
    }

    companion object {
        private const val TAG = "ApercuCameraAppel"
    }
}
