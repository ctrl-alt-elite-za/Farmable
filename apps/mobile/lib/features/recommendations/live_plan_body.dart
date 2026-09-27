/// "What to plant" for a signed-in farmer's section, planned by the backend.
///
/// Leads with whatever is most useful: the unavailable notice when there is
/// no answer at all, the reason and the proposed change when nothing fits,
/// otherwise the plans that fit. The comparison, the farmer's assumptions and
/// the version history follow. Every figure here is in the backend's answer.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.g.dart';
import '../../core/ui/badges.dart';
import '../../core/ui/buttons.dart';
import '../../core/ui/fields.dart';
import '../../core/ui/layout.dart';
import '../../core/utils/dates.dart';
import '../../data/planning/planning_repository.dart';
import '../../domain/money.dart';
import '../../domain/planning/plan_preview.dart';
import '../shell/bottom_nav_island.dart';
import 'budget_input.dart';
import 'live_plan_view_model.dart';

class LivePlanBody extends ConsumerWidget {
  final String sectionId;
  final VoidCallback onBack;

  const LivePlanBody({
    super.key,
    required this.sectionId,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(livePlanProvider(sectionId));
    final text = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.only(bottom: BottomNavIsland.bottomInset),
      children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AlmanacDimens.gutter,
              AlmanacDimens.sp3,
              AlmanacDimens.gutter,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconOnlyButton(
                  icon: LucideIcons.arrowLeft,
                  semanticLabel: 'Back to this section',
                  onPressed: onBack,
                ),
                const SizedBox(height: AlmanacDimens.sp3),
                Text('What to plant', style: text.headlineMedium),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AlmanacDimens.gutter),
          child: view.when(
            // A request is in flight. Said in words, not a bare spinner.
            loading: () => const Padding(
              padding: EdgeInsets.only(top: AlmanacDimens.sp5),
              child: Text('Asking for a plan…'),
            ),
            error: (_, _) => _Unavailable(
              onRetry: () => ref.invalidate(livePlanProvider(sectionId)),
            ),
            data: (value) => value == null
                ? _Unavailable(
                    onRetry: () => ref.invalidate(livePlanProvider(sectionId)),
                  )
                : _Plan(view: value, sectionId: sectionId),
          ),
        ),
      ],
    );
  }
}

class _Plan extends ConsumerWidget {
  final LivePlanView view;
  final String sectionId;

  const _Plan({required this.view, required this.sectionId});

