import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_snackbar.dart';
import '../../core/conversation_cache.dart';
import '../../core/partage_entrant.dart';
import '../../l10n/app_localizations.dart';
import '../../models/conversation.dart';
import '../auth/auth_controller.dart';
import 'chat_repository.dart';
import 'screens/chat_screen.dart';

/// UN PARTAGE REÇU D'UNE AUTRE APPLICATION (07/10/2026) : on choisit la
/// conversation, puis l'écran de discussion fait le reste — aperçu et légende
/// pour un fichier, texte prêt à envoyer dans le champ, chiffré si le fil
/// l'est. Si l'utilisateur a choisi un contact Alanya directement dans la
/// feuille de partage, on va droit à sa conversation.
Future<void> traiterPartageRecu(BuildContext context, PartageRecu partage) async {
  final chat = context.read<ChatRepository>();
  final moi = context.read<AuthController>().user?.id;
  /*
   * 🐛 LE PARTAGE ÉTAIT PERDU EN SILENCE quand la liste ne se chargeait pas
   * (signalé par le user le 13/10/2026 : « ça ouvre l'application, mais on ne
   * voit rien »). Le partage avait DÉJÀ été consommé par `prendre()` : ce
   * `return` le jetait pour de bon, sans un mot.
   *
   * ⚠️ UNE APPLICATION LANCÉE PAR UN PARTAGE L'EST SUR UNE CONNEXION À PEINE
   * RÉVEILLÉE : l'échec réseau est le cas NORMAL ici, pas l'exception. On
   * retombe donc sur les conversations du CACHE, qui suffisent amplement à
   * choisir où envoyer.
   */
  List<Conversation> conversations;
  try {
    conversations = await chat.listConversations();
  } catch (_) {
    try {
      conversations = await ConversationCache.getAll();
    } catch (_) {
      conversations = const [];
    }
  }
  if (!context.mounted) return;

  /*
   * ⚠️ ET SI L'ON N'A VRAIMENT RIEN : ON LE DIT. Ouvrir une feuille vide, ou
   * ne rien faire du tout, laisse quelqu'un devant une application qui vient
   * de s'ouvrir sans raison apparente — c'est exactement ce qu'il a décrit.
   */
  if (conversations.isEmpty) {
    showAppSnackBar(tr(context, 'partage_aucune_conversation'));
    return;
  }

  Conversation? cible;
  if (partage.conversationId != null) {
    for (final c in conversations) {
      if (c.id == partage.conversationId) cible = c;
    }
  }
  cible ??= await showModalBottomSheet<Conversation>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ChoixConversation(conversations: conversations, moi: moi),
  );
  if (cible == null || !context.mounted) return;

  ConvMember? autre;
  if (!cible.isGroup) {
    for (final m in cible.members) {
      if (m.id != moi) autre = m;
    }
  }
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ChatScreen(
        convId: cible!.id,
        title: titrePartage(cible, autre) ?? tr(context, 'chat_untitled'),
        isGroup: cible.isGroup,
        memberNames: cible.memberNames,
        avatarUrl: cible.avatarUrl,
        otherUserId: autre?.id,
        otherPublicNumber: autre?.publicNumber,
        otherIsOnline: autre?.isOnline ?? 0,
        otherLastSeen: autre?.lastSeen,
        partage: partage,
      ),
    ),
  );
}

/// Le nom sous lequel une conversation est proposée.
String? titrePartage(Conversation c, ConvMember? autre) {
  final titre = (c.title ?? '').trim();
  if (titre.isNotEmpty) return titre;
  final pseudo = (autre?.pseudo ?? '').trim();
  if (pseudo.isNotEmpty) return pseudo;
  return autre?.publicNumber;
}

class _ChoixConversation extends StatefulWidget {
  const _ChoixConversation({required this.conversations, required this.moi});
  final List<Conversation> conversations;
  final String? moi;

  @override
  State<_ChoixConversation> createState() => _ChoixConversationState();
}

class _ChoixConversationState extends State<_ChoixConversation> {
  String _filtre = '';

  String _titre(Conversation c) {
    ConvMember? autre;
    if (!c.isGroup) {
      for (final m in c.members) {
        if (m.id != widget.moi) autre = m;
      }
    }
    return titrePartage(c, autre) ?? tr(context, 'chat_untitled');
  }

  @override
  Widget build(BuildContext context) {
    final f = _filtre.toLowerCase();
    final liste = [
      for (final c in widget.conversations)
        if (f.isEmpty || _titre(c).toLowerCase().contains(f)) c,
    ];
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(tr(context, 'share'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: tr(context, 'search'),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _filtre = v.trim()),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: liste.length,
              itemBuilder: (_, i) {
                final c = liste[i];
                final titre = _titre(c);
                return ListTile(
                  leading: CircleAvatar(
                    child: c.isGroup
                        ? const Icon(Icons.group)
                        : Text(titre.isEmpty ? '?' : titre.characters.first.toUpperCase()),
                  ),
                  title: Text(titre, maxLines: 1, overflow: TextOverflow.ellipsis),
                  // 🔴 PLUS DE CADENAS (décision du user, 13/10/2026). Le
                  // chiffrement est partout et par défaut : le montrer sur
                  // CERTAINES conversations laissait croire que les autres ne
                  // le sont pas, et donnait à l'utilisateur une distinction
                  // qu'il n'a pas à connaître.
                  onTap: () => Navigator.of(context).pop(c),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
