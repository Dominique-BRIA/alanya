package com.alanya.telecom

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Person
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.annotation.RequiresApi

private const val TAG = "AlanyaChipAppel"

/**
 * CHIP VERT « APPEL EN COURS » DANS LA BARRE D'ÉTAT (Android 12+).
 *
 * ── LE PROBLÈME RÉSOLU ────────────────────────────────────────────────────
 * Quand un appel arrive application en arrière-plan, la notification d'appel
 * entrant s'affiche en bandeau (`IncomingNotifier`, déjà en `CallStyle`). Mais
 * si l'utilisateur tire le volet des notifications puis le referme, ce bandeau
 * disparaît : l'appel ne survit plus que sous forme de ligne dans le volet, et
 * il faut savoir l'y chercher. Rien, à l'écran, ne dit qu'un appel est en
 * cours.
 *
 * Le chip vert est la réponse d'Android à exactement ça : une pastille
 * permanente dans la barre d'état, visible par-dessus n'importe quelle
 * application, avec le chronomètre de la communication. Un appui dessus ramène
 * l'appel.
 *
 * ── POURQUOI L'EXISTANT NE LE DÉCLENCHAIT PAS ─────────────────────────────
 * Le chip n'est PAS une notification de plus qu'on afficherait : c'est ce
 * qu'Android dessine tout seul lorsqu'il reconnaît un appel en cours. Deux
 * conditions, et il faut les DEUX :
 *
 *   1. une notification de style `Notification.CallStyle.forOngoingCall` ;
 *   2. un service de premier plan de type `phoneCall`.
 *
 * `CallForegroundService` (côté application) tourne bien pendant l'appel et
 * porte déjà un chronomètre — mais c'est un `Notification.Builder` ORDINAIRE,
 * et son type de service est `microphone`. Aucune des deux conditions n'est
 * remplie : Android n'a jamais eu de quoi reconnaître un appel, donc pas de
 * chip.
 *
 * ── CE QUE FAIT CE FICHIER, ET CE QU'IL NE FAIT PAS ───────────────────────
 * Il AJOUTE sa propre notification `CallStyle` portée par son propre service
 * `phoneCall`, sans rien retirer ni modifier de ce qui existe. Conséquence
 * assumée, décidée avec le commanditaire : pendant une communication, le volet
 * contient DEUX lignes d'appel — celle de `CallForegroundService` et celle-ci.
 * Le prix à payer pour ne toucher à aucun code en service.
 *
 * ── CE QUI A DÛ ÊTRE ÉVITÉ ────────────────────────────────────────────────
 * ⚠️ L'identifiant 4242 est DÉJÀ UTILISÉ DEUX FOIS dans ce projet :
 * `IncomingNotifier.NOTIF_ID` et le `NOTIF_ID` privé de
 * `CallForegroundService`. Le réutiliser ici aurait fait que ce service
 * remplace la notification de l'autre, puis l'efface en s'arrêtant — on aurait
 * gagné le chip et perdu la notification d'appel en cours. D'où [NOTIF_ID]
 * ci-dessous, distinct et documenté.
 */
object OngoingCallChip {

    /// ⚠️ NE PAS mettre 4242 : voir l'avertissement dans la documentation de
    /// l'objet. Deux notifications distinctes doivent coexister.
    const val NOTIF_ID = 4243

    private const val CHANNEL = "alanya_appel_en_cours_chip_v1"

    const val ACTION_HANGUP = "com.alanya.telecom.CHIP_HANGUP"

    const val EXTRA_NAME = "chip_name"
    const val EXTRA_SINCE = "chip_since"

