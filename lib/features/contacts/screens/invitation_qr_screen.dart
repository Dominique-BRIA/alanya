import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/alanya_id_formatter.dart';
import '../../../core/api_client.dart';
import '../../../core/app_snackbar.dart';
import '../../../core/realtime_client.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/invitation_qr.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/avatar_circle.dart';
import '../../../widgets/back_app_bar.dart';
import '../../../widgets/qr_alanya.dart';
import '../../auth/auth_controller.dart';
import '../contacts_repository.dart';

/// Diamètre du médaillon de la photo, qui déborde le haut de la carte.
const double _kMedaillon = 84;

/// Ce que « Partager » envoie, au choix de l'utilisateur.
enum _ModePartage { lien, image }

/// INVITER PAR UN QR CODE À USAGE UNIQUE (15 minutes).
///
/// Le QR mène à `https://alanyavox.com/i/<jeton>`. Celui qui l'utilise — en
/// le scannant, en cliquant le lien, ou en lisant l'image depuis sa galerie —
/// et l'utilisateur s'ajoutent mutuellement aux contacts, et leur
/// conversation s'ouvre.
///
/// 🔁 11/11/2026 : présentation et envoi repris de l'application de
/// référence, adaptés à Alanya Work :
///  - LA CARTE PORTE L'IDENTITÉ : photo en médaillon, nom, Alanya ID, le QR et
///    son compte à rebours. C'est elle qui part quand on envoie l'image : le
///    destinataire sait de qui vient le code et combien de temps il vit ;
///  - UN SEUL BOUTON « PARTAGER », qui demande quoi envoyer : le LIEN (texte :
///    se clique dans WhatsApp, un SMS…) ou l'IMAGE (à scanner, ou à lire
///    depuis la galerie). Deux envois distincts plutôt qu'un mélange : sur
///    Android, la plupart des messageries ignorent le texte joint à une image ;
///  - LE TEXTE DU LIEN porte aussi le nom et l'Alanya ID : le code meurt en
///    15 minutes, l'Alanya ID reste le chemin permanent ;
///  - LE CODE SE RENOUVELLE SEUL : à son expiration, et dès qu'il a été
///    utilisé (trame `invitation_utilisee` du serveur) — un code mort ne reste
///    jamais à l'écran. « Nouveau QR » reste disponible à tout moment.
///
/// Les invitations précédentes restent valables jusqu'à leur terme (décision
/// du user : pas d'annulation).
class InvitationQrScreen extends StatefulWidget {
  const InvitationQrScreen({super.key});

  @override
  State<InvitationQrScreen> createState() => _InvitationQrScreenState();
}

class _InvitationQrScreenState extends State<InvitationQrScreen> {
  /// Ce qui est capturé pour « Partager l'image » : la carte entière.
  final _carteKey = GlobalKey();

  InvitationCreee? _invitation;
  DateTime? _finLocale;
  Duration _reste = Duration.zero;
  Timer? _tic;
  bool _chargement = false;
  bool _partage = false;
  String? _erreur;
  StreamSubscription<Map<String, dynamic>>? _rtSub;

  /// Une réponse tardive d'un code déjà remplacé est ignorée.
  int _generation = 0;

  bool get _expiree => _invitation != null && _reste <= Duration.zero;

  @override
  void initState() {
    super.initState();
    _rtSub = context.read<RealtimeClient>().events.listen(_surTrame);
    _creer();
  }

  @override
  void dispose() {
    _tic?.cancel();
    _rtSub?.cancel();
    super.dispose();
  }

  Future<void> _creer() async {
    final generation = ++_generation;
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    final repo = context.read<ContactsRepository>();
    final limite = tr(context, 'invqr_rate_limited');
    final echec = tr(context, 'invqr_create_failed');
    try {
      final inv = await repo.creerInvitation();
      if (!mounted || generation != _generation) return;
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
      if (!mounted || generation != _generation) return;
      setState(() {
        _chargement = false;
        _erreur = e.statusCode == 429 ? limite : echec;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _chargement = false;
        _erreur = echec;
      });
    }
  }

  /// À zéro, un nouveau code est demandé sans geste de l'utilisateur. S'il
  /// ne vient pas (réseau, trop de codes), le code mort est voilé et le bouton
  /// « Nouveau QR » prend le relais.
  void _rafraichir() {
    final fin = _finLocale;
    if (!mounted || fin == null) return;
    final reste = fin.difference(DateTime.now());
    setState(() => _reste = reste.isNegative ? Duration.zero : reste);
    if (_reste == Duration.zero) {
      _tic?.cancel();
      if (!_chargement) _creer();
    }
  }

  /// Notre invitation vient d'être utilisée : un code neuf, et l'on dit par qui.
  Future<void> _surTrame(Map<String, dynamic> e) async {
    if (e["type"] != "invitation_utilisee") return;
    final inv = _invitation;
    if (inv == null || e["jeton"] != inv.jeton) return;
    unawaited(_creer());

    final parId = "${e["parId"] ?? ""}";
    final repo = context.read<ContactsRepository>();
    final quelquun = tr(context, 'invqr_used_someone');
    String? nom;
    try {
      // Le serveur ne transmet que des identifiants : le nom vient de mes
      // contacts, où la personne vient d'entrer.
      final contacts = await repo.list();
      for (final c in contacts) {
        if (c.userId == parId) nom = c.displayName;
      }
    } catch (_) {}
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    showAppSnackBar(nom == null ? quelquun : tr(context, 'invqr_used_by', {'nom': nom}));
  }

