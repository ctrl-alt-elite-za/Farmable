/// The Profile destination: who is signed in, and the way out.
///
/// The first slice of issue #10's account experience. It shows the signed-in
/// farmer and lets them log out; when nobody is signed in it offers Log in and
/// Create account, which is how someone reaches authentication from a farm
/// that opened without it. Nothing here is a gate — Home and Zone Detail open
/// whatever this screen says.
///
/// Profile editing, privacy and consent, data export and account deletion are
/// later slices and are named here as not built rather than hidden.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.g.dart';
import '../../core/ui/buttons.dart';
import '../../core/ui/layout.dart';
import '../../domain/auth/auth_models.dart';
import '../../domain/auth/contact_details.dart';
import '../auth/auth_view_model.dart';
import '../auth/widgets/auth_scaffold.dart';
import '../shell/almanac_scaffold.dart';
import '../shell/bottom_nav_island.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final standing = ref.watch(authViewModelProvider).value;

    return AlmanacScaffold(
      destination: NavDestination.profile,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AlmanacDimens.gutter,
            0,
            AlmanacDimens.gutter,
            // Clear of the floating nav island.
            AlmanacDimens.sp7 * 3,
          ),
          children: [
            const SectionHeader(title: 'Profile'),
            switch (standing) {
              null => const SizedBox.shrink(),
              SignedIn(session: final session) => _SignedIn(session.user),
              AwaitingVerification() => EmptyState(
                icon: LucideIcons.messageSquareText,
                headline: 'Finish creating your account',
                body:
                    'Your account is waiting for a code. Your farm opens on '
                    'this phone either way.',
                actionLabel: 'Enter your code',
                actionIcon: LucideIcons.arrowRight,
                onAction: () => context.go('/auth/verify'),
              ),
              SignedOut() => const _SignedOut(),
            },
            // The device self-test (#4) — the part of "what the app is
            // allowed to use" that exists so far, and the way a phone build
            // that opens on Home reaches it. Asks for nothing until Run.
            SectionHeader(
              title: 'This phone',
              actionLabel: 'Device self-test',
              onAction: () => context.push('/self-test'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignedIn extends ConsumerStatefulWidget {
  final AuthUser user;

  const _SignedIn(this.user);

  @override
  ConsumerState<_SignedIn> createState() => _SignedInState();
}

class _SignedInState extends ConsumerState<_SignedIn> {
  bool _busy = false;
  AuthFailure? _failure;

  Future<void> _logOut() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    final failure = await ref.read(authViewModelProvider.notifier).signOut();
    // On success the standing changes and this widget is replaced by the
    // signed-out view, so there is nothing to reset.
    if (mounted && failure != null) {
      setState(() {
        _busy = false;
        _failure = failure;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_failure != null) AuthNotice(message: authAdvice(_failure!)),
        AlmanacCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(user.fullName, style: text.titleLarge),
              const SizedBox(height: AlmanacDimens.sp3),
              // Masked, as on the verify screen: this is a phone people hand
              // to each other, and the farmer recognises their own details.
              DetailRow(label: 'Phone', value: maskPhone(user.phone)),
              DetailRow(
                label: 'Email',
                value: maskEmail(user.email),
                last: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: AlmanacDimens.sp4),
        Text(
          'Editing your details, privacy choices and downloading your data '
          'are not built yet.',
          style: text.bodySmall?.copyWith(
            color: context.semantic.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AlmanacDimens.sp6),
        AppSecondaryButton(
          label: _busy ? 'Logging out…' : 'Log out',
          icon: LucideIcons.logOut,
          onPressed: _busy ? null : _logOut,
        ),
        const SizedBox(height: AlmanacDimens.sp3),
        Text(
          'Logging out keeps your farm on this phone.',
          style: text.bodySmall?.copyWith(
            color: context.semantic.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _SignedOut extends StatelessWidget {
  const _SignedOut();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const EmptyState(
        icon: LucideIcons.user,
        headline: 'Not logged in',
        body:
            'Your farm opens on this phone without an account. Log in, or '
            'create one, whenever you are ready.',
      ),
      const SizedBox(height: AlmanacDimens.sp5),
      AppPrimaryButton(
        label: 'Log in',
        onPressed: () => context.go('/auth/login'),
      ),
      const SizedBox(height: AlmanacDimens.sp3),
      AppSecondaryButton(
        label: 'Create account',
        onPressed: () => context.go('/auth/signup'),
      ),
    ],
  );
}
