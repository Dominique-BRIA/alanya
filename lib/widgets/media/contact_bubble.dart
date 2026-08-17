import 'package:flutter/material.dart';

import '../../models/message_payload.dart';
import '../../theme/alanya_theme.dart';
import '../avatar_circle.dart';

/// Ce que le destinataire peut faire d'un contact reçu.
///
/// Les trois actions sont fournies par l'écran de discussion : ouvrir une
/// discussion et appeler supposent de créer la conversation et de piloter
/// `CallController`, ce qui n'a rien à faire dans une bulle. L'enregistrement
/// passe par l'écran de création de contact du téléphone (aucune permission
/// d'écriture demandée, l'utilisateur confirme lui-même).
class ContactBubbleActions {
  final void Function(SharedContact contact) onOuvrirDiscussion;
  final void Function(SharedContact contact) onAppeler;
  final void Function(SharedContact contact) onEnregistrer;

  const ContactBubbleActions({
    required this.onOuvrirDiscussion,
    required this.onAppeler,
    required this.onEnregistrer,
  });
}

/// Bulle « fiche de contact » façon WhatsApp.
///
/// Un seul contact → photo, nom, numéro, puis une rangée d'actions.
/// Plusieurs contacts → une ligne de synthèse (« Jean Dupont et 2 autres
/// contacts ») et un bouton « Voir tout » qui déplie la liste, exactement comme
/// WhatsApp : empiler dix fiches dans le fil le rendrait illisible.
class ContactBubble extends StatelessWidget {
  const ContactBubble({
    super.key,
    required this.contacts,
    required this.actions,
    this.photoUrl,
    this.onLongPress,
    this.timestamp,
    this.statusWidget,
    this.isMe = false,
  });

  final List<SharedContact> contacts;
  final ContactBubbleActions actions;

  /// Photo portée par le MÉDIA du message : c'est ainsi qu'arrive la photo d'un
  /// contact du répertoire, la charge JSON ne transportant jamais d'image.
  /// Ne s'applique qu'au partage d'UN seul contact.
  ///
  /// Chemin RELATIF (`/api/media/<id>`) : [AvatarCircle] le résout et va
  /// chercher le jeton lui-même — inutile de le lui passer.
  final String? photoUrl;

  final VoidCallback? onLongPress;
  final String? timestamp;
  final Widget? statusWidget;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final surfaces = surfacesOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final onText = isMe ? surfaces.texteBulleEnvoyee : surfaces.texteBulleRecue;
    final onSub =
        isMe ? Colors.white70 : (dark ? AlanyaColors.craie2 : Colors.black54);
    final trait = isMe
        ? Colors.white.withValues(alpha: 0.25)
        : (dark ? AlanyaColors.ligne : AlanyaColors.sand);

    final multiple = contacts.length > 1;

