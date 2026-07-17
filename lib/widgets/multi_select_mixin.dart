import 'package:flutter/material.dart';
import '../theme/alanya_theme.dart';

/// Mixin réutilisable pour ajouter le mode sélection multiple à une liste.
///
/// Usage :
/// ```dart
/// class _MyScreenState extends State<MyScreen> with MultiSelectMixin<String> {
///   @override
///   Widget build(BuildContext context) {
///     return Scaffold(
///       appBar: isSelecting ? selectAppBar(...) : normalAppBar(),
///       body: ListView.builder(
///         itemBuilder: (_, i) => ListTile(
///           onTap: () => isSelecting ? toggleSelect(items[i].id) : openItem(items[i]),
///           onLongPress: () => startSelecting(items[i].id),
///           leading: isSelecting ? selectCheckbox(items[i].id) : ...,
///         ...
///       ),
///     );
///   }
/// }
/// ```
mixin MultiSelectMixin<T extends StatefulWidget> on State<T> {
  final Set<String> _selectedIds = {};

  bool get isSelecting => _selectedIds.isNotEmpty;
  int get selectedCount => _selectedIds.length;
  Set<String> get selectedIds => Set.from(_selectedIds);

  void startSelecting(String id) {
    setState(() {
      _selectedIds.add(id);
    });
  }

  void toggleSelect(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void selectAll(List<String> allIds) {
    setState(() {
      _selectedIds.addAll(allIds);
    });
  }

  void clearSelection() {
    setState(() {
      _selectedIds.clear();
    });
  }

  bool isSelected(String id) => _selectedIds.contains(id);

  /// AppBar à afficher en mode sélection.
  PreferredSizeWidget selectAppBar({
    required String title,
    required VoidCallback onDelete,
    required VoidCallback onCancel,
    VoidCallback? onSelectAll,
  }) {
    return AppBar(
      backgroundColor: AlanyaColors.terracotta,
      foregroundColor: Colors.white,
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: onCancel,
      ),
      title: Text("$title ($_selectedIds.length)"),
      actions: [
        if (onSelectAll != null)
          IconButton(
            icon: const Icon(Icons.select_all),
            tooltip: "Tout sélectionner",
            onPressed: onSelectAll,
          ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: "Supprimer",
          onPressed: onDelete,
        ),
      ],
    );
  }

  /// Checkbox visuel pour le mode sélection.
  Widget selectCheckbox(String id) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isSelected(id) ? AlanyaColors.terracotta : Colors.transparent,
        border: Border.all(
          color: isSelected(id) ? AlanyaColors.terracotta : AlanyaColors.grey400,
          width: 2,
        ),
      ),
      child: isSelected(id)
          ? const Icon(Icons.check, size: 16, color: Colors.white)
          : null,
    );
  }
}
