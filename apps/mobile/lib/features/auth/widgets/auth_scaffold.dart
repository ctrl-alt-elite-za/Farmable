/// The page frame every auth screen sits in.
///
/// It exists for one reason above all the others: **the keyboard must never
/// cover the field being typed in.** That is not free, and getting it wrong
/// is the single most common defect in a sign-up form. What makes it work
/// here:
///
/// * `resizeToAvoidBottomInset` stays on, so the Scaffold gives the body only
///   the space the keyboard leaves.
/// * The content is inside one `SingleChildScrollView`. Flutter scrolls a
///   newly focused `TextField` into view *within its nearest Scrollable* — if
///   the form is a `Column` with no scroller, there is nowhere to scroll to
///   and the field stays hidden.
/// * The primary action scrolls with the form rather than being pinned to the
///   bottom, so it is never the thing sitting under the keyboard.
/// * The bottom padding adds `viewInsets.bottom`, which keeps the last field
///   reachable on a 360x640 screen where the keyboard takes half the height.
///
/// `test/auth/keyboard_test.dart` holds this to it.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../core/ui/buttons.dart';

class AuthScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;

  /// Where the back arrow goes. Null hides it — used by Auth Choice, which is
  /// the top of this stack and has nowhere above it.
  final VoidCallback? onBack;

  const AuthScaffold({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;
    final insets = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: SingleChildScrollView(
          // Always scrollable: on a 360x640 screen with the keyboard up, even
          // a two-field form is taller than the space left.
          physics: const ClampingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            AlmanacDimens.gutter,
            AlmanacDimens.sp2,
            AlmanacDimens.gutter,
            AlmanacDimens.sp7 + insets,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (onBack != null) ...[
                IconOnlyButton(
                  icon: LucideIcons.arrowLeft,
                  semanticLabel: 'Back',
                  onPressed: onBack,
                ),
                const SizedBox(height: AlmanacDimens.sp4),
              ],
              Text(
                title,
                style: text.headlineMedium?.copyWith(letterSpacing: -0.5),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: text.bodyMedium?.copyWith(color: c.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: AlmanacDimens.sp5),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// Goes back if there is somewhere to go, and to Auth Choice if there is not.
///
/// A deep link opens a screen with an empty stack, and a back arrow that does
/// nothing is worse than no back arrow. Every auth screen is reachable by
/// path, so every one of them can be in that position.
VoidCallback backOr(BuildContext context, String fallback) => () {
  final router = GoRouter.of(context);
  if (router.canPop()) {
    router.pop();
  } else {
    router.go(fallback);
  }
};

/// The one sentence that closes a form, with the link the design specifies.
///
/// A real 48dp target, because "Log in" at the bottom of Sign up is a
/// destination a farmer who tapped the wrong button needs to hit.
class AuthFooterLink extends StatelessWidget {
  final String leading;
  final String linkLabel;
  final VoidCallback onTap;

  const AuthFooterLink({
    super.key,
    required this.leading,
    required this.linkLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;

    return Center(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AlmanacDimens.rSm),
        child: Container(
          constraints: const BoxConstraints(minHeight: AlmanacDimens.touchMin),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: AlmanacDimens.sp3),
          child: Text.rich(
            TextSpan(
              style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
              children: [
                TextSpan(text: '$leading '),
                TextSpan(
                  text: linkLabel,
                  style: text.labelMedium?.copyWith(color: c.primary),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

/// A calm line for a step that did not go through.
///
/// Not a `SnackBar`: a message about the form belongs beside the form, where
/// it is still there after the farmer looks down at the keyboard. Icon, word
/// and colour, like every other status in this app.
class AuthNotice extends StatelessWidget {
  final String message;

  const AuthNotice({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;

    return Container(
      margin: const EdgeInsets.only(bottom: AlmanacDimens.sp4),
      padding: const EdgeInsets.symmetric(
        horizontal: AlmanacDimens.sp4,
        vertical: AlmanacDimens.sp3,
      ),
      decoration: BoxDecoration(
        color: c.statusNeedsAttentionContainer,
        borderRadius: BorderRadius.circular(AlmanacDimens.rMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            LucideIcons.info,
            size: 18,
            color: c.onStatusNeedsAttentionContainer,
          ),
          const SizedBox(width: AlmanacDimens.sp3),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: c.onStatusNeedsAttentionContainer),
            ),
          ),
        ],
      ),
    );
  }
}
