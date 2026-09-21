import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/providers.dart';
import '../../app/theme/tokens.g.dart';
import '../../domain/auth.dart';

/// Keeps authenticated routes closed until the persisted session has been
/// checked. A valid stored session is enough to enter, so offline launch does
/// not become network-dependent.
class AuthGate extends ConsumerWidget {
  final Widget child;

  const AuthGate({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(authControllerProvider)
        .when(
          loading: () => const _AuthChecking(),
          error: (_, _) => const _AuthRequired(),
          data: (state) => state is SignedIn ? child : const _AuthRequired(),
        );
  }
}

class _AuthChecking extends StatelessWidget {
  const _AuthChecking();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _AuthRequired extends StatelessWidget {
  const _AuthRequired();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AlmanacDimens.gutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Spacer(),
            Icon(
              LucideIcons.lockKeyhole,
              size: 40,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              'Your farm is protected',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              'Sign in to open your farm. If you are creating an account, '
              'finish verifying your phone and email first.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => context.go('/home'),
              icon: const Icon(LucideIcons.house),
              label: const Text('Back to Home'),
            ),
            const Spacer(flex: 2),
          ],
        ),
      ),
    ),
  );
}
