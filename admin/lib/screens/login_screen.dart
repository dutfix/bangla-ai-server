import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../api.dart';
import '../theme/hero_icons.dart';
import '../theme/tokens.dart';
import '../widgets/components.dart';
import 'dashboard_screen.dart';

/// Admin sign-in without a password: the admin's email gets a 6-digit code
/// (ADMIN_EMAIL on Render), and the code signs in for 30 days.
/// Texts are Bangla first, with a short English line under the main ones.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.api});
  final AdminApi api;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

enum _Step { email, code }

class _LoginScreenState extends State<LoginScreen> {
  late final _url = TextEditingController(text: widget.api.baseUrl);
  late final _email = TextEditingController(text: widget.api.lastEmail);
  final _code = TextEditingController();
  final _codeFocus = FocusNode();
  _Step _step = _Step.email;
  bool _busy = false;
  bool _waking = false;
  bool _showServer = false;
  String? _error;
  String? _info;
  int _resendIn = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _url.dispose();
    _email.dispose();
    _code.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  void _startTimer(int seconds) {
    _timer?.cancel();
    setState(() => _resendIn = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _resendIn = _resendIn > 0 ? _resendIn - 1 : 0);
      if (_resendIn == 0) t.cancel();
    });
  }

  /// Bangla first, English second, for every error the server can give.
  String _explain(ApiException e) {
    switch (e.kind) {
      case ApiErrorKind.wrongCode:
        final left = e.triesLeft;
        return left == null
            ? 'কোডটি ঠিক নয় বা আর কাজ করছে না। নতুন কোড চান।\nWrong or used code. Ask for a new one.'
            : 'কোডটি ঠিক নয়। আরও $left বার চেষ্টা করা যাবে।\nWrong code. $left ${left == 1 ? 'try' : 'tries'} left.';
      case ApiErrorKind.expiredCode:
        return 'কোডটির মেয়াদ শেষ (১০ মিনিট)। নতুন কোড চান।\nThis code has expired. Ask for a new one.';
      case ApiErrorKind.tooManyTries:
        return 'অনেকবার ভুল কোড দেওয়া হয়েছে, এই কোডটি বাতিল। নতুন কোড চান।\nToo many wrong tries. Ask for a new code.';
      case ApiErrorKind.tooSoon:
        if (e.retryAfter > 0) _startTimer(e.retryAfter);
        return 'একটু অপেক্ষা করুন, তারপর আবার কোড চান।\nPlease wait ${e.retryAfter} seconds before asking again.';
      case ApiErrorKind.invalidEmail:
        return 'সঠিক ইমেইল ঠিকানা লিখুন।\nEnter a valid email address.';
      case ApiErrorKind.waking:
      case ApiErrorKind.timeout:
        return 'সার্ভার জেগে উঠছে। এক মিনিট পরে আবার চেষ্টা করুন।\nThe server is waking up. Try again in a minute.';
      case ApiErrorKind.unreachable:
        return 'সার্ভারে পৌঁছানো যাচ্ছে না। ইন্টারনেট সংযোগ দেখুন।\nCan\'t reach the server. Check your internet.';
      case ApiErrorKind.rateLimited:
      case ApiErrorKind.other:
        return e.message;
    }
  }

  Future<bool> _ensureAwake() async {
    final url = _url.text.trim();
    if (!RegExp(r'^https?://').hasMatch(url)) {
      setState(() {
        _showServer = true;
        _error =
            'সার্ভারের ঠিকানা https:// দিয়ে শুরু হয়।\nThe server address starts with https://';
      });
      return false;
    }
    await widget.api.setBaseUrl(url);
    final awake = await widget.api.wake(
      onWaiting: () {
        if (mounted && !_waking) setState(() => _waking = true);
      },
    );
    if (!awake) {
      throw ApiException('unreachable', kind: ApiErrorKind.unreachable);
    }
    return true;
  }

  Future<void> _sendCode() async {
    final email = _email.text.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(
        () => _error = 'সঠিক ইমেইল ঠিকানা লিখুন।\nEnter a valid email address.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      if (!await _ensureAwake()) return;
      final wait = await widget.api.requestCode(email);
      if (!mounted) return;
      _code.clear();
      setState(() {
        _step = _Step.code;
        _info = null;
      });
      _startTimer(wait);
      _codeFocus.requestFocus();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = _explain(e));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _waking = false;
        });
      }
    }
  }

  Future<void> _verify() async {
    final code = _code.text.replaceAll(RegExp(r'\D'), '');
    if (code.length != 6) {
      setState(
        () => _error = '৬ সংখ্যার কোডটি লিখুন।\nEnter the 6-digit code.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await _ensureAwake()) return;
      await widget.api.verifyCode(_email.text, code);
      if (!mounted) return;
      TextInput.finishAutofillContext();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => DashboardScreen(api: widget.api),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = _explain(e));
      if (e.kind == ApiErrorKind.wrongCode) {
        _code.clear();
        _codeFocus.requestFocus();
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _waking = false;
        });
      }
    }
  }

  void _changeEmail() {
    _timer?.cancel();
    setState(() {
      _step = _Step.email;
      _error = null;
      _info = null;
      _resendIn = 0;
      _code.clear();
    });
  }

  Future<void> _pasteCode() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final digits = (data?.text ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.length < 6) {
      if (mounted) {
        showSnack(
          context,
          'ক্লিপবোর্ডে ৬ সংখ্যার কোড নেই। No 6-digit code copied.',
        );
      }
      return;
    }
    _code.text = digits.substring(0, 6);
    _verify();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final sc = Theme.of(context).colorScheme;
    final muted = t.bodyMedium?.copyWith(
      color: sc.onSurfaceVariant,
      height: 1.5,
    );
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.gutter),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.asset(
                          'assets/branding/logo.png',
                          width: 84,
                          height: 84,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'বাংলা এআই অ্যাডমিন',
                      textAlign: TextAlign.center,
                      style: t.headlineSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Bangla AI Admin',
                      textAlign: TextAlign.center,
                      style: muted,
                    ),
                    const SizedBox(height: 24),
                    if (_step == _Step.email)
                      ..._emailStep(t, sc, muted)
                    else
                      ..._codeStep(t, sc, muted),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: sc.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _error!,
                          style: t.bodyMedium?.copyWith(
                            color: sc.onErrorContainer,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                    if (_info != null) ...[
                      const SizedBox(height: 12),
                      Text(_info!, style: muted),
                    ],
                    if (_waking) ...[
                      const SizedBox(height: 12),
                      Text(
                        'সার্ভার জেগে উঠছে, এক মিনিট পর্যন্ত লাগতে পারে...\nThe server is waking up (up to a minute)...',
                        style: muted,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _emailStep(TextTheme t, ColorScheme sc, TextStyle? muted) => [
    Text(
      'অ্যাডমিন ইমেইল লিখুন। সেই ইমেইলে একটি ৬ সংখ্যার কোড যাবে, পাসওয়ার্ড লাগবে না।',
      textAlign: TextAlign.center,
      style: t.bodyLarge?.copyWith(height: 1.5),
    ),
    const SizedBox(height: 4),
    Text(
      'Enter the admin email. A 6-digit code is sent there, no password needed.',
      textAlign: TextAlign.center,
      style: muted,
    ),
    const SizedBox(height: 20),
    TextField(
      controller: _email,
      keyboardType: TextInputType.emailAddress,
      autocorrect: false,
      enableSuggestions: false,
      textCapitalization: TextCapitalization.none,
      autofillHints: const [AutofillHints.email],
      textInputAction: TextInputAction.send,
      onSubmitted: (_) => _busy ? null : _sendCode(),
      decoration: const InputDecoration(
        labelText: 'ইমেইল / Email',
        hintText: 'you@gmail.com',
        prefixIcon: Padding(
          padding: EdgeInsets.all(12),
          child: HeroIcon(HeroIcons.envelope, size: 20),
        ),
      ),
    ),
    const SizedBox(height: 16),
    PrimaryButton(
      label: _busy ? 'পাঠানো হচ্ছে... Sending...' : 'কোড পাঠান · Send code',
      icon: HeroIcons.envelope,
      expand: true,
      onPressed: _busy || _resendIn > 0 ? null : _sendCode,
    ),
    if (_resendIn > 0) ...[
      const SizedBox(height: 8),
      Text(
        'আবার কোড চাইতে $_resendIn সেকেন্ড অপেক্ষা করুন',
        textAlign: TextAlign.center,
        style: muted,
      ),
    ],
    const SizedBox(height: 12),
    Center(
      child: TextButton(
        onPressed: () => setState(() => _showServer = !_showServer),
        child: Text(
          _showServer
              ? 'সার্ভারের ঠিকানা লুকান'
              : 'সার্ভারের ঠিকানা · Server address',
        ),
      ),
    ),
    if (_showServer)
      TextField(
        controller: _url,
        keyboardType: TextInputType.url,
        autocorrect: false,
        decoration: const InputDecoration(
          labelText: 'Server address',
          prefixIcon: Padding(
            padding: EdgeInsets.all(12),
            child: HeroIcon(HeroIcons.serverStack, size: 20),
          ),
        ),
      ),
  ];

  List<Widget> _codeStep(TextTheme t, ColorScheme sc, TextStyle? muted) => [
    Text(
      '${_email.text.trim()} ঠিকানায় যদি এটি অ্যাডমিন ইমেইল হয়, একটি ৬ সংখ্যার কোড পাঠানো হয়েছে। ইনবক্স (এবং স্প্যাম) দেখুন।',
      textAlign: TextAlign.center,
      style: t.bodyLarge?.copyWith(height: 1.5),
    ),
    const SizedBox(height: 4),
    Text(
      'If this is the admin email, a 6-digit code was sent. Check the inbox and spam. It works for 10 minutes.',
      textAlign: TextAlign.center,
      style: muted,
    ),
    const SizedBox(height: 20),
    TextField(
      key: const Key('codeField'),
      controller: _code,
      focusNode: _codeFocus,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      autofillHints: const [AutofillHints.oneTimeCode],
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(6),
      ],
      style: t.headlineMedium?.copyWith(
        letterSpacing: 10,
        fontFamily: Fonts.mono,
      ),
      onChanged: (v) {
        if (v.length == 6 && !_busy) _verify();
      },
      onSubmitted: (_) => _busy ? null : _verify(),
      decoration: InputDecoration(
        labelText: '৬ সংখ্যার কোড / 6-digit code',
        hintText: '••••••',
        suffixIcon: IconButton(
          tooltip: 'পেস্ট করুন / Paste',
          onPressed: _busy ? null : _pasteCode,
          icon: const HeroIcon(HeroIcons.clipboardDocument, size: 20),
        ),
      ),
    ),
    const SizedBox(height: 16),
    PrimaryButton(
      label: _busy ? 'যাচাই হচ্ছে... Checking...' : 'সাইন ইন · Sign in',
      icon: HeroIcons.check,
      expand: true,
      onPressed: _busy ? null : _verify,
    ),
    const SizedBox(height: 10),
    OutlineButton(
      label: _resendIn > 0
          ? 'আবার কোড পাঠান ($_resendIn সে.) · Resend'
          : 'আবার কোড পাঠান · Resend code',
      icon: HeroIcons.arrowPath,
      expand: true,
      onPressed: _busy || _resendIn > 0 ? null : _sendCode,
    ),
    const SizedBox(height: 6),
    Center(
      child: TextButton(
        onPressed: _busy ? null : _changeEmail,
        child: const Text('ইমেইল বদলান · Change email'),
      ),
    ),
  ];
}
