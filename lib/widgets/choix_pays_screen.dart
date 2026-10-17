import 'package:flutter/material.dart';

import '../core/pays_repository.dart';
import '../l10n/app_localizations.dart';
import '../theme/alanya_theme.dart';
import 'back_app_bar.dart';

/// Choisir un pays dans une liste cherchable.
///
/// Rend le [Pays] choisi par `Navigator.pop`, ou `null` si l'écran est quitté.
///
/// POURQUOI UN ÉCRAN ET PAS UN MENU DÉROULANT : la table en compte 67, et un
/// menu déroulant de 67 lignes se parcourt au pouce sans pouvoir chercher. Sur
/// l'écran de saisie du numéro, le pays est le PREMIER geste — le rater fait
/// saisir un numéro avec le mauvais indicatif.
///
/// La recherche porte aussi sur l'INDICATIF : beaucoup de gens connaissent
/// « +237 » mieux que l'orthographe exacte du libellé, et taper « 237 » est
/// plus rapide que faire défiler.
class ChoixPaysScreen extends StatefulWidget {
  const ChoixPaysScreen({
    super.key,
    required this.pays,
    this.idSelectionne,
  });

  final List<Pays> pays;
  final int? idSelectionne;

  @override
  State<ChoixPaysScreen> createState() => _ChoixPaysScreenState();
}

class _ChoixPaysScreenState extends State<ChoixPaysScreen> {
  final _rechercheCtrl = TextEditingController();
  String _requete = "";

  @override
  void dispose() {
    _rechercheCtrl.dispose();
    super.dispose();
  }

  /// Compare sans tenir compte de la casse ni des accents.
  ///
  /// ⚠️ « Emirats » doit trouver « Émirats ». Sans ce repli, un clavier sans
  /// accent ne trouve rien et la liste paraît vide alors que le pays y est.
  static String _plat(String s) {
    const avec = "àáâäãåçèéêëìíîïñòóôöõùúûüýÿ";
    const sans = "aaaaaaceeeeiiiinooooouuuuyy";
    final b = StringBuffer();
    for (final c in s.toLowerCase().runes) {
      final ch = String.fromCharCode(c);
      final i = avec.indexOf(ch);
      b.write(i == -1 ? ch : sans[i]);
    }
    return b.toString();
  }

  List<Pays> get _filtres {
    final q = _plat(_requete.trim());
    if (q.isEmpty) return widget.pays;
    // L'indicatif se cherche avec ou sans le « + » : on tape rarement le signe.
    final qChiffres = q.replaceAll(RegExp(r"\D"), "");
    return widget.pays.where((p) {
      if (_plat(p.libelle).contains(q)) return true;
      if (qChiffres.isEmpty) return false;
      return p.prefix.replaceAll(RegExp(r"\D"), "").startsWith(qChiffres);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final muted = mutedOf(context, Colors.black54);
    final accent = accentOf(context);
    final liste = _filtres;

    return Scaffold(
      appBar: backAppBar(context, tr(context, 'choose_country')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _rechercheCtrl,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: tr(context, 'country_search_hint'),
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged: (v) => setState(() => _requete = v),
              ),
            ),
            Expanded(
              child: liste.isEmpty
                  ? Center(
                      child: Text(tr(context, 'no_country_found'),
                          style: TextStyle(color: muted)),
                    )
                  : ListView.builder(
                      itemCount: liste.length,
                      itemBuilder: (context, i) {
                        final p = liste[i];
                        final choisi = p.idPays == widget.idSelectionne;
                        return ListTile(
                          title: Text(p.libelle),
                          trailing: Text(
                            p.prefix,
                            style: TextStyle(
                              color: choisi ? accent : muted,
                              fontWeight:
                                  choisi ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                          // La coche marque le pays courant : sans elle, on ne
                          // sait pas ce qui est déjà choisi en arrivant.
                          leading: choisi
                              ? Icon(Icons.check, color: accent)
                              : const SizedBox(width: 24),
                          onTap: () => Navigator.of(context).pop(p),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
