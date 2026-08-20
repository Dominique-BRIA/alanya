import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:provider/provider.dart';

import 'core/api_client.dart';
import 'core/authed_api.dart';
import 'core/connectivity_service.dart';
import 'core/data_saver_service.dart';
import 'core/debug_overlay.dart';
import 'core/geo_service.dart';
import 'core/notification_settings.dart';
import 'core/locale_controller.dart';
import 'core/outbox.dart';
import 'core/presence_store.dart';
import 'core/device_registry.dart';
import 'core/push_service.dart';
import 'core/realtime_client.dart';
import 'core/sonneries_listes.dart';
import 'core/theme_controller.dart';
import 'core/token_storage.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/auth_repository.dart';
import 'features/auth/screens/welcome_screen.dart';
import 'features/account/account_repository.dart';
import 'features/ai/ai_repository.dart';
import 'features/calls/call_banner.dart';
import 'features/calls/call_controller.dart';
import 'features/calls/call_listener.dart';
import 'features/calls/calls_repository.dart';
import 'features/chat/chat_repository.dart';
import 'features/contacts/contact_lists_repository.dart';
import 'features/contacts/contacts_repository.dart';
import 'features/home/home_screen.dart';
import 'widgets/offline_banner.dart';
import 'widgets/biometric_gate.dart';
import 'features/media/media_repository.dart';
import 'features/settings/ringtones_repository.dart';
import 'features/blocked/blocked_repository.dart';
import 'features/meetings/meeting_banner.dart';
import 'features/meetings/meeting_controller.dart';
import 'features/meetings/meetings_repository.dart';
import 'features/status/status_repository.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // TÉMOIN DE VERSION. Si cette ligne n'apparaît pas dans l'overlay au
  // lancement, l'APK installé ne contient pas les correctifs d'appel — et il
  // est inutile d'interpréter quoi que ce soit d'autre.
  traceAppel("build diagnostic appels — traces actives");

  if (!kIsWeb) {
    try {
      await MediaStore.ensureInitialized();
      MediaStore.appFolder = 'Alanya';
    } catch (_) {}
  }

  final api = ApiClient();
  final storage = TokenStorage();
  final repo = AuthRepository(api);
  final authedApi = AuthedApi(api, storage);
  final realtime = RealtimeClient(storage);

  await PushService.instance.tryInitialize(api: api, storage: storage);
  // Registre des appareils : simple câblage, aucun appel réseau ici.
  // L'enregistrement a lieu à l'authentification (voir AuthController).
  DeviceRegistry.instance.init(api: api, storage: storage);
  // Relevé de position : simple câblage. Rien ne démarre ici — c'est le serveur
  // qui dira si ce compte est concerné, et l'utilisateur qui devra l'accepter.
  GeoService.instance.init(authedApi);
  await DataSaverService.instance.load();
  await NotificationSettings.instance.load();

  runApp(
    MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        Provider<AuthRepository>.value(value: repo),
        Provider<TokenStorage>.value(value: storage),
        // Sert directement CallRatingSheet (POST /api/queue/rate) : les autres
        // consommateurs passent par un repository dédié, celui-ci n'en a pas.
        Provider<AuthedApi>.value(value: authedApi),
        Provider<ContactsRepository>.value(
            value: ContactsRepository(authedApi)),
        Provider<ContactListsRepository>.value(
            value: ContactListsRepository(authedApi)),
        // La sonnerie d'un appelant se lit dans SES listes de contacts, et la
        // rangée de filtres des conversations affiche les MÊMES listes. Ce
        // service en est la source unique : il les garde en mémoire — un appel
        // ne doit jamais attendre le réseau pour sonner — et prévient ce qui les
        // affiche dès qu'elles changent.
        //
        // ⚠️ `ChangeNotifierProvider` et non `Provider` : avec ce dernier, un
        // `context.watch` ne serait jamais rebâti et la rangée resterait figée
        // — exactement le défaut que ce lot corrige.
        ChangeNotifierProvider<SonneriesDeListes>.value(
            value: SonneriesDeListes(
                ContactListsRepository(authedApi), api, storage)),
        Provider<ChatRepository>.value(value: ChatRepository(authedApi)),
        Provider<AccountRepository>.value(value: AccountRepository(authedApi)),
        Provider<StatusRepository>.value(value: StatusRepository(authedApi)),
        Provider<AiRepository>.value(value: AiRepository(authedApi)),
        Provider<MediaRepository>.value(value: MediaRepository(authedApi)),
        // Le catalogue de sonneries s'appuie sur le téléversement de médias :
        // l'import se fait en deux temps, fichier puis inscription.
        Provider<RingtonesRepository>.value(
            value: RingtonesRepository(authedApi, MediaRepository(authedApi))),
        Provider<CallsRepository>.value(value: CallsRepository(authedApi)),
        Provider<MeetingsRepository>.value(
            value: MeetingsRepository(authedApi)),
        Provider<BlockedRepository>.value(value: BlockedRepository(authedApi)),
        ChangeNotifierProvider<RealtimeClient>.value(value: realtime),
        ChangeNotifierProvider<PresenceStore>(
          create: (ctx) => PresenceStore(ctx.read<RealtimeClient>()),
        ),
        ChangeNotifierProvider<LocaleController>(
          create: (_) => LocaleController()..load(),
        ),
        ChangeNotifierProvider<ThemeController>(
          create: (_) => ThemeController()..load(),
        ),
        ChangeNotifierProvider<ConnectivityService>(
          create: (ctx) => ConnectivityService(ctx.read<RealtimeClient>()),
        ),
        ChangeNotifierProvider<Outbox>(
          create: (ctx) => Outbox(
            ctx.read<ChatRepository>(),
            ctx.read<ConnectivityService>(),
          ),
        ),
        ChangeNotifierProvider<CallController>(
          create: (ctx) => CallController(
            ctx.read<CallsRepository>(),
            ctx.read<RealtimeClient>(),
            ctx.read<SonneriesDeListes>(),
          ),
        ),
        ChangeNotifierProvider<MeetingController>(
          create: (ctx) => MeetingController(
            ctx.read<CallsRepository>(),
            ctx.read<MeetingsRepository>(),
            ctx.read<RealtimeClient>(),
          ),
        ),
        ChangeNotifierProvider<AuthController>(
          create: (ctx) => AuthController(
            repo,
            storage,
            realtime: ctx.read<RealtimeClient>(),
          )..bootstrap(),
        ),
      ],
      child: const AlanyaApp(),
    ),
  );
}

