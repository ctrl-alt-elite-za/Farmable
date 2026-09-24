/// Reset password — guide §11, second half.
///
/// The same strength meter and the same match indicator as sign-up, from the
/// same [assessPassword] and [passwordsMatch]. Two copies of these rules would
/// drift, and the one that drifts is always the one nobody demos.
///
/// **Deviation from the design set.** `screens-auth.html` screen 13 shows only
/// the two password fields. The code has to be entered somewhere, and the
/// design has no screen between Forgot and Reset that takes it — so the six
/// slots are at the top of this one. One screen, one submit, and the code is
/// beside the thing it authorises.
///
/// After a reset the farmer goes back to Login rather than straight into the
/// app, per §11: the new password gets used once before it is trusted.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/tokens.g.dart';
import '../../core/ui/buttons.dart';
import '../../core/ui/fields.dart';
import '../../core/ui/otp_slots.dart';
import '../../domain/auth/auth_models.dart';
import '../../domain/auth/password_policy.dart';
import 'auth_view_model.dart';
import 'reset_password_flow.dart';
import 'widgets/auth_scaffold.dart';

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();

  bool _busy = false;
  bool _confirmationTouched = false;
  AuthFailure? _failure;

  @override
  void dispose() {
    _code.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  PasswordAssessment get _assessment => assessPassword(_password.text);

  bool get _matches => passwordsMatch(_password.text, _confirmation.text);

  bool get _canSubmit =>
      _code.text.length == otpLength && _assessment.acceptable && _matches;

  Future<void> _submit(ResetRequest request) async {
    if (!_canSubmit || _busy) return;
    setState(() {
      _busy = true;
      _failure = null;
    });

    final failure = await ref
        .read(authViewModelProvider.notifier)
        .resetPassword(
          mode: request.mode,
          country: request.country,
          identifier: request.identifier,
          code: _code.text,
          newPassword: _password.text,
        );

    if (!mounted) return;
    setState(() {
      _busy = false;
      _failure = failure;
    });
    if (failure != null) return;

    ref.read(resetFlowProvider.notifier).clear();
    if (mounted) context.go('/auth/login');
  }

  @override
  Widget build(BuildContext context) {
    final request = ref.watch(resetFlowProvider);

    // Opened directly, or after a restart. Nothing to reset against, so the
    // screen says what to do rather than showing a form that cannot submit.
    if (request == null) {
      return AuthScaffold(
        title: 'Choose a new password',
        subtitle: 'Ask for a code first and this page will be ready for it.',
        onBack: backOr(context, '/auth/login'),
        children: [
          AppPrimaryButton(
            label: 'Send me a code',
            onPressed: () => context.go('/auth/forgot-password'),
          ),
        ],
      );
    }

    final showMatch = _confirmationTouched && _confirmation.text.isNotEmpty;

    return AuthScaffold(
      title: 'Choose a new password',
      subtitle: 'Long is stronger than complicated.',
      onBack: backOr(context, '/auth/forgot-password'),
      children: [
        if (_failure != null) AuthNotice(message: authAdvice(_failure!)),
        Text(
          'Enter the 6-digit code sent to ${request.masked}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: AlmanacDimens.sp3),
        OtpSlots(
          controller: _code,
          enabled: !_busy,
          autofocus: false,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AlmanacDimens.sp6),
        AppPasswordField(
          label: 'New password',
          controller: _password,
          enabled: !_busy,
          autofillHints: const [AutofillHints.newPassword],
          onChanged: (_) => setState(() {}),
        ),
        PasswordStrengthMeter(assessment: _assessment),
        AppPasswordField(
          label: 'Confirm new password',
          controller: _confirmation,
          enabled: !_busy,
          autofillHints: const [AutofillHints.newPassword],
          textInputAction: TextInputAction.done,
          onSubmitted: () => _submit(request),
          onChanged: (_) => setState(() => _confirmationTouched = true),
          tone: !showMatch
              ? FieldTone.neutral
              : _matches
              ? FieldTone.valid
              : FieldTone.error,
          helper: !showMatch
              ? null
              : _matches
              ? 'Passwords match'
              : 'Passwords do not match — retype the second one.',
        ),
        const SizedBox(height: AlmanacDimens.sp2),
        AppPrimaryButton(
          label: 'Save new password',
          busyLabel: _busy ? 'Saving…' : null,
          onPressed: _canSubmit && !_busy ? () => _submit(request) : null,
        ),
      ],
    );
  }
}
