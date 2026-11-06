package com.alanya237.work

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.util.Log
import com.hiennv.flutter_callkit_incoming.CallkitConstants
import com.hiennv.flutter_callkit_incoming.Data
import com.hiennv.flutter_callkit_incoming.addCall
import com.hiennv.flutter_callkit_incoming.getDataActiveCalls

/**
 * Lit le décrochage dans l'intent qui lance l'activité — le seul canal sans
 * course.
 *
 * Le bouton « Décrocher » de la notification pointe vers `TransparentActivity`
 * du plugin, dont `onCreate` fait, dans cet ordre :
 *
 *     sendBroadcast(broadcastIntent)   // asynchrone
 *     startActivity(activityIntent)    // lance MainActivity tout de suite
 *
 * Ces deux lignes partent en course. Le receiver, lui, n'écrit `isAccepted=true`
 * qu'à son avant-dernière instruction, et ses deux tentatives d'atteindre
 * Flutter ne peuvent pas aboutir à froid : l'une exige un moteur vivant, l'autre
 * poste avec 750 ms de retard vers des canaux déjà existants.
 *
 * Pendant ce temps l'application démarre et lit un état CallKit encore non
 * accepté : elle présente un entrant et sonne. Application tuée, le boot prend
 * une à deux secondes et le receiver gagne presque toujours ; application en
 * arrière-plan, le moteur est déjà vivant et c'est Flutter qui gagne.
 *
 * Or `AppUtils.getAppIntent` pose l'action et les données de l'appel sur
 * l'intent de lancement, porté par le **même** `startActivity`. Aucune course
 * possible. Personne ne le lisait.
 *
 * ## Ce que fait cette classe, et surtout ce qu'elle ne fait pas
 *
 * Elle écrit `isAccepted=true`, et rien d'autre. Le nettoyage complet existe
 * déjà et n'a qu'une autorité : l'écouteur `ACTIVE_CALLS` de [TalkyApplication]
 * appelle `CallIncomingHelper.clearIncomingNotification`, qui coupe la sonnerie
 * du plugin, diffuse l'ordre qui **ferme son écran plein écran**, et annule la
 * notification. Couper les sonneries ici créerait une seconde autorité à côté
 * de celle-là.
 */
object CallAcceptFromIntent {

    private const val TAG = "CallAcceptIntent"

    /** Posée par `AppUtils.getAppIntent`, lue par personne jusqu'ici. */
    private const val EXTRA_DATA = "EXTRA_CALLKIT_CALL_DATA"

    /**
     * Au-delà, l'intent est un rejeu et non un décrochage.
     *
     * La notification expire à 40 s et le serveur classe « sans réponse » à
     * 45 s : deux minutes laissent une marge large tout en fermant la porte à
     * un intent ressorti bien plus tard.
     */
    private const val FRAICHEUR_MS = 120_000L

    /**
     * Enregistre l'acceptation portée par [intent], et rend l'identifiant
     * métier de l'appel — ou `null` si cet intent n'en portait pas.
     *
     * Trois conditions, écrites avant tout le reste parce que c'est là qu'est
     * le risque :
     *
     * 1. **Action exacte.** `getAppPendingIntent` pose le même extra *sans*
     *    action, et `getCallbackPendingIntent` passe `ACTION_CALL_CALLBACK` par
     *    la même activité de transit. Un filtre approximatif prendrait un
     *    rappel manqué pour un décrochage.
     * 2. **Entrée déjà connue.** `addCall` sur un identifiant absent
     *    d'`ACTIVE_CALLS` l'**ajoute** avec `isAccepted=true` — un appel accepté
     *    fantôme, que le démarrage à froid suivant décrocherait tout seul
     *    pendant les trois minutes de sa fenêtre de fraîcheur.
     * 3. **Consommation.** Une rotation ou une recréation d'activité rejoue
     *    l'intent courant. `handleNotificationIntent` se protège déjà ainsi.
     */
    fun consommer(activity: Activity, intent: Intent?): String? {
        if (intent == null) return null
        if (intent.action != CallkitConstants.ACTION_CALL_ACCEPT) return null

        val bundle = intent.getBundleExtra(EXTRA_DATA)
        if (bundle == null) {
            Log.w(TAG, "action de décrochage sans données — ignorée")
            neutraliser(activity, intent, EXTRA_DATA)
            return null
        }

        val data = try {
            Data.fromBundle(bundle)
        } catch (e: Exception) {
            Log.e(TAG, "données de décrochage illisibles", e)
            neutraliser(activity, intent, EXTRA_DATA)
            return null
        }

        val id = data.id.trim()
        if (id.isEmpty()) {
            neutraliser(activity, intent, EXTRA_DATA)
            return null
        }

        // Consommer AVANT d'écrire : même si l'écriture échoue, l'intent ne doit
        // pas être rejoué à la prochaine recréation d'activité.
        neutraliser(activity, intent, EXTRA_DATA)

        if (!estFrais(data)) {
            Log.w(TAG, "décrochage périmé ignoré id=$id")
            return null
        }

        val ctx: Context = activity.applicationContext
        val connu = try {
            getDataActiveCalls(ctx).any { it.id == id }
        } catch (e: Exception) {
            Log.e(TAG, "lecture ACTIVE_CALLS échouée", e)
            false
        }
        if (!connu) {
            Log.w(TAG, "décrochage pour un appel inconnu id=$id — pas d'écriture")
            return null
        }

        return try {
            // `Data.equals` ne compare que l'identifiant : l'entrée stockée est
            // retrouvée et seul son `isAccepted` change. Notre reconstruction
            // partielle ne sert qu'à la recherche.
            addCall(ctx, data, true)
            Log.i(TAG, "décrochage enregistré id=$id")
            identifiantMetier(data, id)
        } catch (e: Exception) {
            Log.e(TAG, "écriture du décrochage échouée id=$id", e)
            null
        }
    }

    /** L'entrée est-elle assez récente pour que ce décrochage la concerne ? */
    private fun estFrais(data: Data): Boolean {
        val brut = data.extra["shownAt"] ?: return true // absent : l'existence suffit
        val pose = when (brut) {
            is Long -> brut
            is Int -> brut.toLong()
            is Double -> brut.toLong()
            else -> brut.toString().toDoubleOrNull()?.toLong()
        } ?: return true
        if (pose <= 0L) return true
        return System.currentTimeMillis() - pose <= FRAICHEUR_MS
    }

    /**
     * L'identifiant que connaît le reste de l'application.
     *
     * `data.id` est celui de l'entrée CallKit ; `extra["callId"]` est celui du
     * serveur. Ils coïncident aujourd'hui, mais tout le code Dart raisonne sur
     * le second.
     */
    private fun identifiantMetier(data: Data, repli: String): String {
        val metier = data.extra["callId"]?.toString()?.trim()
        return if (metier.isNullOrEmpty()) repli else metier
    }

    /** Neutralise l'intent pour qu'une recréation d'activité ne le rejoue pas. */
    private fun neutraliser(activity: Activity, intent: Intent, cle: String) {
        intent.removeExtra(cle)
        intent.action = null
        activity.intent = intent
    }
}
