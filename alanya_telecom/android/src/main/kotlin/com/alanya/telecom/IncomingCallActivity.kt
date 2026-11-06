package com.alanya.telecom

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.app.AlertDialog
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Shader
import android.graphics.SurfaceTexture
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CameraMetadata
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.text.InputType
import android.util.Base64
import android.util.Log
import android.util.Size
import android.util.TypedValue
import android.view.Gravity
import android.view.Surface
import android.view.TextureView
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.view.animation.AccelerateDecelerateInterpolator
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import org.json.JSONObject
import java.lang.ref.WeakReference
import java.net.HttpURLConnection
import java.net.URL

private const val TAG = "AlanyaTelecom"

/**
 * L'ÉCRAN D'APPEL ENTRANT NATIF (06/11/2026), comme WhatsApp.
 *
 * Application fermée ou en arrière-plan, c'est LUI qui s'affiche — par-dessus
 * le verrouillage, lancé par la notification d'appel. Il ne démarre PAS
 * l'application Flutter : le processus est déjà vivant (le push l'a réveillé),
 * et une activité Android ordinaire s'affiche en une fraction de seconde, là
 * où le démarrage complet de l'application prenait une à deux secondes
 * d'écran de lancement. L'application ne démarre qu'au décrochage.
 *
 * Même disposition que l'écran Flutter : flèche « Réduire », photo, nom, puis
 * une grille de deux colonnes — Message / Désactiver la vidéo, Refuser /
 * Accepter. Appel vidéo : la caméra frontale est déjà allumée, on se voit
 * avant de décrocher.
 *
 * 🔴 IDEMPOTENCE. Toute action passe par [CallRegistry] avec l'identifiant
 * d'appel de CET écran : un écran resté ouvert sur un appel déjà terminé, ou
 * remplacé par un autre, ne peut ni décrocher ni refuser le suivant. Un seul
 * geste est pris en compte ([actionFaite]) ; la `Connection` a ses propres
 * gardes. Et l'écran se ferme de lui-même dès que l'appel prend fin, par
 * quelque chemin que ce soit (voir [fermer], appelé par la `Connection`).
 */
class IncomingCallActivity : Activity() {

    companion object {
        const val EXTRA_CALL_ID = "callId"
        private const val COULEUR_FOND = 0xFF5C3D2E.toInt()   // chocolat
        private const val COULEUR_AVATAR = 0xFFB85C38.toInt() // terre cuite
        private const val COULEUR_ACCEPTER = 0xFF2D6A4F.toInt()
        private const val COULEUR_REFUSER = 0xFFE53935.toInt()

        @Volatile private var instance: WeakReference<IncomingCallActivity>? = null
        private val principal = Handler(Looper.getMainLooper())

        fun intent(ctx: Context, callId: String?): Intent =
            Intent(ctx, IncomingCallActivity::class.java)
                .putExtra(EXTRA_CALL_ID, callId ?: "")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

        /** Ferme l'écran s'il est ouvert — appelé à TOUTE fin de sonnerie. */
        fun fermer() {
            principal.post { instance?.get()?.terminer() }
        }
    }

    private var callId: String = ""
    private var donnees: Map<String, String> = emptyMap()
    private var actionFaite = false
    private var video = false
    private var cameraActive = true
    private var libelles = JSONObject()

