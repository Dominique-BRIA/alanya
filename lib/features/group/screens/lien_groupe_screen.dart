import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/api_client.dart';
import '../../../core/app_snackbar.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/groupe_lien.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/avatar_circle.dart';
import '../../../widgets/back_app_bar.dart';
import '../../../widgets/qr_alanya.dart';
import '../../chat/chat_repository.dart';

/// LE LIEN ET LE QR CODE D'UN GROUPE (18/11/2026).
///
/// Ouvert depuis les infos du groupe par ceux qui peuvent ajouter des membres
/// (le serveur le vérifie aussi). Partager le lien, partager le QR en image,
/// copier ; un admin peut le RÉINITIALISER : l'ancien lien et l'ancien QR ne
/// mènent alors plus nulle part.
///
/// Le texte sous le code dit ce que fait le lien, selon le type du groupe :
/// entrer directement (public) ou demander (privé).
class LienGroupeScreen extends StatefulWidget {
  const LienGroupeScreen({
    super.key,
    required this.convId,
    required this.nom,
    required this.avatarUrl,
    required this.estAdmin,
  });

  final String convId;
  final String nom;
  final String? avatarUrl;
  final bool estAdmin;

  @override
  State<LienGroupeScreen> createState() => _LienGroupeScreenState();
}

class _LienGroupeScreenState extends State<LienGroupeScreen> {
  final _carteKey = GlobalKey();
  LienGroupe? _lien;
  bool _chargement = true;
  bool _partage = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    final repo = context.read<ChatRepository>();
    final echec = trLu(context, 'grp_link_load_failed');
    try {
      final l = await repo.lienDuGroupe(widget.convId);
      if (mounted) setState(() => _lien = l);
    } on ApiException catch (e) {
      if (mounted) setState(() => _erreur = e.statusCode == 403 ? trLu(context, 'grp_link_admins_only') : echec);
    } catch (_) {
      if (mounted) setState(() => _erreur = echec);
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  Future<void> _reinitialiser() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'grp_link_reset_confirm_title')),
        content: Text(tr(ctx, 'grp_link_reset_confirm_text')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(ctx, 'cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr(ctx, 'grp_link_reset'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final repo = context.read<ChatRepository>();
    final fait = trLu(context, 'grp_link_reset_done');
    final echec = trLu(context, 'grp_link_load_failed');
    setState(() => _chargement = true);
    try {
      final l = await repo.renouvelerLienDuGroupe(widget.convId);
      if (!mounted) return;
      setState(() => _lien = l);
      showAppSnackBar(fait);
    } catch (_) {
      showAppSnackBar(echec);
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  String _texteDePartage(LienGroupe l) =>
      trLu(context, 'grp_link_share_text', {'name': widget.nom, 'link': l.lien});

  Future<void> _partagerLien() async {
    final l = _lien;
    if (l == null) return;
    await SharePlus.instance.share(ShareParams(text: _texteDePartage(l), subject: widget.nom));
  }

  /// La carte à l'écran en PNG ; si la capture échoue, on partage le lien.
  Future<void> _partagerImage() async {
    final l = _lien;
    if (l == null || _partage) return;
    setState(() => _partage = true);
    try {
      final rendu = _carteKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (rendu == null) throw StateError('carte absente');
      final image = await rendu.toImage(pixelRatio: 3);
      final octets = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (octets == null) throw StateError('PNG vide');
      final dossier = await getTemporaryDirectory();
      final fichier = File('${dossier.path}/alanya-groupe.png');
      await fichier.writeAsBytes(octets.buffer.asUint8List(), flush: true);
      if (!mounted) return;
      await SharePlus.instance.share(ShareParams(
        files: [XFile(fichier.path, mimeType: 'image/png')],
        text: _texteDePartage(l),
      ));
    } catch (_) {
      await _partagerLien();
    } finally {
      if (mounted) setState(() => _partage = false);
    }
  }

  void _copier() {
    final l = _lien;
    if (l == null) return;
    Clipboard.setData(ClipboardData(text: l.lien));
    HapticFeedback.selectionClick();
    showAppSnackBar(tr(context, 'grp_link_copied'));
  }

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    return Scaffold(
      backgroundColor: s.fond,
      appBar: backAppBar(context, tr(context, 'grp_link_title')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: _contenu(),
          ),
        ),
      ),
    );
  }

  Widget _contenu() {
    final l = _lien;
    if (_chargement && l == null) {
      return const Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator());
    }
    if (l == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_erreur ?? '', textAlign: TextAlign.center, style: TextStyle(color: dangerOf(context))),
          const SizedBox(height: 16),
          FilledButton(onPressed: _charger, child: Text(tr(context, 'retry'))),
        ],
      );
    }
    final muted = mutedOf(context, Colors.black54);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RepaintBoundary(key: _carteKey, child: _carte(l)),
        const SizedBox(height: 14),
        Text(
          tr(context, l.acces == 'public' ? 'grp_type_public_sub' : 'grp_type_private_sub'),
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, fontSize: 13),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _partage ? null : _partagerLien,
                icon: const Icon(Icons.link, size: 20),
                label: Text(tr(context, 'grp_link_share')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _partage ? null : _partagerImage,
                icon: _partage
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.qr_code_2, size: 20),
                label: Text(tr(context, 'grp_link_share_qr')),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: _copier,
          icon: const Icon(Icons.copy, size: 18),
          label: Text(tr(context, 'grp_link_copy')),
        ),
        if (widget.estAdmin)
          TextButton.icon(
            onPressed: _chargement ? null : _reinitialiser,
            icon: Icon(Icons.autorenew, size: 18, color: dangerOf(context)),
            label: Text(tr(context, 'grp_link_reset'), style: TextStyle(color: dangerOf(context))),
          ),
      ],
    );
  }

  /// La carte capturée pour le partage : fond blanc dans tous les thèmes (un
  /// QR sur fond foncé se scanne mal).
  Widget _carte(LienGroupe l) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AvatarCircle(name: widget.nom, avatarUrl: widget.avatarUrl, radius: 28),
          const SizedBox(height: 10),
          Text(
            widget.nom,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF1F2328), fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(l.acces == 'public' ? Icons.public : Icons.lock_outline,
                  size: 14, color: const Color(0xFF6B7280)),
              const SizedBox(width: 4),
              Text(
                tr(context, l.acces == 'public' ? 'grp_type_public' : 'grp_type_private'),
                style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 10),
          QrAlanya(data: l.lien, size: 210),
          const SizedBox(height: 8),
          Text(
            tr(context, 'grp_link_qr_hint'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
          ),
        ],
      ),
    );
  }
}
