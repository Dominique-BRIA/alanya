import 'package:flutter/material.dart';

import '../../models/message_payload.dart';
import '../../theme/alanya_theme.dart';
import '../avatar_circle.dart';

/// Ce que le destinataire peut faire d'un contact reçu.
///
/// Les trois actions sont fournies par l'écran de discussion : elles supposent
/// de créer une conversation, de piloter `CallController` ou d'écrire dans le
/// répertoire Alanya — rien de tout cela n'a sa place dans une bulle.
///
/// « Ajouter » ajoute la personne aux contacts **Alanya**, et non au carnet
/// d'adresses du téléphone : c'est le répertoire dont cette application se
/// sert pour retrouver quelqu'un, l'appeler et lui écrire.
class ContactBubbleActions {
  final void Function(SharedContact contact) onOuvrirDiscussion;
  final void Function(SharedContact contact) onAppeler;
  final void Function(SharedContact contact) onAjouter;

  const ContactBubbleActions({
    required this.onOuvrirDiscussion,
    required this.onAppeler,
    required this.onAjouter,
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
    this.onLongPress,
    this.timestamp,
    this.statusWidget,
    this.isMe = false,
  });

  final List<SharedContact> contacts;
  final ContactBubbleActions actions;

  final VoidCallback? onLongPress;
  final String? timestamp;
  final Widget? statusWidget;
  final bool isMe;

  /// Fond de l'avatar quand le contact n'a pas de photo.
  ///
  /// 🐛 **Signalé sur device le 17/08/2026 : orange sur orange.** [AvatarCircle]
  /// prend le terre cuite par défaut — la couleur de la bulle ENVOYÉE. Une
  /// pastille terre cuite posée sur une bulle terre cuite disparaissait dans son
  /// fond, et l'initiale blanche flottait sans support.
  ///
  /// Ce vert est choisi pour tenir face aux DEUX fonds, ce qui est la vraie
  /// contrainte ici : la bulle envoyée (terre cuite) et la bulle reçue (blanche
  /// en clair, sombre en Nuit). Il est assez soutenu pour que l'initiale blanche
  /// reste lisible, et assez distinct du terre cuite pour ne pas s'y fondre —
  /// vert et orange sont opposés en teinte, c'est ce qui fait ressortir la
  /// pastille quel que soit le côté de la conversation.
  static const Color _fondAvatar = Color(0xFF3FA971);

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
        // L'avatar du compte Alanya, tel qu'il est en base : chemin relatif,
        // URL absolue ou image base64 — `AvatarCircle` traite les trois formes
        // et va chercher le jeton lui-même.
        name: contact.displayName,
        avatarUrl: contact.avatarUrl,
        radius: 22,
        backgroundColor: _fondAvatar,
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
    // Toutes les fiches partagées viennent des contacts Alanya, donc les trois
    // actions ont toujours un sens. La garde reste néanmoins : la charge peut
    // avoir été écrite par un autre client, et proposer « Appeler » sur une
    // fiche sans Alanya ID donnerait un bouton qui échoue.
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
      if (surAlanya)
        Expanded(
          child: _bouton(
            context,
            label: "Ajouter",
            icone: Icons.person_add_alt_1_outlined,
            onTap: () => actions.onAjouter(contact),
            onText: onText,
          ),
        ),
      // Fiche sans Alanya ID (client tiers) : rien à faire dans l'application,
      // on affiche au moins le numéro, déjà rendu au-dessus.
      if (!surAlanya)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text("Contact hors Alanya",
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12,
                    color: isMe ? Colors.white70 : AlanyaColors.grey500)),
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
                    name: c.displayName,
                    avatarUrl: c.avatarUrl,
                    radius: 20,
                    // Même vert que la fiche : la liste dépliée et la bulle
                    // montrent les mêmes contacts, ils doivent se reconnaître.
                    backgroundColor: ContactBubble._fondAvatar),
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
                  if (c.alanyaId != null)
                    IconButton(
                      tooltip: "Ajouter à mes contacts",
                      icon:
                          const Icon(Icons.person_add_alt_1_outlined, size: 20),
                      onPressed: () => actions.onAjouter(c),
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
