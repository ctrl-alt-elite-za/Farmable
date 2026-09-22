/// "What I used", and the sheet for changing it.
///
/// The card states the farmer's own constraints back to them as chips, because
/// a recommendation whose inputs are invisible is a recommendation nobody can
/// argue with. The sheet is how they argue with it — and it is the issue #22
/// constraint flow: change the budget or ask to keep half the section as
/// cabbage, rerun, get a different answer.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../core/ui/badges.dart';
import '../../../core/ui/buttons.dart';
import '../../../core/ui/layout.dart';
import '../../../core/utils/dates.dart';
import '../../../domain/models.dart';
import '../../../domain/planning/recommendations.dart';
import '../budget_input.dart';

/// The chips above the cards: budget, water, deadline, planting date, share.
class ConstraintsCard extends StatelessWidget {
  final PlanningConstraints constraints;
  final VoidCallback onChange;

  const ConstraintsCard({
    super.key,
    required this.constraints,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;

    return AlmanacCard(
      padding: const EdgeInsets.all(AlmanacDimens.sp4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'WHAT I USED',
            style: text.labelSmall?.copyWith(
              color: c.onSurfaceVariant,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: AlmanacDimens.sp3),
          Wrap(
            spacing: AlmanacDimens.sp2,
            runSpacing: AlmanacDimens.sp2,
            children: [
              ConstraintChip(
                icon: LucideIcons.wallet,
                text: 'Budget ${constraints.budget.formatted}',
              ),
              ConstraintChip(
                icon: LucideIcons.droplet,
                text: constraints.water.label,
                tone: constraints.water == WaterAvailability.limited
                    ? ChipTone.warn
                    : ChipTone.neutral,
              ),
              if (constraints.maxHarvestDays != null)
                ConstraintChip(
                  icon: LucideIcons.clock,
                  text: 'Harvest within ${constraints.maxHarvestDays} days',
                ),
              ConstraintChip(
                icon: LucideIcons.sun,
                text: 'Planting ${longDate(constraints.plantingDate)}',
              ),
              for (final share in constraints.minimumShares.entries)
                ConstraintChip(
                  icon: LucideIcons.layers,
                  text: 'Keep ${share.value}% ${share.key.label.toLowerCase()}',
                ),
            ],
          ),
          const SizedBox(height: AlmanacDimens.sp3),
          AppTonalButton(
            label: 'Change these',
            icon: LucideIcons.pencil,
            onPressed: onChange,
          ),
        ],
      ),
    );
  }
}

/// Returns the edited constraints, or null if the farmer backed out.
Future<PlanningConstraints?> showConstraintsSheet({
  required BuildContext context,
  required PlanningConstraints constraints,
  required DateTime windowStart,
  required DateTime windowEnd,
}) => showModalBottomSheet<PlanningConstraints>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (context) => _ConstraintsForm(
    initial: constraints,
    windowStart: windowStart,
    windowEnd: windowEnd,
  ),
);

class _ConstraintsForm extends StatefulWidget {
  final PlanningConstraints initial;
  final DateTime windowStart;
  final DateTime windowEnd;

  const _ConstraintsForm({
    required this.initial,
    required this.windowStart,
    required this.windowEnd,
  });

  @override
  State<_ConstraintsForm> createState() => _ConstraintsFormState();
}

class _ConstraintsFormState extends State<_ConstraintsForm> {
  late PlanningConstraints _draft = widget.initial;
  late final TextEditingController _budget = TextEditingController(
    // Whole rand. Cents in a budget field are noise, and the planner is given
    // the exact cents this parses back to rather than a rounded double.
    text: (widget.initial.budget.value ~/ 100).toString(),
  );

  /// What the field currently holds, read in full. Recomputed on every
  /// keystroke so the farmer is told while they are still looking at the
  /// field, not after the planner has run on a number they did not type.
  late BudgetInput _parsed = BudgetInput.parse(_budget.text);

  @override
  void dispose() {
    _budget.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AlmanacDimens.r2xl),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(
          AlmanacDimens.gutter,
          AlmanacDimens.sp4,
          AlmanacDimens.gutter,
          AlmanacDimens.sp5,
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: c.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: AlmanacDimens.sp4),
                Text('What should I use?', style: text.titleLarge),
                const SizedBox(height: AlmanacDimens.sp1),
                Text(
                  'Change any of these and I will work it out again.',
                  style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
                ),

                const SizedBox(height: AlmanacDimens.sp5),
                _Label('Money you have to start with'),
                const SizedBox(height: AlmanacDimens.sp2),
                TextField(
                  controller: _budget,
                  keyboardType: TextInputType.number,
                  style: text.bodyLarge,
                  onChanged: (value) =>
                      setState(() => _parsed = BudgetInput.parse(value)),
                  decoration: InputDecoration(
                    prefixText: 'R ',
                    border: const OutlineInputBorder(),
                    // Said on the field, in words that name the amount to type
                    // instead. An amount this app will not plan with is never
                    // quietly turned into one it will.
                    errorText: _parsed.error,
                  ),
                ),

