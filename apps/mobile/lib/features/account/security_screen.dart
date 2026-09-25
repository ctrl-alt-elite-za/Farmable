/// Security actions for the current account. Other devices cannot be listed:
/// the API provides revocation, but no device-session inventory.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.g.dart';
import '../../core/ui/buttons.dart';
import '../../core/ui/layout.dart';
import '../../data/auth/api_auth_service.dart';
import '../../domain/auth/auth_models.dart';
import '../auth/auth_view_model.dart';
import '../auth/widgets/auth_scaffold.dart';

class SecurityScreen extends ConsumerStatefulWidget {
  const SecurityScreen({super.key});

  @override
  ConsumerState<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends ConsumerState<SecurityScreen> {
  bool _busy = false;
  String? _advice;

  Future<void> _signOutHere() async {
    if (_busy) return;
    setState(() => _busy = true);
    final failure = await ref.read(authViewModelProvider.notifier).signOut();
    if (!mounted) return;
    if (failure == null) {
      context.go('/profile');
    } else {
      setState(() {
        _busy = false;
        _advice = authAdvice(failure);
      });
    }
  }

  Future<void> _signOutEverywhere() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log out of every device?'),
        content: const Text(
          'This phone will log out first. Your farm stays on this phone. '
          'Other devices need a signal to receive the sign-out.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Log out everywhere'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _advice = null;
    });
    final failure = await ref
        .read(authViewModelProvider.notifier)
        .signOutEverywhere();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _advice = failure == null
          ? 'You are logged out on this phone and every other device.'
          : failure == AuthFailure.storageUnavailable
          ? 'This phone could not save the sign-out. Clear Almanac storage '
                'in your phone settings before someone else uses it.'
          : 'You are logged out on this phone. We could not confirm the '
                'sign-out on other devices. Connect, log in and try again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(authViewModelProvider).value is SignedIn;
    final hasServerAccount = ref.watch(authServiceProvider) is ApiAuthService;
    final text = Theme.of(context).textTheme;
    final c = context.semantic;

    return AuthScaffold(
      title: 'Security',
      subtitle: 'Choose where your account stays signed in.',
      onBack: _busy ? null : backOr(context, '/profile'),
      children: [
        if (_advice != null) ...[
          AuthNotice(message: _advice!),
          const SizedBox(height: AlmanacDimens.sp4),
        ],
        if (!signedIn)
          const EmptyState(
            icon: LucideIcons.lockKeyhole,
            headline: 'Not logged in',
            body: 'Log in from Profile to manage your account security.',
          )
        else ...[
          Text('Where you are signed in', style: text.titleMedium),
          const SizedBox(height: AlmanacDimens.sp3),
          AlmanacCard(
            child: Row(
              children: [
                Icon(LucideIcons.smartphone, color: c.primary),
                const SizedBox(width: AlmanacDimens.sp3),
                Expanded(
                  child: Text('This phone · active now', style: text.bodyLarge),
                ),
              ],
            ),
          ),
          const SizedBox(height: AlmanacDimens.sp3),
          if (hasServerAccount)
            Text(
              'A list of other devices is not available yet. You can still '
              'log out of all of them.',
              style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
            ),
          const SizedBox(height: AlmanacDimens.sp5),
          AppSecondaryButton(
            label: 'Log out on this phone',
            icon: LucideIcons.logOut,
            onPressed: _busy ? null : _signOutHere,
          ),
          const SizedBox(height: AlmanacDimens.sp3),
          if (hasServerAccount)
            AppDangerButton(
              label: 'Log out of every device',
              icon: LucideIcons.logOut,
              onPressed: _busy ? null : _signOutEverywhere,
            )
          else
            Text(
              'This demo account is only on this phone.',
              style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
            ),
          const SizedBox(height: AlmanacDimens.sp5),
          Text('Change password', style: text.titleMedium),
          const SizedBox(height: AlmanacDimens.sp2),
          Text(
            'Changing your password in Almanac is coming soon.',
            style: text.bodyMedium,
          ),
        ],
      ],
    );
  }
}
