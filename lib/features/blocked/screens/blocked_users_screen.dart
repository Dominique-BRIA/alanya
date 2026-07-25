import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/back_app_bar.dart';
import '../../../widgets/avatar_circle.dart';
import '../../../widgets/motif_background.dart';
import '../../../models/blocked_user.dart';
import '../blocked_repository.dart';

/// Écran de gestion des utilisateurs bloqués.
///
/// Accessible depuis : Profil → "Utilisateurs bloqués".
/// Permet de voir la liste des personnes bloquées et de les débloquer.
class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  List<BlockedUser>? _blocked;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await context.read<BlockedRepository>().fetchBlocked();
      if (!mounted) return;
      setState(() {
        _blocked = list;
        _error = false;
      });
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  Future<void> _unblock(BlockedUser user) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Débloquer ?"),
        content:
            Text("${user.displayName} pourra de nouveau vous contacter."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Annuler")),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Débloquer")),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await context.read<BlockedRepository>().unblockUser(user.idBlock);
      if (mounted) {
        setState(() {
          _blocked = _blocked?.where((b) => b.idBlock != user.idBlock).toList();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${user.displayName} débloqué")),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Action impossible")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: backAppBar(context, "Utilisateurs bloqués"),
      body: MotifBackground(
        overlayOpacity: 0.92,
        child: RefreshIndicator(
          onRefresh: _load,
          child: _buildList(),
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_blocked == null && !_error) {
      return const Center(
        child: CircularProgressIndicator(color: AlanyaColors.terracotta),
      );
    }
    if (_error) {
      return ListView(children: const [
        SizedBox(height: 80),
        Center(child: Text("Erreur de chargement. Tire pour réessayer.")),
      ]);
    }

    final list = _blocked ?? [];
    if (list.isEmpty) {
      return ListView(children: const [
        SizedBox(height: 100),
        Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.block, size: 64, color: AlanyaColors.gold),
                const SizedBox(height: 12),
                Text(
                  "Aucun utilisateur bloqué.\nLes personnes bloquées ne pourront plus vous envoyer de messages ni vous appeler.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: themed(context,
                          light: Colors.black54, dark: AlanyaColors.craie2)),
                ),
              ],
            ),
          ),
        ),
      ]);
    }

    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) => _tile(list[i]),
    );
  }

  Widget _tile(BlockedUser b) {
    return ListTile(
      leading: AvatarCircle(
        name: b.displayName,
        avatarUrl: b.avatarUrl,
        radius: 22,
        backgroundColor: themed(context,
            light: Colors.grey.shade400, dark: AlanyaColors.nuit3),
      ),
      title: Text(b.displayName,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        "Bloqué le ${b.dateBlock.day.toString().padLeft(2, '0')}/${b.dateBlock.month.toString().padLeft(2, '0')}/${b.dateBlock.year}",
        style: TextStyle(
            fontSize: 12,
            color: themed(context,
                light: Colors.black54, dark: AlanyaColors.craie2)),
      ),
      trailing: TextButton(
        onPressed: () => _unblock(b),
        child: Text("Débloquer",
            style: TextStyle(
                color: themed(context,
                    light: Colors.red, dark: AlanyaColors.erreurNuit))),
      ),
    );
  }
}
