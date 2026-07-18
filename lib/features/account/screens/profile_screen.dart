import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../core/server_config.dart';
import '../../../core/token_storage.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/alanya_theme.dart';
import '../../../core/locale_controller.dart';
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

  /// Ouvre le sélecteur d'image, upload le fichier via MediaRepository,
  /// puis met à jour le profil avec la nouvelle avatarUrl.
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

    // Limite douce à 5 Mo côté client pour éviter un aller-retour inutile
    // (le backend limitera aussi, cf. env.media.maxSizeMb).
    if (bytes.length > 5 * 1024 * 1024) {
      _snack("Image trop lourde (max 5 Mo)");
      return;
    }

    setState(() => _uploadingAvatar = true);
    final mediaRepo = context.read<MediaRepository>();
    final account = context.read<AccountRepository>();
    final auth = context.read<AuthController>();

    try {
      // Détecte le MIME à partir des bytes eux-mêmes (magic number) plutôt
      // que du nom de fichier. Le picker Android peut renvoyer un nom sans
      // extension ou avec une extension trompeuse selon l'appli source.
      final mime = _mimeFromBytes(bytes) ?? _mimeFromName(file.name);
      debugPrint("[avatar] upload mime=$mime filename=${file.name} size=${bytes.length}o");

      final uploaded = await mediaRepo.upload(bytes, file.name, mime);
      debugPrint("[avatar] uploaded id=${uploaded.id} url=${uploaded.url}");

      // Envoie l'URL relative (/api/media/<id>). Le backend accepte
      // désormais ce format (cf. updateProfileSchema).
      final res = await account.updateProfile(avatarUrl: uploaded.url);
      auth.applyProfile(
        pseudo: res.pseudo,
        statusMsg: res.statusMsg,
        avatarUrl: res.avatarUrl,
      );
      _snack("Photo de profil mise à jour");
    } on ApiException catch (e) {
      // Message détaillé avec code HTTP pour faciliter le diagnostic.
      debugPrint("[avatar] ❌ ApiException status=${e.statusCode} message=${e.message}");
      _snack("Erreur ${e.statusCode} : ${e.message}");
    } catch (e, st) {
      debugPrint("[avatar] ❌ exception: $e\n$st");
      _snack("Échec de l'envoi de la photo : $e");
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  /// Détecte le type MIME à partir des premiers octets du fichier (magic number).
  /// Beaucoup plus fiable que l'extension du nom, surtout sur Android où le
  /// picker peut renvoyer "image" ou "IMG_1234" sans extension.
  String? _mimeFromBytes(Uint8List bytes) {
    if (bytes.length < 12) return null;
    // JPEG : FF D8 FF
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return "image/jpeg";
    // PNG : 89 50 4E 47
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) return "image/png";
    // GIF : "GIF8"
    if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x38) return "image/gif";
    // WebP : "RIFF" ... "WEBP"
    if (bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
        bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) {
      return "image/webp";
    }
    // HEIC/HEIF : "ftyp" à l'offset 4, puis brand "heic"/"heix"/"mif1"...
    if (bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70) {
      final brand = String.fromCharCodes(bytes.sublist(8, 12));
      if (brand == "heic" || brand == "heix" || brand == "hevc" || brand == "mif1") {
        return "image/heic";
      }
    }
    return null;
  }

  String _mimeFromName(String name) {
    final n = name.toLowerCase();
    if (n.endsWith(".png")) return "image/png";
    if (n.endsWith(".webp")) return "image/webp";
    if (n.endsWith(".gif")) return "image/gif";
    if (n.endsWith(".heic") || n.endsWith(".heif")) return "image/heic";
    return "image/jpeg";
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthController>().user;
    final localeCtrl = context.watch<LocaleController>();
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
              _infoCard(user?.publicNumber ?? "—", user?.email ?? "—"),
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
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AlanyaColors.sand),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.language, color: AlanyaColors.forest),
                      const SizedBox(width: 10),
                      Text(
                        tr(context, 'language_settings'),
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Text(
                      tr(context, 'language_description'),
                      style: const TextStyle(color: Colors.black54, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: LocaleController.supported
                              .any((l) => l.code == localeCtrl.languageCode)
                          ? localeCtrl.languageCode
                          : 'fr',
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                      ),
                      items: LocaleController.supported.map((l) {
                        return DropdownMenuItem(
                          value: l.code,
                          child: Text('${l.flag}  ${l.nativeName}'),
                        );
                      }).toList(),
                      onChanged: (code) {
                        if (code != null) localeCtrl.setLocale(code);
                      },
                    ),
                  ],
                ),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AlanyaColors.sand),
      ),
      child: Column(children: [
        Row(children: [
          const Icon(Icons.tag, color: AlanyaColors.terracotta),
          const SizedBox(width: 10),
          Text(tr(context, 'alanya_number_label'),
              style: const TextStyle(color: Colors.black54)),
          Text(number, style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.email_outlined, color: AlanyaColors.gold),
          const SizedBox(width: 10),
          Expanded(
              child: Text(email, style: const TextStyle(color: Colors.black87))),
        ]),
      ]),
    );
  }
}

/// Avatar circulaire cliquable pour éditer la photo de profil.
/// Affiche :
///  - Une photo réelle si `avatarUrl` est présent (chargée via token JWT).
///  - Sinon l'initiale du pseudo sur fond terracotta.
///  - Un badge caméra en overlay pour indiquer que c'est cliquable.
///  - Un spinner pendant l'upload.
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
    final initial =
        (pseudo?.isNotEmpty ?? false) ? pseudo![0].toUpperCase() : "?";

    // Reconstruit l'URL absolue si avatarUrl est un chemin relatif.
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
              color: AlanyaColors.terracotta,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
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
          // Badge caméra en bas à droite
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AlanyaColors.forest,
                border: Border.all(color: Colors.white, width: 2),
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
