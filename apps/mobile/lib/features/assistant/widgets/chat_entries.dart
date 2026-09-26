/// The conversation's lines: what the farmer asked, and each reply with its
/// tool results and how it ended.
///
/// Reply text is shown with a plain [Text] — never parsed as Markdown, HTML
/// or links. Whatever the model writes, it can only ever be words on screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../core/ui/buttons.dart';
import '../../../domain/assistant/assistant_models.dart';
import '../assistant_controller.dart';
import 'plan_card.dart';

class FarmerBubble extends StatelessWidget {
  final FarmerLine line;

  const FarmerBubble(this.line, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(
          left: AlmanacDimens.sp8,
          top: AlmanacDimens.sp3,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AlmanacDimens.sp4,
          vertical: AlmanacDimens.sp3,
        ),
        decoration: BoxDecoration(
          color: c.primaryContainer,
          borderRadius: BorderRadius.circular(AlmanacDimens.rLg),
        ),
        child: Semantics(
          label: 'You',
          child: Text(
            line.erased ? 'This message has expired.' : line.text,
            style: text.bodyMedium?.copyWith(
              color: c.onPrimaryContainer,
              fontStyle: line.erased ? FontStyle.italic : null,
            ),
          ),
        ),
      ),
    );
  }
}

class ReplyBubble extends ConsumerWidget {
  final ReplyEntry reply;

  const ReplyBubble(this.reply, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;
    final writing = reply.status == ReplyStatus.writing;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        key: Key('assistant-reply-${reply.turnId}'),
        margin: const EdgeInsets.only(
          right: AlmanacDimens.sp6,
          top: AlmanacDimens.sp3,
        ),
        padding: const EdgeInsets.all(AlmanacDimens.sp4),
        decoration: BoxDecoration(
          color: c.surfaceContainer,
          borderRadius: BorderRadius.circular(AlmanacDimens.rLg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (reply.erased)
              Text(
                'This reply has expired. Chats are kept for 30 days.',
                style: text.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
              )
            else if (reply.text.isNotEmpty)
              Text(reply.text, style: text.bodyMedium),
            for (final tool in reply.tools) _ToolLine(tool),
            const SizedBox(height: AlmanacDimens.sp2),
            _Ending(reply: reply, writing: writing),
          ],
        ),
      ),
    );
  }
}

class _ToolLine extends StatelessWidget {
  final ToolResult tool;

  const _ToolLine(this.tool);

  @override
  Widget build(BuildContext context) {
    final tool = this.tool;
    if (tool is PlanPreviewResult) {
      return PlanCard(decisionKey: tool.preview.snapshotHash);
    }
    final line = switch (tool) {
      PlanPreviewResult() => '',
      SectionsResult(:final sections) =>
        sections.isEmpty
            ? 'Looked for sections on your farm account and found none.'
            : 'Looked up your sections: '
                  '${sections.map((s) => s.name).join(', ')}.',
      OutlookResult() => 'Checked the crop outlook.',
      ToolErrorResult(:final code) => switch (code) {
        'outlook_unavailable' =>
          'The crop forecast is switched off on the server, so no plan '
              'could be priced.',
        'invalid_tool_arguments' =>
          'The planner could not read what it was asked, so it did not run.',
        'not_found' => 'That section is not on your farm account.',
        _ => 'A planning check did not finish.',
      },
      OtherToolResult() => 'Used a check this version of the app cannot show.',
    };
    final c = context.semantic;
    return Padding(
      padding: const EdgeInsets.only(top: AlmanacDimens.sp2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.sparkles, size: 16, color: c.onSurfaceVariant),
          const SizedBox(width: AlmanacDimens.sp2),
          Expanded(
            child: Text(
              line,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: c.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// How the reply stands: a live progress line while it is written, and a
/// visible ending — done, stopped, or not finished — once it is not.
class _Ending extends ConsumerWidget {
  final ReplyEntry reply;
  final bool writing;

  const _Ending({required this.reply, required this.writing});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;
    final controller = ref.read(assistantControllerProvider.notifier);
    final canRetry = ref.watch(
      assistantControllerProvider.select(
        (s) => s.stage == AssistantStage.ready && !s.writing,
      ),
    );

    final (IconData icon, String label, Color color) = switch (reply.status) {
      ReplyStatus.writing => (
        LucideIcons.loaderCircle,
        reply.text.isEmpty && reply.tools.isEmpty ? 'Thinking…' : 'Writing…',
        c.onSurfaceVariant,
      ),
      ReplyStatus.done => (LucideIcons.circleCheck, 'Done', c.statusOnTrack),
      ReplyStatus.stopped => (
        LucideIcons.square,
        _stoppedCopy(reply),
        c.onSurfaceVariant,
      ),
      ReplyStatus.failed || ReplyStatus.lost => (
        LucideIcons.triangleAlert,
        _unfinishedCopy(reply),
        c.onStatusNeedsAttentionContainer,
      ),
    };

    final offerRetry =
        (reply.status == ReplyStatus.failed ||
            reply.status == ReplyStatus.lost) &&
        reply.problem != AssistantProblem.consentRequired &&
        reply.problem != AssistantProblem.signedOut &&
        !reply.erased;

    return Semantics(
      liveRegion: true,
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            key: Key('assistant-status-${reply.turnId}'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (writing)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: c.onSurfaceVariant,
                  ),
                )
              else
                Icon(icon, size: 16, color: color),
              const SizedBox(width: AlmanacDimens.sp2),
              Expanded(
                child: Text(
                  label,
                  style: text.labelMedium?.copyWith(color: color),
                ),
              ),
            ],
          ),
          if (offerRetry) ...[
            const SizedBox(height: AlmanacDimens.sp2),
            AppTonalButton(
              key: Key('assistant-retry-${reply.turnId}'),
              label: 'Send again',
              icon: LucideIcons.refreshCw,
              onPressed: canRetry ? () => controller.retry(reply.turnId) : null,
            ),
          ],
        ],
      ),
    );
  }

  static String _stoppedCopy(ReplyEntry reply) => switch (reply.code) {
    'assistant_consent_withdrawn' || 'assistant_consent_required' =>
      'Stopped because you withdrew permission. Nothing was saved.',
    outsideServicesOffCode =>
      'Stopped because you turned outside services off. Nothing was saved.',
    _ => 'Stopped. Nothing was saved.',
  };

  static String _unfinishedCopy(ReplyEntry reply) {
    final ending = reply.status == ReplyStatus.lost
        ? 'The answer did not arrive.'
        : 'The assistant stopped before finishing.';
    final why = switch (reply.problem) {
      AssistantProblem.offline =>
        'There was no signal to the assistant, so it did not answer.',
      AssistantProblem.notAvailable =>
        '$ending The assistant is not taking questions right now.',
      AssistantProblem.tooMany =>
        'That is as many questions as the assistant takes for now. Wait a '
            'little and send again.',
      AssistantProblem.busy =>
        'Another answer is still being written for your account. Wait for '
            'it, then send again.',
      AssistantProblem.consentRequired =>
        '$ending It needs your permission first.',
      AssistantProblem.signedOut => '$ending You are logged out.',
      AssistantProblem.rejected =>
        '$ending It could not take that message as written.',
      _ => ending,
    };
    return '$why Nothing was saved.';
  }
}
