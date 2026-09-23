/// Auth Choice — guide §7.
///
/// Not another onboarding page: logo, one warm image, a headline, two buttons
/// and the legal line. Nothing else goes on this screen.
///
/// The offline promise is made here rather than in onboarding because it is
/// the objection that stops a smallholder signing up at all — "will this eat
/// my airtime" — and this is the last screen before they are asked to commit.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.g.dart';
import '../../core/ui/brand.dart';
import '../../core/ui/buttons.dart';
import '../../core/ui/crop_imagery.dart';
import '../../core/ui/not_built_yet_sheet.dart';

class AuthChoiceScreen extends StatelessWidget {
  const AuthChoiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: ConstrainedBox(
              // Fills a tall screen and scrolls a short one, rather than
              // overflowing at 360x640 — which is where the hero, the
              // headline and two 48dp buttons stop fitting at once.
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AlmanacDimens.gutter,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: AlmanacDimens.sp6),
                      const Center(child: BrandLockup()),
                      const SizedBox(height: AlmanacDimens.sp5),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(
                            AlmanacDimens.r2xl,
                          ),
                          child: const Stack(
                            fit: StackFit.expand,
                            children: [
                              CropImagery(
                                scene: CropScene.farm,
                                seed: 'auth-choice',
                              ),
                              ImageryScrim(),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AlmanacDimens.sp6),
                      Text(
                        'Your farm.\nBetter understood.',
                        style: text.headlineLarge?.copyWith(
                          letterSpacing: -0.6,
                        ),
                      ),
                      const SizedBox(height: AlmanacDimens.sp2),
                      Text(
                        'Works without airtime or data. Your records stay on '
                        'your phone.',
                        style: text.bodyMedium?.copyWith(
                          color: c.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AlmanacDimens.sp5),
                      AppPrimaryButton(
                        label: 'Sign up',
                        onPressed: () => context.go('/auth/signup'),
                      ),
                      const SizedBox(height: AlmanacDimens.sp3),
                      AppSecondaryButton(
                        label: 'Log in',
                        onPressed: () => context.go('/auth/login'),
                      ),
                      const SizedBox(height: AlmanacDimens.sp4),
                      const _LegalLine(),
                      const SizedBox(height: AlmanacDimens.sp5),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The legal sentence, with both documents tappable — guide §7 requires it.
///
/// Laid out word by word in a [Wrap] rather than as a `Text.rich` with a
/// `TapGestureRecognizer`. Two reasons, and the first is the one that decides
/// it:
///
/// * A recognizer gives a link the hit area of its own glyphs — about 16px
///   tall at `label-s`. These links get a real target instead.
/// * Handing the Wrap whole phrases rather than words makes it break between
///   phrases, which stacked this sentence into five centred fragments with a
///   full stop alone on the last line. It was fine in a widget test and wrong
///   on the phone. One word per child lets it flow like the paragraph it is.
class _LegalLine extends StatelessWidget {
  const _LegalLine();

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final body = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: c.onSurfaceVariant);

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      children: [
        for (final word in 'By continuing you agree to the'.split(' '))
          Text(word, style: body),
        const _LegalLink(
          label: 'Terms of Use',
          body:
              'The terms you are agreeing to will be here before the app '
              'goes to farmers. Nothing you do in this version is bound by '
              'them.',
        ),
        for (final word in 'and acknowledge the'.split(' '))
          Text(word, style: body),
        const _LegalLink(
          label: 'Privacy Notice',
          body:
              'What the app records, what stays on your phone and what is '
              'ever sent anywhere will be set out here. Today everything '
              'you enter stays on this device.',
        ),
      ],
    );
  }
}

class _LegalLink extends StatelessWidget {
  final String label;
  final String body;

  const _LegalLink({required this.label, required this.body});

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;

    return InkWell(
      onTap: () => showNotBuiltYetSheet(context, title: label, body: body),
      borderRadius: BorderRadius.circular(AlmanacDimens.rXs),
      // Sized by padding, with no `alignment`. A Container that is given an
      // alignment expands to the full width it is offered — `buttons.dart`
      // documents the same trap — and inside a Wrap that is the whole
      // available line, which pushed each link onto a line of its own and
      // stacked this sentence into four centred fragments. 16 above and below
      // a 16px line box is the 48dp target.
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: c.primary,
            decoration: TextDecoration.underline,
            decorationColor: c.primary,
          ),
        ),
      ),
    );
  }
}
