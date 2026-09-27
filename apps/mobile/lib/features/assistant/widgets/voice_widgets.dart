/// The voice parts of the assistant sheet: the mic button, the strip above
/// the typing box that says what voice is doing, and the spoken exchanges.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../core/ui/buttons.dart';
import '../../../domain/assistant/voice.dart';
import '../assistant_controller.dart';
import '../voice_controller.dart';

/// Silences the assistant mid-answer and goes straight back to listening.
/// The haptic tick is part of the answer: the farmer feels it land.
void interruptVoice(WidgetRef ref) {
  unawaited(HapticFeedback.selectionClick());
  unawaited(ref.read(voiceControllerProvider.notifier).interrupt());
}

/// Mic; Stop while a session is open; and, while the assistant is talking,
/// the tap that cuts it off.
class MicButton extends ConsumerWidget {
  final bool enabled;

  const MicButton({super.key, required this.enabled});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voice = ref.watch(voiceControllerProvider);
    final controller = ref.read(voiceControllerProvider.notifier);
    final c = context.semantic;
    final on = voice.active || voice.phase == VoicePhase.consent;
    if (voice.speaking) {
      return Semantics(
        identifier: 'voice-interrupt',
        button: true,
        label: 'Stop the answer and listen',
        excludeSemantics: true,
        child: IconButton.filled(
          key: const Key('voice-interrupt'),
          constraints: const BoxConstraints(
            minWidth: AlmanacDimens.touchMin,
            minHeight: AlmanacDimens.touchMin,
          ),
          onPressed: () => interruptVoice(ref),
          icon: const Icon(LucideIcons.hand, size: 20),
        ),
      );
    }
    return Semantics(
      identifier: on ? 'voice-stop' : 'voice-start',
      button: true,
      label: on ? 'Stop talking to the assistant' : 'Talk to the assistant',
      excludeSemantics: true,
      child: IconButton.filledTonal(
        key: Key(on ? 'voice-stop' : 'voice-start'),
        constraints: const BoxConstraints(
          minWidth: AlmanacDimens.touchMin,
          minHeight: AlmanacDimens.touchMin,
        ),
        style: IconButton.styleFrom(
          backgroundColor: on ? c.primary : null,
          foregroundColor: on ? c.onPrimary : null,
        ),
        onPressed: on
            ? controller.stop
            : enabled
            ? controller.start
            : null,
        icon: Icon(on ? LucideIcons.square : LucideIcons.mic, size: 20),
      ),
    );
  }
}

/// What voice is doing, above the typing box. Nothing when voice is off and
/// has nothing to say.
class VoiceStrip extends ConsumerWidget {
  const VoiceStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voice = ref.watch(voiceControllerProvider);
    final controller = ref.read(voiceControllerProvider.notifier);
    final text = Theme.of(context).textTheme;
    final c = context.semantic;

    Widget card(List<Widget> children, {Key? key}) => Container(
      key: key,
      margin: const EdgeInsets.only(bottom: AlmanacDimens.sp2),
      padding: const EdgeInsets.all(AlmanacDimens.sp3),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AlmanacDimens.rMd),
        border: Border.all(color: c.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );

    switch (voice.phase) {
      case VoicePhase.consent:
        final consent = voice.consent;
        return card(key: const Key('voice-consent'), [
          Semantics(
            header: true,
            child: Text('Before you talk', style: text.titleSmall),
          ),
          const SizedBox(height: AlmanacDimens.sp2),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 160),
            child: SingleChildScrollView(
              // The server's own notice, exactly as sent: it is what the
              // farmer agrees to, and what Allow sends back.
              child: Text(consent?.notice ?? '', style: text.bodySmall),
            ),
          ),
          const SizedBox(height: AlmanacDimens.sp2),
          Text(
            'Sent to: Google Gemini Live'
            '${(consent?.model ?? '').isEmpty ? '' : ' (${consent!.model})'}',
            style: text.labelMedium?.copyWith(color: c.onSurfaceVariant),
          ),
          const SizedBox(height: AlmanacDimens.sp3),
          Row(
            children: [
              Expanded(
                child: AppTonalButton(
                  key: const Key('voice-decline'),
                  label: 'Not now',
                  icon: LucideIcons.x,
                  onPressed: voice.consentBusy ? null : controller.decline,
                ),
              ),
              const SizedBox(width: AlmanacDimens.sp2),
              Expanded(
                child: AppPrimaryButton(
                  key: const Key('voice-allow'),
                  label: 'Allow',
                  busyLabel: voice.consentBusy ? 'Saving…' : null,
                  icon: LucideIcons.check,
                  onPressed: voice.consentBusy ? null : controller.allow,
                ),
              ),
            ],
          ),
        ]);

      case VoicePhase.connecting:
        return card(key: const Key('voice-connecting'), [
          _Status(
            icon: LucideIcons.mic,
            words: 'Getting the microphone ready…',
            busy: true,
          ),
        ]);

      case VoicePhase.listening:
        return card(key: const Key('voice-listening'), [
          _Status(
            icon: voice.speaking ? LucideIcons.volume2 : LucideIcons.mic,
            words: voice.speaking
                ? 'Answering — tap or talk to interrupt'
                : 'Listening',
          ),
          if (voice.speaking) ...[
            const SizedBox(height: AlmanacDimens.sp2),
            AppPrimaryButton(
              key: const Key('voice-interrupt-strip'),
              label: 'Stop the answer',
              icon: LucideIcons.hand,
              onPressed: () => interruptVoice(ref),
            ),
          ],
          const SizedBox(height: AlmanacDimens.sp1),
          _LanguageChoice(language: voice.language),
        ]);

      case VoicePhase.reconnecting:
        return card(key: const Key('voice-reconnecting'), [
          const _Status(
            icon: LucideIcons.wifiOff,
            words: 'The connection dropped. Trying again…',
            busy: true,
          ),
        ]);

      case VoicePhase.off:
        final ending = voice.ending;
        if (ending == null) return const SizedBox.shrink();
        return card(key: const Key('voice-ended'), [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.keyboard, size: 18, color: c.onSurfaceVariant),
              const SizedBox(width: AlmanacDimens.sp2),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    '${_endingWords(ending)} You can type instead — anything '
                    'you said that was not answered is in the box below.',
                    style: text.bodySmall,
                  ),
                ),
              ),
              IconOnlyButton(
                icon: LucideIcons.x,
                semanticLabel: 'Dismiss',
                onPressed: controller.dismissEnding,
              ),
            ],
          ),
          if (ending == VoiceEnding.micSettingsOnly)
            AppSecondaryButton(
              key: const Key('voice-open-settings'),
              label: 'Open phone settings',
              icon: LucideIcons.settings,
              onPressed: controller.openMicSettings,
            ),
        ]);
    }
  }
}

String _endingWords(VoiceEnding ending) => switch (ending) {
  VoiceEnding.micRefused =>
    'Talking needs the microphone, and it was not allowed.',
  VoiceEnding.micSettingsOnly =>
    'Talking needs the microphone. It can only be turned on in your phone '
        'settings now.',
  VoiceEnding.notAvailable => 'Talking to the assistant is off for now.',
  VoiceEnding.tooMany => 'That was a lot of talking in a short time.',
  VoiceEnding.busy => 'Voice is already open for your account somewhere else.',
  VoiceEnding.offline => 'There is no signal to the assistant right now.',
  VoiceEnding.signedOut => 'Voice stopped because you logged out.',
  VoiceEnding.connectionLost => 'The voice connection was lost.',
  VoiceEnding.expired => 'Voice sessions last ten minutes, and this one ended.',
  VoiceEnding.endedByServer => 'The Farmable server ended the voice session.',
};

class _Status extends StatelessWidget {
  final IconData icon;
  final String words;
  final bool busy;

  const _Status({required this.icon, required this.words, this.busy = false});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.semantic;
    return Row(
      children: [
        busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon, size: 18, color: c.primary),
        const SizedBox(width: AlmanacDimens.sp2),
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: Text(words, style: text.labelLarge),
          ),
        ),
      ],
    );
  }
}

class _LanguageChoice extends ConsumerWidget {
  final ReplyLanguage language;