class AlanyaApp extends StatelessWidget {
  const AlanyaApp({super.key});

  @override
  Widget build(BuildContext context) {
    final localeCtrl = context.watch<LocaleController>();
    final themeCtrl = context.watch<ThemeController>();
    return MaterialApp(
      navigatorKey: PushService.navigatorKey,
      title: "Alanya",
      debugShowCheckedModeBanner: false,
      // Clair ou Blanc selon le choix — même mécanique que pour le sombre :
      // MaterialApp n'accepte qu'UN thème clair.
      theme: themeCtrl.themeClair,
      // Nuit ou Noir selon le choix : MaterialApp n'accepte qu'UN thème sombre,
      // c'est donc le contrôleur qui tranche entre les deux.
      darkTheme: themeCtrl.themeSombre,
      themeMode: themeCtrl.mode,
      locale: localeCtrl.locale,
      supportedLocales: const [
        Locale('fr'),
        Locale('en'),
        Locale('zh'),
        Locale('es'),
        Locale('de'),
        Locale('pt'),
        Locale('ru'),
        Locale('sv'),
        Locale('no'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Bandeau global « appel en cours » superposé à toutes les pages (Lot 2b).
      builder: (context, child) {
        final pile = Stack(
          children: [
            if (child != null) Positioned.fill(child: child),
            const CallBanner(),
            const MeetingBanner(),
          ],
        );
        // ⚠️ L'overlay se place SOUS le `Directionality`, jamais au-dessus.
        // Ce `Directionality` est ici parce qu'il n'en existe pas encore à ce
        // niveau de l'arbre, et le `Stack` interne de l'overlay en exige un :
        // l'envelopper par-dessus levait une exception de rendu, et l'écran
        // restait noir.
        return Directionality(
          textDirection: TextDirection.ltr,
          // DIAGNOSTIC TEMPORAIRE — voir `tracesAppelsVisibles`.
          child: tracesAppelsVisibles ? DebugOverlay(child: pile) : pile,
        );
      },
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    switch (auth.status) {
      case AuthStatus.unknown:
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      case AuthStatus.authenticated:
        return OfflineBanner(
          child: BiometricGate(
            child: CallListener(child: const HomeScreen()),
          ),
        );

      case AuthStatus.unauthenticated:
        return const WelcomeScreen();
    }
  }
}
