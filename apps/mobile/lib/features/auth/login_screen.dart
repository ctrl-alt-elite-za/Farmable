/// Login — guide §9.
///
/// Email **or** phone, chosen with a segmented control. The guide is explicit
/// that the farmer must never be made to supply both, so there is only ever
/// one identifier field on screen and switching the segment swaps it.
///
/// No code is sent here. Issue #9: a normal login sends no OTP, and the only
/// thing that would make this screen send one is somebody adding it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.g.dart';
import '../../core/ui/buttons.dart';
import '../../core/ui/fields.dart';
import '../../core/ui/flow_controls.dart';
import '../../domain/auth/auth_models.dart';
import '../../domain/auth/contact_details.dart';
import 'auth_view_model.dart';
import 'widgets/auth_scaffold.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _identifier = TextEditingController();
  final _password = TextEditingController();

  LoginMode _mode = LoginMode.email;
  DiallingCountry _country = defaultCountry;
  bool _busy = false;
  AuthFailure? _failure;

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Both fields have something in them. Deliberately not the sign-up form's
  /// validation: a farmer whose password predates a policy change must still
  /// be able to type it, and telling them their *existing* password is too
  /// short at the login screen helps nobody.
  bool get _canSubmit =>
      _identifier.text.trim().isNotEmpty && _password.text.isNotEmpty;

  void _switchMode(LoginMode mode) {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      _failure = null;
      // An email left in the box while the phone segment is showing is the
      // bug this screen exists to avoid.
      _identifier.clear();
    });
  }

  Future<void> _submit() async {
    if (!_canSubmit || _busy) return;
    setState(() {
      _busy = true;
      _failure = null;
    });

    final failure = await ref
        .read(authViewModelProvider.notifier)
        .logIn(
          mode: _mode,
          country: _country,
          identifier: _identifier.text,
          password: _password.text,
        );

    if (!mounted) return;
    setState(() {
      _busy = false;
      _failure = failure;
    });
    // `/setup` sends an account with no sections yet through first farm
    // setup, and everyone else on to Home.
    if (failure == null) context.go('/setup');
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Welcome back',
      subtitle: 'Log in with whichever you remember.',
      onBack: backOr(context, '/auth'),
      children: [
        if (_failure != null) AuthNotice(message: authAdvice(_failure!)),
        AppSegmentedControl<LoginMode>(
          value: _mode,
          onChanged: _switchMode,
          options: const [
            SegmentOption(
              value: LoginMode.email,
              label: 'Email',
              icon: LucideIcons.mail,
            ),
            SegmentOption(
              value: LoginMode.phone,
              label: 'Phone',
              icon: LucideIcons.phone,
            ),
          ],
        ),
        const SizedBox(height: AlmanacDimens.sp5),
        AutofillGroup(
          child: Column(
            children: [
              if (_mode == LoginMode.email)
                AppTextField(
                  // Keyed so switching segments rebuilds the field rather than
                  // reusing the one before it, which would keep the email
                  // keyboard up for a phone number.
                  key: const ValueKey('login-email'),
                  label: 'Email',
                  controller: _identifier,
                  leadingIcon: LucideIcons.mail,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  enabled: !_busy,
                  onChanged: (_) => setState(() {}),
                )
              else
                AppPhoneField(
                  key: const ValueKey('login-phone'),
                  label: 'Phone number',
                  controller: _identifier,
                  country: _country,
                  enabled: !_busy,
                  onCountryChanged: (country) =>
                      setState(() => _country = country),
                  onChanged: (_) => setState(() {}),
                ),
              AppPasswordField(
                label: 'Password',
                controller: _password,
                enabled: !_busy,
                textInputAction: TextInputAction.done,
                onSubmitted: _submit,
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: InkWell(
            onTap: () => context.go('/auth/forgot-password'),
            borderRadius: BorderRadius.circular(AlmanacDimens.rXs),
            // No `alignment`: a Container given one expands to the full width
            // it is offered, which cancelled the `Align` above and left this
            // link centred instead of on the right. Padding does the same job
            // and sizes to the words. Third time this bit — `buttons.dart`
            // documents the same trap.
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AlmanacDimens.sp2,
                vertical: 15,
              ),
              child: Text(
                'Forgot password?',
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: context.semantic.primary),
              ),
            ),
          ),
        ),
        const SizedBox(height: AlmanacDimens.sp3),
        AppPrimaryButton(
          label: 'Log in',
          busyLabel: _busy ? 'Logging in…' : null,
          onPressed: _canSubmit && !_busy ? _submit : null,
        ),
        const SizedBox(height: AlmanacDimens.sp5),
        const _OfflineReassurance(),
        const SizedBox(height: AlmanacDimens.sp4),
        AuthFooterLink(
          leading: 'New here?',
          linkLabel: 'Create an account',
          onTap: () => context.go('/auth/signup'),
        ),
      ],
    );
  }
}

/// The line the design puts at the foot of Login.
///
/// It uses the connectivity ramp — a neutral slate — and never the red one.
/// Being offline is a normal operating state for this product, and the whole
/// sentence exists to say that logging in is the *one* thing that wants a
/// signal while everything already saved does not.
class _OfflineReassurance extends StatelessWidget {
  const _OfflineReassurance();

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AlmanacDimens.sp4,
          vertical: AlmanacDimens.sp2,
        ),
        decoration: BoxDecoration(
          color: c.connOfflineContainer,
          borderRadius: BorderRadius.circular(AlmanacDimens.rPill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.cloudOff,
              size: 15,
              color: c.onConnOfflineContainer,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Offline — you can still open your farm',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: c.onConnOfflineContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
