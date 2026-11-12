import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:omni_voice_call/l10n/l10n.dart';
import 'package:omni_voice_call/theme/app_theme.dart';
import 'package:omni_voice_call/theme/hero_icons.dart';
import 'package:omni_voice_call/theme/tokens.dart';
import 'package:omni_voice_call/widgets/components.dart';
import 'package:omni_voice_call/widgets/markdown_view.dart';

void main() {
  test('theme uses the Bangladesh flag roles and type scale', () {
    final light = buildTheme(Brightness.light);
    final dark = buildTheme(Brightness.dark);
    expect(light.colorScheme.primary, Palette.green);
    expect(light.colorScheme.secondary, Palette.red);
    expect(dark.colorScheme.primary, Palette.greenBright);
    expect(light.textTheme.headlineLarge!.fontFamily, Fonts.display);
    expect(light.textTheme.headlineLarge!.fontSize, 21);
    expect(light.textTheme.bodyLarge!.fontFamily, Fonts.body);
    expect(
      light.filledButtonTheme.style!.backgroundColor!.resolve({}),
      Palette.green,
    );
    expect(
      dark.filledButtonTheme.style!.backgroundColor!.resolve({}),
      Palette.greenBright,
    );
  });

  testWidgets('components and a code block render in both themes', (
    tester,
  ) async {
    for (final b in Brightness.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(b),
          locale: const Locale('en'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ListView(
              children: [
                const PageTitle(title: 'Settings', sub: 'Sub'),
                const SectionTitle('Voice'),
                PrimaryButton(
                  label: 'Go',
                  icon: HeroIcons.sparkles,
                  onPressed: () {},
                ),
                OutlineButton(label: 'Cancel', onPressed: () {}),
                ChipButton(label: 'Chip', selected: true, onPressed: () {}),
                const AppCard(
                  child: SettingRow(
                    icon: HeroIcons.key,
                    accent: Accent.amber,
                    title: 'Key',
                    value: 'A long value that goes under the title',
                  ),
                ),
                const MarkdownView(
                  data: '# Hi\n\nSome **bold** text.\n\n```dart\nvoid main() {}\n```',
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.textContaining('SETTINGS', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('dart'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
