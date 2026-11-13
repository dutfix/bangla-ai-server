import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:omni_voice_call/app_services.dart';
import 'package:omni_voice_call/main.dart';
import 'package:omni_voice_call/screens/auth_screen.dart';
import 'package:omni_voice_call/screens/profile_screen.dart';
import 'package:omni_voice_call/services/account_store.dart';
import 'package:omni_voice_call/services/backend.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/rig.dart';

/// A small accounts server in memory, answering like the real one.
class FakeAccounts {
  final users = <String, Map<String, dynamic>>{};
  final passwords = <String, String>{};
  final tokens = <String, String>{}; // token -> email
  final calls = <String>[];
  String code = '123456';
  int n = 0;

  Map<String, dynamic> view(String email) => Map.of(users[email]!);

  http.Response err(int status, String code, [String msg = '']) =>
      http.Response(
        jsonEncode({
          'error': {'code': code, 'message': msg},
        }),
        status,
      );

  http.Response ok(Map<String, dynamic> j, [int status = 200]) => http.Response(
    jsonEncode(j),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  String issue(String email) {
    final t = 'bas_${'t${n++}'.padRight(43, 'x')}';
    tokens[t] = email;
    return t;
  }

  Future<http.Response> handle(http.Request r) async {
    calls.add('${r.method} ${r.url.path}');
    final body = r.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(r.body) as Map<String, dynamic>;
    final auth = r.headers['Authorization'] ?? '';
    final who = tokens[auth.replaceFirst('Bearer ', '')];
    switch (r.url.path) {
      case '/v1/auth/signup':
        final email = '${body['email']}'.toLowerCase();
        if (users.containsKey(email)) return err(409, 'email_taken');
        users[email] = {
          'id': 'u${users.length}',
          'email': email,
          'emailVerified': false,
          'name': body['name'],
          'avatarUrl': null,
          'hasPassword': true,
          'google': false,
        };
        passwords[email] = '${body['password']}';
        return ok({
          'token': issue(email),
          'user': view(email),
          'verificationSent': true,
        }, 201);
      case '/v1/auth/login':
        final email = '${body['email']}'.toLowerCase();
        if (passwords[email] != body['password']) {
          return err(401, 'wrong_login');
        }
        return ok({'token': issue(email), 'user': view(email)});
      case '/v1/auth/verify':
        if (who == null) return err(401, 'signed_out');
        if (body['code'] != code) return err(401, 'wrong_code', '')..headers;
        users[who]!['emailVerified'] = true;
        return ok({'user': view(who)});
      case '/v1/me':
        if (who == null) return err(401, 'signed_out');
        if (r.method == 'PUT') users[who]!['name'] = body['name'];
        return ok({'user': view(who)});
      case '/v1/me/avatar':
        if (who == null) return err(401, 'signed_out');
        final bytes = base64Decode('${body['image']}');
        final pic = img.decodeJpg(bytes);
        if (pic == null || pic.width != pic.height || pic.width > 320) {
          return err(400, 'invalid_image');
        }
        users[who]!['avatarUrl'] = '/v1/avatars/${users[who]!['id']}?v=1';
        return ok({'user': view(who)});
      case '/v1/auth/logout':
        tokens.remove(auth.replaceFirst('Bearer ', ''));
        return ok({'ok': true});
    }
    return err(404, 'not_found');
  }
}

Future<AppServices> rigWithAccounts(
  FakeAccounts server, {
  Map<String, Object> prefs = const {},
  String extraConfig = '',
}) async {
  final base = await rig(voice: false, extraConfig: extraConfig);
  SharedPreferences.setMockInitialValues({
    'voiceSetupPrompted': true,
    ...prefs,
  });
  Backend.authToken = '';
  final account = await AccountStore.load(
    clientFactory: () => MockClient(server.handle),
  );
  return AppServices(
    settings: base.settings,
    speaker: base.speaker,
    listener: base.listener,
    chats: base.chats,
    chat: base.chat,
    call: base.call,
    readAloud: base.readAloud,
    account: account,
  );
}

void main() {
  setUpAll(() async {
    mockPlatform();
    await loadFonts();
  });

  Future<void> phone(
    WidgetTester tester, [
    Size size = const Size(390, 844),
  ]) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
  }

  Finder field(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(TextField));

