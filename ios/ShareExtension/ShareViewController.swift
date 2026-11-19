import share_handler_ios_models

/// L'EXTENSION DE PARTAGE (19/11/2026) : « Partager » depuis une autre
/// application → Alanya Work. Elle n'a pas d'écran à elle : le module
/// `share_handler` range le contenu dans le groupe d'applications, puis ouvre
/// Alanya, où `partage_entrant.dart` propose la discussion.
class ShareViewController: ShareHandlerIosViewController {}