    private var apercu: Apercu? = null
    private var vueCamera: TextureView? = null
    private var voile: View? = null
    private var boutonCamera: Pair<FrameLayout, TextView>? = null
    private var iconeCamera: ImageView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        afficherParDessusVerrouillage()
        instance = WeakReference(this)
        if (!lier(intent)) return
        construire()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // Un autre appel a remplacé le précédent : on reconstruit pour lui.
        apercu?.arreter()
        apercu = null
        actionFaite = false
        if (!lier(intent)) return
        construire()
    }

    /**
     * Rattache l'écran à l'appel qui sonne. Rien ne sonne, ou un autre appel
     * sonne que celui demandé : intention périmée (notification touchée après
     * la fin de l'appel), l'écran se referme aussitôt.
     */
    private fun lier(intent: Intent?): Boolean {
        val demande = intent?.getStringExtra(EXTRA_CALL_ID).orEmpty()
        val sonne = CallRegistry.ringingData()
        val idSonne = sonne?.let { CallRegistry.keyOf(it) }.orEmpty()
        if (sonne == null || (demande.isNotEmpty() && demande != idSonne)) {
            Log.d(TAG, "écran natif : aucun appel en sonnerie pour '$demande' → fermeture")
            finish()
            return false
        }
        callId = idSonne
        donnees = HashMap(sonne)
        video = donnees["callType"] == "video"
        cameraActive = true
        libelles = lireLibelles()
        return true
    }

    // ── Construction de l'écran ───────────────────────────────────────────

    private fun dp(v: Float): Int =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, resources.displayMetrics).toInt()

    private fun libelle(cle: String, repli: String): String =
        libelles.optString(cle, "").ifEmpty { repli }

    private fun construire() {
        val racine = FrameLayout(this).apply { setBackgroundColor(COULEUR_FOND) }

        if (video && permissionCamera()) {
            val vue = TextureView(this)
            racine.addView(vue, FrameLayout.LayoutParams(-1, -1))
            vueCamera = vue
            // Dégradés haut et bas : le texte et les boutons restent lisibles
            // sur l'image, comme dans l'écran Flutter.
            val v = View(this).apply {
                background = GradientDrawable(
                    GradientDrawable.Orientation.TOP_BOTTOM,
                    intArrayOf(0x99000000.toInt(), 0x00000000, 0x00000000, 0xB3000000.toInt())
                )
            }
            racine.addView(v, FrameLayout.LayoutParams(-1, -1))
            voile = v
        }

        val colonne = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            fitsSystemWindows = true
        }
        racine.addView(colonne, FrameLayout.LayoutParams(-1, -1))

        // Flèche « Réduire » : ferme l'écran, l'appel continue de sonner dans
        // la notification. Jamais un refus — c'est le rôle du bouton rouge.
        val reduire = ImageView(this).apply {
            setImageResource(R.drawable.alanya_tel_reduire)
            alpha = 0.8f
            setPadding(dp(12f), dp(12f), dp(12f), dp(12f))
            contentDescription = libelle("call_minimize", "Réduire")
            setOnClickListener { reduire() }
        }
        colonne.addView(reduire, LinearLayout.LayoutParams(dp(56f), dp(56f)))

        colonne.addView(View(this), LinearLayout.LayoutParams(-1, 0, 0.5f))
        colonne.addView(identite(), LinearLayout.LayoutParams(-1, -2))
        colonne.addView(View(this), LinearLayout.LayoutParams(-1, 0, 1f))

        // Grille : deux colonnes de même largeur, les deux rangées partagent
        // les mêmes axes (même règle que l'écran Flutter).
        val message = boutonSecondaire(
            R.drawable.alanya_tel_message, libelle("call_message", "Message")
        ) { repondreParMessage() }
        if (video) {
            val (cadre, texte) = boutonSecondaire(
                R.drawable.alanya_tel_video_coupee,
                libelle("call_video_off", "Désactiver la vidéo")
            ) { basculerCamera() }
            boutonCamera = cadre to texte
            colonne.addView(rangee(message.first, cadre))
        } else {
            colonne.addView(rangee(message.first))
        }
        colonne.addView(View(this), LinearLayout.LayoutParams(-1, dp(28f)))
        colonne.addView(
            rangee(
                boutonPrincipal(
                    R.drawable.alanya_tel_raccrocher, COULEUR_REFUSER,
                    libelle("decline", "Refuser")
                ) { refuser() },
                boutonPrincipal(
                    if (video) R.drawable.alanya_tel_video else R.drawable.alanya_tel_decrocher,
                    COULEUR_ACCEPTER, libelle("accept", "Accepter")
                ) { accepter() },
            )
        )
        colonne.addView(View(this), LinearLayout.LayoutParams(-1, dp(40f)))

        setContentView(racine)
        vueCamera?.let { vue -> apercu = Apercu(vue).also { it.demarrer() } }
    }

    private fun identite(): View {
        val bloc = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
        }
        val nom = donnees["callerName"].orEmpty().ifEmpty { "Alanya" }

        // Photo entourée d'une onde qui respire, comme l'écran Flutter.
        val cadre = FrameLayout(this)
        val onde = View(this).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setStroke(dp(2f), 0x55FFFFFF)
            }
        }
        cadre.addView(onde, FrameLayout.LayoutParams(dp(150f), dp(150f), Gravity.CENTER))
        onde.animate().scaleX(1.12f).scaleY(1.12f).alpha(0.3f).setDuration(1100)
            .setInterpolator(AccelerateDecelerateInterpolator())
            .withEndAction(object : Runnable {
                override fun run() {
                    if (isFinishing) return
                    onde.scaleX = 1f; onde.scaleY = 1f; onde.alpha = 1f
                    onde.animate().scaleX(1.12f).scaleY(1.12f).alpha(0.3f)
                        .setDuration(1100).withEndAction(this).start()
                }
            }).start()

        val initiale = TextView(this).apply {
            text = nom.trim().firstOrNull()?.uppercase() ?: "?"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 46f)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(COULEUR_AVATAR)
            }
        }
        cadre.addView(initiale, FrameLayout.LayoutParams(dp(112f), dp(112f), Gravity.CENTER))
        val photo = ImageView(this)
        cadre.addView(photo, FrameLayout.LayoutParams(dp(112f), dp(112f), Gravity.CENTER))
        chargerPhoto(photo, dp(112f))
        bloc.addView(cadre, LinearLayout.LayoutParams(dp(160f), dp(160f)))

        bloc.addView(TextView(this).apply {
            text = nom
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 26f)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            maxLines = 2
            setPadding(dp(24f), dp(16f), dp(24f), 0)
        })
        val sousTitre = donnees["transferBy"]?.takeIf { it.isNotEmpty() }
            ?.let { "$it · transfert d'appel" }
            ?: if (video) libelle("incoming_video_call", "Appel vidéo entrant…")
            else libelle("incoming_call", "Appel entrant…")
        bloc.addView(TextView(this).apply {
            text = sousTitre
            setTextColor(0xB3FFFFFF.toInt())
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            gravity = Gravity.CENTER
            setPadding(dp(24f), dp(8f), dp(24f), 0)
        })
        return bloc
    }

    private fun rangee(vararg boutons: View): LinearLayout =
        LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(dp(24f), 0, dp(24f), 0)
            for (b in boutons) {
                val cellule = FrameLayout(this@IncomingCallActivity)
                cellule.addView(b, FrameLayout.LayoutParams(-2, -2, Gravity.CENTER_HORIZONTAL or Gravity.TOP))
                addView(cellule, LinearLayout.LayoutParams(0, -2, 1f))
            }
        }

    private fun bouton(
        icone: Int, fond: Int, taille: Float, texte: String, action: () -> Unit,
    ): Pair<FrameLayout, TextView> {
        val bloc = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
        }
        val cercle = FrameLayout(this).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(fond)
            }
            isClickable = true
            setOnClickListener { action() }
            contentDescription = texte
        }
        val image = ImageView(this).apply { setImageResource(icone) }
        val cote = (taille * 0.46f)
        cercle.addView(image, FrameLayout.LayoutParams(dp(cote), dp(cote), Gravity.CENTER))
        bloc.addView(cercle, LinearLayout.LayoutParams(dp(taille), dp(taille)))
        val etiquette = TextView(this).apply {
            text = texte
            setTextColor(0xB3FFFFFF.toInt())
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            gravity = Gravity.CENTER
            maxLines = 2
            maxWidth = dp(140f)
            setPadding(0, dp(8f), 0, 0)
        }
        bloc.addView(etiquette, LinearLayout.LayoutParams(-2, -2))
        // Le cadre RENDU est le bloc entier ; l'icône est retenue pour la
        // bascule de la caméra.
        if (icone == R.drawable.alanya_tel_video_coupee) iconeCamera = image
        val enveloppe = FrameLayout(this)
        enveloppe.addView(bloc)
        return enveloppe to etiquette
    }

    private fun boutonPrincipal(icone: Int, fond: Int, texte: String, action: () -> Unit): View =
        bouton(icone, fond, 72f, texte, action).first

    private fun boutonSecondaire(icone: Int, texte: String, action: () -> Unit) =
        bouton(icone, 0x3DFFFFFF, 60f, texte, action)

    // ── Gestes ─────────────────────────────────────────────────────────────

    private fun accepter() {
        if (actionFaite) return
        actionFaite = true
        // La caméra est rendue AVANT le décrochage : l'application, qui va
        // démarrer, doit pouvoir l'ouvrir à son tour.
        apercu?.arreter()
        apercu = null
        val supplement = if (video && !cameraActive) mapOf("cameraCoupee" to "true") else emptyMap()
        if (!CallRegistry.answer(callId, supplement)) finish()
    }

    private fun refuser() {
        if (actionFaite) return
        actionFaite = true
        apercu?.arreter()
        apercu = null
        CallRegistry.reject(callId)
        finish()
    }

    private fun reduire() {
        apercu?.arreter()
        apercu = null
        finish()
    }

    @Deprecated("Remplacé par OnBackPressedDispatcher, absent d'une Activity nue")
    override fun onBackPressed() {
        // Le retour RÉDUIT, comme dans l'écran Flutter : il ne refuse jamais.
        reduire()
    }

    private fun basculerCamera() {
        cameraActive = !cameraActive
        iconeCamera?.setImageResource(
            if (cameraActive) R.drawable.alanya_tel_video_coupee else R.drawable.alanya_tel_video
        )
        boutonCamera?.second?.text = if (cameraActive)
            libelle("call_video_off", "Désactiver la vidéo")
        else libelle("call_video_on", "Activer la vidéo")
        vueCamera?.visibility = if (cameraActive) View.VISIBLE else View.INVISIBLE
        voile?.visibility = vueCamera?.visibility ?: View.GONE
        if (cameraActive) {
            vueCamera?.let { vue -> apercu = Apercu(vue).also { it.demarrer() } }
        } else {
            apercu?.arreter()
            apercu = null
        }
    }

    /**
     * Répondre par un message : on choisit le texte ICI, puis l'appel est
     * refusé et l'application, ouverte après déverrouillage, l'envoie — elle
     * seule sait chiffrer la conversation. S'il n'est pas déverrouillé, le
     * message part à la prochaine ouverture (voir [ReponseAppel]).
     */
    private fun repondreParMessage() {
        if (actionFaite) return
        val choix = arrayOf(
            libelle("call_quick_busy", "Je ne peux pas répondre pour le moment."),
            libelle("call_quick_later", "Je te rappelle plus tard."),
            libelle("call_quick_on_way", "Je suis en route."),
            libelle("call_quick_custom", "Écrire un message…"),
        )
        AlertDialog.Builder(this)
            .setItems(choix) { _, i ->
                if (i < 3) envoyerMessage(choix[i]) else saisirMessage()
            }
            .show()
    }

    private fun saisirMessage() {
        val champ = EditText(this).apply {
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE or
                InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
            hint = libelle("call_quick_custom", "Écrire un message…")
        }
        val cadre = FrameLayout(this).apply {
            setPadding(dp(20f), dp(12f), dp(20f), 0)
            addView(champ)
        }
        AlertDialog.Builder(this)
            .setView(cadre)
            .setPositiveButton(libelle("send", "Envoyer")) { _, _ ->
                val texte = champ.text.toString().trim()
                if (texte.isNotEmpty()) envoyerMessage(texte)
            }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    }

    private fun envoyerMessage(texte: String) {
        if (actionFaite) return
        val auteur = donnees["callerId"].orEmpty()
        if (auteur.isNotEmpty()) ReponseAppel.garder(this, callId, auteur, texte)
        refuserPuisOuvrir()
    }

    private fun refuserPuisOuvrir() {
        actionFaite = true
        apercu?.arreter()
        apercu = null
        CallRegistry.reject(callId)
        val ouvrir = {
            try {
                packageManager.getLaunchIntentForPackage(packageName)
                    ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    ?.let { startActivity(it) }
            } catch (e: Exception) {
                Log.w(TAG, "ouverture de l'application : $e")
            }
            finish()
        }
        val km = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && km.isKeyguardLocked) {
            km.requestDismissKeyguard(this, object : KeyguardManager.KeyguardDismissCallback() {
                override fun onDismissSucceeded() { ouvrir() }
                override fun onDismissCancelled() { finish() }
                override fun onDismissError() { finish() }
            })
        } else {
            ouvrir()
        }
    }

    // ── Fenêtre, fin, ressources ──────────────────────────────────────────

    private fun afficherParDessusVerrouillage() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        window.statusBarColor = COULEUR_FOND
        window.navigationBarColor = COULEUR_FOND
    }

    private fun terminer() {
        apercu?.arreter()
        apercu = null
        if (!isFinishing) finish()
    }

    override fun onStop() {
        super.onStop()
        // Écran quitté (réduit, autre application) : la caméra se rend. Elle
        // se rouvrira si l'on revient (onStart).
        apercu?.arreter()
        apercu = null
    }

    override fun onStart() {
        super.onStart()
        if (apercu == null && cameraActive && !actionFaite) {
            vueCamera?.let { vue -> apercu = Apercu(vue).also { it.demarrer() } }
        }
    }

    override fun onDestroy() {
        apercu?.arreter()
        apercu = null
        if (instance?.get() === this) instance = null
        super.onDestroy()
    }

    private fun permissionCamera(): Boolean =
        checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED

    /** Libellés traduits, écrits par l'application dans la langue choisie. */
    private fun lireLibelles(): JSONObject = try {
        JSONObject(
            getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .getString("flutter.libelles_appel_natif", null) ?: "{}"
        )
    } catch (_: Exception) {
        JSONObject()
    }

    /**
     * Photo de l'appelant, en tâche de fond. Trois formes coexistent (voir
     * `AvatarSource` côté Dart) : image en base64, URL complète, ou chemin du
     * serveur déjà complété par l'application, avec le jeton de session.
     * Tout échec garde l'initiale.
     */
    private fun chargerPhoto(vue: ImageView, cote: Int) {
        val source = donnees["avatarComplet"].orEmpty().ifEmpty { donnees["callerAvatar"].orEmpty() }
        if (source.isEmpty()) return
        val jeton = donnees["jeton"].orEmpty()
        Thread {
            try {
                val octets: ByteArray? = when {
                    source.startsWith("data:") ->
                        Base64.decode(source.substringAfter(','), Base64.DEFAULT)
                    source.startsWith("https://") || source.startsWith("http://") -> {
                        val c = URL(source).openConnection() as HttpURLConnection
                        c.connectTimeout = 6000
                        c.readTimeout = 8000
                        if (jeton.isNotEmpty()) c.setRequestProperty("Authorization", "Bearer $jeton")
                        try {
                            if (c.responseCode == 200) c.inputStream.use { it.readBytes() } else null
                        } finally {
                            c.disconnect()
                        }
                    }
                    else -> null
                }
                val image = octets?.let { BitmapFactory.decodeByteArray(it, 0, it.size) } ?: return@Thread
                val rond = rogner(image, cote)
                runOnUiThread { if (!isFinishing) vue.setImageBitmap(rond) }
            } catch (e: Exception) {
                Log.w(TAG, "photo de l'appelant : $e")
            }
        }.start()
    }

    private fun rogner(source: Bitmap, cote: Int): Bitmap {
        val sortie = Bitmap.createBitmap(cote, cote, Bitmap.Config.ARGB_8888)
        val echelle = cote.toFloat() / minOf(source.width, source.height)
        val matrice = Matrix().apply {
            setScale(echelle, echelle)
            postTranslate(
                (cote - source.width * echelle) / 2f,
                (cote - source.height * echelle) / 2f,
            )
        }
        val pinceau = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            shader = BitmapShader(source, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
                .also { it.setLocalMatrix(matrice) }
        }
        Canvas(sortie).drawCircle(cote / 2f, cote / 2f, cote / 2f, pinceau)
        return sortie
    }

    // ── Aperçu de la caméra frontale ──────────────────────────────────────

    /**
     * La caméra frontale dans un `TextureView`, en plein écran et rognée au
     * centre. Camera2 nu : aucune dépendance à ajouter au module.
     *
     * Le miroir d'une caméra frontale est appliqué par le système sur les
     * flux d'aperçu ; l'écran est figé en portrait (manifeste), donc seule
     * reste la mise à l'échelle.
     */
    private inner class Apercu(private val vue: TextureView) : TextureView.SurfaceTextureListener {
        private val fil = HandlerThread("alanya-apercu").also { it.start() }
        private val gestionnaire = Handler(fil.looper)
        @Volatile private var arrete = false
        // Ouverture demandée, réponse du système pas encore reçue : le fil ne
        // doit pas s'arrêter avant, sinon la caméra ouverte entre-temps ne
        // serait jamais rendue — et l'application ne pourrait plus l'ouvrir.
        @Volatile private var enOuverture = false
        private var camera: CameraDevice? = null
        private var session: CameraCaptureSession? = null

        private fun liberer() {
            try { session?.close() } catch (_: Exception) {}
            session = null
            try { camera?.close() } catch (_: Exception) {}
            camera = null
            if (!enOuverture) fil.quitSafely()
        }

        fun demarrer() {
            if (vue.isAvailable) ouvrir() else vue.surfaceTextureListener = this
        }

        override fun onSurfaceTextureAvailable(st: SurfaceTexture, w: Int, h: Int) = ouvrir()
        override fun onSurfaceTextureSizeChanged(st: SurfaceTexture, w: Int, h: Int) {}
        override fun onSurfaceTextureDestroyed(st: SurfaceTexture): Boolean = true
        override fun onSurfaceTextureUpdated(st: SurfaceTexture) {}

        @SuppressLint("MissingPermission")
        private fun ouvrir() {
            if (arrete || !permissionCamera()) return
            try {
                val cm = getSystemService(Context.CAMERA_SERVICE) as CameraManager
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
                        if (arrete) { liberer(); return }
                        demarrerSession(d, taille)
                    }
                    override fun onDisconnected(d: CameraDevice) {
                        enOuverture = false
                        d.close(); camera = null
                        if (arrete) liberer()
                    }
                    override fun onError(d: CameraDevice, e: Int) {
                        enOuverture = false
                        d.close(); camera = null
                        if (arrete) liberer()
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
                runOnUiThread { rognerAuCentre(taille) }
                @Suppress("DEPRECATION")
                d.createCaptureSession(listOf(surface), object : CameraCaptureSession.StateCallback() {
                    override fun onConfigured(s: CameraCaptureSession) {
                        if (arrete) { s.close(); return }
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

        fun arreter() {
            if (arrete) return
            arrete = true
            gestionnaire.post { liberer() }
        }
    }
}

/**
 * Le message choisi sur l'écran natif, en attendant que l'application
 * l'envoie (elle seule sait chiffrer la conversation). Un seul à la fois ;
 * périmé au bout de dix minutes, pour qu'une réponse rapide ne parte pas
 * des heures plus tard, hors de propos.
 */
object ReponseAppel {
    private const val PREFS = "alanya_telecom"
    private const val CLE = "reponse_appel"

    fun garder(ctx: Context, callId: String, auteurId: String, texte: String) {
        val json = JSONObject()
            .put("callId", callId)
            .put("callerId", auteurId)
            .put("texte", texte)
            .put("at", System.currentTimeMillis())
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(CLE, json.toString()).apply()
    }

    /** Rend le message en attente et l'efface — une seule fois. */
    fun prendre(ctx: Context): Map<String, String>? {
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val brut = prefs.getString(CLE, null) ?: return null
        prefs.edit().remove(CLE).apply()
        return try {
            val j = JSONObject(brut)
            if (System.currentTimeMillis() - j.optLong("at") > 10 * 60_000) return null
            mapOf(
                "callId" to j.optString("callId"),
                "callerId" to j.optString("callerId"),
                "texte" to j.optString("texte"),
            )
        } catch (_: Exception) {
            null
        }
    }
}
