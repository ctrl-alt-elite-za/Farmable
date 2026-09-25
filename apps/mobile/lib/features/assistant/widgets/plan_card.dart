/// A plan preview from the assistant's planner tool, and the farmer's
/// decision about it.
///
/// Every figure here is a field the server's planner calculated; every label
/// is the app's own wording. The card is headed "not saved" until the server
/// returns a confirmation receipt, and the only control that saves is the
/// Confirm button inside the review step.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../core/ui/buttons.dart';
import '../../../domain/assistant/assistant_models.dart';
import '../../../domain/money.dart';
import '../assistant_controller.dart';
import 'choice_button.dart';

class PlanCard extends ConsumerWidget {
  /// The decision's key: the preview's original snapshot hash.
  final String decisionKey;

  const PlanCard({super.key, required this.decisionKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decision = ref.watch(
      assistantControllerProvider.select((s) => s.decisions[decisionKey]),
    );
    if (decision == null) return const SizedBox.shrink();
    final controller = ref.read(assistantControllerProvider.notifier);
    final c = context.semantic;
    final text = Theme.of(context).textTheme;
    final preview = decision.preview;
    final saved = decision.stage == DecisionStage.saved;

    return Container(
      key: Key('plan-card-$decisionKey'),
      margin: const EdgeInsets.only(top: AlmanacDimens.sp3),
      padding: const EdgeInsets.all(AlmanacDimens.sp4),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AlmanacDimens.rLg),
        border: Border.all(
          color: saved ? c.statusOnTrack : c.outlineVariant,
          width: saved ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                saved ? LucideIcons.circleCheck : LucideIcons.sprout,
                size: 20,
                color: saved ? c.statusOnTrack : c.primary,
              ),
              const SizedBox(width: AlmanacDimens.sp2),
              Expanded(
                child: Text(
                  saved ? 'Plan saved' : 'Plan preview — not saved',
                  style: text.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: AlmanacDimens.sp1),
          Text(
            [
              if (preview.areaM2.isNotEmpty)
                '${DecimalString(preview.areaM2).asArea} section',
              if (preview.plantingDate != null)
                'planting ${preview.plantingDate}',
              if (preview.budgetCents != null)
                'budget ${Cents(preview.budgetCents!).formatted}',
            ].join(' · '),
            style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
          ),
          if (preview.warning != null) ...[
            const SizedBox(height: AlmanacDimens.sp2),
            _Caution(preview.warning!),
          ],
          const SizedBox(height: AlmanacDimens.sp1),
          Text(
            'Amounts are in 2025 rand'
            '${preview.forecastAsOf == null ? '' : ', from the forecast of '
                      '${preview.forecastAsOf}'}'
            '. Estimates, not promises.',
            style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
          ),
          const SizedBox(height: AlmanacDimens.sp3),
          if (!preview.feasible || preview.candidates.isEmpty)
            _NoPlanFits(preview.changeNeeded)
          else ...[
            Text('Choose one', style: text.labelLarge),
            const SizedBox(height: AlmanacDimens.sp2),
            for (final (i, candidate) in preview.candidates.indexed) ...[
              ChoiceButton(
                key: Key('plan-option-$decisionKey-$i'),
                label: candidate.summary,
                detail:
                    'Margin ${Cents(candidate.marginCents).formatted} · '
                    'needs ${Cents(candidate.requiredCashCents).formatted} '
                    'starting cash',
                semanticLabel:
                    'Plan option ${i + 1} of ${preview.candidates.length}: '
                    '${candidate.summary}. Estimated margin '
                    '${Cents(candidate.marginCents).formatted}. Needs '
                    '${Cents(candidate.requiredCashCents).formatted} '
                    'starting cash.',
                selected: candidate.id == decision.candidateId,
                onPressed: _canChoose(decision.stage)
                    ? () =>
                          controller.selectCandidate(decisionKey, candidate.id)
                    : null,
              ),
              const SizedBox(height: AlmanacDimens.sp2),
            ],
          ],
          _Footer(decisionKey: decisionKey, decision: decision),
        ],
      ),
    );
  }

  static bool _canChoose(DecisionStage stage) =>
      stage == DecisionStage.choosing ||
      stage == DecisionStage.reviewing ||
      stage == DecisionStage.changed;
}

class _Footer extends ConsumerWidget {
  final String decisionKey;
  final PlanDecision decision;

  const _Footer({required this.decisionKey, required this.decision});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(assistantControllerProvider.notifier);
    final c = context.semantic;
    final text = Theme.of(context).textTheme;
    final candidate = decision.candidate;

    switch (decision.stage) {
      case DecisionStage.checking:
        return Row(
          key: const Key('plan-checking'),
          children: [
            const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: AlmanacDimens.sp2),
            Expanded(
              child: Text(
                'Checking with your farm account whether this plan was '
                'already saved…',
                style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
              ),
            ),
          ],
        );

      case DecisionStage.choosing:
        if (!decision.preview.feasible || decision.preview.candidates.isEmpty) {
          return const SizedBox.shrink();
        }
        return AppPrimaryButton(
          key: const Key('plan-review'),
          label: candidate == null ? 'Choose a plan first' : 'Review this plan',
          icon: LucideIcons.check,
          onPressed: candidate == null
              ? null
              : () => controller.review(decisionKey),
        );

