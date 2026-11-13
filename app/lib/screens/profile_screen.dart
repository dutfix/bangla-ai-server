import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../app_services.dart';
import '../l10n/l10n.dart';
import '../services/account_store.dart';
import '../theme/hero_icons.dart';
import '../theme/tokens.dart';
import '../widgets/account_widgets.dart';
import '../widgets/components.dart';
import 'auth_screen.dart';

/// The user's profile: picture, name, email, password and sign-out.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.services});
  final AppServices services;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  AccountStore get _account => widget.services.account!;
  late final _name = TextEditingController(text: _account.user?.name ?? '');
  final _nameFocus = FocusNode();
  String? _nameErr;
  bool _savingName = false;
  bool _photoBusy = false;

  @override
  void initState() {
    super.initState();
    _account.addListener(_changed);
    _account.refresh();
  }

  @override
  void dispose() {
    _account.removeListener(_changed);
    _name.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    if (!_account.signedIn) {
      Navigator.of(context).maybePop();
      return;
    }
    // Keep what they are typing; only fill the field when it is not in use.
    if (!_nameFocus.hasFocus && !_savingName) {
      _name.text = _account.user?.name ?? '';
    }
    setState(() {});
  }

  bool get _nameChanged =>
      _name.text.trim() != (_account.user?.name ?? '').trim();

  Future<void> _saveName() async {
    final t = context.l10n;
    final v = _name.text.trim();
    if (v.isEmpty) {
      setState(() => _nameErr = t.errName);
      return;
    }
    setState(() {
      _savingName = true;
      _nameErr = null;
    });
    try {
      await _account.updateName(v);
      if (!mounted) return;
      _nameFocus.unfocus();
      showSnack(context, t.nameSaved);
    } catch (e) {
      if (mounted) setState(() => _nameErr = accountErrorText(context, e));
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  Future<void> _photoMenu() async {
    final t = context.l10n;
    final has = _account.user?.avatar != null;
    final choice = await showChoiceSheet<String>(
      context,
      title: has ? t.changePhoto : t.addPhoto,
      options: [
        ChoiceOption('gallery', t.choosePhoto),
        if (!kIsWeb) ChoiceOption('camera', t.takePhoto),
        if (has) ChoiceOption('remove', t.removePhoto),
      ],
    );
    if (choice == null || !mounted) return;
    if (choice == 'remove') return _removePhoto();
    await _pickPhoto(
      choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
    );
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final t = context.l10n;
    XFile? file;
    try {
      file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 90,
        preferredCameraDevice: CameraDevice.front,
      );
    } catch (_) {
      if (mounted) showSnack(context, t.errImage);
      return;
    }
    if (file == null || !mounted) return;
    setState(() => _photoBusy = true);
    try {
      final bytes = await file.readAsBytes();
      await _account.uploadAvatar(bytes);
      if (mounted) showSnack(context, t.photoUpdated);
    } catch (e) {
      if (mounted) showSnack(context, accountErrorText(context, e));
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _removePhoto() async {
    setState(() => _photoBusy = true);
    try {
      await _account.removeAvatar();
      if (mounted) showSnack(context, context.l10n.photoRemoved);
    } catch (e) {
      if (mounted) showSnack(context, accountErrorText(context, e));
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _signOut() async {
    final t = context.l10n;
    final ok = await showConfirmDialog(
      context,
      title: t.signOutConfirm,
      body: t.signOutBody,
      confirm: t.signOut,
      destructive: true,
    );
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    await _account.signOut();
    messenger.showSnackBar(SnackBar(content: Text(t.signedOut)));
  }

  void _verify() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _SendThenVerify(services: widget.services),
      ),
    );
  }

  void _password() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChangePasswordScreen(services: widget.services),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final text = Theme.of(context).textTheme;
    final sc = Theme.of(context).colorScheme;
    final u = _account.user;
    if (u == null) return const Scaffold();
    final method = u.google && u.hasPassword
        ? t.methodBoth
        : u.google
        ? t.methodGoogle
        : t.methodEmail;
    return Scaffold(
      body: PinnedPage(
        title: t.profile,
        onBack: () => Navigator.of(context).maybePop(),
        children: [
          const SizedBox(height: Space.l),
          Center(
            child: Semantics(
              button: true,
              label: u.avatar == null ? t.addPhoto : t.changePhoto,
              child: GestureDetector(
                onTap: _photoBusy ? null : _photoMenu,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: Brushes.primary,
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: sc.surface,
                        ),
                        child: AccountAvatar(account: u, size: 104),
                      ),
                    ),
                    if (_photoBusy)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Palette.black.withValues(alpha: 0.45),
                          ),
                          alignment: Alignment.center,
                          child: const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.6,
                              color: Palette.white,
                            ),
                          ),
                        ),
                      ),
                    PositionedDirectional(
                      end: -2,
                      bottom: -2,
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Palette.green,
                          border: Border.all(color: sc.surface, width: 3),
                        ),
                        alignment: Alignment.center,
                        child: const HeroIcon(
                          HeroIcons.camera,
                          size: 18,
                          color: Palette.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: Space.sm),
          Center(
            child: TextButton(
              onPressed: _photoBusy ? null : _photoMenu,
              child: Text(u.avatar == null ? t.addPhoto : t.changePhoto),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              Space.sm,
              Space.gutter,
              0,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AuthField(
                    controller: _name,
                    focusNode: _nameFocus,
                    label: t.fieldName,
                    icon: HeroIcons.user,
                    maxLength: 60,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.name],
                    error: _nameErr,
                    onChanged: (_) => setState(() => _nameErr = null),
                    onSubmitted: (_) => _saveName(),
                  ),
                ),
                const SizedBox(width: Space.sm),
                SizedBox(
                  height: 56,
                  child: FilledButton(
                    onPressed: _nameChanged && !_savingName ? _saveName : null,
                    child: _savingName
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: sc.onPrimary,
                            ),
                          )
                        : Text(t.save),
                  ),
                ),
              ],
            ),
          ),
          SectionTitle(t.accountSection),
          AppCard(
            child: Column(
              children: [
                SettingRow(
                  icon: HeroIcons.envelope,
                  accent: Accent.green,
                  title: u.email,
                  sub: u.emailVerified ? t.emailVerified : t.emailNotVerified,
                  showChevron: !u.emailVerified,
                  trailing: u.emailVerified
                      ? const HeroIcon(
                          HeroIcons.checkCircle,
                          size: 22,
                          color: Palette.success,
                        )
                      : TextButton(
                          onPressed: _verify,
                          child: Text(t.verifyNow),
                        ),
                  onTap: u.emailVerified ? null : _verify,
                ),
                const Divider(height: 1),
                SettingRow(
                  icon: HeroIcons.key,
                  accent: Accent.teal,
                  title: t.signInMethod,
                  sub: method,
                  showChevron: false,
                ),
                const Divider(height: 1),
                SettingRow(
                  icon: HeroIcons.lockClosed,
                  accent: Accent.amber,
                  title: u.hasPassword ? t.changePassword : t.setPassword,
                  sub: u.hasPassword ? null : t.setPasswordSub,
                  onTap: _password,
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.l),
          AppCard(
            child: SettingRow(
              icon: HeroIcons.arrowRightStartOnRectangle,
              accent: Accent.red,
              title: t.signOut,
              titleColor: sc.error,
              showChevron: false,
              onTap: _signOut,
            ),
          ),
          const SizedBox(height: Space.pageBottom),
          Center(
            child: Text(
              u.email,
              style: text.bodySmall?.copyWith(color: sc.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: Space.pageBottom),
        ],
      ),
    );
  }
}

