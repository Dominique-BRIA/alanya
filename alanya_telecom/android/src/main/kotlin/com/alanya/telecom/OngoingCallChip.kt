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

    /**
     * Appui sur le chip lui-même (et sur le corps de la notification).
     *
     * ⚠️ POURQUOI PAS SIMPLEMENT L'INTENT DE LANCEMENT DE L'APPLICATION. C'est
     * ce que faisait la première version, et ça ramenait l'application « là où
     * on l'avait laissée ». Après un décroché suivi d'un aller dans une
     * conversation, l'appui sur le chip ramenait donc sur LA CONVERSATION, pas
     * sur l'appel — il fallait ensuite passer par le bandeau vert pour revenir.
     * Deux gestes au lieu d'un, là où WhatsApp en demande un seul.
     *
     * On passe donc par un récepteur qui fait DEUX choses : ramener
     * l'application au premier plan, puis demander à Dart de rouvrir l'écran
     * d'appel.
     */
    const val ACTION_REOPEN = "com.alanya.telecom.CHIP_REOPEN"

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
    /**
     * Journalise une étape du chip — en logcat ET dans les préférences Flutter.
     *
     * ⚠️ POURQUOI PASSER PAR LES PRÉFÉRENCES ET NON PAR `emit`. Le diagnostic
     * doit être lisible SANS câble : la seule surface disponible est l'overlay
     * de débogage, qui vit côté Dart. Or tout ce fichier s'exécute en natif, et
     * souvent AVANT qu'un moteur Flutter ne soit attaché — décrocher DÉMARRE
     * l'application. Un `emit` partirait alors vers zéro moteur et la trace
     * serait perdue, précisément dans le cas qu'on cherche à observer.
     *
     * Le fichier `FlutterSharedPreferences` est déjà lu par ce même greffon
     * (sonnerie choisie, jeton du refus natif) : le chemin est éprouvé en
     * production. Dart relit la clé et la vide.
     */
    internal fun journalise(ctx: Context, msg: String) {
        Log.d(TAG, msg)
        try {
            val prefs = ctx.getSharedPreferences(
                "FlutterSharedPreferences", Context.MODE_PRIVATE
            )
            val heure = android.text.format.DateFormat
                .format("HH:mm:ss", System.currentTimeMillis())
            val avant = prefs.getString("flutter.chip_diag", "") ?: ""
            // Borné à 20 : l'overlay ne tient que 60 lignes au total, et une
            // préférence qui grossit sans fin pèserait sur chaque lecture.
            val lignes = (avant.split("\n").filter { it.isNotEmpty() } + "$heure $msg")
                .takeLast(20)
            prefs.edit().putString("flutter.chip_diag", lignes.joinToString("\n")).apply()
        } catch (e: Exception) {
            Log.w(TAG, "journalise: $e")
        }
    }

    /**
     * Instant de départ du chronomètre, ou 0 si aucun chip n'est posé.
     *
     * ⚠️ SANS CE CHAMP, LE CHRONOMÈTRE REPARTAIT DE ZÉRO. Deux chemins peuvent
     * désormais demander le chip pour le MÊME appel : le natif, quand Telecom
     * porte l'appel (`onAnswer`), et Dart, quand il ne le porte pas (appel
     * décroché application déjà ouverte, ou appel sortant). Les deux se
     * produisent parfois pour un même appel, à quelques centaines de
     * millisecondes d'écart. Recalculer l'instant de départ au second appel
     * ferait visiblement reculer le compteur sous les yeux de l'utilisateur.
     *
     * Le premier qui pose gagne ; les suivants ne font que rafraîchir la
     * notification, sans toucher au temps.
     */
    @Volatile
    private var debutMs: Long = 0L

    fun start(ctx: Context, data: Map<String, String>) {
        journalise(ctx, "start() appelé (API ${Build.VERSION.SDK_INT})")
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            // Avant Android 12, `CallStyle` n'existe pas et le système ne
            // dessine aucun chip. La notification d'appel en cours existante
            // reste seule, ce qui est le comportement d'avant ce fichier.
            journalise(ctx, "ABANDON : API < 31, CallStyle n'existe pas")
            return
        }
        if (debutMs == 0L) debutMs = System.currentTimeMillis()
        val nom = data["callerName"]?.takeIf { it.isNotEmpty() } ?: "Appel en cours"
        val intent = Intent(ctx, OngoingCallService::class.java)
            .putExtra(EXTRA_NAME, nom)
            .putExtra(EXTRA_SINCE, debutMs)
        try {
            ctx.startForegroundService(intent)
            journalise(ctx, "startForegroundService() OK, service demandé")
        } catch (e: Exception) {
            // Android 12+ interdit de démarrer un service de premier plan
            // depuis l'arrière-plan. On y échappe normalement : Telecom LIE le
            // processus tant qu'une Connection est active, ce qui vaut
            // autorisation. Si la garantie saute un jour, l'appel doit
            // continuer sans chip plutôt que de planter — mais SANS silence :
            // un échec muet ferait chercher le défaut du mauvais côté.
            journalise(ctx, "ÉCHEC startForegroundService : ${e.javaClass.simpleName} — $e")
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
        // Remis à zéro AVANT l'arrêt : le prochain appel doit repartir de son
        // propre décroché. L'oublier ici ferait démarrer le chip suivant avec
        // le chronomètre du précédent.
        debutMs = 0L
        try {
            // `stopService` rend vrai seulement s'il y avait un service à
            // arrêter : c'est ce booléen qui distingue « le chip a été retiré »
            // de « il n'y en avait jamais eu ». Sans lui, un retrait prématuré
            // et une absence pure et simple donneraient la même trace.
            val yAvait = ctx.stopService(Intent(ctx, OngoingCallService::class.java))
            if (yAvait) journalise(ctx, "stop() — chip retiré")
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

        // Identifiant de requête 6 : 1, 2 et 3 appartiennent à
        // `IncomingNotifier`, 4 au bouton Raccrocher ci-dessus. Deux
        // PendingIntent de même identifiant ET de même Intent sont LE MÊME
        // objet pour Android — se tromper ici détournerait un bouton existant.
        val ouvrirPi = PendingIntent.getBroadcast(
            ctx, 6,
            Intent(ctx, OngoingCallActionReceiver::class.java).setAction(ACTION_REOPEN),
            flags
        )

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
            OngoingCallChip.journalise(
                this, "ÉCHEC startForeground(phoneCall) : ${e.javaClass.simpleName} — $e"
            )
            stopSelf()
            return START_NOT_STICKY
        }
        OngoingCallChip.journalise(this, "CHIP POSÉ — notification affichée, chrono lancé")
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
        when (intent.action) {
            OngoingCallChip.ACTION_HANGUP -> {
                Log.d(TAG, "raccrocher depuis le chip")
                // Même garde de version que les autres points d'entrée du
                // registre (`CallRegistry.answerCurrent` / `rejectCurrent`) :
                // `AlanyaConnection` est annotée `@RequiresApi(O)`.
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    CallRegistry.current?.onDisconnect()
                }
                // Filet : si la Connection avait déjà disparu, personne
                // n'appellerait `cleanupUi()` et le chip resterait affiché
                // sans appel derrière.
                OngoingCallChip.stop(context)
            }

            OngoingCallChip.ACTION_REOPEN -> {
                Log.d(TAG, "retour à l'appel depuis le chip")
                // 1. Ramener l'application au premier plan. Sans ça, Dart
                //    pousserait un écran dans une application invisible.
                try {
                    val launch = context.packageManager
                        .getLaunchIntentForPackage(context.packageName)
                    launch?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(launch)
                } catch (e: Exception) {
                    Log.w(TAG, "lancement de l'application : $e")
                }
                // 2. Demander l'écran d'appel. La charge est vide À DESSEIN :
                //    c'est `CallController.activeCallId` qui fait foi côté
                //    Dart, pas un identifiant recopié ici qui pourrait être
                //    périmé après un transfert d'appel.
                //
                //    Sans effet si aucun moteur Flutter n'est attaché (`emit`
                //    diffuse alors à zéro moteur). Ce cas est déjà couvert
                //    autrement : au démarrage à froid, `CallListener` lit
                //    `getAcceptedCall()` et ouvre l'écran de lui-même.
                AlanyaTelecomPlugin.emit("reopen", HashMap())
            }
        }
    }
}
