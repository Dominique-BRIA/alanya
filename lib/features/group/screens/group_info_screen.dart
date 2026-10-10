import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import '../../media/media_repository.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/alanya_id_formatter.dart';
import '../../../core/api_client.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/avatar_circle.dart';
import '../../../widgets/back_app_bar.dart';
import '../../../widgets/glass_card.dart';
import '../../../widgets/media/cached_media.dart';
import '../../chat/medias_partages.dart';
import '../../chat/screens/media_gallery_viewer.dart';
import '../../chat/screens/shared_content_screen.dart';
import '../../chat/widgets/bulle_media_chiffre.dart';
import '../../auth/auth_controller.dart';
import '../../chat/chat_repository.dart';
import '../../../widgets/contact_picker_sheet.dart';
import '../../chat/screens/chat_screen.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/e2ee/e2ee_fournisseur.dart';
import '../../contacts/verification_cle.dart';

/// Écran d'infos d'un groupe — style WhatsApp.
///
/// Affiche : nom, avatar, membres, actions (ajouter, retirer, quitter, modifier).
class GroupInfoScreen extends StatefulWidget {
  const GroupInfoScreen({
    super.key,
    required this.convId,
    required this.title,
    required this.avatarUrl,
    required this.members,
  });

  final String convId;
  final String title;
  final String? avatarUrl;
  final List<Map<String, dynamic>> members; // [{id, pseudo, publicNumber, avatarUrl, isOnline, role}]

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  late List<Map<String, dynamic>> _members;
  late String _title;
  late String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _members = List.from(widget.members);
    _title = widget.title;
    _avatarUrl = widget.avatarUrl;
    _refreshMembers();
    _lireEtatChiffrement();
    _chargerMedias();
  }

  /* ══════════════ LES MÉDIAS DU GROUPE (carte « Médias, liens et docs ») ══════════════ */

  /// Les photos et vidéos du fil, en clair ou chiffrées — le même chargement
  /// que la fiche contact (`medias_partages.dart`). `null` tant qu'il tourne.
  List<ConvMediaItem>? _medias;
  String _baseUrl = '';
  String? _token;

  Future<void> _chargerMedias() async {
    _baseUrl = context.read<ApiClient>().baseUrl;
    try {
      final fil = await chargerFilPourMedias(context, widget.convId);
      if (!mounted) return;
      setState(() {
        _token = fil.token;
        _medias = mediasGalerie(fil.messages,
            baseUrl: _baseUrl, token: fil.token, chiffreDe: fil.chiffreDe);
      });
    } catch (_) {
      if (mounted) setState(() => _medias = const []);
    }
  }

  /* ══════════════ LE CHIFFREMENT DU GROUPE (lot 5, chapitre 35) ══════════════ */

  /// Ce groupe est-il chiffré ? `null` tant qu'on ne sait pas.
  bool? _chiffre;
  bool _chiffrementEnCours = false;

  Future<void> _lireEtatChiffrement() async {
    final pile = context.e2ee;
    if (pile == null) return;
    try {
      final actif = await pile.fil.etat(widget.convId);
      if (mounted) setState(() => _chiffre = actif);
    } catch (_) {}
  }

  void _dire(String texte) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texte)));
  }

  /// ACTIVER : le serveur réserve la version 1, CE téléphone tire la clé et la
  /// distribue à chaque appareil de chaque membre.
  Future<void> _activerChiffrement() async {
    final pile = context.e2ee;
    if (pile == null || _chiffrementEnCours) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chiffrer ce groupe ?'),
        content: const Text(
            "Les messages suivants seront chiffrés de bout en bout pour tous les membres. "
            "Le chiffrement ne se retire pas."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(context, 'cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Chiffrer')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _chiffrementEnCours = true);
    try {
      final r = await pile.fil.groupe.activer(widget.convId);
      pile.fil.noteEtat(widget.convId, true);
      if (mounted) setState(() => _chiffre = true);
      final sans = r.bilan?.sansAppareil.length ?? 0;
      _dire(sans == 0
          ? 'Groupe chiffré de bout en bout.'
          : 'Groupe chiffré. $sans membre(s) sans appareil à jour ne lisent pas encore.');
    } on ApiException catch (e) {
      _dire(e.message);
    } catch (_) {
      _dire("Le chiffrement n'a pas pu être activé.");
    } finally {
      if (mounted) setState(() => _chiffrementEnCours = false);
    }
  }

  /// CHANGER LA CLÉ : une nouvelle version, envoyée aux membres actuels — pour
  /// une clé qu'on soupçonne volée, ou une distribution manquée.
  Future<void> _changerCle() async {
    final pile = context.e2ee;
    if (pile == null || _chiffrementEnCours) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Changer la clé du groupe'),
        content: const Text(
            'Une nouvelle clé est créée et envoyée aux membres actuels. '
            'Les anciens messages restent lisibles.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(context, 'cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Changer')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _chiffrementEnCours = true);
    try {
      await pile.fil.groupe.changerCle(widget.convId, 'MANUEL');
      _dire('Clé du groupe changée.');
    } catch (_) {
      _dire("La clé n'a pas pu être changée.");
    } finally {
      if (mounted) setState(() => _chiffrementEnCours = false);
    }
  }

  String get _myId => context.read<AuthController>().user?.id ?? '';

  /// Vérifie si l'utilisateur connecté est admin dans CE groupe.
  bool get _amAdmin {
    if (_members.isEmpty) return false;
    final me = _members.firstWhere(
      (m) => m['id'] == _myId,
      orElse: () => {},
    );
    if ((me['role'] as String?) == 'ADMIN') return true;
    final hasAnyAdmin = _members.any((m) => (m['role'] as String?) == 'ADMIN');
    if (!hasAnyAdmin && _members.first['id'] == _myId) return true;
    return false;
  }

  Future<void> _refreshMembers() async {
    try {
      final data = await context.read<ChatRepository>().getGroupMembers(widget.convId);
      if (mounted) setState(() => _members = data);
    } catch (_) {}
  }

  // ===================== MODIFIER LE NOM =====================

  Future<void> _editName() async {
    if (!_amAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'grp_admin_only_name'))),
      );
      return;
    }
    final ctrl = TextEditingController(text: _title);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'grp_name_label')),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(hintText: tr(ctx, 'grp_name_hint')),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: Text(tr(ctx, 'save'))),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty && newName != _title) {
      try {
        await context.read<ChatRepository>().updateGroup(widget.convId, name: newName);
        setState(() => _title = newName);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr(context, 'grp_name_updated'))),
          );
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr(context, 'grp_update_failed'))),
          );
        }
      }
    }
  }

  // ===================== MODIFIER L'AVATAR =====================

  Future<void> _editAvatar() async {
    if (!_amAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'grp_admin_only_avatar'))),
      );
      return;
    }

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'gallery_open_failed'))),
        );
      }
      return;
    }
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;

    if (bytes.length > 5 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'image_too_large'))),
        );
      }
      return;
    }

    try {
      final mediaRepo = context.read<MediaRepository>();
      final mime = _mimeFromBytes(bytes) ?? _mimeFromName(file.name);
      final uploaded = await mediaRepo.upload(bytes, file.name, mime);

      await context.read<ChatRepository>().updateGroup(widget.convId, avatarUrl: uploaded.url);
      setState(() => _avatarUrl = uploaded.url);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'grp_avatar_updated'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'grp_avatar_failed'))),
        );
      }
    }
  }

  String? _mimeFromBytes(Uint8List bytes) {
    if (bytes.length < 12) return null;
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return "image/jpeg";
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) return "image/png";
    if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x38) return "image/gif";
    return "image/jpeg";
  }

  String _mimeFromName(String name) {
    final n = name.toLowerCase();
    if (n.endsWith(".png")) return "image/png";
    if (n.endsWith(".webp")) return "image/webp";
    if (n.endsWith(".gif")) return "image/gif";
    return "image/jpeg";
  }

  // ===================== AJOUTER DES MEMBRES =====================

  Future<void> _addMembers() async {
    if (!_amAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'grp_admin_only_add'))),
      );
      return;
    }
    final existingNumbers = _members
        .map((m) => (m['publicNumber'] as String?) ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
    final result = await ContactPickerSheet.show(
      context,
      title: tr(context, 'grp_add_members'),
      confirmLabel: tr(context, 'add'),
      excludeNumbers: existingNumbers,
    );
    if (result != null && result.isNotEmpty) {
      try {
        final pile = context.e2ee;
        await context.read<ChatRepository>().addMembersToGroup(widget.convId, result);
        /*
         * 🔴 GROUPE CHIFFRÉ : sans le trousseau, le nouveau membre verrait un
         * groupe muet. L'ajout est fait quoi qu'il arrive ensuite ; un échec du
         * partage est dit, et « Clé » le rattrape.
         */
        if (_chiffre == true && pile != null) {
          try {
            await pile.fil.groupe.partagerApresAjout(widget.convId, result);
          } catch (_) {
            _dire("Membre ajouté, mais la clé du groupe n'a pas pu lui être envoyée.");
          }
        }
        await _refreshMembers();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(trN(context, 'grp_members_added', result.length))),
          );
        }
      } catch (e) {
        if (mounted) {
          final msg = (e is ApiException) ? e.message : tr(context, 'grp_add_failed');
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        }
      }
    }
  }

  // ===================== RETIRER UN MEMBRE =====================

  Future<void> _removeMember(Map<String, dynamic> member) async {
    final name = member['pseudo'] ?? member['publicNumber'] ?? tr(context, 'grp_member');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(tr(context, 'grp_remove_q', {'nom': name})),
        content: Text(tr(context, 'grp_remove_body', {'nom': name})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr(context, 'cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr(context, 'remove'), style: TextStyle(color: dangerOf(context)))),
        ],
      ),
    );
    if (ok == true) {
      try {
        final pile = context.e2ee;
        await context.read<ChatRepository>().removeMemberFromGroup(
              widget.convId,
              member['id'] as String,
            );
        /*
         * 🔴 EXCLUSION D'UN GROUPE CHIFFRÉ (décision du user) : l'exclu connaît
         * la clé actuelle. Une nouvelle version, envoyée aux membres restants,
         * rend illisible ce qui s'écrira ensuite.
         */
        if (_chiffre == true && pile != null) {
          try {
            await pile.fil.groupe.changerCle(widget.convId, 'EXCLUSION');
          } catch (_) {
            _dire("Membre retiré, mais la clé n'a pas pu être changée : utilisez « Clé ».");
          }
        }
        await _refreshMembers();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr(context, 'grp_member_removed', {'nom': name}))),
          );
        }
      } catch (e) {
        if (mounted) {
          final msg = (e is ApiException) ? e.message : "Erreur lors du retrait";
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        }
      }
    }
  }

  Future<void> _changeMemberRole(Map<String, dynamic> member, String role) async {
    final name = member['pseudo'] ?? member['publicNumber'] ?? tr(context, 'grp_member');
    try {
      await context
          .read<ChatRepository>()
          .changeMemberRole(widget.convId, member['id'] as String, role);
      await _refreshMembers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(role == 'ADMIN'
                ? "$name est maintenant administrateur"
                : "$name n'est plus administrateur"),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg =
            (e is ApiException) ? e.message : "Erreur lors du changement de rôle";
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  // ===================== QUITTER LE GROUPE =====================

  Future<void> _leaveGroup() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(tr(context, 'grp_leave_q')),
        content: Text(
            tr(context, 'grp_leave_body')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr(context, 'cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr(context, 'leave_action'), style: TextStyle(color: dangerOf(context)))),
        ],
      ),
    );
    if (ok == true) {
      try {
        await context.read<ChatRepository>().leaveGroup(widget.convId);
        if (mounted) {
          Navigator.of(context).pop(); // retour à la liste
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr(context, 'grp_left'))),
          );
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr(context, 'grp_leave_failed'))),
          );
        }
      }
    }
  }

  // ===================== ENVOYER UN MESSAGE (DM) =====================

  Future<void> _sendMessageTo(Map<String, dynamic> member) async {
    final targetId = member['id'] as String;
    final name = member['pseudo'] ?? member['publicNumber'] ?? tr(context, 'grp_member');
    final avatarUrl = member['avatarUrl'] as String?;

    try {
      // Cherche ou crée une conversation 1-to-1 avec ce membre
      final convData = await context.read<ChatRepository>().getOrCreateDirectConversation(targetId);
      if (!mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            convId: convData['id'] as String,
            title: name,
            avatarUrl: avatarUrl,
            isGroup: false,
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'chat_open_failed'))),
        );
      }
    }
  }

  // ===================== BUILD =====================
  //
  // Des cartes arrondies sur fond uni, dans l'ordre de l'écran de Chris
  // (demande du user, 10/10/2026) : en-tête, médias, membres, chiffrement,
  // quitter.

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor:
          themed(context, light: AlanyaColors.grey100, dark: surfacesOf(context).fond),
      appBar: backAppBar(context, "Infos du groupe"),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _carteEnTete(cs),
          const SizedBox(height: 14),
          _carteMedias(cs),
          const SizedBox(height: 14),
          _carteMembres(cs),
          if (_chiffre != null) ...[
            const SizedBox(height: 14),
            _carteChiffrement(cs),
          ],
          const SizedBox(height: 14),
          GlassCard(
            radius: 22,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              leading: Icon(Icons.logout_rounded, color: dangerOf(context)),
              title: Text(tr(context, 'grp_leave_action'),
                  style: TextStyle(
                      color: dangerOf(context), fontWeight: FontWeight.w600, fontSize: 16)),
              onTap: _leaveGroup,
            ),
          ),
        ],
      ),
    );
  }

  /// Avatar (appareil photo pour l'admin), nom (crayon pour l'admin), compte.
  Widget _carteEnTete(ColorScheme cs) {
    return GlassCard(
      radius: 22,
      padding: const EdgeInsets.fromLTRB(16, 26, 16, 22),
      child: Column(
        children: [
          GestureDetector(
            onTap: _amAdmin ? _editAvatar : null,
            child: Stack(
              children: [
                AvatarCircle(
                  name: _title,
                  avatarUrl: _avatarUrl,
                  radius: 56,
                  backgroundColor: positiveOf(context),
                ),
                if (_amAdmin)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: accentOf(context),
                        shape: BoxShape.circle,
                        border: Border.all(color: cs.surface, width: 3),
                      ),
                      child: const Icon(Icons.camera_alt, size: 18, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(_title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 23, fontWeight: FontWeight.w700, color: cs.onSurface)),
              ),
              if (_amAdmin)
                IconButton(
                  icon: Icon(Icons.edit_outlined, size: 22, color: accentOf(context)),
                  onPressed: _editName,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Groupe • ${trN(context, 'grp_members', _members.length)}',
              style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
          if (_chiffre == true) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_rounded, size: 14, color: positiveOf(context)),
                const SizedBox(width: 5),
                Text('Chiffré de bout en bout',
                    style: TextStyle(
                        fontSize: 12.5,
                        color: positiveOf(context),
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _carteMedias(ColorScheme cs) {
    final recents = (_medias ?? const <ConvMediaItem>[]).take(8).toList();
    void voirTout() => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SharedContentScreen(convId: widget.convId, title: _title)));
    return GlassCard(
      radius: 22,
      padding: const EdgeInsets.fromLTRB(18, 10, 6, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Médias, liens et docs',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 16, color: cs.onSurface)),
              ),
              TextButton(
                onPressed: voirTout,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(tr(context, 'view_all'),
                        style: TextStyle(
                            color: accentOf(context), fontWeight: FontWeight.w600)),
                    Icon(Icons.chevron_right_rounded, size: 20, color: accentOf(context)),
                  ],
                ),
              ),
            ],
          ),
          if (_medias == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                  child: SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else if (recents.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 14, 12, 10),
              child: Center(
                child: Text(tr(context, 'no_shared_media'),
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 12),
              child: SizedBox(
                height: 76,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: recents.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final it = recents[i];
                    final d = it.chiffre;
                    void ouvrir() => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => MediaGalleryViewer(items: _medias!, initialIndex: i)));
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        width: 76,
                        height: 76,
                        child: d != null
                            ? TuileMediaChiffre(
                                descripteur: d, baseUrl: _baseUrl, token: _token, onOuvrir: ouvrir)
                            : GestureDetector(
                                onTap: ouvrir,
                                child: it.isVideo
                                    ? const ColoredBox(
                                        color: Color(0xFF1A1A2E),
                                        child: Icon(Icons.play_circle_fill_rounded,
                                            color: Colors.white70, size: 30),
                                      )
                                    : CachedMedia(
                                        url: it.url, width: 76, height: 76, fit: BoxFit.cover),
                              ),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Les membres : les administrateurs d'abord, puis l'ordre alphabétique ;
  /// « Vous » à sa place. Toucher un membre ouvre ses actions.
  Widget _carteMembres(ColorScheme cs) {
    String nomDe(Map<String, dynamic> m) =>
        '${m['pseudo'] ?? m['publicNumber'] ?? tr(context, 'grp_member')}';
    final tries = [..._members]..sort((a, b) {
        final adminA = (a['role'] as String?) == 'ADMIN' ? 0 : 1;
        final adminB = (b['role'] as String?) == 'ADMIN' ? 0 : 1;
        if (adminA != adminB) return adminA - adminB;
        return nomDe(a).toLowerCase().compareTo(nomDe(b).toLowerCase());
      });
    return GlassCard(
      radius: 22,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
            child: Text(trN(context, 'grp_members', _members.length),
                style: TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 16, color: cs.onSurface)),
          ),
          if (_amAdmin)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 18),
              leading: CircleAvatar(
                radius: 22,
                backgroundColor: accentOf(context).withValues(alpha: 0.12),
                child: Icon(Icons.person_add_alt_1_rounded, color: accentOf(context)),
              ),
              title: Text('Ajouter des participants',
                  style: TextStyle(
                      color: accentOf(context), fontWeight: FontWeight.w600, fontSize: 15.5)),
              onTap: _addMembers,
            ),
          ...tries.map((m) => _ligneMembre(m, nomDe(m), cs)),
        ],
      ),
    );
  }

  Widget _ligneMembre(Map<String, dynamic> m, String name, ColorScheme cs) {
    final isMe = m['id'] == _myId;
    final online = (m['isOnline'] as int?) == 1;
    final isAdmin = (m['role'] as String?) == 'ADMIN';
    final numero = (m['publicNumber'] as String?) ?? '';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18),
      leading: AvatarCircle(
        name: name,
        avatarUrl: m['avatarUrl'] as String?,
        radius: 22,
        backgroundColor: isMe ? accentOf(context) : AlanyaColors.gold,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(isMe ? 'Vous' : name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w500, color: cs.onSurface)),
          ),
          if (isAdmin) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: accentOf(context).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(tr(context, 'grp_admin'),
                  style: TextStyle(
                      fontSize: 11, color: accentOf(context), fontWeight: FontWeight.w600)),
            ),
          ],
        ],
      ),
      subtitle: online
          ? Text("en ligne", style: TextStyle(fontSize: 12, color: positiveOf(context)))
          : (numero.isEmpty
              ? null
              : Text('Alanya ID : ${formatAlanyaId(numero)}',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))),
      trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
      onTap: () => _showMemberOptions(m),
    );
  }

  /// Le chiffrement : l'état pour tous, l'action pour l'administrateur
  /// (chiffrer, puis changer la clé).
  Widget _carteChiffrement(ColorScheme cs) {
    final chiffre = _chiffre == true;
    final String detail;
    if (chiffre) {
      detail = _amAdmin
          ? 'Toucher pour changer la clé du groupe'
          : 'Les messages sont chiffrés pour les seuls membres';
    } else {
      detail = _amAdmin
          ? 'Toucher pour chiffrer ce groupe'
          : 'Seul un administrateur peut l’activer';
    }
    return GlassCard(
      radius: 22,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        leading: Icon(chiffre ? Icons.lock_rounded : Icons.lock_open_rounded,
            color: chiffre ? positiveOf(context) : accentOf(context)),
        title: Text(chiffre ? 'Chiffré de bout en bout' : 'Chiffrement de bout en bout',
            style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w500, color: cs.onSurface)),
        subtitle: Text(detail, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
        trailing: _chiffrementEnCours
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : (_amAdmin ? Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant) : null),
        onTap: !_amAdmin ? null : (chiffre ? _changerCle : _activerChiffrement),
      ),
    );
  }

  void _showMemberOptions(Map<String, dynamic> member) {
    final name = member['pseudo'] ?? member['publicNumber'] ?? tr(context, 'grp_member');
    final isMe = member['id'] == _myId;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(name,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            const Divider(height: 1),
            if (!isMe) ...[
              ListTile(
                leading: Icon(Icons.message, color: positiveOf(context)),
                title: Text(tr(context, 'send_message_action')),
                onTap: () {
                  Navigator.pop(ctx);
                  _sendMessageTo(member);
                },
              ),
              /*
               * VÉRIFIER UN MEMBRE D'UN GROUPE CHIFFRÉ (lot 7) : le même écran
               * qu'en tête-à-tête. C'est la parade contre un appareil glissé
               * par le serveur dans le compte d'un membre (chapitre 31).
               */
              if (_chiffre == true)
                ListTile(
                  leading: Icon(Icons.verified_user_outlined, color: positiveOf(context)),
                  title: Text(tr(context, 'e2ee_verifier_membre')),
                  onTap: () {
                    Navigator.pop(ctx);
                    ouvrirVerificationCle(context,
                        pairId: member['id'] as String, nomPair: '$name');
                  },
                ),
              if (_amAdmin) ...[
                if ((member['role'] as String?) == 'ADMIN')
                  ListTile(
                    leading: Icon(Icons.remove_moderator_outlined,
                        color: themed(context, light: AlanyaColors.chocolate, dark: AlanyaColors.craie2)),
                    title: Text(tr(context, 'remove_admin')),
                    onTap: () {
                      Navigator.pop(ctx);
                      _changeMemberRole(member, 'MEMBER');
                    },
                  )
                else
                  ListTile(
                    leading: Icon(Icons.shield_outlined,
                        color: positiveOf(context)),
                    title: Text(tr(context, 'make_admin')),
                    onTap: () {
                      Navigator.pop(ctx);
                      _changeMemberRole(member, 'ADMIN');
                    },
                  ),
                ListTile(
                  leading: Icon(Icons.remove_circle_outline, color: dangerOf(context)),
                  title: Text(tr(context, 'remove_from_group'),
                      style: TextStyle(color: dangerOf(context))),
                  onTap: () {
                    Navigator.pop(ctx);
                    _removeMember(member);
                  },
                ),
              ],
            ],
            if (isMe)
              ListTile(
                leading: Icon(Icons.exit_to_app, color: dangerOf(context)),
                title: Text(tr(context, 'grp_leave_action'),
                    style: TextStyle(color: dangerOf(context))),
                onTap: () {
                  Navigator.pop(ctx);
                  _leaveGroup();
                },
              ),
          ],
        ),
      ),
    );
  }
}
