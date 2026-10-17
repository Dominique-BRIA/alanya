import 'dart:async';
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
import '../../../models/invitation_qr.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/back_app_bar.dart';
import '../../../widgets/qr_alanya.dart';
import '../contacts_repository.dart';

/// INVITER PAR UN QR CODE À USAGE UNIQUE (15 minutes).
///
/// Le QR mène à `https://alanyavox.com/i/<jeton>`. Celui qui l'utilise — en
/// le scannant, en cliquant le lien, ou en lisant l'image depuis sa galerie —
/// et l'utilisateur s'ajoutent mutuellement aux contacts, et leur
/// conversation s'ouvre.
///
/// Deux façons de le transmettre, au choix (demande du user) :
///   · LE LIEN, en texte — se clique directement dans WhatsApp, Facebook… ;
///   · L'IMAGE du QR — se scanne avec un autre téléphone, ou se lit depuis
///     la galerie (bouton « Choisir une image » du scanner).
///
/// Une invitation est créée à l'ouverture de l'écran ; « Nouveau QR » en crée
/// une autre quand elle a expiré. Les précédentes restent valables jusqu'à
/// leur terme (décision du user : pas d'annulation).
class InvitationQrScreen extends StatefulWidget {
  const InvitationQrScreen({super.key});

  @override
  State<InvitationQrScreen> createState() => _InvitationQrScreenState();
}

class _InvitationQrScreenState extends State<InvitationQrScreen> {
  /// Ce qui est capturé pour « Partager l'image » : la carte blanche, logo et
  /// mention compris, et pas seulement les modules du QR.
  final _carteKey = GlobalKey();

  InvitationCreee? _invitation;
  DateTime? _finLocale;
  Duration _reste = Duration.zero;
  Timer? _tic;
  bool _chargement = false;
  bool _partage = false;
  String? _erreur;

  bool get _expiree => _invitation != null && _reste <= Duration.zero;

  @override
  void initState() {
    super.initState();
    _creer();
  }

  @override
  void dispose() {
    _tic?.cancel();
    super.dispose();
  }

  Future<void> _creer() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    final repo = context.read<ContactsRepository>();
    final limite = tr(context, 'invqr_rate_limited');
    final echec = tr(context, 'invqr_create_failed');
    try {
      final inv = await repo.creerInvitation();
      if (!mounted) return;
      _tic?.cancel();
      setState(() {
        _invitation = inv;
        // Fin calculée sur l'horloge du téléphone À LA RÉCEPTION (voir
        // `InvitationCreee.duree`) : un téléphone mal réglé afficherait
        // sinon un compte à rebours faux.
        _finLocale = DateTime.now().add(inv.duree);
        _reste = inv.duree;
        _chargement = false;
      });
      _tic = Timer.periodic(const Duration(seconds: 1), (_) => _rafraichir());
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _chargement = false;
        _erreur = e.statusCode == 429 ? limite : echec;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _chargement = false;
        _erreur = echec;
      });
    }
  }

  void _rafraichir() {
    final fin = _finLocale;
    if (!mounted || fin == null) return;
    final reste = fin.difference(DateTime.now());
    setState(() => _reste = reste.isNegative ? Duration.zero : reste);
    if (_reste == Duration.zero) _tic?.cancel();
  }

  String _mmss(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ---------------------------------------------------------------------------
  // PARTAGE
  // ---------------------------------------------------------------------------

  Future<void> _partagerLien() async {
    final inv = _invitation;
    if (inv == null || _expiree) return;
    await SharePlus.instance.share(
      ShareParams(
        text: tr(context, 'invqr_share_text', {'lien': inv.lien}),
        subject: 'Alanya Work',
      ),
    );
  }

  /// Capture la carte à l'écran en PNG, puis la partage.
  ///
  /// ⚠️ La légende ne porte PAS le lien : c'est le choix « image » ; qui veut
  /// le lien a son propre bouton. Elle dit seulement quoi faire de l'image.
  Future<void> _partagerImage() async {
    if (_invitation == null || _expiree || _partage) return;
    setState(() => _partage = true);
    final legende = tr(context, 'invqr_image_caption');
    final echec = tr(context, 'error_unexpected');
    try {
      final rendu =
          _carteKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (rendu == null) throw StateError('carte absente');
      // ×3 : l'image reste nette une fois recompressée par les messageries.
      final image = await rendu.toImage(pixelRatio: 3);
      final octets = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (octets == null) throw StateError('PNG vide');

      final dossier = await getTemporaryDirectory();
      final fichier = File('${dossier.path}/alanya-invitation.png');
      await fichier.writeAsBytes(octets.buffer.asUint8List(), flush: true);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(fichier.path, mimeType: 'image/png')],
          text: legende,
        ),
      );
    } catch (_) {
      showAppSnackBar(echec);
    } finally {
      if (mounted) setState(() => _partage = false);
    }
  }

  void _copierLien() {
    final inv = _invitation;
    if (inv == null || _expiree) return;
    Clipboard.setData(ClipboardData(text: inv.lien));
    HapticFeedback.selectionClick();
    showAppSnackBar(tr(context, 'invqr_link_copied'));
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    return Scaffold(
      backgroundColor: s.fond,
      appBar: backAppBar(context, tr(context, 'invqr_title')),
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
    if (_chargement && _invitation == null) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: CircularProgressIndicator(),
      );
    }
    if (_erreur != null && _invitation == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _erreur!,
            textAlign: TextAlign.center,
            style: TextStyle(color: dangerOf(context)),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _creer, child: Text(tr(context, 'retry'))),
        ],
      );
    }

    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            // La carte capturée pour le partage : fond blanc dans tous les
            // thèmes, comme le QR lui-même.
            RepaintBoundary(
              key: _carteKey,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    QrAlanya(data: _invitation!.lien, size: 230),
                    const SizedBox(height: 6),
                    const Text(
                      'Alanya Work',
                      style: TextStyle(
                        color: AlanyaColors.logoVert,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tr(context, 'invqr_single_use'),
                      style: const TextStyle(
                        color: Color(0xFF5B6168),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Expirée : on voile le QR plutôt que de le retirer, pour que
            // l'utilisateur comprenne ce qui s'est passé.
            if (_expiree)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Center(
                    child: Text(
                      tr(context, 'invqr_expired'),
                      style: const TextStyle(
                        color: Color(0xFF1F2328),
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          _expiree
              ? tr(context, 'invqr_expired')
              : tr(context, 'invqr_expires_in', {'temps': _mmss(_reste)}),
          style: TextStyle(
            color: _expiree ? dangerOf(context) : cs.onSurface,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFeatures: const [ui.FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 24),
        if (_expiree)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _chargement ? null : _creer,
              icon: const Icon(Icons.refresh),
              label: Text(tr(context, 'invqr_new')),
            ),
          )
        else ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _partagerLien,
              icon: const Icon(Icons.link),
              label: Text(tr(context, 'invqr_share_link')),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _partage ? null : _partagerImage,
              icon: _partage
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.image_outlined),
              label: Text(tr(context, 'invqr_share_image')),
            ),
          ),
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: _copierLien,
            icon: const Icon(Icons.copy, size: 18),
            label: Text(tr(context, 'invqr_copy_link')),
          ),
        ],
        if (_erreur != null && _invitation != null) ...[
          const SizedBox(height: 8),
          Text(
            _erreur!,
            textAlign: TextAlign.center,
            style: TextStyle(color: dangerOf(context)),
          ),
        ],
      ],
    );
  }
}
