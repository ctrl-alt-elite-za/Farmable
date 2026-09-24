/// Privacy notice and consent.
///
/// The notice says what the app actually does with the farmer's details — no
/// more, and nothing it does not do. The one choice is whether outside
/// services may process what the farmer sends. Nothing is pre-selected: a
/// choice nobody has made is shown as not made, and until it is, the answer
/// the app acts on is "no" (see `externalProcessingConsentProvider`).
///
/// The choice survives a restart on this phone. The backend has no consent
/// endpoint yet, so it cannot follow the farmer to another phone, and the
/// screen says so.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.g.dart';
import '../../core/ui/layout.dart';
import '../../core/utils/dates.dart';
import '../../domain/auth/auth_models.dart';
import '../auth/auth_view_model.dart';
import '../auth/widgets/auth_scaffold.dart';
import 'account_view_model.dart';
import 'widgets/profile_rows.dart';

class PrivacyScreen extends ConsumerStatefulWidget {
  const PrivacyScreen({super.key});

  @override
  ConsumerState<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends ConsumerState<PrivacyScreen> {
  bool _busy = false;
  AuthFailure? _failure;

  Future<void> _choose(bool allow) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    final failure = await ref
        .read(accountViewModelProvider.notifier)
        .setConsent(externalProcessing: allow);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failure = failure;
    });
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(accountViewModelProvider).value;
    final consent = account?.consent;
    final text = Theme.of(context).textTheme;
    final c = context.semantic;

    Widget paragraph(String body) => Padding(
      padding: const EdgeInsets.only(bottom: AlmanacDimens.sp3),
      child: Text(body, style: text.bodyMedium),
    );

    Widget heading(String title) => Padding(
      padding: const EdgeInsets.only(
        top: AlmanacDimens.sp4,
        bottom: AlmanacDimens.sp2,
      ),
      child: Text(title, style: text.titleMedium),
    );

    return AuthScaffold(
      title: 'Privacy and consent',
      subtitle: 'What Almanac keeps, and what you allow.',
      onBack: backOr(context, '/profile'),
      children: [
        if (_failure != null) AuthNotice(message: authAdvice(_failure!)),
        heading('What is kept'),
        paragraph(
          'Your name, phone number, email, language and farm name, so you '
          'can log in and your account knows whose farm it is. Your farm '
          'records — sections, plantings, observations, tasks and money — '
          'are kept on this phone, and on your account once they sync.',
        ),
        paragraph(
          'Your password and verification codes are never stored as you '
          'typed them — only in a form that cannot be turned back into them.',
        ),
        heading('On this phone'),
        paragraph(
          'Your farm opens without a signal because it is stored here. Your '
          'login is kept in the phone\'s secure storage. Logging out removes '
          'your account details from this phone and keeps the farm.',
        ),
        heading('Your choices'),
        paragraph(
          'From Profile you can download a copy of everything on your '
          'account, or delete your account and everything on it.',
        ),
        if (account == null)
          const EmptyState(
            icon: Icons.person_outline,
            headline: 'Not logged in',
            body: 'Log in from Profile to make privacy choices.',
          )
        else ...[
          heading('Outside services'),
          paragraph(
            'Some features send what you give them to services outside '
            'Almanac: turning your voice into words, answering your '
            'questions, checking a photo of a crop, and looking up weather '
            'and soil. They are only used if you allow it.',
          ),
          ChoiceRow(
            label: 'Allow outside services',
            detail: 'Voice, questions, crop photos, weather and soil.',
            selected: consent?.externalProcessing == true,
            onTap: _busy ? null : () => _choose(true),
          ),
          ChoiceRow(
            label: 'Do not allow',
            detail: 'Those features stay off. Everything else works.',
            selected: consent?.externalProcessing == false,
            onTap: _busy ? null : () => _choose(false),
          ),
          const SizedBox(height: AlmanacDimens.sp2),
          Text(
            consent == null
                ? 'You have not chosen yet. Until you do, outside services '
                      'are not used.'
                : 'You chose this on ${longDate(consent.decidedAt.toLocal())}. '
                      'It is kept on this phone; it does not yet follow your '
                      'account to another phone.',
            style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}
