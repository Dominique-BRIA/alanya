/// Charges utiles des messages `CONTACT` et `LOCATION`.
///
/// ⚠️ **MIROIR EXACT de `backend-alanya/src/lib/message-payload.mjs`.** Le
/// format est décidé côté serveur — seul point que les trois clients (ce
/// mobile, le web React, l'application de l'équipe) traversent — et le serveur
/// REFUSE à l'entrée une charge qui ne s'y conforme pas. Toute évolution se
/// fait là-bas d'abord ; changer ce fichier seul reproduirait la panne des
/// appels Web → Android, où une règle partagée avait été modifiée d'un seul
/// côté.
///
/// Rappel du format :
///
///   CONTACT  {"v":1,"contacts":[{"name":"Jean Dupont",
///                               "phones":["+237691234567"],
///                               "alanyaId":"12345678",
///                               "avatarUrl":"https://…"}]}
///
///   LOCATION {"v":1,"location":{"lat":3.848,"lng":11.502,
///                               "accuracy":12.5,"label":"Douala"}}
///
/// La PHOTO d'un contact du répertoire n'est jamais dans la charge : elle est
/// envoyée comme média du message (`media.first`), `content` étant plafonné à
/// 8000 caractères par la validation serveur.
library;

import 'dart:convert';

const int versionCharge = 1;

/// Un contact partagé dans une discussion.
class SharedContact {
  final String? name;
  final List<String> phones;

  /// Alanya ID, quand la personne a un compte : c'est lui qui permet d'ouvrir
  /// une discussion ou de l'appeler dans l'application. Nul pour un contact
  /// venu du répertoire téléphonique.
  final String? alanyaId;

  /// Photo déjà servie par le serveur (avatar d'un compte Alanya). Pour un
  /// contact du répertoire, la photo arrive par le média du message.
  final String? avatarUrl;

  const SharedContact({
    this.name,
    this.phones = const [],
    this.alanyaId,
    this.avatarUrl,
  });

  /// Titre affichable : le nom, sinon le premier numéro, sinon « Contact ».
  String get displayName {
    final n = name?.trim();
    if (n != null && n.isNotEmpty) return n;
    if (phones.isNotEmpty) return phones.first;
    return "Contact";
  }

  /// Sous-titre : le premier numéro s'il ne fait pas déjà office de titre.
  String? get subtitle {
    if (phones.isEmpty) return null;
    return displayName == phones.first ? null : phones.first;
  }

  Map<String, dynamic> toJson() => {
        if (name != null && name!.trim().isNotEmpty) "name": name!.trim(),
        if (phones.isNotEmpty) "phones": phones,
        if (alanyaId != null) "alanyaId": alanyaId,
        if (avatarUrl != null) "avatarUrl": avatarUrl,
      };
}

/// Une position GPS partagée dans une discussion.
class SharedLocation {
  final double lat;
  final double lng;

  /// Précision annoncée par le GPS, en mètres. Affichée telle quelle : une
  /// position à 2 000 m près n'est pas une position, et le destinataire doit
  /// pouvoir en juger.
  final double? accuracy;
  final String? label;

  const SharedLocation({
    required this.lat,
    required this.lng,
    this.accuracy,
    this.label,
  });

  Map<String, dynamic> toJson() => {
        "lat": lat,
        "lng": lng,
        if (accuracy != null) "accuracy": accuracy,
        if (label != null && label!.trim().isNotEmpty) "label": label!.trim(),
      };
}

Map<String, dynamic>? _litJson(String? content) {
  if (content == null || content.isEmpty) return null;
  try {
    final valeur = jsonDecode(content);
    return valeur is Map<String, dynamic> ? valeur : null;
  } catch (_) {
    // Un contenu qui n'est pas du JSON n'est pas une erreur à signaler : c'est
    // le cas de tous les messages TEXT, et de tout message CONTACT qui aurait
    // été écrit par un client plus ancien. L'appelant retombe sur son repli.
    return null;
  }
}

