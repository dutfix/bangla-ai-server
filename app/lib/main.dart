import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'app_services.dart';
import 'l10n/l10n.dart';
import 'screens/chat_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/error_boundary.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installErrorHandling();
  if (!kIsWeb) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
  final services = await AppServices.create();
  runApp(OmniVoiceApp(services: services));
}

class OmniVoiceApp extends StatelessWidget {
  const OmniVoiceApp({super.key, required this.services});
  final AppServices services;

  static final _light = buildTheme(Brightness.light);
  static final _dark = buildTheme(Brightness.dark);
  static final _lightBn = buildTheme(Brightness.light, bangla: true);
  static final _darkBn = buildTheme(Brightness.dark, bangla: true);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: services.settings,
      builder: (context, _) => MaterialApp(
        title: 'Bangla AI',
        debugShowCheckedModeBanner: false,
        themeMode: services.settings.themeMode,
        // Bangla by default; English when picked in Settings.
        locale: Locale(services.settings.language),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: services.settings.language == 'bn' ? _lightBn : _light,
        darkTheme: services.settings.language == 'bn' ? _darkBn : _dark,
        builder: (context, child) {
          final dark = Theme.of(context).brightness == Brightness.dark;
          // Edge to edge, with status bar icons that match the theme.
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value:
                (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
                    .copyWith(
                      statusBarColor: const Color(0x00000000),
                      systemNavigationBarColor: const Color(0x00000000),
                      systemNavigationBarContrastEnforced: false,
                    ),
            child: child!,
          );
        },
        home: ChatScreen(services: services),
      ),
    );
  }
}
