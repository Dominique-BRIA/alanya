import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/e2ee/e2ee_media.dart' show ProtectionPdf;

/// Ce qu'a choisi l'expéditeur : [protection] nulle = aucune (impression
/// permise, pas de mot de passe — la copie sort comme avant).
typedef ChoixProtectionPdf = ({ProtectionPdf? protection});

/// LES PERMISSIONS D'UN PDF SENSIBLE, réglées UNE FOIS à l'envoi (24/10/2026,
/// demande du user) : autoriser l'impression ou non, mettre un mot de passe
/// ou non — et alors en saisir deux, ouverture et propriétaire.
///
/// Rend `null` si l'expéditeur renonce : l'envoi n'a pas lieu.
///
/// Elles valent pour tous les PDF sensibles de cet envoi. Elles s'appliquent
/// à la copie qui SORT d'Alanya (téléchargement) ; voir `ProtectionPdf`.
Future<ChoixProtectionPdf?> demanderProtectionPdf(
  BuildContext context, {
  required int nombre,
}) {
  return showDialog<ChoixProtectionPdf>(
    context: context,
    barrierDismissible: false,
    builder: (_) => DialogueProtectionPdf(nombre: nombre),
  );
}

/// Les mots de passe trop courts ne protègent rien : quatre caractères au
/// moins, comme un code.
const longueurMinMotDePassePdf = 4;

class DialogueProtectionPdf extends StatefulWidget {
  const DialogueProtectionPdf({super.key, required this.nombre});

  /// Le nombre de PDF sensibles concernés.
  final int nombre;

  @override
  State<DialogueProtectionPdf> createState() => _DialogueProtectionPdfState();
}

class _DialogueProtectionPdfState extends State<DialogueProtectionPdf> {
  final _ouverture = TextEditingController();
  final _proprietaire = TextEditingController();
  bool _imprimer = true;
  bool _motDePasse = false;
  bool _cacheOuverture = true;
  bool _cacheProprietaire = true;
  /// Les CLÉS des erreurs, traduites au `build` : `tr()` écoute la langue,
  /// ce qu'un gestionnaire d'appui n'a pas le droit de faire.
  String? _erreurOuverture;
  String? _erreurProprietaire;

  @override
  void dispose() {
    _ouverture.dispose();
    _proprietaire.dispose();
    super.dispose();
  }

  void _valider() {
    if (!_motDePasse) {
      Navigator.of(context).pop<ChoixProtectionPdf>((
        protection: _imprimer
            ? null
            : ProtectionPdf(
                imprimer: false,
                proprietaire: ProtectionPdf.proprietaireAuHasard(),
              ),
      ));
      return;
    }
    // Sans trim : un espace fait partie du mot de passe. Seule règle : la
    // longueur, quels que soient les caractères. Les deux mots de passe
    // PEUVENT être identiques (choix du user, 24/10/2026) — le lecteur PDF
    // donne alors les droits du propriétaire, impression comprise, à qui
    // ouvre avec ce mot.
    final o = _ouverture.text;
    final p = _proprietaire.text;
    final eo = o.length < longueurMinMotDePassePdf ? 'pdfp_trop_court' : null;
    final ep = p.length < longueurMinMotDePassePdf ? 'pdfp_trop_court' : null;
    if (eo != null || ep != null) {
      setState(() {
        _erreurOuverture = eo;
        _erreurProprietaire = ep;
      });
      return;
    }
    Navigator.of(context).pop<ChoixProtectionPdf>((
      protection: ProtectionPdf(
        imprimer: _imprimer,
        ouverture: o,
        proprietaire: p,
      ),
    ));
  }

  Widget _champ({
    required TextEditingController ctrl,
    required String libelle,
    required String aide,
    required String? erreur,
    required bool cache,
    required VoidCallback basculer,
    required Key cle,
    TextInputAction action = TextInputAction.next,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextField(
      key: cle,
      controller: ctrl,
      obscureText: cache,
      textInputAction: action,
      onSubmitted: action == TextInputAction.done ? (_) => _valider() : null,
      decoration: InputDecoration(
        labelText: libelle,
        helperText: aide,
        helperMaxLines: 3,
        errorText: erreur == null
            ? null
            : tr(context, erreur, {'n': '$longueurMinMotDePassePdf'}),
        errorMaxLines: 3,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          icon: Icon(cache ? Icons.visibility : Icons.visibility_off),
          onPressed: basculer,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr(context, 'pdfp_titre')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(
                context,
                widget.nombre > 1 ? 'pdfp_intro_plusieurs' : 'pdfp_intro',
                {'n': '${widget.nombre}'},
              ),
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              key: const Key('pdfp_imprimer'),
              contentPadding: EdgeInsets.zero,
              value: _imprimer,
              onChanged: (v) => setState(() => _imprimer = v),
              title: Text(tr(context, 'pdfp_imprimer')),
              secondary: const Icon(Icons.print_outlined),
            ),
            SwitchListTile(
              key: const Key('pdfp_mot_de_passe'),
              contentPadding: EdgeInsets.zero,
              value: _motDePasse,
              onChanged: (v) => setState(() => _motDePasse = v),
              title: Text(tr(context, 'pdfp_mot_de_passe')),
              subtitle: Text(
                tr(context, 'pdfp_mot_de_passe_aide'),
                style: const TextStyle(fontSize: 12),
              ),
              secondary: const Icon(Icons.password),
            ),
            if (_motDePasse) ...[
              _champ(
                cle: const Key('pdfp_ouverture'),
                ctrl: _ouverture,
                libelle: tr(context, 'pdfp_ouverture'),
                aide: tr(context, 'pdfp_ouverture_aide'),
                erreur: _erreurOuverture,
                cache: _cacheOuverture,
                basculer: () =>
                    setState(() => _cacheOuverture = !_cacheOuverture),
              ),
              _champ(
                cle: const Key('pdfp_proprietaire'),
                ctrl: _proprietaire,
                libelle: tr(context, 'pdfp_proprietaire'),
                aide: tr(context, 'pdfp_proprietaire_aide'),
                erreur: _erreurProprietaire,
                cache: _cacheProprietaire,
                basculer: () =>
                    setState(() => _cacheProprietaire = !_cacheProprietaire),
                action: TextInputAction.done,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr(context, 'cancel')),
        ),
        FilledButton(
          key: const Key('pdfp_valider'),
          onPressed: _valider,
          child: Text(tr(context, 'continue')),
        ),
      ],
    );
  }
}
