/// The section carousel — the signature interaction of the dashboard.
library;

import 'package:flutter/material.dart';

import '../../../app/theme/tokens.g.dart';
import '../../../domain/farm_records.dart';
import 'zone_card.dart';

/// How many times the strip is repeated in each direction.
///
/// `PageView.builder` with an unbounded item count numbers its pages from zero
/// upward, so "infinite" backwards is bought by starting a long way in. A
/// farmer swiping one card per second reaches the start of the strip after
/// about an hour of uninterrupted swiping, which is the same as never.
const _loops = 1000;

/// Maps a page index onto a section.
///
/// This is the whole of the looping trick: the strip is unbounded and the list
/// is not, so page 4001 and page 4005 are the same section when there are four
/// of them. There is no jump to hide because nothing ever jumps — the page
/// number simply keeps counting.
int carouselIndexFor(int page, int count) => count == 0 ? 0 : page % count;

/// The page a carousel of [count] sections starts on.
int carouselInitialPage(int count) => count * _loops;

/// A card's scale from its distance to the centre of the viewport.
///
/// A pure function of scroll offset, not an animation: the centre card is at
/// 1.0 and its neighbours fall to 0.88 continuously as the strip moves, rather
/// than snapping to a new scale once the page settles. [page] is the
/// controller's fractional page; [index] is the card being drawn.
double carouselScaleFor(double page, int index) {
  final distance = (page - index).abs().clamp(0.0, 1.0);
  return 1.0 - 0.12 * distance;
}

/// A card's opacity, on the same continuous basis. Centre 1.0, neighbour 0.78.
double carouselOpacityFor(double page, int index) {
  final distance = (page - index).abs().clamp(0.0, 1.0);
  return 1.0 - 0.22 * distance;
}

class ZoneCarousel extends StatefulWidget {
  final List<SectionSummary> sections;
  final void Function(SectionSummary section) onOpen;

  const ZoneCarousel({
    super.key,
    required this.sections,
    required this.onOpen,
  });

  @override
  State<ZoneCarousel> createState() => _ZoneCarouselState();
}

class _ZoneCarouselState extends State<ZoneCarousel> {
  late final PageController _controller;
  late int _centre;

  @override
  void initState() {
    super.initState();
    _centre = carouselInitialPage(widget.sections.length);
    _controller = PageController(
      // 0.72 of the viewport, so the neighbours are visibly there. A farmer
      // who cannot see that there is another card does not know to swipe, and
      // nothing on this screen tells them to.
      viewportFraction: 0.72,
      initialPage: _centre,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The fractional page, usable before the controller has been laid out.
  double get _page {
    if (!_controller.hasClients) return _centre.toDouble();
    final position = _controller.position;
    if (!position.hasContentDimensions) return _centre.toDouble();
    return _controller.page ?? _centre.toDouble();
  }

  void _tap(int page, SectionSummary section) {
    if (page == _centre) {
      widget.onOpen(section);
      return;
    }
    // Tapping a neighbour brings it to the centre rather than opening it.
    // Opening a card the farmer can only half see would be a mis-tap most of
    // the time, and the scroll is the affordance the design is teaching.
    _controller.animateToPage(
      page,
      duration: AlmanacMotion.durMicro,
      curve: AlmanacMotion.easeStandard,
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.sections.length;

    return SizedBox(
      // The card is 4:5 inside a mat, plus the room the label chip hangs into.
      height: MediaQuery.sizeOf(context).width * 0.72 * 1.25 + 82,
      child: PageView.builder(
        controller: _controller,
        onPageChanged: (page) => setState(() => _centre = page),
        padEnds: true,
        itemBuilder: (context, page) {
          final section = widget.sections[carouselIndexFor(page, count)];
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final p = _page;
              return Opacity(
                opacity: carouselOpacityFor(p, page),
                child: Transform.scale(
                  scale: carouselScaleFor(p, page),
                  // Cards shrink toward the label chip rather than away from
                  // it, so the names stay on one line as the strip moves.
                  alignment: Alignment.bottomCenter,
                  child: child,
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AlmanacDimens.sp2,
              ),
              child: ZoneCard(
                section: section,
                isCentre: page == _centre,
                onTap: () => _tap(page, section),
              ),
            ),
          );
        },
      ),
    );
  }
}
