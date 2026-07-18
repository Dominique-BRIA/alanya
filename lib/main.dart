import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:provider/provider.dart';

import 'core/api_client.dart';
import 'core/authed_api.dart';
import 'core/connectivity_service.dart';
import 'core/locale_controller.dart';
import 'core/outbox.dart';
import 'core/push_service.dart';
import 'core/realtime_client.dart';
import 'core/token_storage.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/auth_repository.dart';
import 'features/auth/screens/welcome_screen.dart';
import 'features/account/account_repository.dart';
import 'features/ai/ai_repository.dart';
import 'features/calls/call_controller.dart';
import 'features/calls/call_listener.dart';
import 'features/calls/calls_repository.dart';
import 'features/chat/chat_repository.dart';
import 'features/contacts/contacts_repository.dart';
import 'features/home/home_screen.dart';
import 'widgets/offline_banner.dart';
import 'widgets/biometric_gate.dart';
import 'features/media/media_repository.dart';
import 'features/blocked/blocked_repository.dart';
import 'features/meetings/meetings_repository.dart';
import 'features/status/status_repository.dart';
import 'theme/alanya_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  runApp(
    MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        Provider<AuthRepository>.value(value: repo),
        Provider<TokenStorage>.value(value: storage),
        Provider<ContactsRepository>.value(value: ContactsRepository(authedApi)),
        Provider<ChatRepository>.value(value: ChatRepository(authedApi)),
        Provider<AccountRepository>.value(value: AccountRepository(authedApi)),
        Provider<StatusRepository>.value(value: StatusRepository(authedApi)),
        Provider<AiRepository>.value(value: AiRepository(authedApi)),
        Provider<MediaRepository>.value(value: MediaRepository(authedApi)),
        Provider<CallsRepository>.value(value: CallsRepository(authedApi)),
        Provider<MeetingsRepository>.value(value: MeetingsRepository(authedApi)),
        Provider<BlockedRepository>.value(value: BlockedRepository(authedApi)),
        ChangeNotifierProvider<RealtimeClient>.value(value: realtime),
        ChangeNotifierProvider<LocaleController>(
          create: (_) => LocaleController()..load(),
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
          ),
        ),
        ChangeNotifierProvider<AuthController>(
          create: (_) => AuthController(repo, storage)..bootstrap(),
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
    return MaterialApp(
      navigatorKey: PushService.navigatorKey,
      title: "Alanya",
      debugShowCheckedModeBanner: false,
      theme: AlanyaTheme.light,
      themeMode: ThemeMode.light,
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
