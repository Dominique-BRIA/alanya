package com.alanya237.work

/**
 * CallIds retirés de CallKit par Flutter (migration foreground, anti-doublon),
 * pas par un refus utilisateur — ne pas POST /calls/reject dans ce cas.
 *
 * Les entrées expirent, et leur nombre est borné. Le registre était un simple
 * Set qui grossissait pour toute la durée de vie du process : croissance lente,
 * mais surtout une entrée jamais consommée restait indéfiniment capable de
 * neutraliser un refus utilisateur portant le même identifiant. Tous les autres
 * registres de déduplication du projet ont un TTL — 120 s pour EndedCallRegistry
 * et `_handledTerminalCallIds`, 90 s pour `_recentIncomingCallIds` — celui-ci
 * s'aligne.
 */
object CallDismissRegistry {
    /** Marge large devant la fenêtre où un retrait programmatique peut être lu. */
    private const val TTL_MS = 120_000L

    /** Garde-fou : un flux d'identifiants ne doit pas faire enfler la mémoire. */
    private const val MAX_ENTRIES = 256

    private val programmaticIds = LinkedHashMap<String, Long>()

    fun markProgrammaticDismiss(callId: String) {
        val id = callId.trim()
        if (id.isEmpty()) return
        synchronized(programmaticIds) {
            purgeExpired()
            programmaticIds[id] = System.currentTimeMillis()
            // LinkedHashMap conserve l'ordre d'insertion : la plus ancienne part.
            while (programmaticIds.size > MAX_ENTRIES) {
                val oldest = programmaticIds.keys.firstOrNull() ?: break
                programmaticIds.remove(oldest)
            }
        }
    }

    fun consumeIfProgrammatic(callId: String): Boolean {
        val id = callId.trim()
        if (id.isEmpty()) return false
        synchronized(programmaticIds) {
            purgeExpired()
            return programmaticIds.remove(id) != null
        }
    }

    /** Appelant sous `synchronized`. */
    private fun purgeExpired() {
        val limite = System.currentTimeMillis() - TTL_MS
        val it = programmaticIds.entries.iterator()
        while (it.hasNext()) {
            if (it.next().value < limite) it.remove() else break
        }
    }
}
