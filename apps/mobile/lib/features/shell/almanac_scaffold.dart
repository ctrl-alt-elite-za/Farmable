/// The persistent app shell: a body, the floating nav island, and the
/// assistant button docked into it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../assistant/assistant_sheet.dart';
import '../assistant/voice_controller.dart';
import 'bottom_nav_island.dart';

/// Wraps a screen in the shell.
///
/// The island is an overlay rather than a `bottomNavigationBar`, because the
/// design requires content to scroll *underneath* it — that is the whole point
/// of the glass. Screens leave [BottomNavIsland.bottomInset] clear at the foot
/// of their scroll view so nothing is trapped beneath it.
class AlmanacScaffold extends ConsumerWidget {
  final Widget body;
  final NavDestination destination;

  /// Zone Detail is reached from Home but belongs to Farm, and the island
  /// should say so. Passing the destination explicitly is how.
  const AlmanacScaffold({
    super.key,
    required this.body,
    required this.destination,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only the phase and whether it is speaking: the transcript streams in
    // many times a second and must not rebuild every screen's scaffold.
    final (phase, speaking) = ref.watch(
      voiceControllerProvider.select((s) => (s.phase, s.speaking)),
    );
    final assistantState = assistantStateFor(phase, speaking: speaking);

    return Scaffold(
      // The body deliberately extends behind the island.
      extendBody: true,
      body: body,
      bottomNavigationBar: SafeArea(
        top: false,
        // The island and the assistant's word sit in fixed heights, so their
        // labels stop growing at 150%. Past that "Farm" and "Speak" were cut
        // off at the bottom — every screen, at the system's larger text sizes.
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.5,
          child: SizedBox(
            // The island's own 64 plus its 16 of bottom inset, and enough above it
            // for the assistant button's top half and its word to ride proud.
            height: 112,
            child: Stack(
              alignment: Alignment.bottomCenter,
              clipBehavior: Clip.none,
              children: [
                BottomNavIsland(
                  current: destination,
                  onSelect: (d) {
                    if (d == destination) return;
                    context.go(d.route);
                  },
                ),
                AIActionButton(
                  state: assistantState,
                  onPressed: () => showAssistantSheet(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What the assistant button shows while voice is in [phase].
AssistantState assistantStateFor(VoicePhase phase, {required bool speaking}) =>
    switch (phase) {
      VoicePhase.listening when speaking => AssistantState.speaking,
      VoicePhase.listening => AssistantState.listening,
      VoicePhase.connecting ||
      VoicePhase.reconnecting => AssistantState.understanding,
      VoicePhase.consent || VoicePhase.off => AssistantState.idle,
    };
