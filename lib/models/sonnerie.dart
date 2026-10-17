/// Une sonnerie importée, inscrite au catalogue du compte.
///
/// ⚠️ MIROIR de `SonnerieJson` dans `backend-alanya/src/lib/ringtones.ts`.
///
/// 🔴 LE CATALOGUE PEUT CITER UN MÉDIA EFFACÉ, et le serveur le dit
/// explicitement : il rend ses entrées « telles quelles, sans vérifier que
/// chaque média existe encore. Ce serait une requête par ligne pour un cas rare,
/// et cela ne réglerait rien : le média peut disparaître entre cette lecture et
/// le moment où le client joue le son. »
///
/// **C'est donc au client d'écarter ce qui répond 404.** Une entrée de catalogue
/// n'est pas une promesse que le fichier est là.
class Sonnerie {
  const Sonnerie({
    required this.id,
    required this.url,
    required this.label,
    required this.createdAt,
  });

  final String id;

  /// Toujours de la forme `/api/media/<id>` — le serveur la refuse autrement.
  ///
  /// ⚠️ C'est la MÊME valeur que `ContactList.ringtone` : les deux colonnes se
  /// comparent directement, sans rien recomposer. Ne jamais la transformer avant
  /// de l'envoyer.
  final String url;

  final String label;
  final DateTime createdAt;

  static Sonnerie fromJson(Map<String, dynamic> j) => Sonnerie(
        id: j["id"] as String,
        url: j["url"] as String? ?? "",
        label: j["label"] as String? ?? "",
        createdAt: DateTime.tryParse(j["createdAt"] as String? ?? "") ??
            DateTime.now(),
      );
}
