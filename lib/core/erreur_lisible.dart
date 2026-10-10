/// DIRE CE QUI A VRAIMENT ÉCHOUÉ.
///
/// 🔴 CE FICHIER EXISTE À CAUSE D'UN DIAGNOSTIC MENSONGER. Les écrans
/// d'authentification faisaient tous la même chose :
///
/// ```dart
/// } on ApiException catch (e) {
///   showAppSnackBar(e.message);
/// } catch (_) {
///   showAppSnackBar(tr(context, 'server_unreachable'));   // ← le mensonge
/// }
/// ```
///
/// Le `catch (_)` attrape TOUT ce qui n'est pas une `ApiException` : une clé
/// invalide dans le coffre sécurisé, un champ manquant dans la réponse, une
/// conversion de type ratée, une préférence illisible. Et il annonce chacune
/// de ces pannes sous le même nom : « Impossible de contacter le serveur. »
///
/// ⚠️ MESURÉ : le serveur répondait en une seconde pendant que l'application
/// affirmait ne pas pouvoir le joindre. Le message n'était pas approximatif,
/// il était FAUX — et il envoyait chercher la panne exactement là où elle
/// n'était pas.
///
/// ⚠️ UN MESSAGE D'ERREUR EST UN OUTIL DE DIAGNOSTIC AVANT D'ÊTRE UNE
/// POLITESSE. Celui qui range toutes les pannes sous une seule étiquette coûte
/// plus cher que pas de message du tout : il donne une piste, et elle est
/// fausse.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import 'api_client.dart';
import '../l10n/app_localizations.dart';

/// Vrai seulement si le serveur est RÉELLEMENT hors d'atteinte.
///
/// ⚠️ LA LISTE EST COURTE EXPRÈS. Tout ce qui n'y figure pas est une panne
/// locale, et l'appeler « réseau » ferait recommencer l'enquête au mauvais
/// endroit. Mieux vaut un message technique exact qu'une phrase rassurante et
/// trompeuse.
bool estUnePanneReseau(Object e) =>
    e is SocketException ||
    e is http.ClientException ||
    e is HandshakeException ||
    e is TimeoutException;

/// Le message à montrer pour une erreur quelconque.
///
/// Trois cas, et un seul d'entre eux parle du réseau :
///
/// - `ApiException` — le serveur a répondu, et il a dit non. On répète ce
///   qu'il a dit : c'est lui qui connaît la raison.
/// - panne réseau avérée — le message habituel, cette fois mérité.
/// - tout le reste — une panne DANS L'APPLICATION. On nomme le type de
///   l'erreur, parce que sans lui personne ne saura par où commencer.
String messageDErreur(BuildContext context, Object e) {
  if (e is ApiException) return e.message;
  if (estUnePanneReseau(e)) return tr(context, 'server_unreachable');
  /*
   * ⚠️ ON MONTRE LE TYPE, PAS SEULEMENT LE TEXTE. `PlatformException` et
   * `_TypeError` ne racontent pas la même histoire, et leur `toString()` seul
   * ne dit pas toujours laquelle des deux on tient. Le type est la première
   * chose qu'on demanderait à quelqu'un qui signale la panne.
   */
  return '${tr(context, 'unexpected_error')} (${_court(e)})';
}

/// Le type de l'erreur, suivi de son texte, coupe court.
///
/// ⚠️ LE TYPE SEUL NE SUFFIT PAS. Une `PlatformException` peut venir du coffre
/// securise, des preferences ou du service de notifications : son texte est ce
/// qui les distingue. Le type seul relancerait l'enquete a zero.
///
/// ⚠️ COUPE A 120 CARACTERES. Une trace complete deborde du bandeau et devient
/// illisible ; les premiers mots portent presque toujours la cause.
String _court(Object e) {
  final texte = e.toString().split(RegExp(r'\s+')).join(' ').trim();
  final entier = '${e.runtimeType}: $texte';
  return entier.length <= 120 ? entier : '${entier.substring(0, 117)}...';
}
