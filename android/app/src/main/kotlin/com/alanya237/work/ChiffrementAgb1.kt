package com.alanya237.work

import android.os.Handler
import android.util.Base64
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * LE FORMAT AGB1, CHIFFRÉ PAR LE PROCESSEUR (18/10/2026).
 *
 * 🐛 « LE CHIFFREMENT N'EST PAS LE PROBLÈME, C'EST UNE PETITE LENTEUR » (patron).
 * Le chiffrement des médias tournait en Dart pur (`pointycastle`) : AES-GCM
 * calculé octet par octet, sans les instructions AES du processeur. Ici,
 * `javax.crypto` (Conscrypt / BoringSSL) les utilise.
 *
 * 🔴 MÊMES OCTETS QUE `e2ee_media.dart` / `e2ee_media_fichier.dart`, et que le
 * web (`e2ee-media.ts`) : blocs de 64 Kio en clair, chacun chiffré en
 * AES-256-GCM, tag de 128 bits accolé (sortie = chiffré ‖ tag) ; nonce de
 * 12 octets nuls sauf le numéro du bloc en gros-boutiste aux octets 7 à 10 et
 * le drapeau « dernier bloc » à l'octet 11 ; aucune donnée associée.
 * L'empreinte est le SHA-256 du fichier CHIFFRÉ.
 *
 * Le travail tourne hors du fil principal ; la progression remonte par
 * `progression` (jeton, fraction), comme le faisait l'isolat Dart.
 */
class ChiffrementAgb1(private val canal: MethodChannel) {

    private companion object {
        const val BLOC = 64 * 1024
        const val TAG = 16
    }

    private val travailleur = Executors.newSingleThreadExecutor()
    private val principal = Handler(Looper.getMainLooper())

    fun traiter(appel: MethodCall, resultat: MethodChannel.Result) {
        when (appel.method) {
            "chiffrerFichier" -> travailleur.execute {
                try {
                    val r = chiffrerFichier(
                        source = appel.argument<String>("source"),
                        octets = appel.argument<ByteArray>("octets"),
                        destination = appel.argument<String>("destination")!!,
                        cle = appel.argument<ByteArray>("cle")!!,
                        jeton = appel.argument<Int>("jeton") ?: 0,
                    )
                    principal.post { resultat.success(r) }
                } catch (e: Exception) {
                    principal.post { resultat.error("ECHEC", e.message, null) }
                }
            }
            "dechiffrer" -> travailleur.execute {
                try {
                    val clair = dechiffrer(
                        chiffre = appel.argument<ByteArray>("chiffre")!!,
                        cle = appel.argument<ByteArray>("cle")!!,
                        empreinte = appel.argument<String>("empreinte")!!,
                        taille = appel.argument<Int>("taille")!!,
                    )
                    principal.post { resultat.success(clair) }
                } catch (e: FichierInvalide) {
                    principal.post { resultat.error("INVALIDE", e.message, null) }
                } catch (e: Exception) {
                    principal.post { resultat.error("ECHEC", e.message, null) }
                }
            }
            else -> resultat.notImplemented()
        }
    }

    private class FichierInvalide(message: String) : Exception(message)

    private fun nonce(index: Int, dernier: Boolean): ByteArray {
        val n = ByteArray(12)
        n[7] = (index ushr 24).toByte()
        n[8] = (index ushr 16).toByte()
        n[9] = (index ushr 8).toByte()
        n[10] = index.toByte()
        n[11] = if (dernier) 1 else 0
        return n
    }

    private fun chiffrerFichier(
        source: String?,
        octets: ByteArray?,
        destination: String,
        cle: ByteArray,
        jeton: Int,
    ): Map<String, Any> {
        require((source == null) != (octets == null)) { "une source : un chemin OU des octets" }
        val cleAes = SecretKeySpec(cle, "AES")
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        val sha = MessageDigest.getInstance("SHA-256")
        val sortieFichier = File(destination)
        sortieFichier.parentFile?.mkdirs()
        val entree = source?.let { FileInputStream(it) }
        val tailleClair = source?.let { File(it).length() } ?: octets!!.size.toLong()
        val nbBlocs = maxOf(1L, (tailleClair + BLOC - 1) / BLOC).toInt()
        val tampon = ByteArray(BLOC)
        var taille = 0L
        var reussi = false
        var dernierPourcent = -1
        try {
            FileOutputStream(sortieFichier).use { sortie ->
                for (i in 0 until nbBlocs) {
                    val debut = i.toLong() * BLOC
                    val n = minOf(BLOC.toLong(), tailleClair - debut).toInt()
                    val bloc: ByteArray
                    val decalage: Int
                    if (entree != null) {
                        var lus = 0
                        while (lus < n) {
                            val k = entree.read(tampon, lus, n - lus)
                            if (k <= 0) throw IllegalStateException("le fichier a changé pendant le chiffrement")
                            lus += k
                        }
                        bloc = tampon
                        decalage = 0
                    } else {
                        bloc = octets!!
                        decalage = debut.toInt()
                    }
                    cipher.init(Cipher.ENCRYPT_MODE, cleAes, GCMParameterSpec(TAG * 8, nonce(i, i == nbBlocs - 1)))
                    val chiffre = cipher.doFinal(bloc, decalage, n)
                    sortie.write(chiffre)
                    sha.update(chiffre)
                    taille += chiffre.size
                    val pourcent = if (tailleClair == 0L) 100 else ((debut + n) * 100 / tailleClair).toInt()
                    if (pourcent != dernierPourcent) {
                        dernierPourcent = pourcent
                        val fraction = pourcent / 100.0
                        principal.post {
                            canal.invokeMethod("progression", mapOf("jeton" to jeton, "fraction" to fraction))
                        }
                    }
                }
            }
            reussi = true
            return mapOf(
                "taille" to taille,
                "tailleClair" to tailleClair,
                "empreinte" to sha.digest(),
            )
        } finally {
            entree?.close()
            if (!reussi) sortieFichier.delete()
        }
    }

    private fun dechiffrer(chiffre: ByteArray, cle: ByteArray, empreinte: String, taille: Int): ByteArray {
        val calculee = Base64.encodeToString(MessageDigest.getInstance("SHA-256").digest(chiffre), Base64.NO_WRAP)
        if (calculee != empreinte) throw FichierInvalide("empreinte différente : fichier remplacé ou abîmé")
        if (cle.size != 32) throw FichierInvalide("clé invalide")
        val blocChiffre = BLOC + TAG
        val nbBlocs = (chiffre.size + blocChiffre - 1) / blocChiffre
        if (nbBlocs == 0) throw FichierInvalide("fichier vide")
        val cleAes = SecretKeySpec(cle, "AES")
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        val sortie = ByteArray(maxOf(0, chiffre.size - nbBlocs * TAG))
        var ecrits = 0
        for (i in 0 until nbBlocs) {
            val debut = i * blocChiffre
            val n = minOf(blocChiffre, chiffre.size - debut)
            if (n < TAG) throw FichierInvalide("bloc tronqué")
            try {
                cipher.init(Cipher.DECRYPT_MODE, cleAes, GCMParameterSpec(TAG * 8, nonce(i, i == nbBlocs - 1)))
                ecrits += cipher.doFinal(chiffre, debut, n, sortie, ecrits)
            } catch (e: Exception) {
                throw FichierInvalide("bloc $i refusé : clé fausse, ordre changé ou fichier coupé")
            }
        }
        if (ecrits != taille) throw FichierInvalide("taille différente de celle annoncée")
        return if (ecrits == sortie.size) sortie else sortie.copyOf(ecrits)
    }
}