  const _LanguageChoice({required this.language});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final c = context.semantic;
    return PopupMenuButton<ReplyLanguage>(
      key: const Key('voice-language'),
      tooltip: 'Reply language',
      initialValue: language,
      onSelected: ref.read(voiceControllerProvider.notifier).setLanguage,
      itemBuilder: (_) => [
        for (final l in ReplyLanguage.values)
          PopupMenuItem(
            key: Key('voice-language-${l.name}'),
            value: l,
            child: Text(
              l.speaks ? '${l.label} — spoken' : '${l.label} — text only',
            ),
          ),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AlmanacDimens.touchMin),
        child: Row(
          children: [
            Icon(
              language.speaks ? LucideIcons.volume2 : LucideIcons.volumeOff,
              size: 16,
              color: c.onSurfaceVariant,
            ),
            const SizedBox(width: AlmanacDimens.sp2),
            Expanded(
              child: Text(
                language.speaks
                    ? 'Replies in ${language.label}, spoken aloud'
                    : 'Replies in ${language.label}, as text only — no '
                          'spoken voice for it yet',
                key: const Key('voice-language-label'),
                style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
              ),
            ),
            Icon(LucideIcons.chevronDown, size: 16, color: c.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// The spoken exchanges, as bubbles after the typed conversation. What is
/// still being heard is grey and italic until it settles.
class VoiceExchanges extends ConsumerWidget {
  const VoiceExchanges({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exchanges = ref.watch(
      voiceControllerProvider.select((s) => s.exchanges),
    );
    final speaking = ref.watch(
      voiceControllerProvider.select((s) => s.speaking),
    );
    final chatReady = ref.watch(
      assistantControllerProvider.select(
        (s) => s.stage == AssistantStage.ready && !s.writing,
      ),
    );
    final heardSomething = exchanges.any((e) => e.heard.trim().isNotEmpty);
    final text = Theme.of(context).textTheme;
    final c = context.semantic;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, e) in exchanges.indexed) ...[
          if (e.heard.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                key: Key('voice-heard-$i'),
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
                  label: 'You said',
                  child: Text(
                    e.heard.trim(),
                    style: text.bodyMedium?.copyWith(
                      color: c.onPrimaryContainer.withValues(
                        alpha: _settled(e) ? 1 : 0.6,
                      ),
                      fontStyle: _settled(e) ? null : FontStyle.italic,
                    ),
                  ),
                ),
              ),
            ),
          if (e.reply.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                key: Key('voice-reply-$i'),
                margin: const EdgeInsets.only(
                  right: AlmanacDimens.sp8,
                  top: AlmanacDimens.sp3,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AlmanacDimens.sp4,
                  vertical: AlmanacDimens.sp3,
                ),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(AlmanacDimens.rLg),
                  border: Border.all(color: c.outlineVariant),
                ),
                child: Semantics(
                  label: e.interrupted
                      ? 'Assistant said, before you interrupted'
                      : 'Assistant said',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        e.interrupted ? '${e.reply.trim()}…' : e.reply.trim(),
                        style: text.bodyMedium?.copyWith(
                          color: e.interrupted ? c.onSurfaceVariant : null,
                        ),
                      ),
                      if (e.interrupted) ...[
                        const SizedBox(height: AlmanacDimens.sp2),
                        Row(
                          key: Key('voice-interrupted-$i'),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              LucideIcons.hand,
                              size: 14,
                              color: c.onSurfaceVariant,
                            ),
                            const SizedBox(width: AlmanacDimens.sp1),
                            Text(
                              'Interrupted',
                              style: text.labelSmall?.copyWith(
                                color: c.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
        if (heardSomething && chatReady && !speaking)
          Padding(
            padding: const EdgeInsets.only(top: AlmanacDimens.sp3),
            child: AppSecondaryButton(
              key: const Key('voice-plan'),
              label: 'Make a plan from this',
              icon: LucideIcons.sprout,
              onPressed: () => _plan(ref),
            ),
          ),
      ],
    );
  }

  /// Hands what was said, corrections included, to the planner as one
  /// message; if the conversation cannot take it now, it waits in the box.
  static Future<void> _plan(WidgetRef ref) async {
    final words = await ref.read(voiceControllerProvider.notifier).takeWords();
    if (words == null) return;
    final chat = ref.read(assistantControllerProvider.notifier);
    if (!await chat.send(words)) chat.returnDraft(words);
  }

  /// The farmer's words stop changing once the model starts answering.
  static bool _settled(VoiceExchange e) => e.done || e.reply.isNotEmpty;
}
