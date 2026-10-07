/// LES DÉLAIS POUR REVENIR SUR UN MESSAGE — décision du user, 07/10/2026.
///
///   - MODIFIER : 2 heures après l'envoi ;
///   - SUPPRIMER POUR TOUT LE MONDE : 24 heures après l'envoi.
///
/// « Supprimer pour moi » n'a pas de délai : il ne touche que son propre écran.
///
/// ⚠️ L'ÉCRAN ANTICIPE, LE SERVEUR TRANCHE. Ces fonctions ne servent qu'à ne
/// pas proposer une action que le serveur refuserait — sa règle, sur SON
/// horloge, vit dans `backend-alanya/src/lib/delais-message.mjs`. Mêmes
/// valeurs que le web (`src/lib/delais-message.ts`).
library;

const Duration delaiModification = Duration(hours: 2);
const Duration delaiSuppressionPourTous = Duration(hours: 24);

/// Les codes que rend le serveur quand le délai est dépassé.
const String delaiModificationDepasse = 'DELAI_MODIFICATION_DEPASSE';
const String delaiSuppressionDepasse = 'DELAI_SUPPRESSION_DEPASSE';

bool peutEncoreModifier(DateTime envoyeLe, {DateTime? maintenant}) =>
    (maintenant ?? DateTime.now()).difference(envoyeLe) <= delaiModification;

bool peutEncoreSupprimerPourTous(DateTime envoyeLe, {DateTime? maintenant}) =>
    (maintenant ?? DateTime.now()).difference(envoyeLe) <=
    delaiSuppressionPourTous;
