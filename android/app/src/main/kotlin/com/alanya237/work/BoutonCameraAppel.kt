package com.alanya237.work

import android.app.Activity
import android.content.Context
import android.util.AttributeSet
import android.util.TypedValue
import android.view.Gravity
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import com.hiennv.flutter_callkit_incoming.CallkitConstants

/**
 * « DÉSACTIVER LA VIDÉO » SUR L'ÉCRAN D'APPEL NATIF (20/11/2026), comme sur
 * l'écran de sonnerie Flutter et sur le web : on coupe sa caméra AVANT de
 * décrocher — application fermée, en arrière-plan ou téléphone verrouillé.
 *
 * Vue posée dans notre maquette de l'écran natif (`callkit_incoming_content.xml`),
 * comme [ApercuCameraAppel] : l'activité du plugin ne se modifie pas, mais elle
 * gonfle notre maquette. Visible pour un appel VIDÉO seulement.
 *
 * Un appui bascule l'état : l'aperçu de la caméra s'éteint (ou se rallume), et
 * le choix est noté pour cet appel ([ChoixCameraAppel]). Flutter le relit au
 * décrochage : l'appel commence alors caméra coupée.
 */
class BoutonCameraAppel @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : LinearLayout(context, attrs) {

    private val pastille = ImageView(context)
    private val libelle = TextView(context)
    private var coupee = false

    init {
        orientation = VERTICAL
        gravity = Gravity.CENTER_HORIZONTAL
        isClickable = true
        isFocusable = true
        val taille = dp(56)
        pastille.layoutParams = LayoutParams(taille, taille)
        pastille.setPadding(dp(14), dp(14), dp(14), dp(14))
        addView(pastille)
        libelle.layoutParams = LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
            topMargin = dp(8)
        }
        libelle.setTextColor(0xFFFFFFFF.toInt())
        libelle.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
        addView(libelle)
        visibility = GONE
        setOnClickListener { basculer() }
    }

    private fun dp(v: Int): Int =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), resources.displayMetrics).toInt()

    private fun donnees() = try {
        (context as? Activity)?.intent?.getBundleExtra(CallkitConstants.EXTRA_CALLKIT_INCOMING_DATA)
    } catch (_: Exception) {
        null
    }

    private fun callId(): String = donnees()?.getString(CallkitConstants.EXTRA_CALLKIT_ID, "") ?: ""

    private fun estAppelVideo(): Boolean =
        (donnees()?.getInt(CallkitConstants.EXTRA_CALLKIT_TYPE, 0) ?: 0) > 0

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        if (!estAppelVideo()) return
        coupee = ChoixCameraAppel.estCoupee(context, callId())
        visibility = VISIBLE
        dessiner()
    }

    private fun basculer() {
        coupee = !coupee
        ChoixCameraAppel.definirCoupee(context, callId(), coupee)
        rootView.findViewById<ApercuCameraAppel>(R.id.apercuCameraAppel)?.appliquerCoupure(coupee)
        dessiner()
    }

    private fun dessiner() {
        // Coupée : pastille blanche et icône barrée, comme le bouton « actif »
        // de l'écran Flutter ; sinon pastille translucide.
        pastille.setBackgroundResource(
            if (coupee) R.drawable.callkit_camera_pastille_active else R.drawable.callkit_camera_pastille
        )
        pastille.setImageResource(
            if (coupee) R.drawable.callkit_ic_videocam_off else R.drawable.callkit_ic_videocam
        )
        pastille.setColorFilter(if (coupee) 0xFF2B1B12.toInt() else 0xFFFFFFFF.toInt())
        val texte = context.getString(
            if (coupee) R.string.callkit_camera_on else R.string.callkit_camera_off
        )
        libelle.text = texte
        contentDescription = texte
    }
}
