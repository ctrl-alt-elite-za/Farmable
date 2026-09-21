/// The section carousel — the signature interaction of the dashboard.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/tokens.g.dart';
import '../../../domain/farm_records.dart';
import 'zone_card.dart';

/// How much of the viewport one card occupies.
///
/// 0.72 leaves the neighbours visibly on screen. A farmer who cannot see that
/// there is another card does not know to swipe, and nothing here tells them.
const _viewportFraction = 0.72;

/// The mat the card leaves below the image, which the label chip sits on.
const _matFoot = 26.0;

/// Half the label chip's 42px height — how far it hangs below the card.
const _chipOverhang = 21.0;

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
///
/// [page] may be negative once it has been shifted by the carousel's identity
/// anchor. Dart's `%` is euclidean for a positive divisor, so -1 of four
/// sections is 3 and the strip still reads backwards correctly.
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

  /// Fires whenever a different section reaches the centre.
  ///
  /// The centred section is the one the farmer is looking at, so it is also
  /// the one the caption beneath describes and the one "Add observation"
  /// writes to.
  final void Function(SectionSummary section)? onCentreChanged;

  const ZoneCarousel({
    super.key,
    required this.sections,
    required this.onOpen,
    this.onCentreChanged,
  });

  @override
  State<ZoneCarousel> createState() => _ZoneCarouselState();
}

class _ZoneCarouselState extends State<ZoneCarousel> {
  late final PageController _controller;

  /// The page the farmer is looking at. It counts upward forever and is not an
  /// index into [ZoneCarousel.sections].
  late int _centre;

  /// The page/index pair that ties the endless page numbering to the list.
  ///
  /// Sections arrive from a live database stream, so the list can gain or lose
  /// one under a carousel that is already on screen. Page numbers cannot be
  /// re-derived from the new length: `page % count` with a different `count`
  /// quietly resolves to a *different* section, and because the controller has
  /// not moved, nothing fires to say so. The caption and the quick actions
  /// would then be writing to a section other than the card on screen.
  ///
  /// So the mapping is anchored to a section identity instead — the card at
  /// [_anchorPage] is `sections[_anchorIndex]` — and when the list changes the
  /// anchor is re-pointed at wherever the centred section moved to. The strip
  /// never jumps, because the page numbering never has to change.
  late int _anchorPage;
  late int _anchorIndex;

  /// The id of the section at the centre, which is what the anchor is
  /// re-established from.
  String? _centreId;

  @override
  void initState() {
    super.initState();
    _centre = carouselInitialPage(widget.sections.length);
    _anchorPage = _centre;
    _anchorIndex = 0;
    _centreId = _sectionAt(_centre)?.id;
    _controller = PageController(
      viewportFraction: _viewportFraction,
      initialPage: _centre,
    );
  }

  @override
  void didUpdateWidget(ZoneCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);

    final oldIds = [for (final s in oldWidget.sections) s.id];
    final newIds = [for (final s in widget.sections) s.id];
    if (listEquals(oldIds, newIds)) return;
    if (newIds.isEmpty) {
      _centreId = null;
      return;
    }

    // Re-anchored on the section that is centred, not on the index it used to
    // sit at: deleting a section ahead of it shifts every index after it, and
    // the identity is the only thing that survives that.
    final moved = newIds.indexOf(_centreId ?? '');
    setState(() {
      _anchorPage = _centre;
      _anchorIndex = moved == -1
          ? carouselIndexFor(_centre, newIds.length)
          : moved;
      _centreId = _sectionAt(_centre)?.id;
    });

    // The centred section itself is gone, so the centre really did change and
    // whatever reads it has to be told. Deferred because didUpdateWidget runs
    // inside the parent's build and the listener's answer is setState.
    if (moved == -1) {
      final section = _sectionAt(_centre);
      final onCentreChanged = widget.onCentreChanged;
      if (section != null && onCentreChanged != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) onCentreChanged(section);
        });
      }
    }
  }

  /// The section drawn on [page], resolved through the identity anchor.
  SectionSummary? _sectionAt(int page) {
    final count = widget.sections.length;
    if (count == 0) return null;
    return widget.sections[carouselIndexFor(
      page - _anchorPage + _anchorIndex,
      count,
    )];
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
    // Measured from the width the strip is actually given, not guessed from
    // the screen width. The old figure was 69px taller than the card, and a
    // PageView hands every page the full height of its viewport — so the card,
    // aligned to the bottom of that box, left a band of dead paper under the
    // "Your farm" header, and the label chip hanging below the card fell
    // outside the viewport and was clipped away.
    return LayoutBuilder(
      builder: (context, constraints) {
        final pageWidth = constraints.maxWidth * _viewportFraction;
        final cardWidth = pageWidth - AlmanacDimens.sp2 * 2;
        final mediaWidth = cardWidth - AlmanacDimens.rFrameInset * 2;
        // The mat: 8 above the 4:5 image and 26 below it.
        final cardHeight =
            mediaWidth * 5 / 4 + AlmanacDimens.rFrameInset + _matFoot;

        return SizedBox(
          height: cardHeight + _chipOverhang,
          child: _strip(cardHeight),
        );
      },
    );
  }

  Widget _strip(double cardHeight) => PageView.builder(
    controller: _controller,
    onPageChanged: (page) {
      final section = _sectionAt(page);
      setState(() {
        _centre = page;
        _centreId = section?.id;
      });
      if (section != null) widget.onCentreChanged?.call(section);
    },
    padEnds: true,
    // The label chip hangs half its height below the card, which is the
    // signature detail of this component. A PageView clips to its bounds
    // by default and was cutting the chip in half.
    clipBehavior: Clip.none,
    itemBuilder: (context, page) {
      final section = _sectionAt(page)!;
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
        // Pinned to the top of the page, and given exactly the card's own
        // height, so the space left underneath is the chip's overhang and
        // nothing else.
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: cardHeight,
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
          ),
        ),
      );
    },
  );
}