    /**
     * Affiche le chip. Appelé au DÉCROCHÉ, jamais à la sonnerie : pendant la
     * sonnerie c'est le bandeau `forIncomingCall` qui parle, et Android ne
     * dessine pas de chip pour un appel qui n'a pas commencé.
     *
     * L'instant de départ du chronomètre est pris ICI, au moment du décroché,
     * et transporté jusqu'à la notification. Le laisser calculer par le service
     * ferait démarrer le compteur à la CRÉATION du service — quelques centaines
     * de millisecondes plus tard, et bien davantage si le système tarde à le
     * lancer.
     */
    fun start(ctx: Context, data: Map<String, String>) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            // Avant Android 12, `CallStyle` n'existe pas et le système ne
            // dessine aucun chip. La notification d'appel en cours existante
            // reste seule, ce qui est le comportement d'avant ce fichier.
            Log.d(TAG, "API ${Build.VERSION.SDK_INT} < 31 : pas de chip, rien à faire")
            return
        }
        val nom = data["callerName"]?.takeIf { it.isNotEmpty() } ?: "Appel en cours"
        val intent = Intent(ctx, OngoingCallService::class.java)
            .putExtra(EXTRA_NAME, nom)
            .putExtra(EXTRA_SINCE, System.currentTimeMillis())
        try {
            ctx.startForegroundService(intent)
        } catch (e: Exception) {
            // Android 12+ interdit de démarrer un service de premier plan
            // depuis l'arrière-plan. On y échappe normalement : Telecom LIE le
            // processus tant qu'une Connection est active, ce qui vaut
            // autorisation. Si la garantie saute un jour, l'appel doit
            // continuer sans chip plutôt que de planter — mais SANS silence :
            // un échec muet ferait chercher le défaut du mauvais côté.
            Log.w(TAG, "démarrage du service refusé, appel sans chip : $e")
        }
    }

    /**
     * Retire le chip. Idempotent : appelable quand rien ne tourne.
     *
     * Branché sur `cleanupUi()` de la Connection, qui est le passage OBLIGÉ de
     * toutes les fins d'appel — refus, raccroché local, raccroché distant,
     * abandon, expiration des 90 s. Un seul point de sortie, donc aucun chemin
     * ne peut laisser un chip orphelin dans la barre d'état.
     */
    fun stop(ctx: Context) {
        try {
            ctx.stopService(Intent(ctx, OngoingCallService::class.java))
        } catch (e: Exception) {
            Log.w(TAG, "arrêt du service : $e")
        }
        // Ceinture et bretelles : si le service avait déjà disparu (processus
        // recyclé) sa notification pourrait subsister. `cancel` sur un
        // identifiant inconnu ne coûte rien.
        try {
            (ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .cancel(NOTIF_ID)
        } catch (_: Exception) {
        }
    }

    /**
     * Construit la notification qui déclenche le chip.
     *
     * `setUsesChronometer(true)` + `setWhen(depuis)` : c'est ce couple, et lui
     * seul, qui fait défiler le compteur — dans le chip comme dans le volet.
     * Sans `setWhen`, Android compte à partir de l'instant d'affichage.
     */
    @RequiresApi(Build.VERSION_CODES.S)
    internal fun build(ctx: Context, nom: String, depuis: Long): Notification {
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val canal = NotificationChannel(
            CHANNEL, "Appel en cours", NotificationManager.IMPORTANCE_DEFAULT
        ).apply {
            // Muet : la sonnerie appartient à la phase d'appel entrant. Une
            // alerte au décroché sonnerait DANS l'oreille de l'utilisateur, qui
            // vient justement de porter le téléphone à son oreille.
            setSound(null, null)
            enableVibration(false)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        nm.createNotificationChannel(canal)

        val flags = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT

        // Raccrocher depuis le chip. Identifiant de requête 4 : 1, 2 et 3 sont
        // pris par `IncomingNotifier` (décrocher, refuser, plein écran). Deux
        // PendingIntent de même identifiant et de même Intent sont LE MÊME
        // objet pour Android — réutiliser 1 ou 2 aurait détourné les boutons de
        // la notification d'appel entrant.
        val raccrocherPi = PendingIntent.getBroadcast(
            ctx, 4,
            Intent(ctx, OngoingCallActionReceiver::class.java).setAction(ACTION_HANGUP),
            flags
        )

        val ouvrir = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
        val ouvrirPi = PendingIntent.getActivity(ctx, 5, ouvrir, flags)

        val person = Person.Builder().setName(nom).setImportant(true).build()

        return Notification.Builder(ctx, CHANNEL)
            .setStyle(Notification.CallStyle.forOngoingCall(person, raccrocherPi))
            .setSmallIcon(android.R.drawable.stat_sys_phone_call)
            .setCategory(Notification.CATEGORY_CALL)
            .setOngoing(true)
            .setUsesChronometer(true)
            .setWhen(depuis)
            .setContentIntent(ouvrirPi)
            .build()
    }
}

/**
 * Service de premier plan de type `phoneCall` : la seconde des deux conditions
 * du chip.
 *
 * ⚠️ ÉCRIT À LA MAIN, et séparé de `CallForegroundService` À DESSEIN. Ce
 * dernier est déclaré `foregroundServiceType="microphone"` ; un service ne peut
 * pas changer de type à l'exécution, et lui ajouter `phoneCall` aurait modifié
 * un fichier en service. Précédents suivis dans ce projet :
 * `CallForegroundService` puis `TransferForegroundService`, tous deux écrits à
 * la main pour la même raison.
 *
 * `START_NOT_STICKY` : si le système tue le service, il ne doit surtout PAS le
 * relancer seul — l'appel, lui, sera terminé, et un chip ressuscité sans
 * communication derrière serait un mensonge permanent dans la barre d'état.
 */
class OngoingCallService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            stopSelf()
            return START_NOT_STICKY
        }
        val nom = intent?.getStringExtra(OngoingCallChip.EXTRA_NAME) ?: "Appel en cours"
        val depuis = intent?.getLongExtra(OngoingCallChip.EXTRA_SINCE, 0L)
            ?.takeIf { it > 0L }
            ?: System.currentTimeMillis()

        val notif = OngoingCallChip.build(this, nom, depuis)
        try {
            startForeground(
                OngoingCallChip.NOTIF_ID,
                notif,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL,
            )
        } catch (e: Exception) {
            // Android 14 exige `FOREGROUND_SERVICE_PHONE_CALL` ET un appel
            // effectivement en cours côté Telecom. Les deux sont réunis ici
            // (`setActive()` précède l'appel à `start`), mais un refus reste
            // possible sur certaines surcouches constructeur. On abandonne le
            // chip proprement plutôt que de laisser un service fantôme sans
            // notification, qu'Android tuerait de toute façon par ANR.
            Log.w(TAG, "startForeground(phoneCall) refusé : $e")
            stopSelf()
            return START_NOT_STICKY
        }
        Log.d(TAG, "chip affiché (depuis=$depuis)")
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        // STOP_FOREGROUND_REMOVE : la notification part AVEC le service. Sans
        // ce retrait explicite, elle survivrait à l'appel dans le volet.
        try {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } catch (e: Exception) {
            Log.w(TAG, "stopForeground : $e")
        }
        super.onDestroy()
    }
}

/**
 * Bouton « Raccrocher » du chip et de sa notification.
 *
 * On passe par la Connection Telecom plutôt que d'arrêter le service
 * directement : c'est elle qui prévient le serveur et le correspondant.
 * Couper seulement le chip laisserait la communication vivante avec un
 * bouton qui semble ne rien faire.
 */
class OngoingCallActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != OngoingCallChip.ACTION_HANGUP) return
        Log.d(TAG, "raccrocher depuis le chip")
        // Même garde de version que les autres points d'entrée du registre
        // (`CallRegistry.answerCurrent` / `rejectCurrent`) : `AlanyaConnection`
        // est annotée `@RequiresApi(O)`.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            CallRegistry.current?.onDisconnect()
        }
        // Filet : si la Connection avait déjà disparu, personne n'appellerait
        // `cleanupUi()` et le chip resterait affiché sans appel derrière.
        OngoingCallChip.stop(context)
    }
}
