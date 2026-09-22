/// The two-step stepper, the segmented control, and the onboarding progress
/// bar. Small pieces that carry state, so each one states it three ways.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/app_motion.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.g.dart';

/// One step of a flow.
class FlowStep {
  final String label;

  const FlowStep(this.label);
}

/// `1 Phone → 2 Email`.
///
/// Used only by verification. A done step is a tick on the on-track ramp, the
/// current step is numbered and on `primary` with its label in full contrast,
/// and an upcoming step is muted — number, colour and weight, so "where am I"
/// survives a monochrome screen.
class FlowStepper extends StatelessWidget {
  final List<FlowStep> steps;
  final int currentIndex;

  const FlowStepper({
    super.key,
    required this.steps,
    required this.currentIndex,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;

    final children = <Widget>[];
    for (var i = 0; i < steps.length; i++) {
      final done = i < currentIndex;
      final now = i == currentIndex;

      if (i > 0) {
        children.add(
          Expanded(
            child: Container(
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: AlmanacDimens.sp2),
              color: done || now ? c.primary : c.outlineVariant,
            ),
          ),
        );
      }

      children.add(
        Semantics(
          label: done
              ? '${steps[i].label}, done'
              : now
              ? '${steps[i].label}, current step'
              : '${steps[i].label}, not started',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done
                      ? c.statusOnTrack
                      : now
                      ? c.primary
                      : c.surfaceContainerHigh,
                ),
                child: done
                    ? const Icon(
                        LucideIcons.check,
                        size: 15,
                        color: Color(0xFFFFFFFF),
                      )
                    : Text(
                        '${i + 1}',
                        style: text.labelSmall?.copyWith(
                          color: now ? c.onPrimary : c.onSurfaceVariant,
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              Text(
                steps[i].label,
                style: text.labelMedium?.copyWith(
                  color: now || done ? c.onSurface : c.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AlmanacDimens.sp5),
      child: Row(children: children),
    );
  }
}

/// One option of a segmented control. Icon **and** word, per COMPONENTS.md.
class SegmentOption<T> {
  final T value;
  final String label;
  final IconData icon;

  const SegmentOption({
    required this.value,
    required this.label,
    required this.icon,
  });
}

/// Full-width pill with a 4px inset track and 44px segments.
///
/// This is what stops Login asking for an email *and* a phone. The selected
/// segment lifts onto `surface` and takes full-contrast text, so selection is
/// fill, elevation and colour rather than colour alone.
class AppSegmentedControl<T> extends StatelessWidget {
  final List<SegmentOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;

  const AppSegmentedControl({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;
    final motion = AppMotion.of(context);

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.surfaceContainer,
        borderRadius: BorderRadius.circular(AlmanacDimens.rPill),
      ),
      child: Row(
        children: [
          for (final option in options) ...[
            if (option != options.first) const SizedBox(width: 4),
            Expanded(
              child: Semantics(
                button: true,
                selected: option.value == value,
                child: InkWell(
                  onTap: () => onChanged(option.value),
                  borderRadius: BorderRadius.circular(AlmanacDimens.rPill),
                  child: AnimatedContainer(
                    duration: motion.micro,
                    curve: AlmanacMotion.easeStandard,
                    height: 44,
                    decoration: BoxDecoration(
                      color: option.value == value
                          ? c.surface
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(AlmanacDimens.rPill),
                      border: Border.all(
                        color: option.value == value
                            ? c.outlineVariant
                            : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          option.icon,
                          size: 17,
                          color: option.value == value
                              ? c.onSurface
                              : c.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            option.label,
                            overflow: TextOverflow.ellipsis,
                            style: text.labelMedium?.copyWith(
                              color: option.value == value
                                  ? c.onSurface
                                  : c.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The onboarding progress bar.
///
/// Takes a continuous [progress] rather than a page index, because guide §6
/// asks for it to move *with* the swipe. Driven from `PageController.page`,
/// which is fractional while a drag is in flight, so the bar is halfway
/// between 25% and 50% when the card is halfway across. A bar fed an `int`
/// jumps on release and that is the thing the guide calls out.
class FlowProgressBar extends StatelessWidget {
  /// 0.0 to 1.0.
  final double progress;

  /// For the screen reader, which cannot see a bar: "Step 2 of 4".
  final String semanticLabel;

  const FlowProgressBar({
    super.key,
    required this.progress,
    required this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;

    return Semantics(
      label: semanticLabel,
      value: '${(progress * 100).round()} percent',
      // `double.infinity` is load-bearing: the bar's parent Column centres
      // its cross axis, so without it the track sizes to the *filled*
      // fraction and the whole bar renders as a short centred stub. It looks
      // right in a widget test and wrong on a phone.
      child: SizedBox(
        width: double.infinity,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Container(
            height: 5,
            color: c.surfaceContainerHigh,
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progress.clamp(0.0, 1.0),
              child: Container(color: c.primary),
            ),
          ),
        ),
      ),
    );
  }
}