  void _setInputs(WidgetRef ref, PlanInputs next) =>
      ref.read(livePlanInputsProvider(sectionId).notifier).update(next);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;
    final preview = view.preview;
    final inputs = view.inputs;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${view.section.name} · ${view.section.section.areaHectares}',
          style: text.labelSmall?.copyWith(color: c.onSurfaceVariant),
        ),
        if (view.stale) ...[
          const SizedBox(height: AlmanacDimens.sp3),
          Align(
            alignment: Alignment.centerLeft,
            child: OfflineBadge(
              key: const ValueKey('plan-age'),
              label: view.ageLabel,
            ),
          ),
        ],
        const SizedBox(height: AlmanacDimens.sp4),
        _InputsCard(
          inputs: inputs,
          onChange: () async {
            final next = await showPlanInputsSheet(context, inputs);
            if (next != null) _setInputs(ref, next);
          },
        ),
        const SizedBox(height: AlmanacDimens.sp3),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Fit my budget')),
            ButtonSegment(value: true, label: Text('Reach a goal')),
          ],
          selected: {inputs.goalMargin != null},
          onSelectionChanged: (selection) async {
            if (selection.first) {
              final next = await showPlanInputsSheet(
                context,
                inputs,
                askGoal: true,
              );
              if (next != null) _setInputs(ref, next);
            } else {
              _setInputs(ref, inputs.copyWith(goalMargin: () => null));
            }
          },
        ),
        if (view.unavailable)
          _Unavailable(
            onRetry: () => ref.invalidate(livePlanProvider(sectionId)),
          )
        else if (preview != null) ...[
          if (preview.warning != null) ...[
            const SizedBox(height: AlmanacDimens.sp3),
            Text(
              preview.warning!,
              style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
            ),
          ],
          if (!preview.feasible)
            _Infeasible(
              change: preview.changeNeeded!,
              onApply: _applyChange(preview.changeNeeded!, inputs) == null
                  ? null
                  : () => _setInputs(
                      ref,
                      _applyChange(preview.changeNeeded!, inputs)!,
                    ),
            )
          else ...[
            SectionHeader(
              title: 'Plans that fit',
              subtitle:
                  '${inputs.plantingDate.year} · '
                  '${monthName(inputs.plantingDate)} planting',
            ),
            for (final (i, candidate) in preview.candidates.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: AlmanacDimens.sp3),
                child: _CandidateCard(
                  rank: i + 1,
                  candidate: candidate,
                  blockCount: 4,
                  onUse: () => _confirm(context, ref, preview, candidate),
                ),
              ),
          ],
          const SectionHeader(
            title: 'Compare crops',
            subtitle: 'Each crop on the whole section',
          ),
          for (final estimate in preview.comparisons)
            Padding(
              padding: const EdgeInsets.only(bottom: AlmanacDimens.sp3),
              child: _ComparisonCard(
                estimate: estimate,
                weather: preview.weather[estimate.crop],
              ),
            ),
          const SectionHeader(title: 'What this assumes'),
          AlmanacCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in preview.assumptions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AlmanacDimens.sp2),
                    child: Text('· $line', style: text.bodySmall),
                  ),
              ],
            ),
          ),
        ],
        const SectionHeader(title: 'Plan versions'),
        _History(versions: view.history, now: view.now),
      ],
    );
  }

  PlanInputs? _applyChange(ChangeNeeded change, PlanInputs inputs) =>
      switch (change) {
        ChangeNeeded(code: 'budget_too_low', :final minimumBudget?) =>
          inputs.copyWith(budget: minimumBudget),
        ChangeNeeded(code: 'goal_unreachable', :final maximumMargin?) =>
          inputs.copyWith(goalMargin: () => maximumMargin),
        _ => null,
      };

  Future<void> _confirm(
    BuildContext context,
    WidgetRef ref,
    PlanPreview preview,
    PlanCandidate candidate,
  ) async {
    final actions = ref.read(livePlanActionsProvider(sectionId));
    final key = actions.newConfirmationKey();
    final summary = candidate.allocations
        .map((a) => '${cropName(a.crop)} ×${a.blocks}')
        .join(', ');
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => _ConfirmSheet(
        summary: summary,
        margin: candidate.margin,
        requiredCash: candidate.requiredCash,
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final version = await actions.confirm(
      key: key,
      preview: preview,
      candidate: candidate,
      summary: summary,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(switch (version.state) {
          PlanVersionState.saved => 'Plan saved.',
          PlanVersionState.waiting =>
            'Plan saved on this phone. It will be sent when you have signal.',
          PlanVersionState.rejected => version.rejectionMessage,
        }),
      ),
    );
  }
}

/// The only state in which the planner has nothing: no fresh answer, and none
/// saved. Everything outside this screen keeps working.
class _Unavailable extends StatelessWidget {
  final VoidCallback onRetry;

  const _Unavailable({required this.onRetry});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AlmanacDimens.sp4),
    child: EmptyState(
      icon: LucideIcons.cloudOff,
      headline: 'Planning temporarily unavailable',
      body:
          'There is no market outlook to plan with right now, and none saved '
          'on this phone for this question. Your farm, tasks and records all '
          'still work. Try again when you have signal.',
      actionLabel: 'Try again',
      actionIcon: LucideIcons.refreshCw,
      onAction: onRetry,
    ),
  );
}

class _Infeasible extends StatelessWidget {
  final ChangeNeeded change;
  final VoidCallback? onApply;

  const _Infeasible({required this.change, required this.onApply});

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AlmanacDimens.sp4),
      child: AlmanacCard(
        key: const ValueKey('plan-infeasible'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nothing fits these constraints', style: text.titleMedium),
            const SizedBox(height: AlmanacDimens.sp2),
            Text(change.message, style: text.bodyMedium),
            const SizedBox(height: AlmanacDimens.sp3),
            Text(
              change.proposal,
              style: text.bodyMedium?.copyWith(color: c.primary),
            ),
            if (onApply != null) ...[
              const SizedBox(height: AlmanacDimens.sp4),
              AppPrimaryButton(label: 'Use this change', onPressed: onApply),
            ],
          ],
        ),
      ),
    );
  }
}

class _InputsCard extends StatelessWidget {
  final PlanInputs inputs;
  final VoidCallback onChange;

