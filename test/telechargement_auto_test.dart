import 'package:alanya/core/data_saver_service.dart';
import 'package:alanya/core/telechargement_auto.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// LE TÉLÉCHARGEMENT AUTOMATIQUE (14/11/2026) : ce qui se télécharge d'office,
/// selon la famille, le réseau et les deux réglages.
TelechargementAuto get t => TelechargementAuto.instance;

void main() {
  late List<ConnectivityResult> reseau;
  var panne = false;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    reseau = [ConnectivityResult.mobile];
    panne = false;
    TelechargementAuto.remplacerPourEssais(() async {
      if (panne) throw Exception('réseau indéterminable');
      return reseau;
    });
    await TelechargementAuto.instance.charger();
    await DataSaverService.instance.setEnabled(false);
  });

  test('par défaut : Wi-Fi uniquement, toutes les familles allumées', () {
    expect(t.wifiSeulement, isTrue);
    for (final f in FamilleMedia.values) {
      expect(t.famille(f), isTrue);
    }
  });

  test('sur données mobiles, une photo reçue est retenue', () async {
    expect(await t.autoriser(FamilleMedia.photo), isFalse);
  });

  test('en Wi-Fi ou en Ethernet, elle se télécharge', () async {
    reseau = [ConnectivityResult.wifi];
    expect(await t.autoriser(FamilleMedia.photo), isTrue);
    reseau = [ConnectivityResult.ethernet];
    expect(await t.autoriser(FamilleMedia.photo), isTrue);
    reseau = [ConnectivityResult.mobile, ConnectivityResult.wifi];
    expect(await t.autoriser(FamilleMedia.photo), isTrue);
  });

  test("ce que j'ai envoyé n'est jamais retenu", () async {
    await t.changerFamille(FamilleMedia.photo, false);
    expect(await t.autoriser(FamilleMedia.photo, moi: true), isTrue);
  });

  test("Wi-Fi uniquement coupé : d'office sur tous les réseaux", () async {
    await t.changerWifiSeulement(false);
    expect(await t.autoriser(FamilleMedia.photo), isTrue);
  });

  test("l'économie de données retient même sans « Wi-Fi uniquement »", () async {
    await t.changerWifiSeulement(false);
    await DataSaverService.instance.setEnabled(true);
    expect(await t.autoriser(FamilleMedia.audio), isFalse);
    reseau = [ConnectivityResult.wifi];
    expect(await t.autoriser(FamilleMedia.audio), isTrue);
  });

  test("une famille éteinte ne se télécharge jamais d'office, même en Wi-Fi", () async {
    reseau = [ConnectivityResult.wifi];
    await t.changerFamille(FamilleMedia.audio, false);
    expect(await t.autoriser(FamilleMedia.audio), isFalse);
    expect(await t.autoriser(FamilleMedia.photo), isTrue);
  });

  test("réseau indéterminable : on s'abstient", () async {
    panne = true;
    expect(await t.autoriser(FamilleMedia.photo), isFalse);
  });

  test('les réglages survivent au redémarrage', () async {
    await t.changerWifiSeulement(false);
    await t.changerFamille(FamilleMedia.audio, false);
    TelechargementAuto.remplacerPourEssais(() async => reseau);
    await TelechargementAuto.instance.charger();
    expect(TelechargementAuto.instance.wifiSeulement, isFalse);
    expect(TelechargementAuto.instance.famille(FamilleMedia.audio), isFalse);
    expect(TelechargementAuto.instance.famille(FamilleMedia.photo), isTrue);
  });

  test('famille d’après le type MIME', () {
    expect(familleDuMime('image/jpeg'), FamilleMedia.photo);
    expect(familleDuMime('audio/ogg'), FamilleMedia.audio);
    expect(familleDuMime('video/mp4'), FamilleMedia.video);
    expect(familleDuMime('application/pdf'), FamilleMedia.document);
  });
}
