import 'dart:convert';

import 'package:bangla_ai_admin/api.dart';
import 'package:bangla_ai_admin/screens/login_screen.dart';
import 'package:bangla_ai_admin/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final calls = <String>[];

  setUp(() {
    calls.clear();
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    AdminApi.testClient = MockClient((req) async {
      calls.add('${req.method} ${req.url.path} ${req.body}');
      final json = {'Content-Type': 'application/json'};
      switch (req.url.path) {
        case '/health':
          return http.Response('{"ok":true}', 200, headers: json);
        case '/admin/request-code':
          return http.Response(
            jsonEncode({
              'ok': true,
              'message': 'sent',
              'resendAfterSeconds': 60,
            }),
            200,
            headers: json,
          );
        case '/admin/verify-code':
          final code = (jsonDecode(req.body) as Map)['code'];
          if (code == '123456') {
            return http.Response(
              jsonEncode({'token': 't', 'expiresInDays': 30}),
              200,
              headers: json,
            );
          }
          return http.Response(
            jsonEncode({
              'error': {
                'message': 'Wrong code. 4 tries left.',
                'code': 'wrong_code',
                'triesLeft': 4,
              },
            }),
            401,
            headers: json,
          );
      }
      return http.Response('{}', 404, headers: json);
    });
  });

  testWidgets('email, send code, wrong code shows tries left', (tester) async {
    final api = await AdminApi.create();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: LoginScreen(api: api),
      ),
    );
    expect(find.text('কোড পাঠান · Send code'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, ' Admin@Example.com ');
    await tester.tap(find.text('কোড পাঠান · Send code'));
    await tester.pumpAndSettle();
    expect(
      calls.any(
        (c) =>
            c.startsWith('POST /admin/request-code') &&
            c.contains('admin@example.com'),
      ),
      isTrue,
    );
    expect(find.byKey(const Key('codeField')), findsOneWidget);
    expect(find.textContaining('(60 সে.)'), findsOneWidget);

    // Letters and spaces are dropped; six digits submit on their own.
    await tester.enterText(find.byKey(const Key('codeField')), '000000');
    await tester.pumpAndSettle();
    expect(find.textContaining('4 tries left'), findsOneWidget);
    expect(
      calls.where((c) => c.startsWith('POST /admin/verify-code')).length,
      1,
    );

    await tester.pump(const Duration(seconds: 61));
    expect(find.text('আবার কোড পাঠান · Resend code'), findsOneWidget);
  });

  test('verifyCode stores the token', () async {
    final api = await AdminApi.create();
    await api.verifyCode('admin@example.com', '123 456');
    expect(api.signedIn, isTrue);
    expect(calls.last, contains('"code":"123456"'));
  });
}
