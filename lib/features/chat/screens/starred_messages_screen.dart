import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../theme/alanya_theme.dart';
import '../../../widgets/back_app_bar.dart';
import '../chat_repository.dart';
import 'chat_screen.dart';
import '../../../l10n/app_localizations.dart';

/// Liste des messages favoris (étoile) — toutes conversations confondues.
class StarredMessagesScreen extends StatefulWidget {
  const StarredMessagesScreen({super.key});

  @override
  State<StarredMessagesScreen> createState() => _StarredMessagesScreenState();
}

class _StarredMessagesScreenState extends State<StarredMessagesScreen> {
  List<Map<String, dynamic>>? _items;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await context.read<ChatRepository>().getStarred();
      if (mounted) setState(() => _items = data);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  String _preview(Map<String, dynamic> m) {
    final type = m["type"] as String? ?? "TEXT";
    switch (type) {
      case "IMAGE":
        return tr(context, 'photo');
      case "VIDEO":
        return tr(context, 'video');
      case "AUDIO":
        return tr(context, 'voice_message');
      case "FILE":
        return tr(context, 'file');
      default:
        return (m["content"] as String?) ?? "";
    }
  }

  void _open(Map<String, dynamic> m) {
    final convId = m["convId"] as String?;
    if (convId == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatScreen(
        convId: convId,
        title: (m["convName"] as String?) ?? "",
        isGroup: (m["isGroup"] as bool?) ?? false,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: backAppBar(context, tr(context, 'starred_title')),
      body: _error
          ? Center(child: Text(tr(context, 'load_error_short')))
          : items == null
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          tr(context, 'no_starred'),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final m = items[i];
                        return ListTile(
                          leading:
                              const Icon(Icons.star, color: AlanyaColors.gold),
                          title: Text(
                            (m["convName"] as String?) ?? "",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            _preview(m),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _open(m),
                        );
                      },
                    ),
    );
  }
}
