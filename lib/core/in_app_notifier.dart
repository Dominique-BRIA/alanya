import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/alanya_theme.dart';
import '../widgets/avatar_circle.dart';
import 'push_service.dart';

/// Type de heads-up actuellement affiché.
enum _Kind { none, message, call }

/// Modèle vivant d'un heads-up **message** (mis à jour en place pour le
/// regroupement intelligent — plusieurs messages du même contact fusionnés).
class _MsgModel {
  const _MsgModel({
    required this.title,
    required this.body,
    required this.count,
    this.avatarUrl,
  });

  final String title;
  final String body;
  final int count; // >1 → regroupement ("N nouveaux messages")
  final String? avatarUrl;

  _MsgModel copyWith({String? body, int? count}) => _MsgModel(
        title: title,
        body: body ?? this.body,
        count: count ?? this.count,
        avatarUrl: avatarUrl,
      );
}

/// Notificateur **in-app** (heads-up custom façon WhatsApp) affiché au-dessus
/// de toutes les pages via l'Overlay racine.
///
/// * Message : carte flottante glassmorphism, slide + fade, auto-disparition
///   (~3,5 s), cliquable, réponse rapide inline, regroupement par conversation.
/// * Appel : carte plus large et plus visible, persistante tant que l'appel
///   sonne, boutons Refuser / Répondre.
class InAppNotifier {
  InAppNotifier._();
  static final InAppNotifier instance = InAppNotifier._();

  static const Duration _messageTtl = Duration(milliseconds: 3500);

  OverlayEntry? _entry;
  Timer? _timer;
  _Kind _kind = _Kind.none;

  // Regroupement message.
  String? _groupKey;
  ValueNotifier<_MsgModel>? _msgModel;

  // Fonction d'animation de sortie fournie par le host actuellement monté.
  Future<void> Function()? _closeCurrent;

  /// Y a-t-il un heads-up d'appel affiché en ce moment ?
  bool get isShowingCall => _kind == _Kind.call;

