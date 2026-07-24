import 'package:flutter/foundation.dart';

class ServerConfig {
  // URL du backend Next.js — VPS (Nginx + SSL), servi sur alanyavox.com.
  // On force l'URL de production même en Debug pour tester sur de vrais téléphones.
  static const String apiBase = String.fromEnvironment(
    'API_URL',
    defaultValue: "https://alanyavox.com",
  );

  // URL du serveur WebSocket — exposé par Nginx sur le VPS au chemin /ws
  // (proxy vers alanya-ws sur localhost:3001).
  //
  // Bascule possible pour un test :
  //   --dart-define=WS_URL=wss://alanya-ws.d-bria00.workers.dev
  static const String wsBase = String.fromEnvironment(
    'WS_URL',
    defaultValue: "wss://alanyavox.com/ws",
  );
}