/// Sends a fresh code, then shows the code page.
class _SendThenVerify extends StatefulWidget {
  const _SendThenVerify({required this.services});
  final AppServices services;

  @override
  State<_SendThenVerify> createState() => _SendThenVerifyState();
}

class _SendThenVerifyState extends State<_SendThenVerify> {
  bool? _sent;
  String? _err;

  @override
  void initState() {
    super.initState();
    widget.services.account!.sendVerification().then(
      (s) {
        if (mounted) setState(() => _sent = s);
      },
      onError: (Object e) {
        if (!mounted) return;
        // Sent less than a minute ago: the earlier code still works.
        final soon = e is AccountException && e.code == 'too_soon';
        setState(() {
          _sent = soon;
          if (!soon) _err = accountErrorText(context, e);
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_sent == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_err != null) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              PageTitle(
                title: context.l10n.verifyTitle,
                onBack: () => Navigator.of(context).maybePop(),
              ),
              Padding(
                padding: const EdgeInsets.all(Space.xxl),
                child: FormNote(text: _err!),
              ),
            ],
          ),
        ),
      );
    }
    return VerifyEmailScreen(services: widget.services, codeSent: _sent!);
  }
}

/// Change the password (or set one on a Google account).
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key, required this.services});
  final AppServices services;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _currentFocus = FocusNode();
  final _nextFocus = FocusNode();
  String? _currentErr, _nextErr, _formErr;
  bool _busy = false;

  AccountStore get _account => widget.services.account!;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _currentFocus.dispose();
    _nextFocus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final t = context.l10n;
    final needCurrent = _account.user?.hasPassword ?? true;
    setState(() {
      _currentErr = needCurrent && _current.text.isEmpty
          ? t.errWrongCurrent
          : null;
      _nextErr = _next.text.characters.length >= 8 ? null : t.errPassword;
      _formErr = null;
    });
    if (_currentErr != null) return _currentFocus.requestFocus();
    if (_nextErr != null) return _nextFocus.requestFocus();
    setState(() => _busy = true);
    try {
      await _account.changePassword(
        current: needCurrent ? _current.text : null,
        password: _next.text,
      );
      if (!mounted) return;
      TextInput.finishAutofillContext();
      showSnack(context, '${t.passwordChanged} ${t.otherDevicesSignedOut}');
      Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      final msg = accountErrorText(context, e);
      setState(() {
        if (e is AccountException && e.code == 'wrong_password') {
          _currentErr = msg;
        } else if (e is AccountException && e.code == 'weak_password') {
          _nextErr = msg;
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
    final needCurrent = _account.user?.hasPassword ?? true;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            PageTitle(
              title: needCurrent ? t.changePassword : t.setPassword,
              onBack: () => Navigator.of(context).maybePop(),
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
                    child: AutofillGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_formErr != null) FormNote(text: _formErr!),
                          if (needCurrent)
                            AuthField(
                              controller: _current,
                              focusNode: _currentFocus,
                              label: t.fieldCurrentPassword,
                              icon: HeroIcons.lockClosed,
                              password: true,
                              enabled: !_busy,
                              autofillHints: const [AutofillHints.password],
                              error: _currentErr,
                              onSubmitted: (_) => _nextFocus.requestFocus(),
                            ),
                          AuthField(
                            controller: _next,
                            focusNode: _nextFocus,
                            label: t.fieldNewPassword,
                            hint: t.passwordHint,
                            icon: HeroIcons.key,
                            password: true,
                            enabled: !_busy,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.newPassword],
                            error: _nextErr,
                            onSubmitted: (_) => _save(),
                          ),
                          const SizedBox(height: Space.sm),
                          BusyButton(
                            label: t.save,
                            busy: _busy,
                            onPressed: _save,
                          ),
                        ],
                      ),
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
