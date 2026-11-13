import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../app_services.dart';
import '../l10n/l10n.dart';
import '../services/account_store.dart';
import '../theme/hero_icons.dart';
import '../theme/tokens.dart';
import '../widgets/account_widgets.dart';
import '../widgets/components.dart';

enum AuthMode { signIn, signUp }

/// Sign in / create account: Google, or email and password.
///
/// The page keeps one fixed widget tree while the keyboard opens and closes
/// (it only scrolls), so a focused field is never rebuilt away and the
/// keyboard stays up.
class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.services,
    this.mode = AuthMode.signIn,
    this.required = false,
    this.onDone,
  });

  final AppServices services;
  final AuthMode mode;

  /// The admin requires accounts: no "Not now" button.
  final bool required;

  /// Called after signing in (instead of closing the page).
  final VoidCallback? onDone;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  late AuthMode _mode = widget.mode;
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _nameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  String? _nameErr, _emailErr, _passwordErr, _formErr;
  bool _busy = false;
  bool _googleStarting = false;

  AccountStore get _account => widget.services.account!;

  @override
  void initState() {
    super.initState();
    _account.addListener(_onAccount);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onAccount());
  }

  @override
  void dispose() {
    _account.removeListener(_onAccount);
    for (final c in [_name, _email, _password]) {
      c.dispose();
    }
    for (final f in [_nameFocus, _emailFocus, _passwordFocus]) {
      f.dispose();
    }
    super.dispose();
  }

  void _onAccount() {
    if (!mounted) return;
    final err = _account.pendingError;
    if (err != null) {
      _account.pendingError = null;
      setState(() => _formErr = googleErrorText(context, err));
    }
    // A sign-up goes on to the code page itself.
    if (_account.signedIn && !_signingUp) _finish();
    setState(() {});
  }

  bool _finished = false;
  bool _signingUp = false;
  void _finish() {
    if (_finished) return;
    _finished = true;
    TextInput.finishAutofillContext();
    if (widget.onDone != null) {
      widget.onDone!();
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(true);
    }
  }

  void _switch(AuthMode m) {
    setState(() {
      _mode = m;
      _nameErr = _emailErr = _passwordErr = _formErr = null;
    });
  }

  bool _validate() {
    final t = context.l10n;
    setState(() {
      _nameErr = _mode == AuthMode.signUp && _name.text.trim().isEmpty
          ? t.errName
          : null;
      _emailErr = looksLikeEmail(_email.text) ? null : t.errEmail;
      _passwordErr = _password.text.characters.length < 8
          ? t.errPassword
          : null;
      _formErr = null;
    });
    final first = _nameErr != null
        ? _nameFocus
        : _emailErr != null
        ? _emailFocus
        : _passwordErr != null
        ? _passwordFocus
        : null;
    first?.requestFocus();
    return first == null;
  }

  Future<void> _submit() async {
    if (_busy || !_validate()) return;
    setState(() => _busy = true);
    try {
      if (_mode == AuthMode.signUp) {
        _signingUp = true;
        final sent = await _account.signUp(
          name: _name.text.trim(),
          email: _email.text.trim(),
          password: _password.text,
        );
        if (!mounted) return;
        _finished = true; // go to the code page instead of closing
        TextInput.finishAutofillContext();
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute<bool>(
            builder: (_) => VerifyEmailScreen(
              services: widget.services,
              codeSent: sent,
              onDone: widget.onDone,
            ),
          ),
        );
      } else {
        await _account.signIn(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
    } catch (e) {
      _signingUp = false;
      if (!mounted) return;
      setState(() {
        _formErr = accountErrorText(context, e);
        if (e is AccountException && e.code == 'email_taken') {
          _mode = AuthMode.signIn;
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() async {
    setState(() {
      _googleStarting = true;
      _formErr = null;
    });
    try {
      final ok = await _account.startGoogle(
        emailHint: looksLikeEmail(_email.text) ? _email.text : null,
      );
      if (!ok && mounted) setState(() => _formErr = context.l10n.googleFailed);
    } catch (_) {
      if (mounted) setState(() => _formErr = context.l10n.googleFailed);
    } finally {
      // On the web the page leaves for Google; elsewhere the browser opens.
      Future<void>.delayed(const Duration(seconds: 4), () {
        if (mounted) setState(() => _googleStarting = false);
      });
    }
  }

  void _forgot() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ResetPasswordScreen(
          services: widget.services,
          email: _email.text.trim(),
        ),
      ),
    );
  }

  void _notNow() {
    _account.introSeen = true;
    if (widget.onDone != null) {
      widget.onDone!();
    } else {
      Navigator.of(context).maybePop(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final text = Theme.of(context).textTheme;
    final s = Theme.of(context).colorScheme;
    final signUp = _mode == AuthMode.signUp;
    final google = widget.services.settings.remote.googleSignIn;
    final googleBusy = _account.googleBusy || _googleStarting;

    return PopScope(
      canPop: !widget.required,
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              Center(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.manual,
                  padding: const EdgeInsets.fromLTRB(
                    Space.xxl,
                    Space.emptyH,
                    Space.xxl,
                    Space.xxl,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: AutofillGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(Radii.card),
                              child: Image.asset(
                                'assets/branding/logo.png',
                                width: 72,
                                height: 72,
                              ),
                            ),
                          ),
                          const SizedBox(height: Space.xl),
                          Text(
                            signUp ? t.authSignUpTitle : t.authWelcome,
                            textAlign: TextAlign.center,
                            style: text.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: Space.s),
                          Text(
                            signUp ? t.authSignUpSub : t.authWelcomeSub,
                            textAlign: TextAlign.center,
                            style: text.bodyMedium?.copyWith(
                              color: s.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: Space.xxl),
                          if (google) ...[
                            GoogleButton(
                              label: t.continueWithGoogle,
                              busy: googleBusy,
                              onPressed: _busy ? null : _google,
                            ),
                            const SizedBox(height: Space.xl),
                            Row(
                              children: [
                                Expanded(
                                  child: Divider(color: s.outlineVariant),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: Space.ml,
                                  ),
                                  child: Text(
                                    t.orWithEmail,
                                    style: text.bodySmall?.copyWith(
                                      color: s.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Divider(color: s.outlineVariant),
                                ),
                              ],
                            ),
                            const SizedBox(height: Space.xl),
                          ],
                          if (_formErr != null) FormNote(text: _formErr!),
                          // The name field is always in the tree (hidden when
                          // signing in), so the fields below it keep their place.
                          Offstage(
                            offstage: !signUp,
                            child: TickerMode(
                              enabled: signUp,
                              child: AuthField(
                                controller: _name,
                                focusNode: _nameFocus,
                                label: t.fieldName,
                                icon: HeroIcons.user,
                                enabled: signUp && !_busy,
                                autofillHints: signUp
                                    ? const [AutofillHints.name]
                                    : null,
                                textCapitalization: TextCapitalization.words,
                                maxLength: 60,
                                error: _nameErr,
                                onSubmitted: (_) => _emailFocus.requestFocus(),
                              ),
                            ),
                          ),
                          AuthField(
                            controller: _email,
                            focusNode: _emailFocus,
                            label: t.fieldEmail,
                            icon: HeroIcons.envelope,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [
                              AutofillHints.email,
                              AutofillHints.username,
                            ],
                            enabled: !_busy,
                            error: _emailErr,
                            onSubmitted: (_) => _passwordFocus.requestFocus(),
                          ),
                          AuthField(
                            controller: _password,
                            focusNode: _passwordFocus,
                            label: t.fieldPassword,
                            hint: signUp ? t.passwordHint : null,
                            icon: HeroIcons.lockClosed,
                            password: true,
                            enabled: !_busy,
                            textInputAction: TextInputAction.done,
                            autofillHints: [
                              signUp
                                  ? AutofillHints.newPassword
                                  : AutofillHints.password,
                            ],
                            error: _passwordErr,
                            onSubmitted: (_) => _submit(),
                          ),
                          if (!signUp)
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: TextButton(
                                onPressed: _busy ? null : _forgot,
                                child: Text(t.forgotPassword),
                              ),
                            ),
                          const SizedBox(height: Space.sm),
                          BusyButton(
                            label: signUp ? t.signUp : t.signIn,
                            busy: _busy,
                            onPressed: _submit,
                          ),
                          const SizedBox(height: Space.l),
                          Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                signUp ? t.haveAccount : t.noAccount,
                                style: text.bodyMedium,
                              ),
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _switch(
                                        signUp
                                            ? AuthMode.signIn
                                            : AuthMode.signUp,
                                      ),
                                child: Text(signUp ? t.signIn : t.signUp),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (!widget.required)
                PositionedDirectional(
                  top: Space.sm,
                  end: Space.sm,
                  child: TextButton(onPressed: _notNow, child: Text(t.notNow)),
                ),
              if (_account.googleBusy)
                Positioned.fill(
                  child: ColoredBox(
                    color: s.surface.withValues(alpha: 0.85),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: Space.l),
                        Text(t.googleSigningIn, style: text.bodyLarge),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A six-digit code field: digits only, big and spaced.
class CodeField extends StatelessWidget {
  const CodeField({
    super.key,
    required this.controller,
    this.focusNode,
    this.error,
    this.onSubmitted,
    this.enabled = true,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String? error;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.l),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        autofillHints: const [AutofillHints.oneTimeCode],
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(6),
        ],
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 26,
          letterSpacing: 10,
          fontWeight: FontWeight.w700,
          fontFamily: Fonts.mono,
        ),
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          labelText: context.l10n.codeLabel,
          errorText: error,
          errorMaxLines: 3,
          counterText: '',
        ),
      ),
    );
  }
}

/// Counts down to when another code may be sent.
mixin _ResendTimer<T extends StatefulWidget> on State<T> {
  int resendIn = 0;
  Timer? _timer;

  void startResendTimer([int seconds = 60]) {
    _timer?.cancel();
    setState(() => resendIn = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => resendIn = resendIn > 0 ? resendIn - 1 : 0);
      if (resendIn == 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class _CodePage extends StatelessWidget {
  const _CodePage({
    required this.title,
    required this.children,
    this.onClose,
    this.closeLabel,
  });

  final String title;
  final List<Widget> children;
  final VoidCallback? onClose;
  final String? closeLabel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            PageTitle(
              title: title,
              onBack: () => Navigator.of(context).maybePop(),
              actions: [
                if (onClose != null)
                  TextButton(onPressed: onClose, child: Text(closeLabel ?? '')),
              ],
            ),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    Space.xxl,
                    Space.l,
                    Space.xxl,
                    Space.xxl,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: children,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Enter the code that was emailed after sign-up (or later, from Profile).
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({
    super.key,
    required this.services,
    this.codeSent = true,
    this.onDone,
  });

  final AppServices services;
  final bool codeSent;
  final VoidCallback? onDone;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen>
    with _ResendTimer {
  final _code = TextEditingController();
  final _focus = FocusNode();
  String? _err;
  String? _note;
  bool _busy = false;
  late bool _sent = widget.codeSent;

  AccountStore get _account => widget.services.account!;

  @override
  void initState() {
    super.initState();
    if (_sent) startResendTimer();
  }

  @override
  void dispose() {
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _close() {
    if (widget.onDone != null) {
      widget.onDone!();
    } else {
      Navigator.of(context).maybePop(true);
    }
  }

  Future<void> _verify() async {
    if (_busy) return;
    if (_code.text.length != 6) {
      setState(() => _err = context.l10n.errCodeDigits);
      _focus.requestFocus();
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await _account.verifyEmail(_code.text);
      if (!mounted) return;
      showSnack(context, context.l10n.emailVerified);
      _close();
    } catch (e) {
      if (mounted) setState(() => _err = accountErrorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _err = null;
      _note = null;
    });
    try {
      final sent = await _account.sendVerification();
      if (!mounted) return;
      if (_account.user?.emailVerified == true) return _close();
      setState(() {
        _sent = sent;
        _note = sent ? context.l10n.codeResent : context.l10n.verifyNotSent;
      });
      startResendTimer();
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = accountErrorText(context, e));
      if (e is AccountException && e.retryAfter != null) {
        startResendTimer(e.retryAfter!);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final text = Theme.of(context).textTheme;
    final s = Theme.of(context).colorScheme;
    final email = _account.user?.email ?? '';
    final name = _account.user?.name ?? '';
    return _CodePage(
      title: t.verifyTitle,
      onClose: _close,
      closeLabel: t.notNow,
      children: [
        if (_account.justCreated && name.isNotEmpty) ...[
          Text(
            t.welcomeName(name),
            style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: Space.sm),
        ],
        Text(
          _sent ? t.codeSentTo(email) : t.verifyNotSent,
          style: text.bodyMedium?.copyWith(
            color: s.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        if (_sent) ...[
          const SizedBox(height: Space.xs),
          Text(
            t.checkSpam,
            style: text.bodySmall?.copyWith(color: s.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: Space.xl),
        if (_note != null) FormNote(text: _note!, error: false),
        CodeField(
          controller: _code,
          focusNode: _focus,
          error: _err,
          enabled: !_busy,
          onSubmitted: (_) => _verify(),
        ),
        BusyButton(label: t.verifyButton, busy: _busy, onPressed: _verify),
        const SizedBox(height: Space.sm),
        Center(
          child: TextButton(
            onPressed: resendIn > 0 ? null : _resend,
            child: Text(
              resendIn > 0
                  ? t.resendIn(localDigits('$resendIn'))
                  : t.resendCode,
            ),
          ),
        ),
      ],
    );
  }
}

/// Forgot password: email -> code + new password -> signed in.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({
    super.key,
    required this.services,
    this.email = '',
  });

  final AppServices services;
  final String email;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen>
    with _ResendTimer {
  late final _email = TextEditingController(text: widget.email);
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _emailFocus = FocusNode();
  final _codeFocus = FocusNode();
  final _passwordFocus = FocusNode();
  bool _codeStep = false;
  bool _busy = false;
  String? _emailErr, _codeErr, _passwordErr, _formErr, _note;

  AccountStore get _account => widget.services.account!;

  @override
  void dispose() {
    for (final c in [_email, _code, _password]) {
      c.dispose();
    }
    for (final f in [_emailFocus, _codeFocus, _passwordFocus]) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy) return;
    if (!looksLikeEmail(_email.text)) {
      setState(() => _emailErr = context.l10n.errEmail);
      _emailFocus.requestFocus();
      return;
    }
    setState(() {
      _busy = true;
      _emailErr = _formErr = null;
    });
    try {
      await _account.forgotPassword(_email.text.trim());
      if (!mounted) return;
      setState(() {
        _codeStep = true;
        _note = context.l10n.resetCodeSent(_email.text.trim());
      });
      startResendTimer();
      _codeFocus.requestFocus();
    } catch (e) {
      if (!mounted) return;
      setState(() => _formErr = accountErrorText(context, e));
      if (e is AccountException && e.retryAfter != null && _codeStep) {
        startResendTimer(e.retryAfter!);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    if (_busy) return;
    final t = context.l10n;
    setState(() {
      _codeErr = _code.text.length == 6 ? null : t.errCodeDigits;
      _passwordErr = _password.text.characters.length >= 8
          ? null
          : t.errPassword;
      _formErr = null;
    });
    if (_codeErr != null) return _codeFocus.requestFocus();
    if (_passwordErr != null) return _passwordFocus.requestFocus();
    setState(() => _busy = true);
    try {
      await _account.resetPassword(
        email: _email.text.trim(),
        code: _code.text,
        password: _password.text,
      );
      if (!mounted) return;
      TextInput.finishAutofillContext();
      showSnack(context, t.passwordChanged);
      // Signed in: close this page and the sign-in page under it.
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (!mounted) return;
      final msg = accountErrorText(context, e);
      setState(() {
        if (e is AccountException &&
            (e.code.contains('code') || e.code == 'too_many_tries')) {
          _codeErr = msg;
        } else if (e is AccountException && e.code == 'weak_password') {
          _passwordErr = msg;
        } else {
          _formErr = msg;
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final text = Theme.of(context).textTheme;
    final s = Theme.of(context).colorScheme;
    return _CodePage(
      title: t.resetTitle,
      children: [
        Text(
          _codeStep ? (_note ?? '') : t.resetSub,
          style: text.bodyMedium?.copyWith(
            color: s.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        if (_codeStep) ...[
          const SizedBox(height: Space.xs),
          Text(
            t.checkSpam,
            style: text.bodySmall?.copyWith(color: s.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: Space.xl),
        if (_formErr != null) FormNote(text: _formErr!),
        AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AuthField(
                controller: _email,
                focusNode: _emailFocus,
                label: t.fieldEmail,
                icon: HeroIcons.envelope,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [
                  AutofillHints.email,
                  AutofillHints.username,
                ],
                enabled: !_busy && !_codeStep,
                error: _emailErr,
                textInputAction: _codeStep
                    ? TextInputAction.next
                    : TextInputAction.done,
                onSubmitted: (_) =>
                    _codeStep ? _codeFocus.requestFocus() : _send(),
              ),
              if (_codeStep) ...[
                CodeField(
                  controller: _code,
                  focusNode: _codeFocus,
                  error: _codeErr,
                  enabled: !_busy,
                  onSubmitted: (_) => _passwordFocus.requestFocus(),
                ),
                AuthField(
                  controller: _password,
                  focusNode: _passwordFocus,
                  label: t.fieldNewPassword,
                  hint: t.passwordHint,
                  icon: HeroIcons.lockClosed,
                  password: true,
                  enabled: !_busy,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.newPassword],
                  error: _passwordErr,
                  onSubmitted: (_) => _reset(),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: Space.sm),
        BusyButton(
          label: _codeStep ? t.setNewPassword : t.sendCode,
          busy: _busy,
          onPressed: _codeStep ? _reset : _send,
        ),
        if (_codeStep) ...[
          const SizedBox(height: Space.sm),
          Center(
            child: TextButton(
              onPressed: resendIn > 0 || _busy ? null : _send,
              child: Text(
                resendIn > 0
                    ? t.resendIn(localDigits('$resendIn'))
                    : t.resendCode,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