                const SizedBox(height: AlmanacDimens.sp5),
                _Label('Water you can give it'),
                const SizedBox(height: AlmanacDimens.sp2),
                _Choices<WaterAvailability>(
                  values: WaterAvailability.values,
                  selected: _draft.water,
                  label: (v) => switch (v) {
                    WaterAvailability.limited => 'Limited',
                    WaterAvailability.adequate => 'Enough',
                    WaterAvailability.good => 'Plenty',
                  },
                  onSelect: (v) => setState(() {
                    _draft = _draft.copyWith(water: v);
                  }),
                ),

                const SizedBox(height: AlmanacDimens.sp5),
                _Label('Longest you can wait for harvest'),
                const SizedBox(height: AlmanacDimens.sp2),
                _Choices<int?>(
                  values: const [60, 90, 120, null],
                  selected: _draft.maxHarvestDays,
                  label: (v) => v == null ? 'No limit' : '$v days',
                  onSelect: (v) => setState(() {
                    _draft = v == null
                        ? _draft.copyWith(clearDeadline: true)
                        : _draft.copyWith(maxHarvestDays: v);
                  }),
                ),

                const SizedBox(height: AlmanacDimens.sp5),
                _Label('Keep part of the section for one crop'),
                const SizedBox(height: AlmanacDimens.sp2),
                for (final crop in Crop.values) ...[
                  Text(
                    crop.label,
                    style: text.labelSmall?.copyWith(color: c.onSurfaceVariant),
                  ),
                  const SizedBox(height: AlmanacDimens.sp2),
                  _Choices<int>(
                    values: const [0, 25, 50, 75],
                    selected: _draft.minimumShares[crop] ?? 0,
                    label: (v) => v == 0 ? 'No minimum' : 'At least $v%',
                    onSelect: (v) => setState(() {
                      final shares = {..._draft.minimumShares};
                      if (v == 0) {
                        shares.remove(crop);
                      } else {
                        shares[crop] = v;
                      }
                      _draft = _draft.copyWith(minimumShares: shares);
                    }),
                  ),
                  const SizedBox(height: AlmanacDimens.sp3),
                ],

                const SizedBox(height: AlmanacDimens.sp2),
                _Label('Planting date'),
                const SizedBox(height: AlmanacDimens.sp2),
                AppTonalButton(
                  label: longDate(_draft.plantingDate),
                  icon: LucideIcons.calendar,
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _clamp(_draft.plantingDate),
                      // The sample scenario covers one month. Offering dates
                      // outside it would be offering a refusal.
                      firstDate: widget.windowStart,
                      lastDate: widget.windowEnd,
                    );
                    if (picked != null) {
                      setState(() {
                        _draft = _draft.copyWith(plantingDate: picked);
                      });
                    }
                  },
                ),
                const SizedBox(height: AlmanacDimens.sp2),
                Text(
                  'These sample figures only cover '
                  '${longDate(widget.windowStart)} to '
                  '${longDate(widget.windowEnd)}.',
                  style: text.labelSmall?.copyWith(color: c.onSurfaceVariant),
                ),

                const SizedBox(height: AlmanacDimens.sp6),
                AppPrimaryButton(
                  label: 'Work it out again',
                  icon: LucideIcons.refreshCw,
                  // Nothing reruns while the budget is unreadable. The
                  // alternative — rerunning on the last good number — would
                  // answer a question the farmer did not ask.
                  onPressed: _parsed.isValid
                      ? () =>
                            Navigator.of(context)
                                .pop(_draft.copyWith(budget: _parsed.value))
                      : null,
                ),
                const SizedBox(height: AlmanacDimens.sp2),
                AppTonalButton(
                  label: 'Cancel',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  DateTime _clamp(DateTime value) {
    if (value.isBefore(widget.windowStart)) return widget.windowStart;
    if (value.isAfter(widget.windowEnd)) return widget.windowEnd;
    return value;
  }
}

class _Label extends StatelessWidget {
  final String text;

  const _Label(this.text);

  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.titleSmall);
}

/// A row of single-choice pills. Icon-free by design — each one is a word or a
/// figure, which is the label — but every one is 48dp tall.
class _Choices<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onSelect;

  const _Choices({
    required this.values,
    required this.selected,
    required this.label,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    return Wrap(
      spacing: AlmanacDimens.sp2,
      runSpacing: AlmanacDimens.sp2,
      children: [
        for (final value in values)
          Material(
            color: value == selected ? c.primaryContainer : c.surfaceContainer,
            shape: StadiumBorder(
              side: BorderSide(
                color: value == selected ? c.primary : c.outlineVariant,
                width: value == selected ? 1.5 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => onSelect(value),
              child: Container(
                constraints: const BoxConstraints(
                  minHeight: AlmanacDimens.touchMin,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AlmanacDimens.sp4,
                ),
                // No `alignment` here: a Container with one expands to fill
                // whatever bounded width it is offered, which made every pill
                // span the sheet and turned a row of choices into a stack.
                // The Row below is `MainAxisSize.min` and centres itself.
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Selection is never carried by the fill alone: the chosen
                    // pill also takes a tick and a heavier border.
                    if (value == selected) ...[
                      Icon(
                        LucideIcons.check,
                        size: 16,
                        color: c.onPrimaryContainer,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      label(value),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: value == selected
                            ? c.onPrimaryContainer
                            : c.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
