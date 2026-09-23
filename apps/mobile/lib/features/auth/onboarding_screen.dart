/// Onboarding — guide §6.
///
/// Four cards in a horizontal `PageView` with fixed chrome: Skip stays top
/// LEFT, the progress bar and the Next button stay at the foot, and only the
/// artwork and copy move. The guide is specific about the two details people
/// get wrong, so both are called out where they happen:
///
/// * **Skip is top left**, and the top right stays empty.
/// * **The progress bar moves with the swipe**, not on release. It is fed
///   `PageController.page`, which is fractional mid-drag, so the bar sits
///   between 25% and 50% when the card is halfway across. Feeding it an `int`
///   index is what makes a bar jump, and it is the thing §6 calls out.
///
/// Skip and Get started both go to Auth Choice, per §6.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/app_motion.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.g.dart';
import '../../core/ui/buttons.dart';
import '../../core/ui/flow_controls.dart';
import 'widgets/onboarding_art.dart';

class _Card {
  final OnboardingArt art;
  final String headline;
  final String body;

  const _Card({required this.art, required this.headline, required this.body});
}

/// Copy is the guide's, word for word. It is not placeholder text and should
/// not be rewritten without going back to §6.
const _cards = <_Card>[
  _Card(
    art: OnboardingArt.zones,
    headline: 'See your farm clearly',
    body:
        'Keep every section, crop, task and observation connected to the '
        'land it belongs to.',
  ),
  _Card(
    art: OnboardingArt.scan,
    headline: 'Check crop health with your camera',
    body:
        'Scan crops, record observations and keep a history for every '
        'section of your farm.',
  ),
  _Card(
    art: OnboardingArt.compare,
    headline: 'Make better planting decisions',
    body:
        'Compare crops using your land, costs, available water and expected '
        'market conditions.',
  ),
  _Card(
    art: OnboardingArt.voice,
    headline: 'Run your farm by voice',
    body:
        'Record notes, update farm records and ask questions without '
        'stopping your work.',
  ),
];

class OnboardingScreen extends StatefulWidget {
  /// Where Skip and Get started both go. Injected so the test names it once
  /// and the screen has no opinion about routing.
  final VoidCallback onFinished;

  const OnboardingScreen({super.key, required this.onFinished});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pages = PageController();

  /// The continuous position, 0.0 to 3.0. Kept in state rather than read from
  /// the controller during build, because `PageController.page` throws before
  /// the first layout and is the value that has to drive the bar.
  double _position = 0;

  @override
  void initState() {
    super.initState();
    _pages.addListener(() {
      final page = _pages.hasClients ? _pages.page : null;
      if (page != null && page != _position) setState(() => _position = page);
    });
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  int get _index => _position.round();

  bool get _isLast => _index == _cards.length - 1;

  void _next() {
    if (_isLast) {
      widget.onFinished();
      return;
    }
    _pages.nextPage(
      duration: AppMotion.of(context).screen,
      curve: AlmanacMotion.easeEmphasised,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          children: [
            // Fixed chrome. Skip is the first thing in the first row, which is
            // what puts it top left and keeps the top right clean.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AlmanacDimens.gutter,
                AlmanacDimens.sp2,
                AlmanacDimens.gutter,
                0,
              ),
              child: Row(
                children: [
                  AppTonalButton(
                    label: 'Skip',
                    block: false,
                    onPressed: widget.onFinished,
                  ),
                  const Spacer(),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: _cards.length,
                itemBuilder: (context, i) => _CardBody(
                  card: _cards[i],
                  // -1 to 1 for the neighbours, 0 for the centred card.
                  parallax: (i - _position).clamp(-1.0, 1.0),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AlmanacDimens.gutter,
                AlmanacDimens.sp4,
                AlmanacDimens.gutter,
                AlmanacDimens.sp5,
              ),
              child: Column(
                children: [
                  FlowProgressBar(
                    // Page 1 is 25%, page 4 is 100%, and everything between
                    // is continuous because `_position` is.
                    progress: (_position + 1) / _cards.length,
                    semanticLabel: 'Step ${_index + 1} of ${_cards.length}',
                  ),
                  const SizedBox(height: AlmanacDimens.sp4),
                  Row(
                    children: [
                      Text(
                        '${_index + 1} of ${_cards.length}',
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: c.onSurfaceVariant),
                      ),
                      const Spacer(),
                      AppPrimaryButton(
                        label: _isLast ? 'Get started' : 'Next',
                        icon: _isLast
                            ? LucideIcons.check
                            : LucideIcons.arrowRight,
                        iconAfterLabel: true,
                        block: false,
                        onPressed: _next,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardBody extends StatelessWidget {
  final _Card card;
  final double parallax;

  const _CardBody({required this.card, required this.parallax});

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AlmanacDimens.gutter),
      child: Column(
        children: [
          const SizedBox(height: AlmanacDimens.sp4),
          Expanded(
            child: OnboardingArtwork(art: card.art, offset: parallax),
          ),
          const SizedBox(height: AlmanacDimens.sp6),
          // The copy is not squeezed into whatever the artwork leaves: it is
          // measured first and the artwork takes the rest, because a headline
          // that wraps to three lines on a 360x640 screen must not be the
          // thing that gets clipped.
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: double.infinity,
                child: Text(
                  card.headline,
                  style: text.headlineSmall?.copyWith(letterSpacing: -0.4),
                ),
              ),
              const SizedBox(height: AlmanacDimens.sp2),
              Text(
                card.body,
                style: text.bodyMedium?.copyWith(color: c.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