  const _InputsCard({required this.inputs, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('Budget', '${inputs.budget.formatted} (2025 rand)'),
      ('Planting', longDate(inputs.plantingDate)),
      if (inputs.cashDeadline != null)
        ('Paid by', longDate(inputs.cashDeadline!)),
      if (inputs.goalMargin != null)
        ('Profit goal', inputs.goalMargin!.formatted),
      for (final crop in inputs.crops)
        if (crop.minimumPercent > 0)
          ('At least', '${crop.minimumPercent}% ${cropName(crop.crop)}'),
      for (final crop in inputs.crops)
        if (crop.promisedKg != '0' && crop.promisedKg.isNotEmpty)
          ('Promised', '${crop.promisedKg} kg ${cropName(crop.crop)}'),
      ('Cost at planting', '${inputs.plantingCostPercent}%'),
      (
        'Commission',
        '${_percent(inputs.marketCommissionBps)} market · '
            '${_percent(inputs.agentCommissionBps)} agent',
      ),
    ];
    return AlmanacCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, (label, value)) in rows.indexed)
            DetailRow(label: label, value: value, last: i == rows.length - 1),
          const SizedBox(height: AlmanacDimens.sp3),
          AppSecondaryButton(
            label: 'Change what I told you',
            icon: LucideIcons.slidersHorizontal,
            onPressed: onChange,
          ),
        ],
      ),
    );
  }
}

class _CandidateCard extends StatelessWidget {
  final int rank;
  final PlanCandidate candidate;
  final int blockCount;
  final VoidCallback onUse;

  const _CandidateCard({
    required this.rank,
    required this.candidate,
    required this.blockCount,
    required this.onUse,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;
    return AlmanacCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Plan $rank', style: text.titleMedium),
          const SizedBox(height: AlmanacDimens.sp2),
          DetailRow(
            label: 'Expected profit (middle price)',
            value: candidate.margin.formatted,
          ),
          DetailRow(
            label: 'Cash you need',
            value: candidate.requiredCash.formatted,
          ),
          for (final a in candidate.allocations)
            DetailRow(
              label: '${cropName(a.crop)} · ${a.blocks} of $blockCount blocks',
              value:
                  '${a.quantityKg.trimmed} kg · harvest ${shortDate(a.harvestDate)}',
            ),
          DetailRow(
            label: 'Left unplanted',
            value: candidate.unplantedBlocks == 0
                ? 'None'
                : '${candidate.unplantedBlocks} of $blockCount blocks',
            last: true,
          ),
          const SizedBox(height: AlmanacDimens.sp3),
          Text('Cash through the season', style: text.labelLarge),
          for (final event in candidate.cashTimeline)
            Padding(
              padding: const EdgeInsets.only(top: AlmanacDimens.sp1),
              child: Text(
                '${shortDate(event.date)} · '
                '${event.cost.value > 0 ? 'spend ${event.cost.formatted}' : ''}'
                '${event.receipts.value > 0 ? 'paid ${event.receipts.formatted}' : ''}'
                ' · balance ${event.balance.formatted}',
                style: text.bodySmall?.copyWith(
                  color: event.balance.isNegative
                      ? c.statusActionRequired
                      : c.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: AlmanacDimens.sp4),
          AppPrimaryButton(label: 'Use this plan', onPressed: onUse),
        ],
      ),
    );
  }
}

class _ComparisonCard extends StatelessWidget {
  final CropEstimate estimate;
  final WeatherExposure? weather;

