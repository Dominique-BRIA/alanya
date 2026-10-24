import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/e2ee/e2ee_media.dart' show ProtectionPdf;

/// Ce qu'on a déjà montré d'un mot de passe en VUE UNIQUE, par média.
///
/// ⚠️ LOCAL À L'APPAREIL, comme le mot de passe lui-même, qui n'existe que
/// dans l'enveloppe chiffrée : le serveur ne sait pas qu'il existe, il ne peut
/// donc pas compter les vues.
class VuesMotDePassePdf {
  VuesMotDePassePdf._();

  static String _cle(String mediaId) => 'pdf_mdp_vu.$mediaId';

  static Future<bool> dejaVu(String mediaId) async =>
      (await SharedPreferences.getInstance()).getBool(_cle(mediaId)) ?? false;

  static Future<void> marquerVu(String mediaId) async =>
      (await SharedPreferences.getInstance()).setBool(_cle(mediaId), true);
}

/// SOUS LE PDF SENSIBLE PROTÉGÉ (24/10/2026, demande du user) :
///
/// * chez l'EXPÉDITEUR, les mots de passe EN CLAIR — il les a choisis, il doit
///   pouvoir les retrouver ;
/// * chez le DESTINATAIRE, le mot de passe d'ouverture en VUE UNIQUE. Le
///   propriétaire ne lui est jamais montré : c'est lui qui lève l'interdiction
///   d'imprimer.
///
/// Et, des deux côtés, si l'impression est interdite, on le dit.
class InfosProtectionPdf extends StatefulWidget {
  const InfosProtectionPdf({
    super.key,
    required this.protection,
    required this.mediaId,
    required this.isMe,
    required this.couleurDiscrete,
  });

  final ProtectionPdf protection;
  final String mediaId;
  final bool isMe;
  final Color couleurDiscrete;

  @override
  State<InfosProtectionPdf> createState() => _InfosProtectionPdfState();
}

class _InfosProtectionPdfState extends State<InfosProtectionPdf> {
  /// `null` tant qu'on ne sait pas encore (lecture des préférences).
  bool? _vu;

  ProtectionPdf get p => widget.protection;

  @override
  void initState() {
    super.initState();
    if (!widget.isMe && p.avecMotDePasse) {
      VuesMotDePassePdf.dejaVu(widget.mediaId).then((v) {
        if (mounted) setState(() => _vu = v);
      });
    }
  }

  Future<void> _voir() async {
    // Marqué AVANT d'être montré : fermer l'application pendant l'affichage
    // ne doit pas offrir une seconde vue.
    await VuesMotDePassePdf.marquerVu(widget.mediaId);
    if (!mounted) return;
    setState(() => _vu = true);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'pdfp_mdp_ouverture_titre')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              p.ouverture!,
              key: const Key('pdfp_mdp_revele'),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              tr(ctx, 'pdfp_vue_unique_avis'),
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: p.ouverture!)),
            icon: const Icon(Icons.copy, size: 18),
            label: Text(tr(ctx, 'copy')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(tr(ctx, 'ok')),
          ),
        ],
      ),
    );
  }

  Widget _ligne(IconData icone, Widget texte) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icone, size: 15, color: widget.couleurDiscrete),
        const SizedBox(width: 6),
        Expanded(child: texte),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final discret = TextStyle(fontSize: 12, color: widget.couleurDiscrete);
    const fort = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      fontFamily: 'monospace',
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!p.imprimer)
          _ligne(
            Icons.print_disabled_outlined,
            Text(tr(context, 'pdfp_impression_interdite'), style: discret),
          ),
        if (p.avecMotDePasse && widget.isMe) ...[
          _ligne(
            Icons.lock_open_outlined,
            Text.rich(
              TextSpan(children: [
                TextSpan(text: '${tr(context, 'pdfp_ouverture')} : ', style: discret),
                TextSpan(text: p.ouverture, style: fort),
              ]),
              key: const Key('pdfp_mdp_expediteur'),
            ),
          ),
          _ligne(
            Icons.admin_panel_settings_outlined,
            Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: '${tr(context, 'pdfp_proprietaire')} : ',
                  style: discret,
                ),
                TextSpan(text: p.proprietaire, style: fort),
              ]),
            ),
          ),
        ],
        if (p.avecMotDePasse && !widget.isMe)
          if (_vu == false)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: TextButton.icon(
                key: const Key('pdfp_voir'),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _voir,
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: Text(tr(context, 'pdfp_voir_une_fois')),
              ),
            )
          else if (_vu == true)
            _ligne(
              Icons.visibility_off_outlined,
              Text(tr(context, 'pdfp_deja_vu'), style: discret),
            ),
      ],
    );
  }
}
