/// The assistant sheet: type a question, watch the answer arrive, choose from
/// what the planner offers, and confirm before anything is saved.
///
/// Voice is not part of this (#24). What is here is the typed conversation
/// against the backend's assistant contract (`docs/assistant-backend.md`).
///
/// ## Words for states that are not faults
///
/// Being logged out, having no signal, or talking to a server where the
/// assistant is switched off are ordinary days. The sheet says which one it
/// is, plainly, and never calls it an "error" or "failed" — the farmer cannot
/// tell "broken" from "not now" by the word alone, and would only learn that
/// the app breaks. Each of those states keeps the message box (the draft
/// stays) and offers the planner on this phone, which needs neither.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/providers.dart';
import '../../app/theme/app_motion.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.g.dart';
import '../../core/ui/buttons.dart';
import '../../domain/assistant/assistant_models.dart';
import 'assistant_controller.dart';
import 'widgets/chat_entries.dart';
import 'widgets/choice_button.dart';

Future<void> showAssistantSheet(BuildContext context) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  barrierColor: context.semantic.backdrop,
  transitionAnimationController: null,
  builder: (context) => const AssistantSheet(),
);

class AssistantSheet extends ConsumerStatefulWidget {
  const AssistantSheet({super.key});

  @override
  ConsumerState<AssistantSheet> createState() => _AssistantSheetState();
}