      case DecisionStage.reviewing || DecisionStage.saving:
        final saving = decision.stage == DecisionStage.saving;
        return Container(
          key: const Key('plan-confirm-step'),
          padding: const EdgeInsets.all(AlmanacDimens.sp4),
          decoration: BoxDecoration(
            color: c.surfaceContainer,
            borderRadius: BorderRadius.circular(AlmanacDimens.rMd),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Save this plan to your farm?',
                  style: text.titleSmall,
                ),
              ),
              const SizedBox(height: AlmanacDimens.sp2),
              Text(
                '${candidate?.summary ?? ''}. Estimated margin '
                '${Cents(candidate?.marginCents ?? 0).formatted}, needing '
                '${Cents(candidate?.requiredCashCents ?? 0).formatted} '
                'starting cash.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: AlmanacDimens.sp2),
              Text(
                'This saves it as an approved plan on your farm account. It '
                'does not mark anything as planted, and nothing is saved '
                'until you tap Confirm.',
                style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
              ),
              if (decision.problem != null) ...[
                const SizedBox(height: AlmanacDimens.sp2),
                _Caution(_confirmProblem(decision.problem!)),
              ],
              const SizedBox(height: AlmanacDimens.sp3),
              AppPrimaryButton(
                key: const Key('plan-confirm'),
                label: 'Confirm and save',
                busyLabel: saving ? 'Saving…' : null,
                icon: LucideIcons.check,
                onPressed: saving
                    ? null
                    : () => controller.confirm(decisionKey),
              ),
              const SizedBox(height: AlmanacDimens.sp2),
              AppTonalButton(
                key: const Key('plan-back'),
                label: 'Back',
                icon: LucideIcons.undo2,
                onPressed: saving
                    ? null
                    : () => controller.cancelReview(decisionKey),
              ),
            ],
          ),
        );

      case DecisionStage.saved:
        final saved = decision.saved!;
        return Semantics(
          liveRegion: true,
          child: Column(
            key: const Key('plan-saved'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Saved to your farm account as version ${saved.version}.',
                style: text.bodyMedium?.copyWith(color: c.statusOnTrack),
              ),
              if (decision.revision?.origin == 'planner_confirmation')
                Text(
                  'Recorded in the plan history as your confirmation.',
                  style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
                ),
              Text(
                'Plans on this phone are kept separately for now, so it will '
                'not show in this phone\'s planner yet.',
                style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
              ),
            ],
          ),
        );

      case DecisionStage.stale || DecisionStage.refreshing:
        final refreshing = decision.stage == DecisionStage.refreshing;
        return Column(
          key: const Key('plan-stale'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Caution(
              decision.problem == null ||
                      decision.problem == AssistantProblem.planStale
                  ? 'The numbers changed since this preview, so it was not '
                        'saved. Get fresh numbers and choose again.'
                  : _confirmProblem(decision.problem!),
            ),
            const SizedBox(height: AlmanacDimens.sp3),
            AppSecondaryButton(
              key: const Key('plan-refresh'),
              label: refreshing
                  ? 'Getting fresh numbers…'
                  : 'Get fresh numbers',
              icon: LucideIcons.refreshCw,
              onPressed: refreshing
                  ? null
                  : () => controller.refresh(decisionKey),
            ),
          ],
        );

      case DecisionStage.changed:
        return _Caution(
          'This plan was changed somewhere else, so this one was not saved. '
          'Choose again to review it.',
        );
    }
  }

  static String _confirmProblem(AssistantProblem problem) => switch (problem) {
    // No reply is not "not saved": it may have arrived and the answer been
    // lost. Confirm again asks the server first, so it never saves twice.
    AssistantProblem.offline =>
      'This may not have reached the server, so it may not be saved yet. '
          'Tap Confirm again when you have signal — it checks first, and '
          'never saves the plan twice.',
    AssistantProblem.signedOut =>
      'You are logged out, so nothing was saved. Log in and try once more.',
    AssistantProblem.outlookNotAvailable =>
      'The crop forecast is switched off on the server, so nothing was '
          'saved.',
    AssistantProblem.planStale =>
      'The numbers changed since this preview, so it was not saved.',
    _ => 'The server did not save it. Nothing has changed on your farm.',
  };
}

class _NoPlanFits extends StatelessWidget {
  final Map<String, Object?>? changeNeeded;

  const _NoPlanFits(this.changeNeeded);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final change = changeNeeded;
    final minimum = change?['minimum_budget_cents'];
    final maxMargin = change?['maximum_margin_within_budget_cents'];
    final advice = switch (change?['code']) {
      'budget_too_low' when minimum is int =>
        'It needs at least ${Cents(minimum).formatted} starting cash, or '
            'fewer conditions.',
      'goal_unreachable' when maxMargin is int =>
        'The most this budget can aim for is about '
            '${Cents(maxMargin).formatted} margin.',
      'constraints_infeasible' =>
        'Loosen the minimum shares, the promised quantity, or the cash '
            'deadline.',
      _ => 'Change the budget or the conditions and ask again.',
    };
    return Column(
      key: const Key('plan-none-fits'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('No plan fits these conditions', style: text.titleSmall),
        const SizedBox(height: AlmanacDimens.sp1),
        Text(advice, style: text.bodyMedium),
        const SizedBox(height: AlmanacDimens.sp1),
        Text('Nothing was saved.', style: text.bodySmall),
      ],
    );
  }
}

class _Caution extends StatelessWidget {
  final String message;

  const _Caution(this.message);

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    return Container(
      padding: const EdgeInsets.all(AlmanacDimens.sp3),
      decoration: BoxDecoration(
        color: c.statusNeedsAttentionContainer,
        borderRadius: BorderRadius.circular(AlmanacDimens.rSm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            LucideIcons.triangleAlert,
            size: 18,
            color: c.onStatusNeedsAttentionContainer,
          ),
          const SizedBox(width: AlmanacDimens.sp2),
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
