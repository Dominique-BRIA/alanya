import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/pays_repository.dart';
import '../core/telephone.dart';
import '../l10n/app_localizations.dart';
import '../theme/alanya_theme.dart';
import 'choix_pays_screen.dart';

/// Retrouve un pays par son identifiant dans une liste.
Pays? paysParId(List<Pays> pays, int? idPays) {
  if (idPays == null) return null;
  for (final p in pays) {
    if (p.idPays == idPays) return p;
  }
  return null;
}

/// Le pays et le numéro, saisis comme à l'inscription WhatsApp.
///
/// Un pays sur sa ligne, puis l'indicatif et le numéro côte à côte, soulignés.
///
/// 🔴 UN SEUL COMPOSANT POUR LES DEUX ENDROITS QUI DEMANDENT UN NUMÉRO :
/// l'inscription et les réglages. Ils avaient chacun leur formulaire, avec des
/// règles de mise en forme légèrement différentes — et c'est exactement ainsi
/// qu'un numéro finit stocké sous deux formes dans une colonne UNIQUE.
///
/// POURQUOI CETTE DISPOSITION : elle rend l'ordre des gestes évident. Le pays
/// vient avant le numéro parce que c'est lui qui donne l'indicatif, et
/// l'indicatif s'affiche à gauche du champ AVANT qu'on tape — on voit donc le
/// numéro entier pendant qu'on le compose.
///
/// ⚠️ LE CHAMP N'ACCEPTE QUE DES CHIFFRES. L'indicatif est dans sa propre case ;
/// un « + » tapé ici produirait un numéro à deux indicatifs.
class SaisiePaysNumero extends StatelessWidget {
  const SaisiePaysNumero({
    super.key,
    required this.pays,
    required this.idPays,
    required this.controller,
    required this.onPays,
    this.actif = true,
    this.autofocus = false,
  });

  /// La table de référence. Vide tant qu'elle charge : le sélecteur invite
  /// alors à choisir, plutôt que d'ouvrir une liste vide.
  final List<Pays> pays;

  final int? idPays;

  /// Ne contient QUE le numéro national, sans indicatif.
  final TextEditingController controller;

  final ValueChanged<int> onPays;
  final bool actif;
  final bool autofocus;

  /// Le numéro complet, en forme canonique — ou `""` si l'un des deux manque.
  ///
  /// ⚠️ L'indicatif est recollé ICI parce qu'il n'est pas dans le champ. Le
  /// serveur normalise ensuite, avec la même règle qu'ailleurs : cette
  /// composition n'est qu'un préalable, pas la source de vérité.
  static String numeroComplet(List<Pays> pays, int? idPays, String saisie) {
    final p = paysParId(pays, idPays);
    final n = saisie.trim();
    if (p == null || n.isEmpty) return "";
    return normaliserTelephone(n, p.prefix);
  }

  @override
  Widget build(BuildContext context) {
    final accent = accentOf(context);
    final muted = mutedOf(context, Colors.black54);
    final choisi = paysParId(pays, idPays);

    // Soulignement seul, sans remplissage : c'est ce qui donne à ce bloc son
    // allure de saisie de numéro plutôt que de formulaire. Le thème global
    // remplit et arrondit les champs — il est écarté ici, et seulement ici.
    InputDecoration souligne({String? hint}) => InputDecoration(
          hintText: hint,
          filled: false,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: accent.withValues(alpha: 0.45)),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: accent, width: 2),
          ),
          border: const UnderlineInputBorder(),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Le pays, sur sa propre ligne ────────────────────────────────
        InkWell(
          onTap: !actif || pays.isEmpty
              ? null
              : () async {
                  final p = await Navigator.of(context).push<Pays>(
                    MaterialPageRoute(
                      builder: (_) => ChoixPaysScreen(
                        pays: pays,
                        idSelectionne: idPays,
                      ),
                    ),
                  );
                  if (p != null) onPays(p.idPays);
                },
          child: InputDecorator(
            decoration: souligne(),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    choisi?.libelle ??
                        tr(context,
                            pays.isEmpty ? 'loading' : 'choose_country'),
                    style: TextStyle(
                      fontSize: 16,
                      color: choisi == null ? muted : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.arrow_drop_down, color: accent),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),

        // ── L'indicatif, puis le numéro ─────────────────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // L'indicatif est AFFICHÉ, pas saisi : il suit le pays choisi
            // au-dessus. Le rendre modifiable ouvrirait la porte à un
            // indicatif qui contredit le pays, et il faudrait alors décider
            // lequel des deux fait foi.
            SizedBox(
              width: 76,
              child: InputDecorator(
                decoration: souligne(),
                child: Text(
                  choisi == null || choisi.prefix.isEmpty ? "+" : choisi.prefix,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: TextField(
                controller: controller,
                enabled: actif,
                autofocus: autofocus,
                keyboardType: TextInputType.phone,
                maxLength: 20,
                style: const TextStyle(fontSize: 16),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: souligne(hint: tr(context, 'phone_hint'))
                    .copyWith(counterText: ""),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