  // ---------------------------------------------------------------------------
  // MESSAGE
  // ---------------------------------------------------------------------------
  void showMessage({
    required String title,
    required String body,
    String? avatarUrl,
    VoidCallback? onTap,
    String? groupKey,
    Future<void> Function(String text)? onQuickReply,
  }) {
    // Regroupement intelligent : nouveau message de la MÊME conversation alors
    // qu'un heads-up message est déjà affiché → on fusionne (compteur + dernier
    // aperçu) sans relancer l'animation d'entrée.
    if (_kind == _Kind.message &&
        _groupKey != null &&
        groupKey != null &&
        _groupKey == groupKey &&
        _msgModel != null) {
      final prev = _msgModel!.value;
      _msgModel!.value = prev.copyWith(body: body, count: prev.count + 1);
      _restartTimer(_messageTtl);
      return;
    }

    final overlay = PushService.navigatorKey.currentState?.overlay;
    if (overlay == null) return;

    _hardRemove(); // supersede tout heads-up en cours (sans animation de sortie)

    _kind = _Kind.message;
    _groupKey = groupKey;
    final model = ValueNotifier<_MsgModel>(
      _MsgModel(title: title, body: body, count: 1, avatarUrl: avatarUrl),
    );
    _msgModel = model;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _BannerHost(
        swipeToDismiss: true,
        onSwipe: _hardRemove,
        onReady: (close) => _closeCurrent = close,
        child: _MessageCard(
          model: model,
          onTap: () {
            dismiss();
            onTap?.call();
          },
          onQuickReply: onQuickReply,
          onReplyOpen: _pauseAutoDismiss,
          onSent: dismiss,
        ),
      ),
    );
    _entry = entry;
    overlay.insert(entry);
    _restartTimer(_messageTtl);
  }

  // ---------------------------------------------------------------------------
  // APPEL
  // ---------------------------------------------------------------------------
  /// Heads-up d'appel entrant : persistant, boutons Refuser / Répondre.
  void showCall({
    required String title,
    String? avatarUrl,
    bool isVideo = false,
    VoidCallback? onTap,
    VoidCallback? onAccept,
    VoidCallback? onReject,
  }) {
    final overlay = PushService.navigatorKey.currentState?.overlay;
    if (overlay == null) return;

    _hardRemove();
    _kind = _Kind.call;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _BannerHost(
        swipeToDismiss: false, // persistant : pas de glisser-pour-fermer
        onSwipe: () {},
        onReady: (close) => _closeCurrent = close,
        child: _CallCard(
          title: title,
          avatarUrl: avatarUrl,
          isVideo: isVideo,
          onTap: onTap,
          onAccept: onAccept == null
              ? null
              : () {
                  dismiss();
                  onAccept();
                },
          onReject: onReject == null
              ? null
              : () {
                  dismiss();
                  onReject();
                },
        ),
      ),
    );
    _entry = entry;
    overlay.insert(entry);
    // Pas de timer : l'appel reste affiché tant que l'appelant sonne. C'est le
    // CallListener qui appelle dismiss() quand l'appel est annulé/terminé.
  }

  /// Ferme uniquement si le heads-up courant est un appel (évite de fermer un
  /// message qui serait arrivé entre-temps).
  void dismissCall() {
    if (_kind == _Kind.call) dismiss();
  }

  // ---------------------------------------------------------------------------
  // FERMETURE / TIMERS
  // ---------------------------------------------------------------------------
  /// Ferme le heads-up courant avec l'animation de sortie.
  void dismiss() {
    _timer?.cancel();
    _timer = null;
    // Capture l'entrée courante pour la retirer une fois l'animation finie.
    final entry = _entry;
    final close = _closeCurrent;
    _closeCurrent = null;
    _entry = null;
    _kind = _Kind.none;
    _groupKey = null;
    _msgModel = null;
    if (close != null) {
      close().whenComplete(() {
        try {
          entry?.remove();
        } catch (_) {}
      });
    } else {
      try {
        entry?.remove();
      } catch (_) {}
    }
  }

  /// Retrait immédiat, sans animation (utilisé quand un nouveau heads-up
  /// remplace l'ancien, ou sur glisser-pour-fermer).
  void _hardRemove() {
    _timer?.cancel();
    _timer = null;
    _closeCurrent = null;
    try {
      _entry?.remove();
    } catch (_) {}
    _entry = null;
    _kind = _Kind.none;
    _groupKey = null;
    _msgModel = null;
  }

  void _restartTimer(Duration d) {
    _timer?.cancel();
    _timer = Timer(d, dismiss);
  }

  /// Suspend l'auto-disparition (pendant la saisie d'une réponse rapide).
  void _pauseAutoDismiss() {
    _timer?.cancel();
    _timer = null;
  }
}

// =============================================================================
// HOST — animation d'entrée/sortie (slide depuis le haut + fade) + glisser
// =============================================================================
class _BannerHost extends StatefulWidget {
  const _BannerHost({
    required this.child,
    required this.swipeToDismiss,
    required this.onSwipe,
    required this.onReady,
  });

  final Widget child;
  final bool swipeToDismiss;
  final VoidCallback onSwipe;

  /// Remonte au notificateur la fonction qui joue l'animation de sortie.
  final void Function(Future<void> Function() close) onReady;

  @override
  State<_BannerHost> createState() => _BannerHostState();
}

class _BannerHostState extends State<_BannerHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
    reverseDuration: const Duration(milliseconds: 240),
  );

  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, -1.15),
    end: Offset.zero,
  ).animate(CurvedAnimation(
    parent: _c,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  ));

  late final Animation<double> _fade = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    reverseCurve: Curves.easeIn,
  );

  @override
  void initState() {
    super.initState();
    _c.forward();
    widget.onReady(() async {
      if (!mounted) return;
      try {
        await _c.reverse();
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget card = SlideTransition(
      position: _slide,
      child: FadeTransition(opacity: _fade, child: widget.child),
    );

    if (widget.swipeToDismiss) {
      card = Dismissible(
        key: const ValueKey('inapp_heads_up'),
        direction: DismissDirection.up,
        onDismissed: (_) => widget.onSwipe(),
        child: card,
      );
    }

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: card,
        ),
      ),
    );
  }
}

