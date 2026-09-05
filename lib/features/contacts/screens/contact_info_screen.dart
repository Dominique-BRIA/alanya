import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api_client.dart';
import '../../../core/alanya_id_formatter.dart';
import '../../../core/app_snackbar.dart';
import '../../../core/locale_controller.dart';
import '../../../core/memoire_langues.dart';
import '../../../core/traduction_appareil.dart';
import '../../../core/token_storage.dart';
import '../../../models/message.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/avatar_circle.dart';
import '../../../widgets/dialogues_traduction.dart';
import '../../../widgets/glass_card.dart';
import '../../../widgets/media/cached_media.dart';
import '../../account/screens/avatar_viewer_screen.dart';
import '../../calls/call_controller.dart';
import '../../calls/message_erreur_appel.dart';
import '../../calls/screens/active_call_screen.dart';
import '../../chat/chat_repository.dart';
import '../../chat/screens/shared_content_screen.dart';
import '../contacts_repository.dart';

/// Écran "Info Contact" — design premium glassmorphism, mode sombre prioritaire.
///
/// Sections :
///  - Header collapsible (dégradé + glass, avatar qui se réduit au scroll,
///    nom, statut en ligne / dernière connexion)
///  - Actions rapides : Appeler, Message, Vidéo (boutons ronds)
///  - Informations : numéro, bio, username (optionnel) — cartes glass
///  - Médias partagés : liste horizontale de miniatures arrondies
///  - Paramètres : sourdine (locale) + bloquer le contact
///
/// [contactId] est optionnel — présent quand on ouvre depuis la liste des
/// contacts (requis pour bloquer). [isOnline]/[lastSeen] alimentent le statut
/// (snapshot, pas de présence temps réel). [username] est optionnel.
class ContactInfoScreen extends StatefulWidget {
  const ContactInfoScreen({
    super.key,
    required this.userId,
    required this.name,
    required this.publicNumber,
    this.avatarUrl,
    this.statusMsg,
    this.username,
    this.convId,
    this.contactId,
    this.isBlocked = false,
    this.isOnline = false,
    this.lastSeen,
  });

  final String userId;
  final String name;
  final String publicNumber;
  final String? avatarUrl;
  final String? statusMsg;
  final String? username;
  final String? convId;
  final String? contactId;
  final bool isBlocked;
  final bool isOnline;
  final DateTime? lastSeen;

  @override
  State<ContactInfoScreen> createState() => _ContactInfoScreenState();
}

class _ContactInfoScreenState extends State<ContactInfoScreen> {
  static const double _expandedHeight = 300;

  late bool _isBlocked = widget.isBlocked;
  List<Message>? _sharedMedia;
  bool _loadingMedia = false;

  /// Garde-fou : l'appel peut passer par une création de conversation, donc
  /// par un aller-retour réseau. Sans ça, deux appuis lancent deux appels.
  bool _callStarting = false;
  String _baseUrl = "";
  String? _token;

  bool _muted = false;

  /// La langue FIXÉE pour ce correspondant, ou `null` pour « auto ».
  String? _langueFixee;

  String get _muteKey => "mute_${widget.convId ?? widget.userId}";

  @override
  void initState() {
    super.initState();
    _loadMuted();
    _loadLangue();
    _loadSharedMedia();
  }

  Future<void> _loadLangue() async {
    final fixee = await MemoireLangues.langueFixee(widget.userId);
    if (mounted) setState(() => _langueFixee = fixee);
  }

