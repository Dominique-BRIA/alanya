import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/alanya_theme.dart';
import '../widgets/avatar_circle.dart';
import 'push_service.dart';

/// Données d'un bandeau de notification in-app.
class _BannerData {
  _BannerData({
    required this.title,
    required this.body,
    required this.icon,
    required this.color,
    this.avatarName,
    this.avatarUrl,
    this.onTap,
    this.autoDismiss,
    this.actions = const [],
  });

  final String title;
  final String body;
  final IconData icon;
  final Color color;
  final String? avatarName;
  final String? avatarUrl;
  final VoidCallback? onTap;
  final Duration? autoDismiss; // null = persistant (appel)
  final List<Widget> actions; // boutons optionnels (accepter/refuser)
}

/// Bandeau de notification **in-app** (heads-up custom) affiché au-dessus de
/// toutes les pages via l'Overlay racine. Messages : auto-disparaît ; appels :
/// persistant jusqu'à réponse/annulation. Cliquable, glisser pour fermer.
class InAppNotifier {
  InAppNotifier._();
  static final InAppNotifier instance = InAppNotifier._();

  OverlayEntry? _entry;
  Timer? _timer;

  void showMessage({
    required String title,
    required String body,
    String? avatarUrl,
    VoidCallback? onTap,
  }) {
    _show(_BannerData(
      title: title,
      body: body,
      icon: Icons.chat_bubble_rounded,
      color: AlanyaColors.forest,
      avatarName: title,
      avatarUrl: avatarUrl,
      onTap: onTap,
      autoDismiss: const Duration(seconds: 4),
    ));
  }

  /// Bandeau d'appel entrant : persistant, avec boutons accepter/refuser.
  void showCall({
    required String title,
    String? avatarUrl,
    VoidCallback? onTap,
    VoidCallback? onAccept,
    VoidCallback? onReject,
  }) {
    _show(_BannerData(
      title: title,
      body: "Appel entrant…",
      icon: Icons.call,
      color: AlanyaColors.terracotta,
      avatarName: title,
      avatarUrl: avatarUrl,
      onTap: onTap,
      autoDismiss: null,
      actions: [
        if (onReject != null)
          _circleAction(Icons.call_end, Colors.red, () {
            dismiss();
            onReject();
          }),
        if (onAccept != null)
          _circleAction(Icons.call, AlanyaColors.forest, () {
            dismiss();
            onAccept();
          }),
      ],
    ));
  }

  static Widget _circleAction(IconData icon, Color color, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Material(
        color: color,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
              width: 40, height: 40, child: Icon(icon, color: Colors.white, size: 20)),
        ),
      ),
    );
  }

  void _show(_BannerData data) {
    dismiss();
    final overlay = PushService.navigatorKey.currentState?.overlay;
    if (overlay == null) return;
    _entry = OverlayEntry(builder: (_) => _Banner(data: data, onClose: dismiss));
    overlay.insert(_entry!);
    if (data.autoDismiss != null) {
      _timer = Timer(data.autoDismiss!, dismiss);
    }
  }

  void dismiss() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }
}

class _Banner extends StatefulWidget {
  const _Banner({required this.data, required this.onClose});
  final _BannerData data;
  final VoidCallback onClose;

  @override
  State<_Banner> createState() => _BannerState();
}

class _BannerState extends State<_Banner> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
            .animate(CurvedAnimation(parent: _c, curve: Curves.easeOut)),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
            child: Dismissible(
              key: const ValueKey('inapp_banner'),
              direction: DismissDirection.horizontal,
              onDismissed: (_) => widget.onClose(),
              child: Material(
                color: Colors.white,
                elevation: 8,
                borderRadius: BorderRadius.circular(16),
                shadowColor: Colors.black45,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    widget.onClose();
                    d.onTap?.call();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        AvatarCircle(
                          name: d.avatarName ?? d.title,
                          avatarUrl: d.avatarUrl,
                          radius: 22,
                          backgroundColor: d.color.withValues(alpha: 0.15),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                d.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AlanyaColors.chocolate,
                                ),
                              ),
                              Text(
                                d.body,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.black54, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        ...d.actions,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