/// Nombre d'une charge JSON, ou `null` si ce n'en est pas un.
///
/// ⚠️ NE PAS revenir à `as num?` : sur `{"lat":"ici"}`, le transtypage LÈVE une
/// exception au lieu de rendre nul, et l'exception part depuis un `build()` —
/// donc écran rouge dans le fil de discussion. Le serveur, lui, se contente de
/// refuser la charge (`Number("ici")` vaut NaN). Le miroir doit refuser de la
/// même façon, pas plus brutalement. Attrapé en exécutant les cas de contrôle,
/// et invisible à `flutter analyze`.
double? _nombre(Object? valeur) => valeur is num ? valeur.toDouble() : null;

String? _texte(Object? valeur, int maxi) {
  if (valeur is! String) return null;
  final t = valeur.trim();
  if (t.isEmpty) return null;
  return t.length > maxi ? t.substring(0, maxi) : t;
}

/// Contacts portés par un message `CONTACT`, ou `null` si la charge est
/// invalide ou absente. Mêmes règles de rejet que le serveur : un contact sans
/// nom ET sans numéro n'a rien d'affichable.
List<SharedContact>? contactsDepuisContenu(String? content) {
  final brut = _litJson(content)?["contacts"];
  if (brut is! List || brut.isEmpty) return null;

  final contacts = <SharedContact>[];
  for (final c in brut) {
    if (c is! Map) continue;
    final name = _texte(c["name"], 200);
    final phones = <String>[];
    final phonesBrut = c["phones"];
    if (phonesBrut is List) {
      for (final p in phonesBrut) {
        final t = _texte(p, 40);
        if (t != null) phones.add(t);
        if (phones.length >= 10) break;
      }
    }
    if (name == null && phones.isEmpty) continue;
    contacts.add(SharedContact(
      name: name,
      phones: phones,
      alanyaId: _texte(c["alanyaId"], 10),
      avatarUrl: _texte(c["avatarUrl"], 500),
    ));
  }
  if (contacts.isEmpty) return null;
  return contacts.length > 10 ? contacts.sublist(0, 10) : contacts;
}

/// Position portée par un message `LOCATION`, ou `null` si la charge est
/// invalide. Les bornes sont celles du serveur : une longitude hors [-180, 180]
/// n'afficherait qu'une carte vide, sans dire d'où vient le problème.
SharedLocation? positionDepuisContenu(String? content) {
  final brut = _litJson(content)?["location"];
  if (brut is! Map) return null;

  final lat = _nombre(brut["lat"]);
  final lng = _nombre(brut["lng"]);
  if (lat == null || lng == null) return null;
  if (lat.isNaN || lng.isNaN || lat.isInfinite || lng.isInfinite) return null;
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;

  final acc = _nombre(brut["accuracy"]);
  return SharedLocation(
    lat: lat,
    lng: lng,
    accuracy: (acc != null && !acc.isNaN && acc >= 0) ? acc : null,
    label: _texte(brut["label"], 200),
  );
}

/// Encode la charge d'un message `CONTACT`.
String encodeContacts(List<SharedContact> contacts) => jsonEncode({
      "v": versionCharge,
      "contacts": contacts.map((c) => c.toJson()).toList(),
    });

/// Encode la charge d'un message `LOCATION`.
String encodeLocation(SharedLocation position) => jsonEncode({
      "v": versionCharge,
      "location": position.toJson(),
    });

/// Libellé court d'un message structuré, pour les endroits qui n'affichent
/// qu'une ligne : citation d'une réponse, bandeau du message épinglé, favoris.
///
/// ⚠️ Sans lui, ces endroits afficheraient la charge JSON brute — ils lisent
/// tous `content` directement. Renvoie `null` pour un type non structuré, afin
/// que l'appelant garde son comportement d'origine.
String? apercuStructure(String type, String? content) {
  if (type == "CONTACT") {
    final contacts = contactsDepuisContenu(content);
    if (contacts == null) return "👤 Contact";
    final premier = contacts.first.displayName;
    if (contacts.length == 1) return "👤 $premier";
    final autres = contacts.length - 1;
    return "👤 $premier et $autres autre${autres > 1 ? "s" : ""}";
  }
  if (type == "LOCATION") {
    final position = positionDepuisContenu(content);
    if (position == null) return "📍 Position";
    final label = position.label;
    return label != null ? "📍 $label" : "📍 Position partagée";
  }
  return null;
}
