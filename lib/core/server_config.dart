import 'package:flutter/foundation.dart';

class ServerConfig {
  // URL du backend Next.js (Vercel)
  // On force l'URL de production même en Debug pour pouvoir tester sur des vrais téléphones.
  static const String apiBase = String.fromEnvironment(
    'API_URL',
    defaultValue: "https://backend-alanya.vercel.app",
  );

  // URL du serveur WebSocket.
  //
  // On passe désormais par un Cloudflare Worker qui proxifie vers Render
  // (wss://alanya-ws.onrender.com). Motif : certains opérateurs mobiles
  // africains (notamment au Cameroun) bloquent ou filtrent activement les
  // domaines *.onrender.com, empêchant l'établissement de la WebSocket
  // (errno=7 DNS lookup failed, errno=103 connection abort).
  //
  // Le Worker Cloudflare sort en IP Cloudflare, quasiment jamais filtrée,
  // ce qui débloque les appels temps réel pour les utilisateurs concernés.
  // Code du Worker : voir alanya-ws-worker.js à la racine du repo.
  //
  // Si tu veux revenir à Render en direct (test), passe --dart-define=WS_URL=wss://alanya-ws.onrender.com
  static const String wsBase = String.fromEnvironment(
    'WS_URL',
    defaultValue: "wss://alanya-ws.d-bria00.workers.dev",
  );
}

