/// Sign up — guide §8.
///
/// Six fields in the order the guide fixes: Name, Surname, Phone, Email,
/// Password, Confirm. Nothing else is asked for; the farm is set up later,
/// and every extra question here is someone deciding not to sign up.
///
/// The password rules live in `domain/auth/password_policy.dart` and the
/// field-level validity in [SignUpDraft]. This file decides nothing — it lays
/// the fields out, hands keystrokes to the draft, and disables the button when
/// the draft says it is not valid.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/tokens.g.dart';
import '../../core/ui/buttons.dart';
import '../../core/ui/fields.dart';
import '../../domain/auth/auth_models.dart';
import 'auth_view_model.dart';
import 'sign_up_draft.dart';
import 'widgets/auth_scaffold.dart';

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _firstName = TextEditingController();
  final _surname = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();

  SignUpDraft _draft = const SignUpDraft();
  bool _busy = false;
  AuthFailure? _failure;

  /// Whether the farmer has left the confirm field once.
  ///
  /// Without this the form shouts "Passwords do not match" at the first
  /// character of a password that is being typed correctly. The match
  /// indicator appears once there is something to compare.
  bool _confirmationTouched = false;

  @override
  void dispose() {
    for (final controller in [
      _firstName,
      _surname,
      _phone,
      _email,
      _password,
      _confirmation,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_draft.isValid || _busy) return;
    setState(() {
      _busy = true;
      _failure = null;
    });

    final failure = await ref
        .read(authViewModelProvider.notifier)
        .signUp(
          firstName: _draft.firstName,
          surname: _draft.surname,
          country: _draft.country,
          phone: _draft.phone,
          email: _draft.email,
          password: _draft.password,
        );

    if (!mounted) return;
    setState(() {
      _busy = false;
      _failure = failure;
    });
    if (failure == null) context.go('/auth/verify');
  }

  @override
  Widget build(BuildContext context) {
    final assessment = _draft.passwordAssessment;
    final showMatch = _confirmationTouched && _draft.confirmation.isNotEmpty;

    return AuthScaffold(
      title: 'Create your account',
      subtitle: 'You only need these six things.',
      onBack: backOr(context, '/auth'),
      children: [
        if (_failure != null) AuthNotice(message: authAdvice(_failure!)),

        // `AutofillGroup` is what lets a password manager save the whole set
        // as one credential rather than offering six unrelated fields.
        AutofillGroup(
          child: Column(
            children: [
              AppTextField(
                label: 'Name',
                controller: _firstName,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.givenName],
                enabled: !_busy,
                onChanged: (v) =>
                    setState(() => _draft = _draft.copyWith(firstName: v)),
              ),
              AppTextField(
                label: 'Surname',
                controller: _surname,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.familyName],
                enabled: !_busy,
                onChanged: (v) =>
                    setState(() => _draft = _draft.copyWith(surname: v)),
              ),
              AppPhoneField(
                label: 'Phone number',
                controller: _phone,
                country: _draft.country,
                enabled: !_busy,
                onCountryChanged: (country) =>
                    setState(() => _draft = _draft.copyWith(country: country)),
                onChanged: (v) =>
                    setState(() => _draft = _draft.copyWith(phone: v)),
                tone: _draft.phone.isEmpty || _draft.hasPhone
                    ? FieldTone.neutral
                    : FieldTone.error,
                helper: _draft.phone.isEmpty || _draft.hasPhone
                    ? null
                    : 'Enter the number without the leading 0 — for example '
                          '82 555 0123.',
              ),
              AppTextField(
                label: 'Email',
                controller: _email,
                leadingIcon: LucideIcons.mail,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                enabled: !_busy,
                onChanged: (v) =>
                    setState(() => _draft = _draft.copyWith(email: v)),
                tone: _draft.email.isEmpty || _draft.hasEmail
                    ? FieldTone.neutral
                    : FieldTone.error,
                helper: _draft.email.isEmpty || _draft.hasEmail
                    ? null
                    : 'Include the @ and the part after it, like '
                          'name@gmail.com.',
              ),
              AppPasswordField(
                label: 'Password',
                controller: _password,
                enabled: !_busy,
                autofillHints: const [AutofillHints.newPassword],
                onChanged: (v) =>
                    setState(() => _draft = _draft.copyWith(password: v)),
              ),
              // The meter is the password field's helper line, so it replaces
              // one rather than sitting under one.
              PasswordStrengthMeter(assessment: assessment),
              AppPasswordField(
                label: 'Confirm password',
                controller: _confirmation,
                enabled: !_busy,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.done,
                onSubmitted: _submit,
                onChanged: (v) => setState(() {
                  _confirmationTouched = true;
                  _draft = _draft.copyWith(confirmation: v);
                }),
                tone: !showMatch
                    ? FieldTone.neutral
                    : _draft.confirmationMatches
                    ? FieldTone.valid
                    : FieldTone.error,
                helper: !showMatch
                    ? null
                    : _draft.confirmationMatches
                    ? 'Passwords match'
                    : 'Passwords do not match — retype the second one.',
              ),
            ],
          ),
        ),
        const SizedBox(height: AlmanacDimens.sp2),
        AppPrimaryButton(
          label: 'Create account',
          busyLabel: _busy ? 'Creating account…' : null,
          // Guide §8: disabled until the fields pass basic validation. The
          // definition of that lives in the draft, not here.
          onPressed: _draft.isValid && !_busy ? _submit : null,
        ),
        const SizedBox(height: AlmanacDimens.sp4),
        AuthFooterLink(
          leading: 'Already have an account?',
          linkLabel: 'Log in',
          onTap: () => context.go('/auth/login'),
        ),
      ],
    );
  }
}