  testWidgets(
    'first open shows sign-up; create account, verify email, lands in chat',
    (tester) async {
      await phone(tester);
      final server = FakeAccounts();
      final sv = await rigWithAccounts(server);
      await tester.pumpWidget(OmniVoiceApp(services: sv));
      await settle(tester, 4);

      expect(find.byType(AuthScreen), findsOneWidget);
      expect(find.text('নতুন অ্যাকাউন্ট'), findsOneWidget);
      expect(
        find.text('পরে করব'),
        findsOneWidget,
        reason: 'skippable when not required',
      );

      // Empty submit: errors under the fields, nothing sent.
      await tester.tap(find.widgetWithText(FilledButton, 'অ্যাকাউন্ট খুলুন'));
      await settle(tester);
      expect(find.text('আপনার নাম লিখুন'), findsOneWidget);
      expect(find.text('সঠিক ইমেইল ঠিকানা লিখুন'), findsOneWidget);
      expect(server.calls, isEmpty);

      await tester.enterText(field('আপনার নাম'), 'রহিম');
      await tester.enterText(field('ইমেইল'), 'rahim@example.com');
      await tester.enterText(field('পাসওয়ার্ড'), 'secret123');
      await tester.tap(find.widgetWithText(FilledButton, 'অ্যাকাউন্ট খুলুন'));
      await settle(tester, 4);
      expect(server.calls, contains('POST /v1/auth/signup'));

      expect(find.byType(VerifyEmailScreen), findsOneWidget);
      expect(find.textContaining('rahim@example.com'), findsWidgets);
      await tester.enterText(field('৬ সংখ্যার কোড'), '000000');
      await tester.tap(find.widgetWithText(FilledButton, 'যাচাই করুন'));
      await settle(tester, 3);
      expect(
        find.text('কোডটি ঠিক নয় বা মেয়াদ শেষ হয়ে গেছে।'),
        findsOneWidget,
      );
      await tester.enterText(field('৬ সংখ্যার কোড'), '123456');
      await tester.tap(find.widgetWithText(FilledButton, 'যাচাই করুন'));
      await settle(tester, 12);
      expect(find.byType(VerifyEmailScreen), findsNothing);
      expect(find.byType(AuthScreen), findsNothing);
      expect(sv.account!.user!.emailVerified, isTrue);
      expect(Backend.authToken, startsWith('bas_'));
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('account_token_v1'),
        Backend.authToken,
        reason: 'stays signed in after restart',
      );
      await tester.pump(const Duration(seconds: 5));
    },
  );

  testWidgets(
    'sign in: wrong password shows the error; right one closes the page',
    (tester) async {
      await phone(tester);
      final server = FakeAccounts();
      server.users['a@b.co'] = {
        'id': 'u9',
        'email': 'a@b.co',
        'emailVerified': true,
        'name': 'করিম',
        'avatarUrl': null,
        'hasPassword': true,
        'google': false,
      };
      server.passwords['a@b.co'] = 'rightpass1';
      final sv = await rigWithAccounts(
        server,
        prefs: {'account_intro_seen_v1': true},
      );
      await tester.pumpWidget(OmniVoiceApp(services: sv));
      await settle(tester, 4);
      expect(
        find.byType(AuthScreen),
        findsNothing,
        reason: 'seen once and skipped: not shown again',
      );

      // Open it from the sidebar's account row.
      await tester.tap(find.byTooltip('চ্যাট').first);
      await settle(tester, 3);
      await tester.tap(find.byKey(const ValueKey('sidebar-account')));
      await settle(tester, 4);
      expect(find.text('স্বাগতম'), findsOneWidget);

      await tester.enterText(field('ইমেইল'), 'A@B.co');
      await tester.enterText(field('পাসওয়ার্ড'), 'wrongpass1');
      await tester.tap(find.widgetWithText(FilledButton, 'সাইন ইন'));
      await settle(tester, 3);
      expect(find.text('ইমেইল বা পাসওয়ার্ড ঠিক নয়।'), findsOneWidget);

      await tester.enterText(field('পাসওয়ার্ড'), 'rightpass1');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester, 12);
      expect(find.byType(AuthScreen), findsNothing);
      expect(sv.account!.user!.name, 'করিম');
      await tester.pump(const Duration(seconds: 5));
    },
  );

  testWidgets(
    'the keyboard stays up on the sign-in page while the page shrinks',
    (tester) async {
      await phone(tester);
      final sv = await rigWithAccounts(FakeAccounts());
      await tester.pumpWidget(OmniVoiceApp(services: sv));
      await settle(tester, 4);
      for (final label in ['আপনার নাম', 'ইমেইল', 'পাসওয়ার্ড']) {
        await tester.tap(field(label));
        await settle(tester, 2);
        tester.testTextInput.log.clear();
        // Chrome on Android shrinks the page; Android apps get an inset.
        for (final h in [700.0, 520.0, 430.0, 380.0]) {
          tester.view.physicalSize = Size(390, h);
          await settle(tester, 2);
        }
        tester.view.physicalSize = const Size(390, 844);
        tester.view.viewInsets = const FakeViewPadding(bottom: 330);
        await settle(tester, 2);
        final editable = tester.state<EditableTextState>(
          find.descendant(
            of: field(label),
            matching: find.byType(EditableText),
          ),
        );
        expect(
          editable.widget.focusNode.hasFocus,
          isTrue,
          reason: '$label keeps focus',
        );
        expect(
          tester.testTextInput.log.where(
            (c) =>
                c.method == 'TextInput.hide' ||
                c.method == 'TextInput.clearClient',
          ),
          isEmpty,
          reason: '$label: keyboard not closed',
        );
        await tester.enterText(field(label), 'abc@d.ee');
        tester.view.viewInsets = FakeViewPadding.zero;
        await settle(tester, 2);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('admin requires sign-in: no "not now", back does not leave', (
    tester,
  ) async {
    await phone(tester);
    // The server says accounts are required, and Google is set up.
    final sv = await rigWithAccounts(
      FakeAccounts(),
      prefs: {'account_intro_seen_v1': true},
      extraConfig: '"requireSignIn":true,"accounts":{"google":true},',
    );
    await sv.settings.refreshRemote();
    await tester.pumpWidget(OmniVoiceApp(services: sv));
    await settle(tester, 4);
    expect(find.byType(AuthScreen), findsOneWidget);
    expect(find.text('পরে করব'), findsNothing);
    expect(
      find.text('Google দিয়ে চালিয়ে যান'),
      findsOneWidget,
      reason: 'Google button when the server has it',
    );
    await tester.binding.handlePopRoute();
    await settle(tester, 2);
    expect(find.byType(AuthScreen), findsOneWidget);
  });

  testWidgets(
    'profile: change name, upload a picture (cropped square), sign out',
    (tester) async {
      await phone(tester);
      final server = FakeAccounts();
      server.users['p@q.co'] = {
        'id': 'u7',
        'email': 'p@q.co',
        'emailVerified': true,
        'name': 'পুরনো নাম',
        'avatarUrl': null,
        'hasPassword': true,
        'google': false,
      };
      server.passwords['p@q.co'] = 'pass12345';
      final sv = await rigWithAccounts(
        server,
        prefs: {'account_intro_seen_v1': true},
      );
      await sv.account!.signIn(email: 'p@q.co', password: 'pass12345');
      await tester.pumpWidget(OmniVoiceApp(services: sv));
      await settle(tester, 3);
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      nav.push(
        MaterialPageRoute<void>(builder: (_) => ProfileScreen(services: sv)),
      );
      await settle(tester, 4);
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.text('ইমেইল যাচাই হয়েছে'), findsOneWidget);

      await tester.enterText(field('আপনার নাম'), 'নতুন নাম');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'সংরক্ষণ'));
      await settle(tester, 3);
      expect(server.users['p@q.co']!['name'], 'নতুন নাম');
      expect(sv.account!.user!.name, 'নতুন নাম');

      // A wide photo becomes a 320 px square JPEG before upload.
      final wide = img.Image(width: 1200, height: 600);
      final bytes = img.encodePng(wide);
      await tester.runAsync(() => sv.account!.uploadAvatar(bytes));
      await settle(tester, 2);
      expect(sv.account!.user!.avatarUrl, '/v1/avatars/u7?v=1');

      final row = find.descendant(
        of: find.byType(ProfileScreen),
        matching: find.text('সাইন আউট'),
      );
      await tester.ensureVisible(row);
      await settle(tester, 2);
      await tester.tap(row);
      await settle(tester, 4);
      expect(find.text('সাইন আউট করবেন?'), findsOneWidget);
      await tester.tap(find.text('সাইন আউট').last);
      await settle(tester, 12);
      expect(sv.account!.signedIn, isFalse);
      expect(Backend.authToken, isEmpty);
      expect(server.calls, contains('POST /v1/auth/logout'));
      expect(find.byType(ProfileScreen), findsNothing);
      await tester.pump(const Duration(seconds: 5));
    },
  );

  test('squareJpeg crops to a centred square, at most 320 px', () {
    final out = squareJpeg(img.encodePng(img.Image(width: 900, height: 400)))!;
    final pic = img.decodeJpg(out)!;
    expect(pic.width, 320);
    expect(pic.height, 320);
    expect(squareJpeg(Uint8List.fromList(utf8.encode('<svg/>'))), isNull);
    expect(File('assets/branding/logo.png').existsSync(), isTrue);
  });
}