// =============================================================================
// SURFACE GLASSMORPHISM commune
// =============================================================================
class _GlassSurface extends StatelessWidget {
  const _GlassSurface({
    required this.child,
    required this.radius,
    this.borderColor,
    this.glowColor,
    this.glowStrength = 0.18,
  });

  final Widget child;
  final double radius;
  final Color? borderColor;
  final Color? glowColor;
  final double glowStrength;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Fond semi-transparent (glassmorphism) + léger dégradé pour la profondeur.
    final Color fillTop = dark
        ? const Color(0xFF262019).withValues(alpha: 0.82)
        : Colors.white.withValues(alpha: 0.80);
    final Color fillBottom = dark
        ? const Color(0xFF1C1712).withValues(alpha: 0.78)
        : Colors.white.withValues(alpha: 0.68);
    final Color border = borderColor ??
        (dark
            ? Colors.white.withValues(alpha: 0.10)
            : Colors.white.withValues(alpha: 0.65));

    // Ombre douce portée à l'EXTÉRIEUR du ClipRRect (sinon elle serait rognée).
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: (glowColor ?? Colors.black).withValues(alpha: glowStrength),
            blurRadius: 26,
            spreadRadius: -2,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [fillTop, fillBottom],
              ),
              border: Border.all(color: border, width: 1),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// CARTE MESSAGE
// =============================================================================
class _MessageCard extends StatefulWidget {
  const _MessageCard({
    required this.model,
    required this.onTap,
    required this.onReplyOpen,
    required this.onSent,
    this.onQuickReply,
  });

  final ValueNotifier<_MsgModel> model;
  final VoidCallback onTap;
  final VoidCallback onReplyOpen;
  final VoidCallback onSent;
  final Future<void> Function(String text)? onQuickReply;

  @override
  State<_MessageCard> createState() => _MessageCardState();
}

class _MessageCardState extends State<_MessageCard> {
  final TextEditingController _reply = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _replyOpen = false;
  bool _sending = false;

