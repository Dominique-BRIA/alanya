import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/media/media_picker_sheet.dart' show MediaPickResult;
import '../../chat/screens/media_gallery_picker_screen.dart';
import '../../media/media_repository.dart';
import '../status_repository.dart';
import 'status_viewer_screen.dart' show dureeVideoStatutMax;

/// Convertit un hex (#RRGGBB) en Color opaque.
Color colorFromHex(String hex) {
  final h = hex.replaceFirst("#", "");
  return Color(int.parse("FF$h", radix: 16));
}

/// Composition d'un statut texte sur fond coloré (style WhatsApp).
class CreateStatusScreen extends StatefulWidget {
  const CreateStatusScreen({super.key});

  @override
  State<CreateStatusScreen> createState() => _CreateStatusScreenState();
}

class _CreateStatusScreenState extends State<CreateStatusScreen> {
  static const _palette = <String>[
    "#C75B39", // terracotta
    "#2E6F40", // forest
    "#5A3825", // chocolate
    "#B07D56", // clay
    "#2C3E50",
    "#8E44AD",
    "#16A085",
    "#C0392B",
  ];

  final _textCtrl = TextEditingController();
  int _colorIndex = 0;
  bool _publishing = false;

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) {
      _snack("Écris quelque chose");
      return;
    }
    setState(() => _publishing = true);
    final repo = context.read<StatusRepository>();
    final nav = Navigator.of(context);
    try {
      await repo.createText(text, _palette[_colorIndex]);
      nav.pop(true);
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack("Publication impossible");
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  /// Sélectionne des médias, les téléverse, puis publie un statut par média.
  ///
  /// 🔴 PASSE PAR LE SÉLECTEUR DE LA DISCUSSION, ET C'EST TOUT L'INTÉRÊT.
  ///
  /// L'ancien chemin ouvrait `FilePicker` et envoyait les octets D'ORIGINE :
  /// 3 à 8 Mo pour une photo de téléphone, affichée dans un écran qui n'en
  /// montre qu'un dixième. `MediaGalleryPickerScreen` applique déjà la règle
  /// de `core/compression_image.dart` — miroir du web, bord long 1600 px,
  /// qualité 82, et retour aux octets d'origine à la moindre incertitude.
  /// Écrire une seconde compression ici aurait fait deux règles à tenir
  /// accordées.
  ///
  /// Il corrige au passage un défaut du chemin précédent : le type était
  /// deviné sur l'extension, et seuls `.mov` et `.mp4` étaient reconnus — un
  /// PNG, un WebP ou un GIF partaient étiquetés `image/jpeg`.
  Future<void> _pickAndPublishMedia() async {
    List<MediaPickResult>? choisis;
    try {
      choisis = await MediaGalleryPickerScreen.open(context);
    } catch (_) {
      _snack("Sélection de média indisponible sur cette plateforme");
      return;
    }
    if (choisis == null || choisis.isEmpty || !mounted) return;

    // ⚠️ Une vidéo plus longue que la visionneuse ne sert à rien : elle serait
    // coupée à `dureeVideoStatutMax` à la lecture, APRÈS avoir été téléversée
    // en entier. On le dit avant l'envoi plutôt que de faire payer la donnée.
    if (choisis.any(
        (m) => (m.durationMs ?? 0) > dureeVideoStatutMax.inMilliseconds)) {
      _snack("Une vidéo de statut ne peut pas dépasser "
          "${dureeVideoStatutMax.inSeconds} secondes");
      return;
    }

    setState(() => _publishing = true);
    final media = context.read<MediaRepository>();
    final repo = context.read<StatusRepository>();
    final nav = Navigator.of(context);
    var publies = 0;
    try {
      for (final m in choisis) {
        final uploaded = await media.upload(m.bytes, m.fileName, m.mimeType);
        await repo.createMedia(
          uploaded.id,
          m.mimeType.startsWith('video/') ? 'VIDEO' : 'IMAGE',
        );
        publies++;
      }
      nav.pop(true);
    } on ApiException catch (e) {
      _snack(publies == 0
          ? e.message
          : "$publies statut(s) publié(s), puis : ${e.message}");
    } catch (_) {
      _snack(publies == 0
          ? "Publication du média impossible"
          : "$publies statut(s) publié(s), l'envoi s'est interrompu ensuite");
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final bg = colorFromHex(_palette[_colorIndex]);
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        title: const Text("Nouveau statut"),
        actions: [
          IconButton(
            tooltip: "Publier une photo ou vidéo",
            icon: const Icon(Icons.photo_camera_outlined),
            onPressed: _publishing ? null : _pickAndPublishMedia,
          ),
          IconButton(
            tooltip: "Changer la couleur",
            icon: const Icon(Icons.palette),
            onPressed: () =>
                setState(() => _colorIndex = (_colorIndex + 1) % _palette.length),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: TextField(
                  controller: _textCtrl,
                  maxLength: 700,
                  maxLines: null,
                  textAlign: TextAlign.center,
                  autofocus: true,
                  cursorColor: Colors.white,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    // Contour-matériel (résout le fond blanc hérité du thème global).
                    filled: true,
                    fillColor: Colors.transparent,
                    counterStyle: const TextStyle(color: Colors.white70),
                    hintText: "Tape ton statut…",
                    hintStyle: const TextStyle(color: Colors.white60, fontSize: 24),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _palette.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) => GestureDetector(
                          onTap: () => setState(() => _colorIndex = i),
                          child: Container(
                            width: 40,
                            decoration: BoxDecoration(
                              color: colorFromHex(_palette[i]),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: i == _colorIndex ? Colors.white : Colors.white24,
                                width: i == _colorIndex ? 3 : 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FloatingActionButton(
                    backgroundColor: Colors.white,
                    onPressed: _publishing ? null : _publish,
                    child: _publishing
                        ? const CircularProgressIndicator(color: AlanyaColors.terracotta)
                        : Icon(Icons.send, color: bg),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
