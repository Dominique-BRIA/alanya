/// L'ÉCRAN PROFIL — refait sur la maquette du user (28/09/2026).
///
/// Il s'ouvre d'un appui sur la carte d'identité de l'écran Discussions, et
/// devient le raccourci vers ce qu'on règle le plus souvent :
///
///   · la carte : photo (appui = la changer), nom, @pseudo, statut
///     (appui = les modifier), Alanya ID (appui = le copier, icône = QR code),
///     drapeau et pays ;
///   · « Contacts préférés » : les contacts enregistrés ;
///   · les préférences des réglages, la sauvegarde chiffrée, puis Paramètres ;
///   · la déconnexion, à part, en rouge.
///
/// ⚠️ LES COULEURS SONT CELLES DE L'APPLICATION, pas celles de la maquette :
/// terre cuite en clair, indigo en Nuit. La mise en page, elle, est reprise.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/alanya_id_formatter.dart';
import '../../../core/api_client.dart';
import '../../../core/pays_repository.dart';
import '../../../core/token_storage.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/auth_user.dart';
import '../../../models/contact.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/avatar_circle.dart';
import '../../../widgets/avatar_source.dart';
import '../../../widgets/back_app_bar.dart';
import '../../../widgets/motif_background.dart';
import '../../auth/auth_controller.dart';
import '../../contacts/contacts_repository.dart';
import '../../contacts/screens/contact_info_screen.dart';
import '../../media/media_repository.dart';
import '../../parametres/screens/sauvegarde_chiffree_screen.dart';
import '../../settings/deconnexion.dart';
import '../../settings/screens/settings_screen.dart';
import '../../settings/widgets/preferences_section.dart';
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

  /// Les contacts enregistrés — « Contacts préférés » de la maquette (« ce
  /// sont mes contacts que j'ai enregistrés »). Nuls pendant le chargement.
  List<Contact>? _contacts;
  bool _contactsEnErreur = false;

  /// Lu une fois : sans ce cache, chaque reconstruction relancerait la requête.
  Future<Pays?>? _paysFutur;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthController>().user;
    _pseudoCtrl = TextEditingController(text: user?.pseudo ?? "");
    _statusCtrl = TextEditingController(text: user?.statusMsg ?? "");
    _loadToken();
    _chargerContacts();
  }

  Future<void> _loadToken() async {
    final t = await context.read<TokenStorage>().accessToken;
    if (mounted) setState(() => _token = t);
  }

  Future<void> _chargerContacts() async {
    try {
      final liste = await context.read<ContactsRepository>().list();
      if (!mounted) return;
      // Un contact bloqué n'a pas sa place parmi les « préférés ».
      setState(() => _contacts = liste.where((c) => !c.isBlocked).toList());
    } catch (_) {
      if (mounted) setState(() => _contactsEnErreur = true);
    }
  }

  Future<Pays?> _paysDe(int? idPays) async {
    if (idPays == null) return null;
    final tous = await context.read<PaysRepository>().liste();
    for (final p in tous) {
      if (p.idPays == idPays) return p;
    }
    return null;
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
      _snack(tr(context, 'profile_photo_updated'));
    } on ApiException catch (e) {
      _snack("Erreur ${e.statusCode} : ${e.message}");
    } catch (e) {
      _snack(tr(context, 'avatar_upload_failed', {'erreur': '$e'}));
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  String? _mimeFromBytes(Uint8List bytes) {
    if (bytes.length < 12) return null;
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return "image/jpeg";
    }
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return "image/png";
    }
    if (bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38) {
      return "image/gif";
    }
    if (bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
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

  /* ══════════════ LES GESTES ══════════════ */

  void _copierId(String publicNumber) {
    // L'ID brut, sans espaces : c'est ce que le clavier « Saisir ID » attend.
    Clipboard.setData(ClipboardData(text: publicNumber));
    HapticFeedback.selectionClick();
    _snack(tr(context, 'alanya_number_copied'));
  }

  void _montrerQr(String publicNumber) {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          tr(context, 'alanya_number_label'),
          textAlign: TextAlign.center,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ⚠️ FOND BLANC DANS LES DEUX THÈMES : un QR code sur fond sombre ne
            // se lit pas avec tous les lecteurs.
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(12),
              child: QrImageView(data: publicNumber, size: 200),
            ),
            const SizedBox(height: 12),
            Text(
              formatAlanyaId(publicNumber),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(tr(context, 'close')),
          ),
        ],
      ),
    );
  }

  /// Modifier le pseudo et le statut.
  ///
  /// ⚠️ LA MAQUETTE N'A PLUS DE CHAMPS SUR LA PAGE : ils s'ouvrent d'un appui
  /// sur le nom. Les retirer sans cette porte aurait supprimé la seule façon
  /// de changer son pseudo.
  Future<void> _modifierIdentite() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(c).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _pseudoCtrl,
              // Aligné sur la colonne users.pseudo, passée en VARCHAR(50).
              maxLength: 50,
              decoration: InputDecoration(
                labelText: tr(context, 'pseudo'),
                prefixIcon: const Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 8),
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
              onPressed: () async {
                if (_saving) return;
                await _save();
                if (c.mounted) Navigator.pop(c);
              },
              icon: const Icon(Icons.save),
              label: Text(tr(context, 'save')),
            ),
          ],
        ),
      ),
    );
  }

  /* ══════════════ LA PAGE ══════════════ */

  Color get _accent => themed(
    context,
    light: AlanyaColors.terracotta,
    dark: AlanyaColors.terracottaNuit,
  );
  Color get _muted =>
      themed(context, light: AlanyaColors.grey500, dark: AlanyaColors.craie2);

  /// Une carte arrondie, comme celles de la maquette.
  Widget _carte({required Widget child, EdgeInsets? padding}) => Container(
    padding: padding,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: themed(
        context,
        light: Colors.white,
        dark: surfacesOf(context).surface,
      ),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: themed(
          context,
          light: AlanyaColors.grey200,
          dark: AlanyaColors.ligne,
        ),
        width: 0.5,
      ),
    ),
    // Les tuiles sont des `ListTile` : elles ont besoin d'un `Material`
    // pour leur effet d'appui, sans quoi il se dessinerait sous la carte.
    child: Material(type: MaterialType.transparency, child: child),
  );

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthController>().user;
    return Scaffold(
      appBar: backAppBar(context, tr(context, 'my_profile')),
      body: MotifBackground(
        overlayOpacity: 0.92,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _enTete(user),
            _titreSection('Contacts préférés'),
            _contactsPreferes(),
            const SizedBox(height: 20),
            // Les préférences, la sauvegarde chiffrée, puis « Paramètres » en
            // dernier (demande du user). Même bloc que les réglages.
            _carte(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const PreferencesSection(
                    margeHorizontale: 0,
                    avecSeparateurs: true,
                  ),
                  separateurReglage(context),
                  TuileReglage(
                    icone: Icons.backup_outlined,
                    couleur: themed(
                      context,
                      light: AlanyaColors.forest,
                      dark: AlanyaColors.indigoLight,
                    ),
                    titre: 'Sauvegarde chiffrée',
                    sousTitre:
                        'Retrouver vos messages chiffrés sur un autre appareil',
                    fin: chevronReglage(context),
                    margeHorizontale: 0,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SauvegardeChiffreeScreen(),
                      ),
                    ),
                  ),
                  separateurReglage(context),
                  TuileReglage(
                    icone: Icons.settings_outlined,
                    couleur: _accent,
                    titre: tr(context, 'settings'),
                    fin: chevronReglage(context),
                    margeHorizontale: 0,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Même confirmation que depuis les réglages — avec l'avertissement
            // sur les messages chiffrés sans sauvegarde.
            _carte(
              child: TuileReglage(
                icone: Icons.logout,
                couleur: themed(
                  context,
                  light: Colors.red,
                  dark: AlanyaColors.erreurNuit,
                ),
                titre: tr(context, 'logout'),
                fin: chevronReglage(context),
                margeHorizontale: 0,
                onTap: () => confirmerDeconnexion(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _titreSection(String titre) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
    child: Text(
      titre,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
    ),
  );

  /// La carte d'identité : photo, nom, @pseudo, statut, Alanya ID, pays.
  Widget _enTete(AuthUser? user) {
    final nom = user?.nom ?? user?.pseudo ?? tr(context, 'home_me');
    final pseudo = user?.pseudo;
    final statut = user?.statusMsg;
    return _carte(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      child: Column(
        children: [
          _AvatarWithEdit(
            pseudo: user?.nom ?? user?.pseudo,
            avatarUrl: user?.avatarUrl,
            token: _token,
            uploading: _uploadingAvatar,
            onTap: _pickAvatar,
          ),
          const SizedBox(height: 16),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _modifierIdentite,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(
                children: [
                  Text(
                    nom,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (pseudo != null && pseudo.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '@$pseudo',
                      style: TextStyle(fontSize: 15, color: _muted),
                    ),
                  ],
                  if (statut != null && statut.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      statut,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: _muted),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (user != null) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _copierId(user.publicNumber),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.badge_outlined, size: 20, color: _accent),
                        const SizedBox(width: 6),
                        Text(
                          formatAlanyaId(user.publicNumber),
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: _accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'QR code',
                  icon: Icon(Icons.qr_code_2, color: _accent),
                  onPressed: () => _montrerQr(user.publicNumber),
                ),
              ],
            ),
            FutureBuilder<Pays?>(
              future: _paysFutur ??= _paysDe(user.idPays),
              builder: (_, snap) {
                final pays = snap.data;
                if (pays == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '${pays.drapeau}  ${pays.libelle}',
                    style: TextStyle(fontSize: 15, color: _muted),
                  ),
                );
              },
            ),
            // L'adresse e-mail, sous le pays (demande du user) — absente pour
            // les comptes créés sans adresse.
            if ((user.email ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.email_outlined, size: 18, color: _muted),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        user.email!,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15, color: _muted),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _contactsPreferes() {
    final contacts = _contacts;
    final Widget contenu;
    if (contacts == null && !_contactsEnErreur) {
      contenu = const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    } else if (contacts == null || contacts.isEmpty) {
      contenu = Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          _contactsEnErreur
              ? tr(context, 'contacts_load_error')
              : 'Aucun contact enregistré pour l’instant.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted),
        ),
      );
    } else {
      contenu = SizedBox(
        height: 150,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          itemCount: contacts.length,
          separatorBuilder: (_, __) => const SizedBox(width: 18),
          itemBuilder: (_, i) => _vignetteContact(contacts[i]),
        ),
      );
    }
    return _carte(child: contenu);
  }

  /// Un contact : photo, nom, Alanya ID. Appui = sa fiche.
  Widget _vignetteContact(Contact c) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ContactInfoScreen(
            userId: c.userId,
            name: c.displayName,
            publicNumber: c.publicNumber,
            avatarUrl: c.avatarUrl,
            username: c.pseudo,
            contactId: c.id,
            isBlocked: c.isBlocked,
            isOnline: c.online,
            lastSeen: c.lastSeen,
          ),
        ),
      ),
      child: SizedBox(
        width: 88,
        child: Column(
          children: [
            AvatarCircle(
              name: c.displayName,
              avatarUrl: c.avatarUrl,
              radius: 38,
              backgroundColor: AlanyaColors.terracotta,
            ),
            const SizedBox(height: 8),
            Text(
              c.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: _muted),
            ),
            const SizedBox(height: 2),
            Text(
              formatAlanyaId(c.publicNumber),
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: const TextStyle(fontSize: 13, letterSpacing: 0.5),
            ),
          ],
        ),
      ),
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
    final initial = (pseudo?.isNotEmpty ?? false)
        ? pseudo![0].toUpperCase()
        : "?";

    // Trois formes coexistent en base, dont des images base64 ecrites par
    // l'application de l'equipe sur la base partagee. Voir [AvatarSource].
    final photo = AvatarSource.depuis(
      avatarUrl,
    ).image(width: 100, height: 100, token: token);

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
              color: themed(
                context,
                light: AlanyaColors.terracotta,
                dark: AlanyaColors.terracottaNuit,
              ),
              // Le liseré reprend le fond de page (crème en clair, nuit en Nuit).
              border: Border.all(
                color: themed(
                  context,
                  light: Colors.white,
                  dark: surfacesOf(context).fond,
                ),
                width: 3,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ClipOval(
              child:
                  photo ??
                  Center(
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
                color: themed(
                  context,
                  light: AlanyaColors.forest,
                  dark: AlanyaColors.terracottaNuit,
                ),
                border: Border.all(
                  color: themed(
                    context,
                    light: Colors.white,
                    dark: surfacesOf(context).fond,
                  ),
                  width: 2,
                ),
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
                  : const Icon(Icons.camera_alt, color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}
