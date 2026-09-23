/// Forgot password — guide §11, first half.
///
/// Email or phone, the same segmented control Login uses, for the same
/// reason: the farmer supplies whichever one they remember.
///
/// It reports success identically whether or not the account exists. Saying
/// "no account with that email" here would hand back exactly the
/// account-existence oracle that Login's generic error spends effort denying.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/tokens.g.dart';
import '../../core/ui/buttons.dart';
import '../../core/ui/fields.dart';
import '../../core/ui/flow_controls.dart';
import '../../domain/auth/auth_models.dart';
import '../../domain/auth/contact_details.dart';
import 'auth_view_model.dart';
import 'reset_password_flow.dart';
import 'widgets/auth_scaffold.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _identifier = TextEditingController();

  LoginMode _mode = LoginMode.phone;
  DiallingCountry _country = defaultCountry;
  bool _busy = false;
  AuthFailure? _failure;

  @override
  void dispose() {
    _identifier.dispose();
    super.dispose();
  }

  bool get _canSubmit => _mode == LoginMode.email
      ? isPlausibleEmail(_identifier.text)
      : isPlausiblePhone(_identifier.text);

  Future<void> _submit() async {
    if (!_canSubmit || _busy) return;
    setState(() {
      _busy = true;
      _failure = null;
    });

    final request = ResetRequest(
      mode: _mode,
      country: _country,
      identifier: _identifier.text,
    );

    final failure = await ref
        .read(authViewModelProvider.notifier)
        .requestPasswordReset(
          mode: request.mode,
          country: request.country,
          identifier: request.identifier,
        );

    if (!mounted) return;
    setState(() {
      _busy = false;
      _failure = failure;
    });
    if (failure != null) return;

    ref.read(resetFlowProvider.notifier).start(request);
    if (mounted) context.go('/auth/reset-password');
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Reset your password',
      subtitle: 'We will send you a code.',
      onBack: backOr(context, '/auth/login'),
      children: [
        if (_failure != null) AuthNotice(message: authAdvice(_failure!)),
        AppSegmentedControl<LoginMode>(
          value: _mode,
          onChanged: (mode) => setState(() {
            _mode = mode;
            _identifier.clear();
          }),
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
        if (_mode == LoginMode.email)
          AppTextField(
            key: const ValueKey('forgot-email'),
            label: 'Email',
            controller: _identifier,
            leadingIcon: LucideIcons.mail,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            enabled: !_busy,
            onSubmitted: _submit,
            onChanged: (_) => setState(() {}),
          )
        else
          AppPhoneField(
            key: const ValueKey('forgot-phone'),
            label: 'Phone number',
            controller: _identifier,
            country: _country,
            enabled: !_busy,
            textInputAction: TextInputAction.done,
            onSubmitted: _submit,
            onCountryChanged: (country) => setState(() => _country = country),
            onChanged: (_) => setState(() {}),
          ),
        const SizedBox(height: AlmanacDimens.sp2),
        AppPrimaryButton(
          label: 'Send code',
          busyLabel: _busy ? 'Sending…' : null,
          onPressed: _canSubmit && !_busy ? _submit : null,
        ),
        const SizedBox(height: AlmanacDimens.sp4),
        AuthFooterLink(
          leading: 'Remembered it?',
          linkLabel: 'Back to log in',
          onTap: () => context.go('/auth/login'),
        ),
      ],
    );
  }
}