  @override
  void dispose() {
    _reply.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _openReply() {
    widget.onReplyOpen(); // suspend l'auto-disparition
    setState(() => _replyOpen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  Future<void> _send() async {
    final text = _reply.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.onQuickReply?.call(text);
    } catch (_) {}
    widget.onSent(); // ferme le heads-up
  }

  @override
  Widget build(BuildContext context) {
    return _GlassSurface(
      radius: 26,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(26),
          onTap: _replyOpen ? null : widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: ValueListenableBuilder<_MsgModel>(
              valueListenable: widget.model,
              builder: (context, m, _) {
                final subtitle =
                    m.count > 1 ? "${m.count} nouveaux messages" : m.body;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        _AvatarBadge(
                          name: m.title,
                          avatarUrl: m.avatarUrl,
                          count: m.count,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                m.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  letterSpacing: -0.1,
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.2,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (widget.onQuickReply != null && !_replyOpen) ...[
                          const SizedBox(width: 8),
                          _QuickReplyButton(onTap: _openReply),
                        ],
                      ],
                    ),
                    if (_replyOpen) ...[
                      const SizedBox(height: 10),
                      _ReplyField(
                        controller: _reply,
                        focusNode: _focus,
                        sending: _sending,
                        onSend: _send,
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Avatar + pastille de compteur (regroupement).
class _AvatarBadge extends StatelessWidget {
  const _AvatarBadge({
    required this.name,
    required this.avatarUrl,
    required this.count,
  });

  final String name;
  final String? avatarUrl;
  final int count;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      height: 46,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AvatarCircle(
            name: name,
            avatarUrl: avatarUrl,
            radius: 23,
            backgroundColor: AlanyaColors.forest.withValues(alpha: 0.18),
            textColor: AlanyaColors.forest,
          ),
          if (count > 1)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                decoration: BoxDecoration(
                  color: AlanyaColors.terracotta,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF201A14)
                        : Colors.white,
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Text(
                    count > 9 ? "9+" : "$count",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _QuickReplyButton extends StatelessWidget {
  const _QuickReplyButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AlanyaColors.forest.withValues(alpha: 0.14),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const SizedBox(
          width: 40,
          height: 40,
          child:
              Icon(Icons.reply_rounded, color: AlanyaColors.forest, size: 20),
        ),
      ),
    );
  }
}

class _ReplyField extends StatelessWidget {
  const _ReplyField({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSend(),
            minLines: 1,
            maxLines: 3,
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: "Réponse rapide…",
              hintStyle: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 14,
              ),
              filled: true,
              fillColor: dark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.04),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Material(
          color: AlanyaColors.forest,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: sending ? null : onSend,
            child: SizedBox(
              width: 40,
              height: 40,
              child: sending
                  ? const Padding(
                      padding: EdgeInsets.all(11),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.send_rounded,
                      color: Colors.white, size: 19),
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// CARTE APPEL
// =============================================================================
class _CallCard extends StatelessWidget {
  const _CallCard({
    required this.title,
    required this.avatarUrl,
    required this.isVideo,
    this.onTap,
    this.onAccept,
    this.onReject,
  });

  final String title;
  final String? avatarUrl;
  final bool isVideo;
  final VoidCallback? onTap;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    return _GlassSurface(
      radius: 30,
      glowColor: AlanyaColors.terracotta,
      glowStrength: 0.28,
      borderColor: AlanyaColors.terracotta.withValues(alpha: 0.45),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    _AppGlyph(isVideo: isVideo),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              letterSpacing: -0.2,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              const _PulseDot(),
                              const SizedBox(width: 6),
                              Text(
                                isVideo
                                    ? "Appel vidéo entrant…"
                                    : "Appel entrant…",
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: AlanyaColors.terracotta,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    AvatarCircle(
                      name: title,
                      avatarUrl: avatarUrl,
                      radius: 26,
                      backgroundColor:
                          AlanyaColors.terracotta.withValues(alpha: 0.18),
                      textColor: AlanyaColors.terracotta,
                      borderColor:
                          AlanyaColors.terracotta.withValues(alpha: 0.35),
                      borderWidth: 2,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _CallActionButton(
                        icon: Icons.call_end_rounded,
                        label: "Refuser",
                        background: AlanyaColors.error,
                        onTap: onReject,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _CallActionButton(
                        icon: isVideo
                            ? Icons.videocam_rounded
                            : Icons.call_rounded,
                        label: "Répondre",
                        background: AlanyaColors.forest,
                        onTap: onAccept,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Icône de l'application dans un carré arrondi (à gauche de la carte appel).
class _AppGlyph extends StatelessWidget {
  const _AppGlyph({required this.isVideo});
  final bool isVideo;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AlanyaColors.terracottaLight, AlanyaColors.terracotta],
        ),
        boxShadow: [
          BoxShadow(
            color: AlanyaColors.terracotta.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.asset(
          'assets/images/app_icon.png',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Icon(
            isVideo ? Icons.videocam_rounded : Icons.call_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
      ),
    );
  }
}

/// Petit point pulsant devant « Appel entrant… ».
class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1.0).animate(_c),
      child: Container(
        width: 7,
        height: 7,
        decoration: const BoxDecoration(
          color: AlanyaColors.terracotta,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _CallActionButton extends StatelessWidget {
  const _CallActionButton({
    required this.icon,
    required this.label,
    required this.background,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color background;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
