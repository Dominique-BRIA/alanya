/// Âge d'un statut, en toutes lettres.
///
/// Deux écrans affichent cet âge — la liste de l'onglet Status et l'en-tête de
/// la visionneuse. Ils doivent dire la même chose au même moment, d'où cette
/// fonction partagée plutôt qu'une copie de chaque côté.
///
/// Un statut vit 24 h : au-delà de « il y a 23 h » il a normalement disparu du
/// fil. La branche en jours reste par sûreté, elle ne coûte rien.
String horodatageStatut(DateTime creeLe) {
  final diff = DateTime.now().difference(creeLe);
  if (diff.inMinutes < 1) return "à l'instant";
  if (diff.inMinutes < 60) return "il y a ${diff.inMinutes} min";
  if (diff.inHours < 24) return "il y a ${diff.inHours} h";
  return "il y a ${diff.inDays} j";
}
