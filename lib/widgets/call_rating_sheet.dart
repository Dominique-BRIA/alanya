import 'package:flutter/material.dart';
import '../core/authed_api.dart';
import '../theme/alanya_theme.dart';

/// Modal d'évaluation de l'appel post-communication (Note sur 5 étoiles + Avis).
class CallRatingSheet extends StatefulWidget {
  final String idHist;
  final AuthedApi api;

  const CallRatingSheet({
    super.key,
    required this.idHist,
    required this.api,
  });

  static Future<void> show(BuildContext context, {required String idHist, required AuthedApi api}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CallRatingSheet(idHist: idHist, api: api),
    );
  }

  @override
  State<CallRatingSheet> createState() => _CallRatingSheetState();
}

class _CallRatingSheetState extends State<CallRatingSheet> {
  int _rating = 5;
  final TextEditingController _commentCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      await widget.api.post('/api/queue/rate', {
        'idHist': widget.idHist,
        'note': _rating,
        'avisCommentaire': _commentCtrl.text.trim(),
      });
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Merci pour votre évaluation !"),
            backgroundColor: AlanyaColors.forest,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erreur d'envoi de la note: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomPadding),
      decoration: const BoxDecoration(
        color: Color(0xFF1F2C34),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Poignée
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: Colors.white30,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          const Text(
            "Évaluez votre appel",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 6),
          const Text(
            "Comment s'est passée votre communication avec l'agent ?",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.white70),
          ),
          const SizedBox(height: 20),

          // Étoiles (1 à 5)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final starIndex = i + 1;
              final isFilled = starIndex <= _rating;
              return IconButton(
                iconSize: 36,
                icon: Icon(
                  isFilled ? Icons.star : Icons.star_border,
                  color: isFilled ? AlanyaColors.gold : Colors.white38,
                ),
                onPressed: () => setState(() => _rating = starIndex),
              );
            }),
          ),
          const SizedBox(height: 16),

          // Champ de commentaire
          TextField(
            controller: _commentCtrl,
            maxLines: 3,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: "Un commentaire ou une remarque ? (optionnel)",
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
              filled: true,
              fillColor: const Color(0xFF2A3942),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 20),

          // Boutons
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: _submitting ? null : () => Navigator.of(context).pop(),
                  child: const Text("Passer", style: TextStyle(color: Colors.white60)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AlanyaColors.gold,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text("Envoyer", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
