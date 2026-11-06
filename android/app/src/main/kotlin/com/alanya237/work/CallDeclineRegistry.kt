package com.alanya237.work

/**
 * CallIds que l'utilisateur a explicitement REFUSÉS, par opposition à ceux dont
 * la notification a simplement expiré.
 *
 * L'écouteur `ACTIVE_CALLS` de [TalkyApplication] ne voit qu'une chose : une
 * entrée a disparu. Refus et expiration s'y présentent à l'identique — son
 * propre journal disait « refus/timeout détecté » —, et il postait un
 * `/calls/reject` dans les deux cas. Le serveur écrivait alors `status = 2`
 * (refusé) cinq secondes avant que son minuteur de 45 s n'ait écrit
 * `status = 3` (sans réponse). Un appel qu'on n'a pas entendu, téléphone dans
 * la poche, s'inscrivait « Rejeté » chez les deux correspondants.
 *
 * Le discriminant est dans le plugin, et il est exact : sa branche `DECLINE`
 * appelle `FlutterCallkitIncomingPlugin.notifyEventCallbacks(DECLINE, data)`,
 * sa branche `TIMEOUT` n'appelle rien — l'énumération `CallkitEventCallback`
 * ne connaît d'ailleurs que ACCEPT, DECLINE et END. Un refus se signale donc,
 * une expiration jamais. Ce registre retient les premiers ; tout ce qui
 * disparaît sans y figurer est une expiration, et le minuteur serveur la
 * classera correctement.
 *
 * Même forme que [CallDismissRegistry], y compris son TTL et sa borne : les
 * deux marquages arrivent quelques microsecondes avant la lecture, dans le même
 * processus, mais rien ne doit enfler si l'un d'eux n'est jamais consommé.
 */
object CallDeclineRegistry {

    /** Marge large devant la fenêtre où le retrait est lu. */
    private const val TTL_MS = 120_000L

    /** Garde-fou : un flux d'identifiants ne doit pas faire enfler la mémoire. */
    private const val MAX_ENTRIES = 256

    private val declinedIds = LinkedHashMap<String, Long>()

    fun markDeclined(callId: String) {
        val id = callId.trim()
        if (id.isEmpty()) return
        synchronized(declinedIds) {
            purgeExpired()
            declinedIds[id] = System.currentTimeMillis()
            // LinkedHashMap conserve l'ordre d'insertion : la plus ancienne part.
            while (declinedIds.size > MAX_ENTRIES) {
                val oldest = declinedIds.keys.firstOrNull() ?: break
                declinedIds.remove(oldest)
            }
        }
    }

    /** True si [callId] a été refusé par l'utilisateur. Consomme la marque. */
    fun consumeIfDeclined(callId: String): Boolean {
        val id = callId.trim()
        if (id.isEmpty()) return false
        synchronized(declinedIds) {
            purgeExpired()
            return declinedIds.remove(id) != null
        }
    }

    /** Appelant sous `synchronized`. */
    private fun purgeExpired() {
        val limite = System.currentTimeMillis() - TTL_MS
        val it = declinedIds.entries.iterator()
        while (it.hasNext()) {
            if (it.next().value < limite) it.remove() else break
        }
    }
}
