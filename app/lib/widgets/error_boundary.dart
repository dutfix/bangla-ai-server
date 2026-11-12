import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/tokens.dart';

/// Keeps one broken widget from blanking a screen.
///
/// By default a release build paints a widget that throws while building
/// as a grey box that fills all the space it is given, which can swallow a
/// whole screen. This replaces it with a small notice that only takes the
/// room it needs, so the rest of the screen keeps working, and logs the
/// error instead of letting it end the app.
void installErrorHandling() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (kReleaseMode) {
      // Keep it in the device log for bug reports.
      debugPrint('Bangla AI UI error: ${details.exceptionAsString()}');
      debugPrint(details.stack?.toString().split('\n').take(8).join('\n'));
    } else {
      previous?.call(details);
    }
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Bangla AI error: $error');
    return true;
  };
  if (kReleaseMode) {
    ErrorWidget.builder = (details) => const BrokenPart();
  }
}

/// The small notice shown in place of a widget that failed to build.
class BrokenPart extends StatelessWidget {
  const BrokenPart({super.key});

  @override
  Widget build(BuildContext context) {
    final dark =
        MediaQuery.maybePlatformBrightnessOf(context) == Brightness.dark;
    final fg = dark ? const Color(0xFFB9C4BF) : const Color(0xFF4A5753);
    // Built without Theme or Localizations, which may be what failed.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        widthFactor: 1,
        heightFactor: 1,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'এই অংশটি দেখানো যাচ্ছে না',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: Fonts.body,
              fontFamilyFallback: Fonts.fallback,
              fontSize: 13,
              height: 1.5,
              color: fg,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}
