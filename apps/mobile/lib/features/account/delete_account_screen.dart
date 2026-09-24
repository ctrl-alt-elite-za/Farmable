/// Delete your account — permanently.
///
/// Two deliberate acts, both required: re-entering the password, because a
/// phone left unlocked is not consent; and ticking that this cannot be
/// undone, because a password typed out of habit is not understanding. The
/// button is on the red ramp and outline-only, as every destructive action in
/// this design is — never the heaviest thing on screen.
///
/// On success the account is gone on the server, access on this phone has
/// already ended, and everything the app kept here has been cleared. The
/// farmer lands on Home — which still opens, on the fresh-install demo farm,
/// because Home never needed an account.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.g.dart';
import '../../core/ui/buttons.dart';
import '../../core/ui/fields.dart';
import '../../core/ui/layout.dart';
import '../../domain/account/account_models.dart';
import '../../domain/auth/auth_models.dart';
import '../auth/auth_view_model.dart';
import '../auth/widgets/auth_scaffold.dart';
import 'account_view_model.dart';
import 'widgets/profile_rows.dart';

class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _password = TextEditingController();
  bool _understood = false;
  bool _busy = false;
  bool _unconfirmed = false;
  AuthFailure? _failure;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  bool get _ready => _password.text.isNotEmpty && _understood && !_busy;

  Future<void> _delete() async {
    if (!_ready) return;
    setState(() {
      _busy = true;
      _failure = null;
    });

    final result = await ref
        .read(accountViewModelProvider.notifier)
        .deleteAccount(password: _password.text);

    if (!mounted) return;
    final outcome = result.outcome;
    if (outcome == DeletionOutcome.unconfirmed) {
      setState(() {
        _busy = false;
        _unconfirmed = true;
      });
      return;
    }
    if (outcome != null) {
      // The account is gone either way. What differs is whether the phone
      // could clear everything, and the farmer is told which — never that
      // nothing was deleted, and never that the phone is clean when it isn't.
      final messenger = ScaffoldMessenger.maybeOf(context);
      context.go('/home');
      messenger?.showSnackBar(
        SnackBar(
          content: Text(switch (outcome) {
            DeletionOutcome.complete =>
              'Your account has been deleted, and this phone has been '
                  'cleared.',
            DeletionOutcome.phoneNotCleared =>
              'Your account has been deleted and you are logged out. This '
                  "phone could not clear everything - clear Almanac's "
                  "storage in your phone's settings to finish.",
            DeletionOutcome.accountChangedBeforeCleanup =>
              'That account has been deleted.',
            DeletionOutcome.unconfirmed => _unconfirmedAdvice,
          }),
        ),
      );
      return;
    }
    final failure = result.failure ?? AuthFailure.unknown;
    setState(() {
      _busy = false;
      _failure = failure;
      // A wrong password is typed again from nothing, not edited.
      if (failure == AuthFailure.invalidCredentials) _password.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(authViewModelProvider).value is SignedIn;
    final text = Theme.of(context).textTheme;
    final c = context.semantic;

    Widget point(String body) => Padding(
      padding: const EdgeInsets.only(bottom: AlmanacDimens.sp2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Icon(LucideIcons.dot, size: 18, color: c.onSurfaceVariant),
          ),
          const SizedBox(width: AlmanacDimens.sp2),
          Expanded(child: Text(body, style: text.bodyMedium)),
        ],
      ),
    );

    // No way back while the request is out. Leaving would let the farmer log
    // out, or someone else log in, before the server's answer arrives — the
    // service refuses to clean up for the wrong login, but the screen should
    // not invite the switch in the first place.
    return PopScope(
      canPop: !_busy,
      child: AuthScaffold(
        title: 'Delete your account',
        subtitle: 'This is permanent and cannot be undone.',
        onBack: _busy ? null : backOr(context, '/profile'),
        children: [
          if (_unconfirmed)
            const AuthNotice(message: _unconfirmedAdvice)
          else if (_failure != null)
            AuthNotice(message: _advice(_failure!)),
          // Not while this screen's own deletion is out: the server revoking
          // the session is part of it, and must not read as "not logged in".
          if (!signedIn && !_busy)
            const EmptyState(
              icon: Icons.person_outline,
              headline: 'Not logged in',
              body: 'Log in from Profile to delete your account.',
            )
          else ...[
            Text('What happens', style: text.titleMedium),
            const SizedBox(height: AlmanacDimens.sp3),
            point('Your account and the farm records on it are deleted.'),
            point('You are logged out on every phone, straight away.'),
            point(
              'Everything Almanac kept on this phone is cleared, and it opens '
              'like a new install.',
            ),
            point(
              'If you want a copy first, go back and use Download your data.',
            ),
            const SizedBox(height: AlmanacDimens.sp4),
            AppPasswordField(
              label: 'Your password',
              controller: _password,
              enabled: !_busy,
              textInputAction: TextInputAction.done,
              autofillHints: const [],
              onChanged: (_) => setState(() {}),
            ),
            ChoiceRow(
              label: 'I understand this cannot be undone',
              selected: _understood,
              onTap: _busy
                  ? null
                  : () => setState(() => _understood = !_understood),
            ),
            const SizedBox(height: AlmanacDimens.sp5),
            AppDangerButton(
              label: _busy ? 'Deleting…' : 'Delete my account',
              icon: LucideIcons.trash2,
              onPressed: _ready ? _delete : null,
            ),
          ],
        ],
      ),
    );
  }

  static const _unconfirmedAdvice =
      'We could not confirm whether your account was deleted. Your data on '
      'this phone has been kept. Reconnect and try again. If you can no longer '
      'log in, ask the Almanac team to confirm deletion before clearing '
      "Almanac's storage in your phone's settings.";

  /// Only definite refusals say nothing was deleted. An earlier unconfirmed
  /// attempt keeps its warning even if a retry meets a revoked session.
  String _advice(AuthFailure failure) => switch (failure) {
    AuthFailure.invalidCredentials =>
      'That password is not right. Nothing has been deleted.',
    AuthFailure.offline => _unconfirmedAdvice,
    AuthFailure.tooManyAttempts =>
      'Too many tries. Wait a minute. Nothing has been deleted.',
    _ => authAdvice(failure),
  };
}