class _AssistantSheetState extends ConsumerState<AssistantSheet> {
  final _draft = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(assistantControllerProvider.notifier).open();
    });
  }

  @override
  void dispose() {
    _draft.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final message = _draft.text;
    if (message.trim().isEmpty) return;
    _draft.clear();
    ref.read(assistantControllerProvider.notifier).send(message);
  }

  /// Closes the sheet, then goes to [location]. The router is read first:
  /// the sheet's context is gone once it has closed.
  void _leaveFor(String location) {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.go(location);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final state = ref.watch(assistantControllerProvider);
    AppMotion.of(context);

    // Keep the newest line in view as the answer grows. Only new words move
    // the view: choosing on an older plan card must not scroll it away.
    ref.listen(assistantControllerProvider, (previous, next) {
      if (previous?.entries != next.entries) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.jumpTo(_scroll.position.maxScrollExtent);
          }
        });
      }
    });

    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AlmanacDimens.r2xl),
        ),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(
            // The dashboard stays visible above it, which keeps the assistant
            // an overlay on the farm rather than a place the farmer is taken.
            height:
                (MediaQuery.sizeOf(context).height - keyboard) *
                (keyboard > 0 ? 0.95 : 0.85),
            width: double.infinity,
            decoration: BoxDecoration(
              color: c.glassSurface,
              border: Border(top: BorderSide(color: c.glassHairlineStrong)),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AlmanacDimens.r2xl),
              ),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AlmanacDimens.gutter,
            ),
            child: Column(
              children: [
                const SizedBox(height: AlmanacDimens.sp2),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                _Header(state: state),
                Expanded(child: _body(state)),
                if (state.cropQuestion != null)
                  _CropQuestionPanel(
                    onEdit: () {
                      final pending = ref
                          .read(assistantControllerProvider.notifier)
                          .editPending();
                      if (pending != null) _draft.text = pending;
                    },
                  )
                else if (state.stage != AssistantStage.starting)
                  _Composer(
                    draft: _draft,
                    state: state,
                    onSend: _send,
                    onStop: () =>
                        ref.read(assistantControllerProvider.notifier).stop(),
                  ),
                const SizedBox(height: AlmanacDimens.sp4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(AssistantChatState state) {
    final controller = ref.read(assistantControllerProvider.notifier);
    final planOnPhone = _PlanOnThisPhone(onOpen: _leaveFor);

    switch (state.stage) {
      case AssistantStage.starting:
        return const _Starting();

      case AssistantStage.ready:
        return _Conversation(state: state, scroll: _scroll);

      case AssistantStage.needsConsent:
        return _ConsentPanel(state: state, footer: planOnPhone);

      case AssistantStage.chooseFarm:
        return _Panel(
          icon: LucideIcons.mapPin,
          title: 'Which farm is this about?',
          body:
              'Your account has more than one farm. The assistant talks '
              'about one at a time.',
          actions: [
            for (final farm in state.farms)
              Padding(
                padding: const EdgeInsets.only(bottom: AlmanacDimens.sp2),
                child: ChoiceButton(
                  label: farm.name.isEmpty ? 'Unnamed farm' : farm.name,
                  onPressed: () => controller.chooseFarm(farm),
                ),
              ),
          ],
        );

      case AssistantStage.declined:
        return _Panel(
          key: const Key('assistant-declined'),
          icon: LucideIcons.lock,
          title: state.withdrawn
              ? 'You stopped sharing with the assistant'
              : 'Nothing is sent to the assistant',
          body: state.withdrawn
              ? 'Nothing more goes to it from this conversation. What was '
                    'already sent cannot be called back. Planning on this '
                    'phone works as before.'
              : 'You said no, so nothing you type here leaves this phone. '
                    'Planning on this phone works as before.',
          actions: [
            AppSecondaryButton(
              key: const Key('assistant-ask-again'),
              label: 'Ask me again',
              icon: LucideIcons.messageCircle,
              onPressed: controller.askAgain,
            ),
          ],
          footer: planOnPhone,
        );

      case AssistantStage.notConnected:
        return _Panel(
          key: const Key('assistant-not-connected'),
          icon: LucideIcons.wifiOff,
          title: 'The assistant is not connected in this copy of Almanac',
          body:
              'This build runs without the Farmable server, so there is '
              'nothing to ask. Your farm and the planner on this phone work '
              'as normal.',
          footer: planOnPhone,
        );

      case AssistantStage.signedOut:
        return _Panel(
          key: const Key('assistant-signed-out'),
          icon: LucideIcons.logIn,
          title: 'Log in to ask the assistant',
          body:
              'The assistant answers from your farm account, so it needs you '
              'logged in. Everything on this phone keeps working without it.',
          actions: [
            AppPrimaryButton(
              label: 'Log in',
              icon: LucideIcons.logIn,
              onPressed: () => _leaveFor('/auth/login'),
            ),
          ],
          footer: planOnPhone,
        );

      case AssistantStage.offline:
        return _Panel(
          key: const Key('assistant-offline'),
          icon: LucideIcons.wifiOff,
          title: 'The assistant cannot be reached right now',
          body:
              'There is no signal to it at the moment. Your message stays in '
              'the box below, and the planner on this phone works without '
              'signal.',
          actions: [
            AppSecondaryButton(
              key: const Key('assistant-check-again'),
              label: 'Check again',
              icon: LucideIcons.refreshCw,
              onPressed: controller.retryOpen,
            ),
          ],
          footer: planOnPhone,
        );

      case AssistantStage.notAvailable:
        return _Panel(
          key: const Key('assistant-not-available'),
          icon: LucideIcons.messageCircle,
          title: 'The assistant is switched off for now',
          body:
              'The Farmable server answered, but its assistant is not taking '
              'questions at the moment. Your message stays in the box below, '
              'and the planner on this phone works as normal.',
          actions: [
            AppSecondaryButton(
              key: const Key('assistant-check-again'),
              label: 'Check again',
              icon: LucideIcons.refreshCw,
              onPressed: controller.retryOpen,
            ),
          ],
          footer: planOnPhone,
        );

      case AssistantStage.outsideServicesOff:
        return _Panel(
          key: const Key('assistant-outside-services-off'),
          icon: LucideIcons.lock,
          title: 'Outside services are off',
          body:
              'The assistant sends your questions to Google Gemini to answer '
              'them. That only happens if you allow outside services in your '
              'privacy choices.',
          actions: [
            AppSecondaryButton(
              label: 'Open privacy choices',
              icon: LucideIcons.lock,
              onPressed: () => _leaveFor('/profile/privacy'),
            ),
          ],
          footer: planOnPhone,
        );

      case AssistantStage.noFarm:
        return _Panel(
          key: const Key('assistant-no-farm'),
          icon: LucideIcons.mapPin,
          title: 'Your account has no farm on the server yet',
          body:
              'The assistant plans for the farm on your account, and this '
              'account does not have one there yet. The planner on this phone '
              'works as normal.',
          footer: planOnPhone,
        );
    }
  }
}

class _Header extends ConsumerWidget {
  final AssistantChatState state;

  const _Header({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final c = context.semantic;
    final controller = ref.read(assistantControllerProvider.notifier);
    final canWithdraw =
        state.stage == AssistantStage.ready &&
        (state.consent?.granted ?? false);

    return Padding(
      padding: const EdgeInsets.only(top: AlmanacDimens.sp3),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text('Ask Almanac', style: text.titleLarge),
                ),
                Text(
                  'Type a question about your farm.',
                  style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (canWithdraw)
            TextButton.icon(
              key: const Key('assistant-withdraw'),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, AlmanacDimens.touchMin),
              ),
              onPressed: state.consentBusy ? null : controller.withdraw,
              icon: const Icon(LucideIcons.shieldOff, size: 18),
              label: const Text('Stop sharing'),
            ),
          IconOnlyButton(
            icon: LucideIcons.x,
            semanticLabel: 'Close the assistant',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _Starting extends StatelessWidget {
  const _Starting();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Semantics(
        liveRegion: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(height: AlmanacDimens.sp3),
            Text('Getting the assistant ready…', style: text.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _Conversation extends StatelessWidget {
  final AssistantChatState state;
  final ScrollController scroll;

  const _Conversation({required this.state, required this.scroll});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.semantic;
    if (state.entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AlmanacDimens.sp4),
          child: Text(
            'Ask something like “I want to plant cabbages in the north '
            'plot”. Any plan it suggests is only a preview until you tap '
            'Confirm.',
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: c.onSurfaceVariant),
          ),
        ),
      );
    }
    return ListView(
      key: const Key('assistant-conversation'),
      controller: scroll,
      padding: const EdgeInsets.only(bottom: AlmanacDimens.sp3),
      children: [
        for (final entry in state.entries)
          switch (entry) {
            FarmerLine() => FarmerBubble(entry),
            ReplyEntry() => ReplyBubble(entry),
          },
      ],
    );
  }
}

class _ConsentPanel extends ConsumerWidget {
  final AssistantChatState state;
  final Widget footer;

  const _ConsentPanel({required this.state, required this.footer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final c = context.semantic;
    final controller = ref.read(assistantControllerProvider.notifier);
    final consent = state.consent;

    return ListView(
      key: const Key('assistant-consent'),
      padding: const EdgeInsets.only(top: AlmanacDimens.sp4),
      children: [
        Semantics(
          header: true,
          child: Text('Before you ask', style: text.titleMedium),
        ),
        const SizedBox(height: AlmanacDimens.sp2),
        Text(
          'The assistant needs your permission for this conversation. '
          'Nothing is sent until you tap Allow.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: AlmanacDimens.sp3),
        Container(
          padding: const EdgeInsets.all(AlmanacDimens.sp4),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(AlmanacDimens.rMd),
            border: Border.all(color: c.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The server's own notice, shown exactly as sent: it is what
              // the farmer is agreeing to, and what Allow sends back.
              Text(consent?.notice ?? '', style: text.bodySmall),
              const SizedBox(height: AlmanacDimens.sp2),
              Text(
                'Sent to: Google Gemini'
                '${(consent?.model ?? '').isEmpty ? '' : ' (${consent!.model})'}',
                style: text.labelMedium?.copyWith(color: c.onSurfaceVariant),
              ),
            ],
          ),
        ),
        if (state.consentProblem != null) ...[
          const SizedBox(height: AlmanacDimens.sp3),
          Text(
            state.consentProblem == AssistantProblem.consentRequired
                ? 'The notice has changed since it was shown. Read the one '
                      'above, then choose again.'
                : 'Your answer did not reach the server. Nothing was sent to '
                      'the assistant.',
            style: text.bodySmall?.copyWith(
              color: c.onStatusNeedsAttentionContainer,
            ),
          ),
        ],
        const SizedBox(height: AlmanacDimens.sp4),
        AppPrimaryButton(
          key: const Key('assistant-allow'),
          label: 'Allow',
          busyLabel: state.consentBusy ? 'Saving your answer…' : null,
          icon: LucideIcons.check,
          onPressed: state.consentBusy || consent == null
              ? null
              : controller.allow,
        ),
        const SizedBox(height: AlmanacDimens.sp2),
        AppTonalButton(
          key: const Key('assistant-decline'),
          label: 'Not now',
          icon: LucideIcons.x,
          onPressed: state.consentBusy ? null : controller.decline,
        ),
        const SizedBox(height: AlmanacDimens.sp4),
        footer,
      ],
    );
  }
}

/// A state that is not a conversation: an icon, a plain sentence or two, what
/// the farmer can do, and the planner on this phone underneath.
class _Panel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final List<Widget> actions;
  final Widget? footer;

  const _Panel({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.actions = const [],
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.only(top: AlmanacDimens.sp5),
      children: [
        Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: c.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: c.onPrimaryContainer, size: 24),
          ),
        ),
        const SizedBox(height: AlmanacDimens.sp4),
        Semantics(
          liveRegion: true,
          child: Text(
            title,
            style: text.titleMedium,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: AlmanacDimens.sp2),
        Text(
          body,
          style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AlmanacDimens.sp4),
        ...actions,
        if (footer != null) ...[
          const SizedBox(height: AlmanacDimens.sp4),
          footer!,
        ],
      ],
    );
  }
}

/// The planner that runs on the phone, one button per section on the phone.
/// Reads the farm on disk; needs no login, no signal and no assistant.
class _PlanOnThisPhone extends ConsumerWidget {
  final void Function(String location) onOpen;

  const _PlanOnThisPhone({required this.onOpen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final sections = ref.watch(farmProvider).value?.sections ?? const [];
    if (sections.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const Key('assistant-plan-on-phone'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Plan on this phone instead', style: text.labelLarge),
        const SizedBox(height: AlmanacDimens.sp2),
        for (final summary in sections)
          Padding(
            padding: const EdgeInsets.only(bottom: AlmanacDimens.sp2),
            child: ChoiceButton(
              label: 'What should I plant in ${summary.section.name}?',
              onPressed: () => onOpen('/farm/zone/${summary.section.id}/plant'),
            ),
          ),
      ],
    );
  }
}

class _CropQuestionPanel extends ConsumerWidget {
  final VoidCallback onEdit;

  const _CropQuestionPanel({required this.onEdit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final question = ref.watch(
      assistantControllerProvider.select((s) => s.cropQuestion),
    );
    if (question == null) return const SizedBox.shrink();
    final controller = ref.read(assistantControllerProvider.notifier);
    final c = context.semantic;

    return Container(
      key: const Key('assistant-crop-question'),
      margin: const EdgeInsets.only(top: AlmanacDimens.sp2),
      padding: const EdgeInsets.all(AlmanacDimens.sp4),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AlmanacDimens.rLg),
        border: Border.all(color: c.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              question.options.length == 1
                  ? 'Did you mean ${question.options.single.label.toLowerCase()} '
                        'for “${question.word}”?'
                  : 'Which crop did you mean by “${question.word}”?',
              style: text.titleSmall,
            ),
          ),
          const SizedBox(height: AlmanacDimens.sp3),
          for (final crop in question.options)
            Padding(
              padding: const EdgeInsets.only(bottom: AlmanacDimens.sp2),
              child: ChoiceButton(
                key: Key('crop-choice-${crop.wire}'),
                label: crop.label,
                onPressed: () => controller.answerCrop(crop),
              ),
            ),
          ChoiceButton(
            key: const Key('crop-choice-as-typed'),
            label: 'Keep “${question.word}” as I typed it',
            onPressed: () => controller.answerCrop(null),
          ),
          const SizedBox(height: AlmanacDimens.sp2),
          AppTonalButton(
            label: 'Edit my message',
            icon: LucideIcons.pencil,
            onPressed: onEdit,
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController draft;
  final AssistantChatState state;
  final VoidCallback onSend;
  final VoidCallback onStop;

  const _Composer({
    required this.draft,
    required this.state,
    required this.onSend,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;
    final ready = state.stage == AssistantStage.ready;
    final writing = state.writing;

    return Padding(
      padding: const EdgeInsets.only(top: AlmanacDimens.sp2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!ready)
            Padding(
              padding: const EdgeInsets.only(bottom: AlmanacDimens.sp1),
              child: Text(
                'You can keep typing. It is sent once the assistant can '
                'take it.',
                style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  key: const Key('assistant-input'),
                  controller: draft,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 4000,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) {
                    if (ready && !writing) onSend();
                  },
                  decoration: InputDecoration(
                    hintText: 'Ask about your farm',
                    counterText: '',
                    filled: true,
                    fillColor: c.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AlmanacDimens.rLg),
                      borderSide: BorderSide(color: c.outlineVariant),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AlmanacDimens.sp2),
              if (writing)
                AppTonalButton(
                  key: const Key('assistant-stop'),
                  label: 'Stop',
                  icon: LucideIcons.square,
                  block: false,
                  onPressed: onStop,
                )
              else
                AppPrimaryButton(
                  key: const Key('assistant-send'),
                  label: 'Send',
                  icon: LucideIcons.send,
                  block: false,
                  onPressed: ready ? onSend : null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
