/// LES ÉLÉMENTS D'INTERFACE DU CHIFFREMENT — tickets 4.11 à 4.13.
///
/// 🔴 CES TROIS ÉLÉMENTS NE SONT PAS DÉCORATIFS. Ils sont la seule façon dont
/// l'utilisateur apprend ce que le chiffrement fait, ce qu'il ne fait pas, et
/// quand quelque chose a changé. Un chiffrement qui marche sans que personne le
/// sache ne protège pas de la même façon : on ne vérifie pas ce qu'on ignore.
///
/// ⚠️ ANALYSÉS, JAMAIS AFFICHÉS SUR UN TÉLÉPHONE. L'APK n'est pas construit
/// localement. Les règles qu'ils portent sont éprouvées côté web ; leur rendu ne
/// l'est pas.
library;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../services/e2ee/e2ee_service.dart';

/// Le bouclier de la barre de conversation — ticket 4.11.
///
/// 🔴 UN BOUCLIER, PAS UN CADENAS. Le cadenas sert déjà à la RÉSERVATION de
/// conversation, et deux cadenas voisins — chacun avec un état ouvert et un état
/// fermé — faisaient quatre combinaisons pour deux formes identiques (signalé
/// par le user le 24/09/2026).
///
/// ⚠️ ET LE CADENAS DÉCRIT MIEUX LA RÉSERVATION : elle s'ouvre et se referme. Le
/// chiffrement, lui, NE SE DÉFAIT PAS — un cadenas qu'on ne peut pas rouvrir est
/// une métaphore qui ment.
class BoutonChiffrement extends StatelessWidget {
  const BoutonChiffrement({
    super.key,
    required this.actif,
    required this.activable,
    required this.onAppui,
    this.motifRefus,
  });

  final bool actif;
  final bool activable;
  final VoidCallback onAppui;
  final String? motifRefus;

  @override
  Widget build(BuildContext context) {
    /*
     * ⚠️ L'ÉTAT PASSE PAR LE LIBELLÉ, jamais par un attribut qui suggère un
     * interrupteur. Le chiffrement ne se retire pas, et l'étiquette le dit en
     * toutes lettres — sans quoi les gens croient qu'on peut le désactiver et
     * cherchent comment.
     */
    final libelle = actif
        ? 'Chiffrée de bout en bout — le chiffrement ne se retire pas. '
            'Appuyez pour vérifier le code de sécurité.'
        : motifRefus ?? 'Chiffrer cette conversation de bout en bout';

    return Tooltip(
      message: libelle,
      child: IconButton(
        onPressed: (actif || activable) ? onAppui : null,
        icon: Icon(actif ? Icons.verified_user : Icons.shield_outlined),
        color: actif ? Theme.of(context).colorScheme.onPrimary : null,
        style: actif
            ? IconButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary)
            : null,
        tooltip: null,
      ),
    );
  }
}

/// La bannière « à partir d'ici, chiffré » — ticket 4.11.
///
/// 🔴 ELLE DIT UNE VÉRITÉ QUI SE TAIRAIT AUTREMENT : les messages ANTÉRIEURS
/// restent lisibles par le serveur. Activer le chiffrement ne protège pas
/// rétroactivement, et laisser croire le contraire serait un mensonge par
/// omission — le plus dangereux, parce qu'il rassure.
class BanniereChiffrement extends StatelessWidget {
  const BanniereChiffrement({super.key, this.verifie = false});

  final bool verifie;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E8),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.verified_user, size: 15, color: Color(0xFFB85C38)),
          const SizedBox(width: 7),
          const Flexible(
            child: Text(
              'À partir d’ici, les messages sont chiffrés de bout en bout.',
              style: TextStyle(fontSize: 12.5, color: Color(0xFF7A4A2E)),
            ),
          ),
          /*
           * ⚠️ LE BADGE NE DIT PAS « C'EST SÛR ». Il dit « VOUS avez comparé ce
           * code ». Le produit n'en sait rien de plus que ce que l'utilisateur a
           * déclaré, et la nuance est tout le sujet.
           */
          if (verifie) ...[
            const SizedBox(width: 8),
            const Icon(Icons.check, size: 13, color: Color(0xFF2C6B34)),
            const Text(' vérifié',
                style: TextStyle(fontSize: 11.5, color: Color(0xFF2C6B34))),
          ],
        ],
      ),
    );
  }
}

/// L'avertissement de changement de clé — ticket 4.12.
///
/// 🔴 ON AVERTIT, ON NE BLOQUE JAMAIS (modèle WhatsApp, décision du 21/09/2026).
/// Un changement de clé est soit une réinstallation, soit une interposition — et
/// les deux sont INDISTINGUABLES. Bloquer punirait la réinstallation, qui est le
/// cas de très loin le plus fréquent.
///
/// ⚠️ LA SEULE ACTION UTILE EST DE COMPARER LE CODE hors du canal. C'est donc la
/// seule que cet avertissement propose.
class AvertissementCleChangee extends StatelessWidget {
  const AvertissementCleChangee({
    super.key,
    required this.nomPair,
    required this.onVerifier,
    required this.onIgnorer,
  });

  final String nomPair;
  final VoidCallback onVerifier;
  final VoidCallback onIgnorer;

