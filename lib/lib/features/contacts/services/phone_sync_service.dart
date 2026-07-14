import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as fc;
import 'package:permission_handler/permission_handler.dart';

import '../../../models/contact.dart';

/// Un contact du répertoire téléphonique qui correspond à un compte Alanya.
class PhoneContactMatch {
  /// Nom affiché dans le répertoire téléphonique natif.
  final String phoneName;

  /// Résultat renvoyé par le backend.
  final UserSearchResult alanyaUser;

  PhoneContactMatch({required this.phoneName, required this.alanyaUser});
}

/// Service qui :
/// 1. Demande la permission d'accès aux contacts
/// 2. Lit le répertoire téléphonique natif
/// 3. Extrait tous les numéros à 6 ou 8 chiffres (en supprimant espaces/tirets)
/// 4. Envoie une requête batch au backend pour savoir lesquels sont sur Alanya
/// 5. Renvoie la liste des correspondances
class PhoneSyncService {
  PhoneSyncService(this._matchFn);

  /// Fonction qui appelle POST /api/users/match avec un tableau de numéros.
  final Future<List<UserSearchResult>> Function(List<String> numbers) _matchFn;

  /// Vérifie si l'app a la permission d'accéder aux contacts.
  Future<bool> hasPermission() async {
    if (kIsWeb) return false;
    final status = await Permission.contacts.status;
    return status.isGranted;
  }

  /// Demande la permission si nécessaire. Retourne true si accordée.
  Future<bool> requestPermission() async {
    if (kIsWeb) return false;
    final status = await Permission.contacts.request();
    return status.isGranted;
  }

  /// Lance la synchronisation complète.
  /// [onProgress] est appelé avec un message décrivant l'étape en cours.
  Future<PhoneSyncResult> sync({void Function(String)? onProgress}) async {
    // 1. Permission
    onProgress?.call("Demande de permission…");
    final granted = await requestPermission();
    if (!granted) {
      return PhoneSyncResult.permissionDenied();
    }

    // 2. Lecture des contacts
    onProgress?.call("Lecture du répertoire…");
    List<fc.Contact> phoneContacts;
    try {
      phoneContacts = await fc.FlutterContacts.getContacts(
        withProperties: true, // charge les numéros de téléphone
        withPhoto: false,
      );
    } catch (e) {
      return PhoneSyncResult.error("Impossible de lire les contacts : $e");
    }

    if (phoneContacts.isEmpty) {
      return PhoneSyncResult.empty();
    }

    // 3. Extraction des numéros à 6 ou 8 chiffres
    onProgress?.call("Analyse des ${phoneContacts.length} contacts…");
    final Map<String, String> numberToName = {}; // numéro → nom affiché
    final _sixDigits = RegExp(r'^(\d{6}|\d{8})$');

    for (final contact in phoneContacts) {
      final displayName = contact.displayName.trim();

      for (final phone in contact.phones) {
        // Normalise : supprime espaces, tirets, parenthèses, +
        final cleaned = phone.number
            .replaceAll(RegExp(r'[\s\-\(\)\+]'), '')
            .trim();

        // Ne garde que les chaînes de exactement 6 ou 8 chiffres
        if (_sixDigits.hasMatch(cleaned)) {
          // Si plusieurs contacts ont le même numéro, on garde le premier nom trouvé
          numberToName.putIfAbsent(cleaned, () => displayName.isNotEmpty ? displayName : cleaned);
        }
      }
    }

    if (numberToName.isEmpty) {
      return PhoneSyncResult.noAlanyaNumbers();
    }

    // 4. Requête batch au backend
    onProgress?.call("Vérification de ${numberToName.length} numéros sur Alanya…");
    List<UserSearchResult> matched;
    try {
      matched = await _matchFn(numberToName.keys.toList());
    } catch (e) {
      return PhoneSyncResult.error("Erreur réseau : $e");
    }

    if (matched.isEmpty) {
      return PhoneSyncResult.noMatches(numberToName.length);
    }

    // 5. Croise les résultats avec les noms du répertoire
    final results = matched.map((user) {
      final phoneName = numberToName[user.publicNumber] ?? user.publicNumber;
      return PhoneContactMatch(phoneName: phoneName, alanyaUser: user);
    }).toList();

    return PhoneSyncResult.success(
      matches: results,
      totalScanned: numberToName.length,
    );
  }
}

// ---------------------------------------------------------------------------

enum PhoneSyncStatus {
  success,
  permissionDenied,
  empty,
  noAlanyaNumbers,
  noMatches,
  error,
}

class PhoneSyncResult {
  final PhoneSyncStatus status;
  final List<PhoneContactMatch> matches;
  final int totalScanned;
  final String? errorMessage;

  PhoneSyncResult._({
    required this.status,
    this.matches = const [],
    this.totalScanned = 0,
    this.errorMessage,
  });

  factory PhoneSyncResult.success({
    required List<PhoneContactMatch> matches,
    required int totalScanned,
  }) =>
      PhoneSyncResult._(
        status: PhoneSyncStatus.success,
        matches: matches,
        totalScanned: totalScanned,
      );

  factory PhoneSyncResult.permissionDenied() =>
      PhoneSyncResult._(status: PhoneSyncStatus.permissionDenied);

  factory PhoneSyncResult.empty() =>
      PhoneSyncResult._(status: PhoneSyncStatus.empty);

  factory PhoneSyncResult.noAlanyaNumbers() =>
      PhoneSyncResult._(status: PhoneSyncStatus.noAlanyaNumbers);

  factory PhoneSyncResult.noMatches(int scanned) =>
      PhoneSyncResult._(status: PhoneSyncStatus.noMatches, totalScanned: scanned);

  factory PhoneSyncResult.error(String msg) =>
      PhoneSyncResult._(status: PhoneSyncStatus.error, errorMessage: msg);

  bool get isSuccess => status == PhoneSyncStatus.success;
}
