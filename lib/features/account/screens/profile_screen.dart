import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/alanya_id_formatter.dart';
import '../../../core/api_client.dart';
import '../../../core/server_config.dart';
import '../../../core/token_storage.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/auth_network_image.dart';
import '../../../widgets/back_app_bar.dart';
import '../../../widgets/motif_background.dart';
import '../../auth/auth_controller.dart';
import '../../media/media_repository.dart';
import '../account_repository.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _pseudoCtrl;
  late final TextEditingController _statusCtrl;
  bool _saving = false;
  bool _uploadingAvatar = false;
  String? _token;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthController>().user;
    _pseudoCtrl = TextEditingController(text: user?.pseudo ?? "");
    _statusCtrl = TextEditingController(text: user?.statusMsg ?? "");
    _loadToken();
  }

  Future<void> _loadToken() async {
    final t = await context.read<TokenStorage>().accessToken;
    if (mounted) setState(() => _token = t);
  }

  @override
  void dispose() {
    _pseudoCtrl.dispose();
    _statusCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final pseudo = _pseudoCtrl.text.trim();
    if (pseudo.length < 2) {
      _snack(tr(context, 'pseudo_min_2'));
      return;
    }
    setState(() => _saving = true);
    final account = context.read<AccountRepository>();
    final auth = context.read<AuthController>();
    try {
      final res = await account.updateProfile(
        pseudo: pseudo,
        statusMsg: _statusCtrl.text.trim(),
      );
      auth.applyProfile(
        pseudo: res.pseudo,
        statusMsg: res.statusMsg,
        avatarUrl: res.avatarUrl,
      );
      _snack(tr(context, 'profile_updated'));
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack(tr(context, 'profile_update_failed'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAvatar() async {
    if (_uploadingAvatar) return;

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
    } catch (_) {
      _snack(tr(context, 'file_picker_linux'));
      return;
    }
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;

    if (bytes.length > 5 * 1024 * 1024) {
      _snack("Image trop lourde (max 5 Mo)");
      return;
    }

    setState(() => _uploadingAvatar = true);
    final mediaRepo = context.read<MediaRepository>();
    final account = context.read<AccountRepository>();
    final auth = context.read<AuthController>();

    try {
      final mime = _mimeFromBytes(bytes) ?? _mimeFromName(file.name);
      final uploaded = await mediaRepo.upload(bytes, file.name, mime);
      final res = await account.updateProfile(avatarUrl: uploaded.url);
      auth.applyProfile(
        pseudo: res.pseudo,
        statusMsg: res.statusMsg,
        avatarUrl: res.avatarUrl,
      );
      _snack("Photo de profil mise à jour");
    } on ApiException catch (e) {
      _snack("Erreur ${e.statusCode} : ${e.message}");
    } catch (e) {
      _snack("Échec de l'envoi de la photo : $e");
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  String? _mimeFromBytes(Uint8List bytes) {
    if (bytes.length < 12) return null;
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return "image/jpeg";
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) return "image/png";
    if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x38) return "image/gif";
    if (bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
        bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) {
      return "image/webp";
    }
    return null;
  }

  String _mimeFromName(String name) {
    final n = name.toLowerCase();
    if (n.endsWith(".png")) return "image/png";
    if (n.endsWith(".webp")) return "image/webp";
    if (n.endsWith(".gif")) return "image/gif";
    return "image/jpeg";
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthController>().user;
    return Scaffold(
      appBar: backAppBar(context, tr(context, 'my_profile')),
      body: MotifBackground(
        overlayOpacity: 0.92,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: _AvatarWithEdit(
                  pseudo: user?.pseudo,
                  avatarUrl: user?.avatarUrl,
                  token: _token,
                  uploading: _uploadingAvatar,
                  onTap: _pickAvatar,
                ),
              ),
              const SizedBox(height: 16),
              // Le repli « — » reste hors du formateur : celui-ci ne garde que
              // les chiffres et effacerait le tiret.
              _infoCard(
                  user?.publicNumber == null
                      ? "—"
                      : formatAlanyaId(user!.publicNumber),
                  user?.email ?? "—"),
              const SizedBox(height: 20),
              TextField(
                controller: _pseudoCtrl,
                decoration: InputDecoration(
                  labelText: tr(context, 'pseudo'),
                  prefixIcon: const Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _statusCtrl,
                maxLength: 255,
                decoration: InputDecoration(
                  labelText: tr(context, 'status_hint'),
                  prefixIcon: const Icon(Icons.info_outline),
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save),
                label: Text(tr(context, 'save')),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () => context.read<AuthController>().logout(),
                icon: const Icon(Icons.logout),
                label: Text(tr(context, 'logout')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoCard(String number, String email) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: themed(context, light: Colors.white, dark: AlanyaColors.nuit2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: themed(context,
                light: AlanyaColors.grey200, dark: AlanyaColors.ligne),
            width: 0.5),
      ),
      child: Column(children: [
        Row(children: [
          Icon(Icons.tag,
              color: themed(context,
                  light: AlanyaColors.terracotta,
                  dark: AlanyaColors.terracottaNuit)),
          const SizedBox(width: 10),
          Text(tr(context, 'alanya_number_label'),
              style: TextStyle(
                  color: themed(context,
                      light: Colors.black54, dark: AlanyaColors.craie2))),
          Text(number, style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.email_outlined, color: AlanyaColors.gold),
          const SizedBox(width: 10),
          Expanded(
              child: Text(email,
                  style: TextStyle(
                      color: themed(context,
                          light: Colors.black87, dark: AlanyaColors.craie)))),
        ]),
      ]),
    );
  }
}

class _AvatarWithEdit extends StatelessWidget {
  const _AvatarWithEdit({
    required this.pseudo,
    required this.avatarUrl,
    required this.token,
    required this.uploading,
    required this.onTap,
  });

  final String? pseudo;
  final String? avatarUrl;
  final String? token;
  final bool uploading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final initial = (pseudo?.isNotEmpty ?? false) ? pseudo![0].toUpperCase() : "?";

    String? fullUrl;
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      fullUrl = avatarUrl!.startsWith("http")
          ? avatarUrl!
          : "${ServerConfig.apiBase}$avatarUrl";
    }

    return GestureDetector(
      onTap: uploading ? null : onTap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: themed(context,
                  light: AlanyaColors.terracotta,
                  dark: AlanyaColors.terracottaNuit),
              // Le liseré reprend le fond de page (crème en clair, nuit en Nuit).
              border: Border.all(
                  color: themed(context,
                      light: Colors.white, dark: AlanyaColors.nuit),
                  width: 3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ClipOval(
              child: fullUrl != null && token != null
                  ? AuthNetworkImage(
                      url: fullUrl,
                      token: token,
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                    )
                  : Center(
                      child: Text(
                        initial,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 40,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: themed(context,
                    light: AlanyaColors.forest,
                    dark: AlanyaColors.terracottaNuit),
                border: Border.all(
                    color: themed(context,
                        light: Colors.white, dark: AlanyaColors.nuit),
                    width: 2),
              ),
              child: uploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(
                      Icons.camera_alt,
                      color: Colors.white,
                      size: 18,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
