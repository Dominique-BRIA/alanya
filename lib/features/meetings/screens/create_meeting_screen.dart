import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/back_app_bar.dart';
import '../meetings_repository.dart';

/// Écran de création d'une réunion audio ou vidéo.
class CreateMeetingScreen extends StatefulWidget {
  const CreateMeetingScreen({super.key});

  @override
  State<CreateMeetingScreen> createState() => _CreateMeetingScreenState();
}

class _CreateMeetingScreenState extends State<CreateMeetingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _objetCtrl = TextEditingController();
  final _participantsCtrl = TextEditingController();
  int _typeMedia = 1; // 1 = audio, 2 = vidéo
  int _duree = 3600; // 1h par défaut
  bool _loading = false;

  @override
  void dispose() {
    _objetCtrl.dispose();
    _participantsCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      // Parse les numéros séparés par des virgules.
      final raw = _participantsCtrl.text.trim();
      final numbers = raw.isEmpty
          ? <String>[]
          : raw
              .split(RegExp(r'[,\s]+'))
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();

      await context.read<MeetingsRepository>().createMeeting(
            objet: _objetCtrl.text.trim(),
            typeMedia: _typeMedia,
            duree: _duree,
            participantNumbers: numbers.isEmpty ? null : numbers,
          );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Réunion créée !")),
      );
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Erreur serveur")),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: backAppBar(context, "Nouvelle réunion"),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- Type de réunion ---
              const Text("Type de réunion",
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(
                    value: 1,
                    label: Text("Audio"),
                    icon: Icon(Icons.call),
                  ),
                  ButtonSegment(
                    value: 2,
                    label: Text("Vidéo"),
                    icon: Icon(Icons.videocam),
                  ),
                ],
                selected: {_typeMedia},
                onSelectionChanged: (s) =>
                    setState(() => _typeMedia = s.first),
              ),
              const SizedBox(height: 20),

              // --- Objet ---
              TextFormField(
                controller: _objetCtrl,
                decoration: const InputDecoration(
                  labelText: "Objet de la réunion",
                  prefixIcon: Icon(Icons.subject),
                ),
                validator: (v) =>
                    (v ?? "").trim().isEmpty ? "L'objet est requis" : null,
              ),
              const SizedBox(height: 16),

              // --- Participants ---
              TextFormField(
                controller: _participantsCtrl,
                decoration: const InputDecoration(
                  labelText: "Participants (numéros Alanya)",
                  hintText: "Ex: 67641599, 69912345",
                  prefixIcon: Icon(Icons.people_outline),
                ),
                keyboardType: TextInputType.text,
              ),
              const SizedBox(height: 8),
              const Text(
                "Sépare les numéros par des virgules. Laisse vide pour une réunion solo.",
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 20),

              // --- Durée ---
              const Text("Durée prévue",
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                value: _duree,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.timer_outlined),
                ),
                items: const [
                  DropdownMenuItem(value: 900, child: Text("15 minutes")),
                  DropdownMenuItem(value: 1800, child: Text("30 minutes")),
                  DropdownMenuItem(value: 3600, child: Text("1 heure")),
                  DropdownMenuItem(value: 5400, child: Text("1h30")),
                  DropdownMenuItem(value: 7200, child: Text("2 heures")),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _duree = v);
                },
              ),
              const SizedBox(height: 32),

              // --- Bouton créer ---
              ElevatedButton.icon(
                onPressed: _loading ? null : _submit,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.add),
                label: const Text("Créer la réunion"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