  @override
  Widget build(BuildContext context) {
    return MaterialBanner(
      backgroundColor: const Color(0xFFFDF0F0),
      content: Text(
        'La clé de sécurité de $nomPair a changé. '
        'Cela arrive après une réinstallation — ou si quelqu’un s’interpose.',
        style: const TextStyle(fontSize: 13, color: Color(0xFF9B2C2C)),
      ),
      actions: [
        TextButton(onPressed: onVerifier, child: const Text('Vérifier')),
        TextButton(onPressed: onIgnorer, child: const Text('Plus tard')),
      ],
    );
  }
}

/// L'écran de vérification — ticket 4.13.
///
/// ⚠️ LE CODE VIENT AVANT LE QR, jamais l'inverse. Face à quelqu'un sans
/// caméra — un ordinateur — les chiffres sont le SEUL moyen. Les cacher derrière
/// une image les rendrait inaccessibles là où ils sont indispensables.
class EcranVerification extends StatelessWidget {
  const EcranVerification({
    super.key,
    required this.code,
    required this.nomPair,
    required this.verifie,
    required this.onBasculer,
    this.onScanner,
    this.codesParAppareil,
  });

  final String code;
  final String nomPair;
  final bool verifie;
  final VoidCallback onBasculer;
  final VoidCallback? onScanner;

  /// Un code par appareil chiffré du correspondant, quand il en a plusieurs.
  ///
  /// 🔴 UNE IDENTITÉ PAR APPAREIL, DONC UN CODE PAR APPAREIL. N'en montrer
  /// qu'un quand le pair en a deux ferait comparer le mauvais une fois sur
  /// deux — et conclure à une interposition qui n'existe pas. Nul ou à un
  /// seul élément : l'écran rend le code unique, comme avant.
  final Map<int, String>? codesParAppareil;

  /// Les douze groupes de cinq chiffres.
  ///
  /// ⚠️ GROUPÉS POUR ÊTRE LUS À VOIX HAUTE. Soixante chiffres d'affilée ne se
  /// dictent pas : on perd sa place, on recommence, et on finit par renoncer à
  /// vérifier — ce qui est exactement le résultat qu'on cherche à éviter.
  static List<String> _groupesDe(String c) =>
      List.generate(12, (i) => c.substring(i * 5, i * 5 + 5));

  Widget _blocsCode(String c) {
    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 6,
          children: _groupesDe(c)
              .map((g) => Text(g,
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 17, letterSpacing: 1)))
              .toList(),
        ),
        const SizedBox(height: 22),
        Center(
          /*
           * 🔴 LE QR ENCODE LE CODE LUI-MÊME. Deux formats — l'un pour l'œil,
           * l'autre pour la caméra — pourraient DIVERGER, et le défaut ne se
           * verrait qu'au moment où quelqu'un s'inquiète vraiment.
           */
          child: QrImageView(
            data: E2eeService.qrDepuisCode(c),
            size: 190,
            // ⚠️ FOND BLANC IMPOSÉ : un QR sur fond sombre ne se scanne pas.
            backgroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Non-nul dans tous les cas : à un seul code, le plan de repli porte le
    // code unique — et la branche « plusieurs » ne le voit jamais.
    final parAppareil = codesParAppareil ?? {0: code};
    final plusieurs = parAppareil.length > 1;
    return Scaffold(
      appBar: AppBar(title: const Text('Code de sécurité')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            plusieurs
                ? '$nomPair a ${parAppareil.length} appareils chiffrés : '
                    'comparez chaque code avec le sien, de vive voix ou en '
                    'face à face.'
                : 'Comparez ce code avec $nomPair, de vive voix ou en face à face.',
            style: const TextStyle(fontSize: 13.5),
          ),
          /*
           * 🔴 « HORS DE CETTE CONVERSATION » N'EST PAS UN DÉTAIL DE FORMULATION.
           * Envoyer ce code DANS le fil qu'il doit vérifier ne prouve rien : un
           * serveur qui s'interpose réécrirait le message au passage.
           */
          const SizedBox(height: 6),
          const Text(
            'Ne l’envoyez pas dans cette conversation : c’est justement '
            'elle que vous vérifiez.',
            style: TextStyle(fontSize: 12, color: Color(0xFF8A8A90)),
          ),
          const SizedBox(height: 18),
          if (!plusieurs)
            _blocsCode(code)
          else
            for (final entree in parAppareil.entries) ...[
              Row(
                children: [
                  const Icon(Icons.smartphone, size: 16, color: Color(0xFF8A8A90)),
                  const SizedBox(width: 6),
                  Text(
                    'Appareil ${entree.key}',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF8A8A90)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _blocsCode(entree.value),
              const SizedBox(height: 22),
              const Divider(),
              const SizedBox(height: 14),
            ],
          if (onScanner != null) ...[
            const SizedBox(height: 14),
            Center(
              child: OutlinedButton.icon(
                onPressed: onScanner,
                icon: const Icon(Icons.qr_code_scanner, size: 18),
                label: const Text('Scanner son code'),
              ),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: onBasculer,
            child: Text(verifie ? 'Marquer comme non vérifié' : 'Marquer vérifié'),
          ),
          const SizedBox(height: 10),
          /*
           * ⚠️ CE QUE LE BADGE SIGNIFIE VRAIMENT, écrit sous le bouton qui le
           * pose. Le produit ne sait pas si la comparaison a eu lieu ; il note
           * seulement ce que l'utilisateur déclare.
           */
          const Text(
            'Marquer vérifié ne prouve rien par soi-même : cela note que VOUS '
            'avez comparé. La marque disparaît si la clé change.',
            style: TextStyle(fontSize: 11.5, color: Color(0xFF8A8A90)),
          ),
        ],
      ),
    );
  }
}