  const _ComparisonCard({required this.estimate, required this.weather});

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;
    return AlmanacCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(cropName(estimate.crop), style: text.titleMedium),
          DetailRow(label: 'Expected profit', value: estimate.margin.formatted),
          DetailRow(
            label: 'Chance of breaking even',
            value: estimate.breakEvenChanceLabel,
          ),
          DetailRow(
            label: 'Harvest · paid',
            value:
                '${shortDate(estimate.harvestDate)} · '
                '${shortDate(estimate.paymentDate)}',
            last: true,
          ),
          const SizedBox(height: AlmanacDimens.sp2),
          // The reasons, in the backend's own numbers.
          Text(
            'Breaks even above R${estimate.breakEvenPricePerKg.trimmed}/kg. '
            'Costs ${estimate.productionCost.formatted}, sells for about '
            '${estimate.sales.formatted} before '
            '${estimate.commission.formatted} commission.',
            style: text.bodySmall,
          ),
          const SizedBox(height: AlmanacDimens.sp1),
          Text(
            weather?.label ?? 'Weather history not available yet.',
            style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _History extends StatelessWidget {
  final List<PlanVersion> versions;
  final DateTime now;

  const _History({required this.versions, required this.now});

  @override
  Widget build(BuildContext context) {
    if (versions.isEmpty) {
      return const EmptyState(
        icon: LucideIcons.history,
        headline: 'No plan saved yet',
        body:
            'Nothing is saved until you choose a plan and confirm it. Each '
            'plan you confirm is kept here as a version.',
      );
    }
    final text = Theme.of(context).textTheme;
    return AlmanacCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, v) in versions.indexed) ...[
            DetailRow(
              label: v.summary,
              value: switch (v.state) {
                PlanVersionState.saved => 'Version ${v.savedVersion}',
                PlanVersionState.waiting => 'Waiting to send',
                PlanVersionState.rejected => 'Not accepted',
              },
              last:
                  v.state != PlanVersionState.rejected &&
                  i == versions.length - 1,
            ),
            if (v.state == PlanVersionState.rejected)
              Text(v.rejectionMessage, style: text.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _ConfirmSheet extends StatelessWidget {
  final String summary;
  final Cents margin;
  final Cents requiredCash;

  const _ConfirmSheet({
    required this.summary,
    required this.margin,
    required this.requiredCash,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AlmanacDimens.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Save this plan?', style: text.titleLarge),
            const SizedBox(height: AlmanacDimens.sp3),
            Text(summary, style: text.bodyLarge),
            Text(
              'Expected profit ${margin.formatted} · needs '
              '${requiredCash.formatted}. These are estimates, not promises.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: AlmanacDimens.sp5),
            AppPrimaryButton(
              label: 'Save plan',
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: AlmanacDimens.sp2),
            AppSecondaryButton(
              label: 'Not yet',
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    );
  }
}

/// Edits the question. Returns null when cancelled; nothing is saved either
/// way — the answer is asked for again with the new inputs.
Future<PlanInputs?> showPlanInputsSheet(
  BuildContext context,
  PlanInputs inputs, {
  bool askGoal = false,
}) => showModalBottomSheet<PlanInputs>(
  context: context,
  isScrollControlled: true,
  builder: (context) => _InputsSheet(inputs: inputs, askGoal: askGoal),
);

class _InputsSheet extends StatefulWidget {
  final PlanInputs inputs;
  final bool askGoal;

  const _InputsSheet({required this.inputs, required this.askGoal});

  @override
  State<_InputsSheet> createState() => _InputsSheetState();
}

class _InputsSheetState extends State<_InputsSheet> {
  late final _budget = TextEditingController(
    text: '${widget.inputs.budget.value ~/ 100}',
  );
  late final _goal = TextEditingController(
    text: widget.inputs.goalMargin == null
        ? ''
        : '${widget.inputs.goalMargin!.value ~/ 100}',
  );
  late final _plantingCost = TextEditingController(
    text: '${widget.inputs.plantingCostPercent}',
  );
  late final _market = TextEditingController(
    text: _percent(widget.inputs.marketCommissionBps).replaceAll('%', ''),
  );
  late final _agent = TextEditingController(
    text: _percent(widget.inputs.agentCommissionBps).replaceAll('%', ''),
  );
  late final Map<String, TextEditingController> _shares = {
    for (final c in widget.inputs.crops)
      c.crop: TextEditingController(
        text: c.minimumPercent == 0 ? '' : '${c.minimumPercent}',
      ),
  };
  late final Map<String, TextEditingController> _promised = {
    for (final c in widget.inputs.crops)
      c.crop: TextEditingController(
        text: c.promisedKg == '0' ? '' : c.promisedKg,
      ),
  };
  late DateTime _planting = widget.inputs.plantingDate;
  late DateTime? _deadline = widget.inputs.cashDeadline;
  String? _error;

  @override
  void dispose() {
    for (final c in [
      _budget,
      _goal,
      _plantingCost,
      _market,
      _agent,
      ..._shares.values,
      ..._promised.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  int? _whole(String raw, {int max = 100}) {
    final value = int.tryParse(raw.trim().isEmpty ? '0' : raw.trim());
    return value == null || value < 0 || value > max ? null : value;
  }

  int? _bps(String raw) {
    final value = double.tryParse(raw.trim().isEmpty ? '0' : raw.trim());
    if (value == null || value < 0 || value > 50) return null;
    return (value * 100).round();
  }

  void _save() {
    final budget = BudgetInput.parse(_budget.text);
    if (!budget.isValid) return setState(() => _error = budget.error);
    Cents? goal;
    if (widget.askGoal || _goal.text.trim().isNotEmpty) {
      final parsed = BudgetInput.parse(_goal.text);
      if (!parsed.isValid) {
        return setState(() => _error = 'Profit goal: ${parsed.error}');
      }
      goal = parsed.value;
    }
    final plantingCost = _whole(_plantingCost.text);
    final market = _bps(_market.text);
    final agent = _bps(_agent.text);
    if (plantingCost == null || market == null || agent == null) {
      return setState(
        () => _error = 'Cost at planting is 0–100%; each commission is 0–50%.',
      );
    }
    final crops = <CropInput>[];
    for (final crop in widget.inputs.crops) {
      final share = _whole(_shares[crop.crop]!.text);
      final promised = _promised[crop.crop]!.text.trim();
      if (share == null ||
          (promised.isNotEmpty &&
              !RegExp(r'^\d{1,7}(\.\d{1,3})?$').hasMatch(promised))) {
        return setState(
          () => _error =
              '${cropName(crop.crop)}: share is 0–100%, promised kg a '
              'number with up to 3 decimals.',
        );
      }
      crops.add(
        crop.copyWith(
          minimumPercent: share,
          // Leading zeros dropped: the server echoes the decimal it parsed
          // ("0500" comes back as "500"), and the echo must match.
          promisedKg: promised.isEmpty
              ? '0'
              : promised.replaceFirst(RegExp(r'^0+(?=\d)'), ''),
        ),
      );
    }
    final next = widget.inputs.copyWith(
      budget: budget.value,
      plantingDate: _planting,
      cashDeadline: () => _deadline,
      goalMargin: () => goal,
      crops: crops,
      plantingCostPercent: plantingCost,
      marketCommissionBps: market,
      agentCommissionBps: agent,
    );
    final problem = next.problem;
    if (problem != null) return setState(() => _error = problem);
    Navigator.of(context).pop(next);
  }

  Future<DateTime?> _pick(DateTime initial) => showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(initial.year - 1),
    lastDate: DateTime(initial.year + 2),
  );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final digits = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,R ]'))];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(AlmanacDimens.gutter),
          children: [
            Text('What should the plan meet?', style: text.titleLarge),
            const SizedBox(height: AlmanacDimens.sp4),
            AppTextField(
              label: 'Budget (rand, 2025 prices)',
              controller: _budget,
              keyboardType: TextInputType.number,
              inputFormatters: digits,
            ),
            if (widget.askGoal || widget.inputs.goalMargin != null)
              AppTextField(
                label: 'Profit goal (rand)',
                controller: _goal,
                keyboardType: TextInputType.number,
                inputFormatters: digits,
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Planting date'),
              subtitle: Text(longDate(_planting)),
              onTap: () async {
                final picked = await _pick(_planting);
                if (picked != null) setState(() => _planting = picked);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Need the money by'),
              subtitle: Text(
                _deadline == null ? 'No deadline' : longDate(_deadline!),
              ),
              trailing: _deadline == null
                  ? null
                  : IconButton(
                      tooltip: 'Remove deadline',
                      icon: const Icon(LucideIcons.x),
                      onPressed: () => setState(() => _deadline = null),
                    ),
              onTap: () async {
                final picked = await _pick(_deadline ?? _planting);
                if (picked != null) setState(() => _deadline = picked);
              },
            ),
            const SizedBox(height: AlmanacDimens.sp3),
            Text('Per crop (leave blank for none)', style: text.labelLarge),
            for (final crop in widget.inputs.crops)
              Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      label: '${cropName(crop.crop)} min %',
                      controller: _shares[crop.crop]!,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: AlmanacDimens.sp3),
                  Expanded(
                    child: AppTextField(
                      label: 'Promised kg',
                      controller: _promised[crop.crop]!,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: AlmanacDimens.sp3),
            Text('Your assumptions', style: text.labelLarge),
            AppTextField(
              label: 'Share of cost paid at planting (%)',
              controller: _plantingCost,
              keyboardType: TextInputType.number,
            ),
            AppTextField(
              label: 'Market commission (%)',
              controller: _market,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            AppTextField(
              label: 'Agent commission (%)',
              controller: _agent,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AlmanacDimens.sp3),
              Text(
                _error!,
                key: const ValueKey('plan-inputs-error'),
                style: text.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: AlmanacDimens.sp4),
            AppPrimaryButton(label: 'Ask again', onPressed: _save),
          ],
        ),
      ),
    );
  }
}

String _percent(int bps) {
  final whole = bps ~/ 100;
  final rest = bps % 100;
  return rest == 0 ? '$whole%' : '$whole.${rest.toString().padLeft(2, '0')}%';
}

/// `green_beans` → `Green beans`.
String cropName(String crop) {
  final words = crop.replaceAll('_', ' ');
  return words[0].toUpperCase() + words.substring(1);
}