    return GestureDetector(
      onLongPress: onLongPress,
      child: SizedBox(
        width: 236,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            multiple
                ? _synthese(context, onText, onSub)
                : _fiche(context, contacts.first, onText, onSub),
            const SizedBox(height: 8),
            Divider(height: 1, thickness: 0.5, color: trait),
            const SizedBox(height: 2),
            multiple
                ? _bouton(
                    context,
                    label: "Voir tout",
                    icone: Icons.list_rounded,
                    onTap: () => ContactListSheet.show(
                      context,
                      contacts: contacts,
                      actions: actions,
                    ),
                    onText: onText,
                  )
                : _actionsRow(context, contacts.first, onText),
            if (timestamp != null) ...[
              const SizedBox(height: 2),
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Spacer(),
                Text(timestamp!, style: TextStyle(fontSize: 11, color: onSub)),
                if (statusWidget != null) ...[
                  const SizedBox(width: 3),
                  statusWidget!,
                ],
              ]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _fiche(
      BuildContext context, SharedContact contact, Color onText, Color onSub) {
    final sousTitre = contact.subtitle;
    return Row(children: [
      AvatarCircle(
        name: contact.displayName,
        // La photo du média prime : elle vient du répertoire de l'expéditeur,
        // alors que `avatarUrl` n'existe que pour un compte Alanya.
        avatarUrl: photoUrl ?? contact.avatarUrl,
        radius: 22,
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              contact.displayName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: onText, fontWeight: FontWeight.w600, fontSize: 14.5),
            ),
            if (sousTitre != null) ...[
              const SizedBox(height: 2),
              Text(sousTitre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: onSub)),
            ],
            if (contact.alanyaId != null) ...[
              const SizedBox(height: 2),
              Text("Sur Alanya",
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isMe ? Colors.white70 : positiveOf(context))),
            ],
          ],
        ),
      ),
    ]);
  }

  Widget _synthese(BuildContext context, Color onText, Color onSub) {
    final autres = contacts.length - 1;
    return Row(children: [
      Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: isMe
              ? Colors.white.withValues(alpha: 0.18)
              : AlanyaColors.terracotta.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.contacts_rounded,
            size: 22, color: isMe ? Colors.white : AlanyaColors.terracotta),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              contacts.first.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: onText, fontWeight: FontWeight.w600, fontSize: 14.5),
            ),
            const SizedBox(height: 2),
            Text(
                "et $autres autre${autres > 1 ? "s" : ""} contact${autres > 1 ? "s" : ""}",
                style: TextStyle(fontSize: 12.5, color: onSub)),
          ],
        ),
      ),
    ]);
  }

  Widget _actionsRow(
      BuildContext context, SharedContact contact, Color onText) {
    // Un contact du répertoire n'a pas de compte : lui « ouvrir une
    // discussion » ou l'appeler DANS Alanya n'a aucun sens, et proposer une
    // action qui échoue est pire que ne pas la proposer. Il reste
    // « Enregistrer », qui vaut pour tout le monde.
    final surAlanya = contact.alanyaId != null;
    return Row(children: [
      if (surAlanya)
        Expanded(
          child: _bouton(
            context,
            label: "Message",
            icone: Icons.chat_bubble_outline_rounded,
            onTap: () => actions.onOuvrirDiscussion(contact),
            onText: onText,
          ),
        ),
      if (surAlanya)
        Expanded(
          child: _bouton(
            context,
            label: "Appeler",
            icone: Icons.call_outlined,
            onTap: () => actions.onAppeler(contact),
            onText: onText,
          ),
        ),
      Expanded(
        child: _bouton(
          context,
          label: "Enregistrer",
          icone: Icons.person_add_alt_1_outlined,
          onTap: () => actions.onEnregistrer(contact),
          onText: onText,
        ),
      ),
    ]);
  }

  Widget _bouton(
    BuildContext context, {
    required String label,
    required IconData icone,
    required VoidCallback onTap,
    required Color onText,
  }) {
    final couleur = isMe ? Colors.white : accentOf(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icone, size: 15, color: couleur),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: couleur),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Liste dépliée des contacts d'un partage multiple, avec les mêmes actions
/// que la fiche unique.
class ContactListSheet extends StatelessWidget {
  const ContactListSheet({
    super.key,
    required this.contacts,
    required this.actions,
  });

  final List<SharedContact> contacts;
  final ContactBubbleActions actions;

  static Future<void> show(
    BuildContext context, {
    required List<SharedContact> contacts,
    required ContactBubbleActions actions,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => ContactListSheet(contacts: contacts, actions: actions),
      );

  @override
  Widget build(BuildContext context) {
    final surfaces = surfacesOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fond = dark ? surfaces.surface : Colors.white;
    final onSub = dark ? AlanyaColors.craie2 : Colors.black54;

    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          margin: const EdgeInsets.only(top: 12, bottom: 10),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: AlanyaColors.grey300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Text("${contacts.length} contacts",
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: contacts.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final c = contacts[i];
              return ListTile(
                leading: AvatarCircle(
                    name: c.displayName, avatarUrl: c.avatarUrl, radius: 20),
                title: Text(c.displayName,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: c.subtitle != null
                    ? Text(c.subtitle!,
                        style: TextStyle(fontSize: 12.5, color: onSub))
                    : null,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (c.alanyaId != null)
                    IconButton(
                      tooltip: "Message",
                      icon: const Icon(Icons.chat_bubble_outline_rounded,
                          size: 20),
                      onPressed: () {
                        Navigator.of(context).pop();
                        actions.onOuvrirDiscussion(c);
                      },
                    ),
                  IconButton(
                    tooltip: "Enregistrer",
                    icon: const Icon(Icons.person_add_alt_1_outlined, size: 20),
                    onPressed: () => actions.onEnregistrer(c),
                  ),
                ]),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
      ]),
    );
  }
}