  Future<void> _loadMuted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) setState(() => _muted = prefs.getBool(_muteKey) ?? false);
    } catch (_) {}
  }

  Future<void> _toggleMuted(bool value) async {
    setState(() => _muted = value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_muteKey, value);
    } catch (_) {}
    // ⚠️ `tr()` LIT LE CONTEXTE, ce qu'un libellé en dur ne faisait pas :
    // l'écriture des préférences est asynchrone, l'écran a pu être quitté
    // entre-temps.
    if (!mounted) return;
    showAppSnackBar(
        value ? tr(context, 'ci_muted') : tr(context, 'ci_unmuted'));
  }

  Future<void> _loadSharedMedia() async {
    final convId = widget.convId;
    if (convId == null) return;
    setState(() => _loadingMedia = true);
    _baseUrl = context.read<ApiClient>().baseUrl;
    _token = await context.read<TokenStorage>().accessToken;
    try {
      final msgs = await context.read<ChatRepository>().getMessages(convId);
      if (!mounted) return;
      setState(() {
        _sharedMedia = msgs
            .where((m) =>
                (m.type == "IMAGE" || m.type == "VIDEO") && m.media.isNotEmpty)
            .toList();
        _loadingMedia = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMedia = false);
    }
  }

  Future<void> _toggleBlock() async {
    final contactId = widget.contactId;
    if (contactId == null) {
      showAppSnackBar(
          tr(context, 'ci_add_first_to_block'));
      return;
    }
    final newState = !_isBlocked;
    try {
      await context.read<ContactsRepository>().setBlocked(contactId, newState);
      if (!mounted) return;
      setState(() => _isBlocked = newState);
      showAppSnackBar(newState ? tr(context, 'ci_blocked') : tr(context, 'ci_unblocked'));
    } on ApiException catch (e) {
      showAppSnackBar(e.message);
    } catch (_) {
      showAppSnackBar(tr(context, 'action_failed'));
    }
  }

  /// Lance un appel depuis la fiche contact.
  ///
  /// La conversation est créée à la volée quand elle n'existe pas encore :
  /// [CallController.startOutgoing] exige un `convId`, et refuser d'appeler
  /// tant qu'on n'a pas ouvert une discussion (l'ancien comportement) n'avait
  /// aucune raison d'être — `createDirect` récupère la conversation existante
  /// ou la crée, sans effet de bord visible.
  Future<void> _startCall(String type) async {
    if (_callStarting) return;
    final cc = context.read<CallController>();
    setState(() => _callStarting = true);
    try {
      var convId = widget.convId;
      convId ??= await context
          .read<ChatRepository>()
          .createDirect(widget.publicNumber);
      if (!mounted) return;
      await cc.startOutgoing(convId, type, widget.name);
      if (!mounted) return;
      // Même enchaînement que depuis le fil de discussion : sans cette
      // ouverture, l'appel démarrait sans que rien ne s'affiche, seul le
      // bandeau global le signalait.
      await Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const ActiveCallScreen(),
        ),
      );
    } catch (e) {
      showAppSnackBar(messageErreurAppel(e));
    } finally {
      if (mounted) setState(() => _callStarting = false);
    }
  }

  void _openMessage() {
    // La fiche est ouverte depuis le chat → revenir affiche la conversation.
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      showAppSnackBar(tr(context, 'ci_open_from_home'));
    }
  }

  void _openAvatarViewer() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AvatarViewerScreen(
          name: widget.name,
          avatarUrl: widget.avatarUrl,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          _buildHeader(context),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              child: Column(
                children: [
                  _actionsRow(),
                  const SizedBox(height: 18),
                  _infoCard(),
                  const SizedBox(height: 16),
                  _sharedMediaCard(),
                  const SizedBox(height: 16),
                  _settingsCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HEADER collapsible (dégradé + glass, avatar qui se réduit au scroll)
  // ---------------------------------------------------------------------------
  Widget _buildHeader(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final topPad = MediaQuery.of(context).padding.top;
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: dark
          // Plus de `const` ici : surfacesOf() est un appel, pas une constante.
          // Le `const` de la branche claire est conservé, elle n'a pas changé.
          ? [AlanyaColors.indigo, surfacesOf(context).surface]
          : const [AlanyaColors.terracotta, AlanyaColors.forest],
    );

    return SliverAppBar(
      pinned: true,
      stretch: true,
      expandedHeight: _expandedHeight,
      backgroundColor:
          dark ? surfacesOf(context).surface : AlanyaColors.terracottaDark,
      foregroundColor: Colors.white,
      elevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      flexibleSpace: LayoutBuilder(
        builder: (context, constraints) {
          final maxH = _expandedHeight + topPad;
          final minH = kToolbarHeight + topPad;
          final h = constraints.maxHeight;
          // t = 1 (déployé) → 0 (replié).
          final t = ((h - minH) / (maxH - minH)).clamp(0.0, 1.0);
          final avatarRadius = 34 + 24 * t; // 34 → 58
          return Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(decoration: BoxDecoration(gradient: gradient)),
              // Voile sombre en bas pour la lisibilité du texte.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black26],
                  ),
                ),
              ),
              // Titre replié (apparaît quand le header se réduit).
              Positioned(
                top: topPad,
                left: 56,
                right: 56,
                height: kToolbarHeight,
                child: Opacity(
                  opacity: (1 - t * 1.6).clamp(0.0, 1.0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 20,
                child: Opacity(
                  opacity: (t * 1.4 - 0.15).clamp(0.0, 1.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: _openAvatarViewer,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.85),
                              width: 3,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.25),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: AvatarCircle(
                            name: widget.name,
                            avatarUrl: widget.avatarUrl,
                            radius: avatarRadius,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.22),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          widget.name,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      _presenceLine(),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _presenceLine() {
    final label = _presenceLabel();
    if (label == null) return const SizedBox.shrink();
    final online = widget.isOnline;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (online) ...[
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AlanyaColors.forestLight,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
        ],
        Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
            color: Colors.white.withValues(alpha: 0.92),
          ),
        ),
      ],
    );
  }

  String? _presenceLabel() {
    if (widget.isOnline) return tr(context, 'presence_online');
    final ls = widget.lastSeen;
    if (ls == null) return null;
    final diff = DateTime.now().difference(ls);
    if (diff.inMinutes < 1) return tr(context, 'presence_just_now');
    if (diff.inMinutes < 60) return tr(context, 'presence_min', {'n': '${diff.inMinutes}'});
    if (diff.inHours < 24) return tr(context, 'presence_hour', {'n': '${diff.inHours}'});
    return tr(context, 'presence_day', {'n': '${diff.inDays}'});
  }

  // ---------------------------------------------------------------------------
  // ACTIONS RAPIDES
  // ---------------------------------------------------------------------------
  Widget _actionsRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _RoundAction(
          icon: Icons.call_rounded,
          label: tr(context, 'call_action'),
          onTap: () => _startCall("AUDIO"),
        ),
        _RoundAction(
          icon: Icons.chat_bubble_rounded,
          label: tr(context, 'message_action'),
          onTap: _openMessage,
        ),
        _RoundAction(
          icon: Icons.videocam_rounded,
          label: tr(context, 'video'),
          onTap: () => _startCall("VIDEO"),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // INFORMATIONS
  // ---------------------------------------------------------------------------
  Widget _infoCard() {
    final bio = widget.statusMsg?.isNotEmpty == true
        ? widget.statusMsg!
        : tr(context, 'ci_default_invite');
    final username = widget.username;
    return GlassCard(
      radius: 22,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Column(
        children: [
          _infoRow(
            icon: Icons.phone_rounded,
            label: tr(context, 'phone'),
            value: "#${_formatNumber(widget.publicNumber)}",
            onTap: () {
              Clipboard.setData(ClipboardData(text: widget.publicNumber));
              showAppSnackBar(tr(context, 'number_copied'));
            },
            trailing: Icons.copy_rounded,
          ),
          _divider(),
          _infoRow(
            icon: Icons.info_outline_rounded,
            label: tr(context, 'about'),
            value: bio,
          ),
          if (username != null && username.isNotEmpty) ...[
            _divider(),
            _infoRow(
              icon: Icons.alternate_email_rounded,
              label: tr(context, 'username'),
              value: username,
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoRow({
    required IconData icon,
    required String label,
    required String value,
    VoidCallback? onTap,
    IconData? trailing,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 22, color: accentOf(context)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: cs.onSurface,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 10),
                Icon(trailing, size: 18, color: cs.onSurfaceVariant),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _divider() {
    final cs = Theme.of(context).colorScheme;
    return Divider(
      height: 1,
      thickness: 0.5,
      indent: 48,
      endIndent: 12,
      color: cs.onSurface.withValues(alpha: 0.08),
    );
  }

  // ---------------------------------------------------------------------------
  // MÉDIAS PARTAGÉS
  // ---------------------------------------------------------------------------
  Widget _sharedMediaCard() {
    final cs = Theme.of(context).colorScheme;
    final hasConv = widget.convId != null;
    final recent = (_sharedMedia ?? const <Message>[]).take(8).toList();
    return GlassCard(
      radius: 22,
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      onTap: hasConv
          ? () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SharedContentScreen(
                    convId: widget.convId!, title: widget.name),
              ))
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.perm_media_rounded,
                  size: 20, color: accentOf(context)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tr(context, 'shared_media'),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: cs.onSurface,
                  ),
                ),
              ),
              if (_loadingMedia)
                const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
              else
                Text("${_sharedMedia?.length ?? 0}",
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
              Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
            ],
          ),
          if (recent.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: SizedBox(
                height: 76,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: recent.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final m = recent[i];
                    final media = m.media.first;
                    final isVideo = m.type == "VIDEO";
                    final url = '$_baseUrl${media.url}?token=$_token';
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        width: 76,
                        height: 76,
                        child: isVideo
                            ? const ColoredBox(
                                color: Color(0xFF1A1A2E),
                                child: Icon(Icons.play_circle_fill_rounded,
                                    color: Colors.white70, size: 30),
                              )
                            : CachedMedia(
                                url: url,
                                width: 76,
                                height: 76,
                                fit: BoxFit.cover),
                      ),
                    );
                  },
                ),
              ),
            ),
          if (_sharedMedia != null && _sharedMedia!.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(tr(context, 'no_shared_media'),
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PARAMÈTRES
  // ---------------------------------------------------------------------------
  /// LA LANGUE DU CORRESPONDANT — « auto » par défaut.
  ///
  /// 🔴 POURQUOI CE RÉGLAGE EXISTE (demande du user, 31/08/2026). La détection
  /// automatique se trompe souvent : « merci » est français, portugais et
  /// proche de l'italien, et un message de trois mots n'a pas de quoi trancher.
  /// L'utilisateur, lui, SAIT dans quelle langue son interlocuteur écrit. Le
  /// lui demander une fois vaut mieux que le deviner cent fois.
  ///
  /// ⚠️ « AUTO » N'EST PAS UNE LANGUE : c'est l'absence de consigne, et donc le
  /// mécanisme actuel — détection, puis mémoire de ce qu'on a observé chez
  /// cette personne. Le défaut ne s'écrit nulle part : ne rien stocker dit
  /// déjà « devine ».
  ///
  /// Une langue fixée PRIME sur tout, et l'observation cesse de la corriger
  /// (voir `core/memoire_langues.dart`).
  Widget _ligneLangue(ColorScheme cs) {
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Icon(Icons.translate_rounded, color: accentOf(context)),
        title: Text(
          tr(context, 'ci_language_of', {'nom': widget.name}),
          style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w500, color: cs.onSurface),
        ),
        subtitle: Text(
          _langueFixee == null
              ? tr(context, 'lang_auto')
              : nomAutonyme(_langueFixee!),
          style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
        ),
        trailing: const Icon(Icons.chevron_right_rounded, size: 20),
        onTap: _choisirLangue,
      ),
    );
  }

  Future<void> _choisirLangue() async {
    final choix = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final langues = languesTraduisibles();
        return SafeArea(
          child: ListView.builder(
            shrinkWrap: true,
            // +1 : la première ligne est « Auto », qui n'est pas une langue.
            itemCount: langues.length + 1,
            itemBuilder: (_, i) {
              if (i == 0) {
                return ListTile(
                  leading: Icon(Icons.auto_awesome_outlined,
                      color: accentOf(context)),
                  title: Text(tr(context, 'lang_auto')),
                  trailing: _langueFixee == null
                      ? Icon(Icons.check, color: accentOf(context))
                      : null,
                  onTap: () => Navigator.pop(ctx, ""),
                );
              }
              final code = langues[i - 1].bcpCode;
              return ListTile(
                title: Text(nomAutonyme(code)),
                trailing: _langueFixee == code
                    ? Icon(Icons.check, color: accentOf(context))
                    : null,
                onTap: () => Navigator.pop(ctx, code),
              );
            },
          ),
        );
      },
    );
    if (choix == null || !mounted) return;
    // La chaîne vide porte « auto » : `null` voudrait dire « annulé », et les
    // deux ne se distingueraient plus au retour de la feuille.
    final langue = choix.isEmpty ? null : choix;
    await MemoireLangues.fixe(widget.userId, langue);
    if (!mounted) return;
    setState(() => _langueFixee = langue);
    showAppSnackBar(langue == null
        ? tr(context, 'lang_auto_detected')
        : tr(context, 'ci_read_as', {'nom': widget.name, 'langue': nomAutonyme(langue)}));
    if (langue != null) await _installeCoupleSiNecessaire(langue);
  }

  /// Installe le couple de langues DANS LA FOULÉE, une seule fois.
  ///
  /// 🔴 DEMANDE DU USER (31/08/2026), et c'est le bon moment : fixer la langue
  /// de quelqu'un, c'est annoncer qu'on va lire ses messages traduits. Attendre
  /// le premier message pour découvrir qu'il manque un modèle repousse le
  /// téléchargement au pire instant — celui où l'on veut lire, souvent sans
  /// Wi-Fi.
  ///
  /// ⚠️ « UNE FOIS » AU SENS STRICT : si le couple est déjà prêt, rien ne se
  /// passe et rien ne s'affiche. La question n'est reposée que si l'état change
  /// — modèle évincé par le système, ou langue de lecture changée.
  ///
  /// ⚠️ LE TÉLÉCHARGEMENT RESTE UN GESTE : la confirmation habituelle annonce
  /// le poids, et le repli données mobiles n'est proposé que si le Wi-Fi était
  /// bien la contrainte. On ne tire pas des dizaines de mégaoctets parce que
  /// quelqu'un a touché un menu.
  Future<void> _installeCoupleSiNecessaire(String source) async {
    final cible = context.read<LocaleController>().languageCode;
    final etat = await etatCouple(source, cible);
    if (!mounted) return;
    // `pret` : déjà là. `indisponible` : même langue que la mienne, ou langue
    // non traduisible — dans les deux cas il n'y a rien à télécharger, et
    // proposer une installation impossible serait trompeur.
    if (etat != EtatCouple.aTelecharger) return;

    final manquantes = await nomsLanguesManquantes(source, cible);
    if (!mounted) return;
    final libelle =
        manquantes.isEmpty ? nomAutonyme(source) : manquantes.join(" + ");
    if (!await confirmerInstallationLangues(context, libelle)) return;
    if (!mounted) return;

    var installe = await telechargerCouple(source, cible);
    if (!installe &&
        wifiExige &&
        mounted &&
        await proposerDonneesMobiles(context)) {
      installe = await telechargerCouple(source, cible, wifiSeulement: false);
    }
    if (!mounted) return;
    showAppSnackBar(installe
        ? tr(context, 'lang_installed', {'langue': nomAutonyme(source)})
        : tr(context, 'trans_install_failed'));
  }

  Widget _settingsCard() {
    final cs = Theme.of(context).colorScheme;
    return GlassCard(
      radius: 22,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Column(
        children: [
          SwitchListTile.adaptive(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            secondary: Icon(
              _muted
                  ? Icons.notifications_off_rounded
                  : Icons.notifications_rounded,
              color: accentOf(context),
            ),
            title: Text(
              tr(context, 'set_notifications'),
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurface),
            ),
            subtitle: Text(
              _muted ? tr(context, 'ci_muted_state') : tr(context, 'ci_active_state'),
              style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
            ),
            value: !_muted,
            activeColor: positiveOf(context),
            onChanged: (on) => _toggleMuted(!on),
          ),
          _divider(),
          _ligneLangue(cs),
          _divider(),
          Material(
            type: MaterialType.transparency,
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              leading: Icon(
                _isBlocked ? Icons.lock_open_rounded : Icons.block_rounded,
                color: AlanyaColors.error,
              ),
              title: Text(
                _isBlocked
                    ? tr(context, 'ci_unblock_name', {'nom': widget.name})
                    : tr(context, 'ci_block_name', {'nom': widget.name}),
                style: const TextStyle(
                    color: AlanyaColors.error,
                    fontWeight: FontWeight.w500,
                    fontSize: 15),
              ),
              onTap: _toggleBlock,
            ),
          ),
        ],
      ),
    );
  }

  String _formatNumber(String n) => formatAlanyaId(n);
}

/// Bouton d'action rond avec icône + label (micro-interaction au tap).
class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: accentOf(context).withValues(alpha: 0.12),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 60,
              height: 60,
              child: Icon(icon, color: accentOf(context), size: 26),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
