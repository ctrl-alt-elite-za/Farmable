/// The assistant button follows voice (#24, #25): idle, understanding while it
/// connects, listening, and speaking while a reply plays.
library;

import 'package:almanac/features/assistant/voice_controller.dart';
import 'package:almanac/features/shell/almanac_scaffold.dart';
import 'package:almanac/features/shell/bottom_nav_island.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every voice phase maps to a button state', () {
    expect(
      assistantStateFor(VoicePhase.off, speaking: false),
      AssistantState.idle,
    );
    expect(
      assistantStateFor(VoicePhase.consent, speaking: false),
      AssistantState.idle,
    );
    expect(
      assistantStateFor(VoicePhase.connecting, speaking: false),
      AssistantState.understanding,
    );
    expect(
      assistantStateFor(VoicePhase.reconnecting, speaking: false),
      AssistantState.understanding,
    );
    expect(
      assistantStateFor(VoicePhase.listening, speaking: false),
      AssistantState.listening,
    );
    expect(
      assistantStateFor(VoicePhase.listening, speaking: true),
      AssistantState.speaking,
    );
  });

  test('speaking shows only while voice is listening', () {
    // A stale speaking flag never lights the button once voice is off.
    expect(
      assistantStateFor(VoicePhase.off, speaking: true),
      AssistantState.idle,
    );
  });
}