  String _mmss(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ---------------------------------------------------------------------------
  // IDENTITÉ AFFICHÉE
  // ---------------------------------------------------------------------------

  String _nom() {
    final u = context.read<AuthController>().user;
    final nom = u?.nom?.trim();
    if (nom != null && nom.isNotEmpty) return nom;
    final pseudo = u?.pseudo?.trim();
    if (pseudo != null && pseudo.isNotEmpty) return pseudo;
    return u == null ? 'Alanya Work' : formatAlanyaId(u.publicNumber);
  }

  String _alanyaId() {
    final n = context.read<AuthController>().user?.publicNumber ?? '';
    return n.isEmpty ? '' : formatAlanyaId(n);
  }

  // ---------------------------------------------------------------------------
  // PARTAGE
  // ---------------------------------------------------------------------------

  String _texteDePartage(InvitationCreee inv) => tr(context, 'invqr_share_text2', {
        'nom': _nom(),
        'id': _alanyaId(),
        'lien': inv.lien,
      });

  Future<void> _partager() async {
    if (_invitation == null || _expiree) return;
    final choix = await showModalBottomSheet<_ModePartage>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text(
                tr(ctx, 'invqr_share_sheet_title'),
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: Text(tr(ctx, 'invqr_share_link')),
              subtitle: Text(tr(ctx, 'invqr_share_link_hint')),
              onTap: () => Navigator.pop(ctx, _ModePartage.lien),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: Text(tr(ctx, 'invqr_share_image')),
              subtitle: Text(tr(ctx, 'invqr_share_image_hint')),
              onTap: () => Navigator.pop(ctx, _ModePartage.image),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || choix == null) return;
    await (choix == _ModePartage.lien ? _partagerLien() : _partagerImage());
  }

  Future<void> _partagerLien() async {
    final inv = _invitation;
    if (inv == null || _expiree) return;
    await SharePlus.instance.share(
      ShareParams(text: _texteDePartage(inv), subject: 'Alanya Work'),
    );
  }

  /// Capture la carte à l'écran en PNG, puis la partage. Si la capture
  /// échoue, on n'envoie pas un partage vide : on retombe sur le lien.
  Future<void> _partagerImage() async {
    final inv = _invitation;
    if (inv == null || _expiree || _partage) return;
    setState(() => _partage = true);
    final legende = tr(context, 'invqr_image_caption');
    try {
      final rendu =
          _carteKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
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
      await _partagerLien();
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _carte(),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: (_expiree || _partage) ? null : _partager,
                icon: _partage
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.ios_share, size: 20),
                label: Text(tr(context, 'invqr_share')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _chargement ? null : _creer,
                icon: _chargement
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.autorenew, size: 20),
                label: Text(tr(context, 'invqr_new')),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: _expiree ? null : _copierLien,
          icon: const Icon(Icons.copy, size: 18),
          label: Text(tr(context, 'invqr_copy_link')),
        ),
        if (_erreur != null) ...[
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

  /// La carte capturée pour le partage : fond blanc dans tous les thèmes (un
  /// QR sur fond foncé se scanne mal), photo en médaillon au-dessus.
  Widget _carte() {
    final u = context.watch<AuthController>().user;
    final nom = _nom();
    final id = _alanyaId();
    return RepaintBoundary(
      key: _carteKey,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Container(
            margin: const EdgeInsets.only(top: _kMedaillon / 2),
            padding: const EdgeInsets.fromLTRB(18, _kMedaillon / 2 + 10, 18, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  nom,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF1F2328),
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (id.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    tr(context, 'home_alanya_id', {'id': id}),
                    style: const TextStyle(
                      color: AlanyaColors.logoVert,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    QrAlanya(data: _invitation!.lien, size: 220),
                    // Code mort et pas encore remplacé : voilé plutôt que
                    // retiré, pour que l'on comprenne ce qui se passe.
                    if (_expiree)
                      Positioned.fill(
                        child: ColoredBox(
                          color: Colors.white.withValues(alpha: 0.92),
                          child: Center(
                            child: _chargement
                                ? const CircularProgressIndicator()
                                : Text(
                                    tr(context, 'invqr_expired'),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Color(0xFF1F2328),
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                // Le décompte vit SUR la carte : il fait partie de ce que dit
                // le code (« je suis temporaire »), image partagée comprise.
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: AlanyaColors.logoVert.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.timer_outlined, size: 16, color: AlanyaColors.logoVert),
                      const SizedBox(width: 6),
                      Text(
                        _expiree
                            ? tr(context, 'invqr_expired')
                            : tr(context, 'invqr_expires_in', {'temps': _mmss(_reste)}),
                        style: const TextStyle(
                          color: AlanyaColors.logoVert,
                          fontWeight: FontWeight.w600,
                          fontFeatures: [ui.FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  tr(context, 'invqr_card_note'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF5B6168), fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  'Alanya Work · ${tr(context, 'invqr_single_use')}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF8A9096), fontSize: 11.5),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: AvatarCircle(
              name: nom,
              avatarUrl: u?.avatarUrl,
              radius: (_kMedaillon - 8) / 2,
              backgroundColor: AlanyaColors.gold,
            ),
          ),
        ],
      ),
    );
  }
}
