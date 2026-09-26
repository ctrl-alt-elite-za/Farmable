/// The assistant conversation: who it is for, whether it may run, and each
/// turn from question to a visible ending.
///
/// ## Every turn ends where the farmer can see it
///
/// A turn's reply is [ReplyStatus.writing] only while events are arriving.
/// It leaves that state by exactly one of: the server's terminal event; the
/// durable snapshot, read when the stream is cut short; or the watchdog in
/// [AssistantTiming], which gives up on a silent stream, reads the snapshot a
/// bounded number of times, and then says the answer was lost. There is no
/// path that leaves a spinner running.
///
/// ## Nothing is saved without a Confirm tap
///
/// The model can only *preview* a plan (its tools are read-only). A preview
/// becomes a [PlanDecision]; the farmer chooses a candidate, reviews it, and
/// taps Confirm, and only [confirm] — reachable only from that review — calls
/// the server's `planning/confirm`. Typing "yes" is just another message.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/utils/ids.dart';
import '../../data/assistant/api_assistant_service.dart';
import '../../data/assistant/conversation_store.dart';
import '../../data/auth/api_auth_service.dart';
import '../../domain/assistant/assistant_api.dart';
import '../../domain/assistant/assistant_models.dart';
import '../../domain/assistant/crop_choices.dart';
import '../../domain/auth/auth_models.dart';
import '../auth/auth_view_model.dart';

// ---------------------------------------------------------------- providers

/// Makes an [AssistantApi] bound to whoever is signed in right now, or null
/// when this build has no server to talk to (demo and unconfigured builds).
final assistantApiFactoryProvider = Provider<AssistantApi? Function()>((ref) {
  final auth = ref.watch(authServiceProvider);
  return () => auth is ApiAuthService ? ApiAssistantService(auth) : null;
});

final assistantConversationStoreProvider = Provider<AssistantConversationStore>(
  (ref) => AssistantConversationStore(ref.watch(assistantStorageProvider)),
);

/// How long the app waits before deciding a turn has gone quiet.
///
/// The server gives a turn 60 seconds overall and 10 to its first words per
/// model call, so [overall] sits past that deadline rather than racing it.
class AssistantTiming {
  /// No event for this long and the stream is treated as cut.
  final Duration idle;

  /// However busy the stream, a turn is not waited on longer than this.
  final Duration overall;

  /// Snapshot reads after the stream is cut, and the gap between them.
  final int snapshotAttempts;
  final Duration snapshotGap;

  /// Opening calls: farms, conversation, consent, history.
  final Duration request;

  const AssistantTiming({
    this.idle = const Duration(seconds: 30),
    this.overall = const Duration(seconds: 90),
    this.snapshotAttempts = 3,
    this.snapshotGap = const Duration(seconds: 2),
    this.request = const Duration(seconds: 20),
  });
}

final assistantTimingProvider = Provider<AssistantTiming>(
  (ref) => const AssistantTiming(),
);

final assistantControllerProvider =
    NotifierProvider<AssistantController, AssistantChatState>(
      AssistantController.new,
    );

// -------------------------------------------------------------------- state

enum AssistantStage {
  /// Checking who is signed in, their farm and the conversation.
  starting,

  /// This build has no Farmable server (demo or unconfigured).
  notConnected,

  signedOut,

  /// No signal, or the server did not answer.
  offline,

  /// The server answered: the assistant is off or out of capacity.
  notAvailable,

  /// The farmer has not allowed outside services in Profile → Privacy.
  outsideServicesOff,

  /// The account has no farm on the server.
  noFarm,

  /// More than one server farm: the farmer picks which one to talk about.
  chooseFarm,

  /// The conversation needs the farmer's explicit permission first.
  needsConsent,

  /// The farmer said no, or withdrew permission. Nothing is sent.
  declined,

  ready,
}

enum ReplyStatus { writing, done, stopped, failed, lost }

sealed class ChatEntry {
  final String turnId;
  const ChatEntry(this.turnId);
}

class FarmerLine extends ChatEntry {
  final String text;

  /// Past the 30-day retention: the server has erased the words.
  final bool erased;

  const FarmerLine(super.turnId, this.text, {this.erased = false});
}

class ReplyEntry extends ChatEntry {
  /// The question, kept so a turn that did not finish can be sent again.
  final String message;
  final String text;
  final List<ToolResult> tools;
  final ReplyStatus status;

  /// Why it did not finish — for choosing words, never shown raw.
  final AssistantProblem? problem;
  final String? code;
  final bool erased;

  /// The server recorded this turn: it answered with an event, or its
  /// snapshot was read. Sending the same id again only replays what it
  /// recorded, so a retry of a recorded ending is a new turn.
  final bool admitted;

  const ReplyEntry(
    super.turnId, {
    required this.message,
    this.text = '',
    this.tools = const [],
    this.status = ReplyStatus.writing,
    this.problem,
    this.code,
    this.erased = false,
    this.admitted = false,
  });

  ReplyEntry copyWith({
    String? text,
    List<ToolResult>? tools,
    ReplyStatus? status,
    AssistantProblem? problem,
    String? code,
    bool? admitted,
  }) => ReplyEntry(
    turnId,
    message: message,
    text: text ?? this.text,
    tools: tools ?? this.tools,
    status: status ?? this.status,
    problem: problem ?? this.problem,
    code: code ?? this.code,
    erased: erased,
    admitted: admitted ?? this.admitted,
  );
}

enum DecisionStage {
  /// Reopened from history with plan ids this phone sent: asking the server
  /// whether one of them was saved before offering anything.
  checking,

  /// Candidates shown; the farmer may pick one.
  choosing,

  /// One picked; the confirm step is showing. Nothing sent yet.
  reviewing,

  /// Confirm tapped; waiting for the server.
  saving,

  saved,

  /// The server says the numbers changed since this preview.
  stale,

  /// Fetching a fresh preview after [stale].
  refreshing,

  /// The saved plan changed underneath this one.
  changed,
}

/// The farmer's decision about one plan preview.
class PlanDecision {
  final PlanPreview preview;
  final String? candidateId;
  final DecisionStage stage;

  /// The plan this confirmation creates. `expected_version: 0` makes it a
  /// new plan, so the server takes one confirmation per id, ever: once a
  /// confirm with this id *may* have reached it ([maybeSent]), different
  /// content gets a fresh id and this one moves to [earlierPlanIds].
  final String planId;

  /// Minted when a candidate goes to review, and kept for every retry of that
  /// exact confirmation — the server's replay protection depends on it.
  final String? mutationId;

  /// A confirm with [planId] was sent and may have been saved.
  final bool maybeSent;

  /// Plan ids of earlier confirmations for this preview that may have been
  /// saved. The server's history for each is read before anything new is
  /// sent, so a lost reply can never become a second plan.
  final List<String> earlierPlanIds;

  final ConfirmedPlan? saved;
  final PlanRevision? revision;

  /// Why the last attempt did not land, when it did not.
  final AssistantProblem? problem;

  const PlanDecision({
    required this.preview,
    required this.planId,
    this.candidateId,
    this.stage = DecisionStage.choosing,
    this.mutationId,
    this.maybeSent = false,
    this.earlierPlanIds = const [],
    this.saved,
    this.revision,
    this.problem,
  });

  PlanCandidate? get candidate {
    for (final c in preview.candidates) {
      if (c.id == candidateId) return c;
    }
    return null;
  }

  PlanDecision copyWith({
    PlanPreview? preview,
    String? planId,
    String? Function()? candidateId,
    DecisionStage? stage,
    String? Function()? mutationId,
    bool? maybeSent,
    List<String>? earlierPlanIds,
    ConfirmedPlan? saved,
    PlanRevision? revision,
    AssistantProblem? Function()? problem,
  }) => PlanDecision(
    preview: preview ?? this.preview,
    planId: planId ?? this.planId,
    candidateId: candidateId != null ? candidateId() : this.candidateId,
    stage: stage ?? this.stage,
    mutationId: mutationId != null ? mutationId() : this.mutationId,
    maybeSent: maybeSent ?? this.maybeSent,
    earlierPlanIds: earlierPlanIds ?? this.earlierPlanIds,
    saved: saved ?? this.saved,
    revision: revision ?? this.revision,
    problem: problem != null ? problem() : this.problem,
  );
}

class AssistantChatState {
  final AssistantStage stage;
  final AssistantConsent? consent;
  final List<ServerFarm> farms;
  final List<ChatEntry> entries;

  /// Keyed by the preview's original snapshot hash, which also keys its card.
  final Map<String, PlanDecision> decisions;

  /// A near-miss crop word in the message waiting to be sent.
  final CropQuestion? cropQuestion;
  final String? pendingMessage;

  /// Words the controller took from the box but could not send. The sheet
  /// puts them back where the farmer typed them ([takeReturnedDraft]).
  final String? returnedDraft;

  /// A consent change is on its way to the server.
  final bool consentBusy;

  /// The farmer withdrew permission (as opposed to never giving it).
  final bool withdrawn;

  /// A consent call did not reach the server; the farmer can try again.
  final AssistantProblem? consentProblem;

  /// Outside services were turned off while this conversation was open (as
  /// opposed to never having been on).
  final bool outsideServicesTurnedOff;

  const AssistantChatState({
    this.stage = AssistantStage.starting,
    this.consent,
    this.farms = const [],
    this.entries = const [],
    this.decisions = const {},
    this.cropQuestion,
    this.pendingMessage,
    this.returnedDraft,
    this.consentBusy = false,
    this.withdrawn = false,
    this.consentProblem,
    this.outsideServicesTurnedOff = false,
  });

  bool get writing =>
      entries.any((e) => e is ReplyEntry && e.status == ReplyStatus.writing);

  AssistantChatState copyWith({
    AssistantStage? stage,
    AssistantConsent? consent,
    List<ServerFarm>? farms,
    List<ChatEntry>? entries,
    Map<String, PlanDecision>? decisions,
    CropQuestion? Function()? cropQuestion,
    String? Function()? pendingMessage,
    String? Function()? returnedDraft,
    bool? consentBusy,
    bool? withdrawn,
    AssistantProblem? Function()? consentProblem,
    bool? outsideServicesTurnedOff,
  }) => AssistantChatState(
    stage: stage ?? this.stage,
    consent: consent ?? this.consent,
    farms: farms ?? this.farms,
    entries: entries ?? this.entries,
    decisions: decisions ?? this.decisions,
    cropQuestion: cropQuestion != null ? cropQuestion() : this.cropQuestion,
    pendingMessage: pendingMessage != null
        ? pendingMessage()
        : this.pendingMessage,
    returnedDraft: returnedDraft != null ? returnedDraft() : this.returnedDraft,
    consentBusy: consentBusy ?? this.consentBusy,
    withdrawn: withdrawn ?? this.withdrawn,
    consentProblem: consentProblem != null
        ? consentProblem()
        : this.consentProblem,
    outsideServicesTurnedOff:
        outsideServicesTurnedOff ?? this.outsideServicesTurnedOff,
  );
}

// --------------------------------------------------------------- controller

/// The longest message the server takes (`TurnCreate.message`).
const maxMessageLength = 4000;

/// The ending code of a turn stopped because outside services were turned off.
const outsideServicesOffCode = 'outside_services_off';

class AssistantController extends Notifier<AssistantChatState> {
  AssistantApi? _api;
  String? _userId;
  String? _farmId;
  String? _conversationId;
  Future<void>? _opening;

  /// Bumped on every reset, so a late answer for an earlier account or
  /// conversation is dropped instead of written into this one.
  int _epoch = 0;

  _Run? _run;

  /// Outside services are off as far as this conversation knows. Set the
  /// moment they are turned off; cleared only by reading them on again.
  bool _servicesOff = false;

  /// A turn is waiting on the permission check, so a second tap is ignored.
  bool _admitting = false;

  AssistantTiming get _timing => ref.read(assistantTimingProvider);

  @override
  AssistantChatState build() {
    // Another account, or nobody: nothing of this conversation may remain.
    ref.listen(authViewModelProvider, (previous, next) {
      final standing = next.value;
      final id = standing is SignedIn ? standing.session.user.id : null;
      if (_userId != null && id != _userId) _reset();
    });
    // Outside services turned off in Profile → Privacy while this
    // conversation is open: stop at once, not at the next open.
    ref.listen(externalProcessingConsentProvider, (previous, next) {
      if (next.isLoading) return;
      if (next case AsyncData(value: true)) return;
      // Never opened: [open] reads the choice itself when it is.
      if (_api == null) return;
      _outsideServicesOff();
    });
    ref.onDispose(() => _run?.cancel());
    return const AssistantChatState();
  }

  String? get farmId => _farmId;

  /// Called when the sheet opens. Cheap when the conversation is already
  /// open for this account; otherwise works out where the farmer stands.
  Future<void> open() =>
      _opening ??= _open().whenComplete(() => _opening = null);

  Future<void> _open() async {
    final api = ref.read(assistantApiFactoryProvider)();
    if (api == null) {
      state = const AssistantChatState(stage: AssistantStage.notConnected);
      return;
    }

    final AuthStanding standing;
    try {
      standing = await ref.read(authViewModelProvider.future);
    } on Object {
      state = const AssistantChatState(stage: AssistantStage.signedOut);
      return;
    }
    if (standing is! SignedIn) {
      _reset();
      state = const AssistantChatState(stage: AssistantStage.signedOut);
      return;
    }

    final userId = standing.session.user.id;
    if (userId != _userId) _reset();
    _userId = userId;
    final epoch = _epoch;

    // Read every time, a conversation already open included: the farmer may
    // have turned outside services off since it was opened.
    if (!await _outsideServicesOn(epoch)) return;
    if (state.outsideServicesTurnedOff) {
      state = state.copyWith(outsideServicesTurnedOff: false);
    }

    const settled = {
      AssistantStage.ready,
      AssistantStage.needsConsent,
      AssistantStage.declined,
      AssistantStage.chooseFarm,
    };
    if (_api != null && settled.contains(state.stage)) return;

    _api = api;

    state = state.copyWith(stage: AssistantStage.starting);
    try {
      final farms = await api.farms().timeout(_timing.request);
      if (epoch != _epoch || _servicesOff) return;
      if (farms.isEmpty) {
        state = state.copyWith(stage: AssistantStage.noFarm);
      } else if (farms.length > 1) {
        state = state.copyWith(stage: AssistantStage.chooseFarm, farms: farms);
      } else {
        await _startConversation(farms.single, epoch);
      }
    } on Object catch (e) {
      if (epoch == _epoch && !_servicesOff) _openFailed(e);
    }
  }

  /// The farmer picked which server farm to talk about.
  Future<void> chooseFarm(ServerFarm farm) async {
    if (state.stage != AssistantStage.chooseFarm) return;
    final epoch = _epoch;
    state = state.copyWith(stage: AssistantStage.starting);
    try {
      await _startConversation(farm, epoch);
    } on Object catch (e) {
      if (epoch == _epoch) _openFailed(e);
    }
  }

  Future<void> _startConversation(ServerFarm farm, int epoch) async {
    final api = _api!;
    final store = ref.read(assistantConversationStoreProvider);
    final remembered = await store.conversationFor(
      userId: _userId!,
      farmId: farm.id,
    );
    var conversationId = remembered ?? newUuid();
    try {
      await api
          .openConversation(conversationId: conversationId, farmId: farm.id)
          .timeout(_timing.request);
    } on AssistantException catch (e) {
      // A remembered conversation the server no longer knows — deleted with
      // an account, say. Start a new one rather than failing.
      if (remembered == null ||
          (e.problem != AssistantProblem.notFound &&
              e.problem != AssistantProblem.rejected)) {
        rethrow;
      }
      conversationId = newUuid();
      await api
          .openConversation(conversationId: conversationId, farmId: farm.id)
          .timeout(_timing.request);
    }
    if (epoch != _epoch) return;
    _farmId = farm.id;
    _conversationId = conversationId;
    await store.remember(
      userId: _userId!,
      farmId: farm.id,
      conversationId: conversationId,
    );

    final consent = await api.consent(conversationId).timeout(_timing.request);
    if (epoch != _epoch) return;

    var entries = const <ChatEntry>[];
    var decisions = const <String, PlanDecision>{};
    try {
      final turns = await api.history(conversationId).timeout(_timing.request);
      final sent = await store.plansFor(
        userId: _userId!,
        farmId: farm.id,
        conversationId: conversationId,
      );
      entries = [for (final t in turns) ..._entriesFor(t)];
      decisions = {
        for (final t in turns)
          for (final tool in t.tools)
            if (tool is PlanPreviewResult)
              tool.preview.snapshotHash: _restoredDecision(
                tool.preview,
                sent[tool.preview.snapshotHash] ?? const [],
              ),
      };
    } on Object {
      // Earlier turns are a convenience. Their absence does not stop today's.
    }
    if (epoch != _epoch) return;
    // Turned off while this was loading.
    if (_servicesOff) {
      state = state.copyWith(entries: entries, decisions: decisions);
      return;
    }

    state = state.copyWith(
      stage: consent.granted
          ? AssistantStage.ready
          : _declined
          ? AssistantStage.declined
          : AssistantStage.needsConsent,
      consent: consent,
      entries: entries,
      decisions: decisions,
    );
    for (final t in entries.whereType<ReplyEntry>()) {
      if (t.status == ReplyStatus.writing) {
        unawaited(_settleFromSnapshot(t.turnId, AssistantProblem.offline));
      }
    }
    for (final MapEntry(:key, :value) in decisions.entries) {
      if (value.stage == DecisionStage.checking) {
        unawaited(_settleRestored(key));
      }
    }
  }

  /// A preview read back from history. If this phone sent a confirmation for
  /// it, the card waits for the server's history before offering Confirm.
  PlanDecision _restoredDecision(PlanPreview preview, List<String> sent) =>
      PlanDecision(
        preview: preview,
        planId: newUuid(),
        earlierPlanIds: sent,
        stage: sent.isEmpty ? DecisionStage.choosing : DecisionStage.checking,
      );

  /// Said no this run. Not sent anywhere: "no" is the absence of a grant.
  bool _declined = false;

  void _openFailed(Object e) {
    final problem = e is AssistantException
        ? e.problem
        : AssistantProblem.offline;
    state = state.copyWith(
      stage: switch (problem) {
        AssistantProblem.signedOut => AssistantStage.signedOut,
        AssistantProblem.offline => AssistantStage.offline,
        AssistantProblem.noFarm ||
        AssistantProblem.notFound => AssistantStage.noFarm,
        _ => AssistantStage.notAvailable,
      },
    );
  }

  /// Starts again from nothing: another account, or a sign-out.
  void _reset() {
    _epoch++;
    _run?.cancel();
    _run = null;
    _api = null;
    _userId = null;
    _farmId = null;
    _conversationId = null;
    _declined = false;
    _servicesOff = false;
    _admitting = false;
    state = const AssistantChatState();
  }

  /// Reads the farmer's current outside-services choice. When it is off,
  /// moves to [AssistantStage.outsideServicesOff] and answers false; also
  /// false when [epoch] has moved on meanwhile.
  Future<bool> _outsideServicesOn(int epoch) async {
    bool allowed;
    try {
      allowed = await ref.read(externalProcessingConsentProvider.future);
    } on Object {
      allowed = false;
    }
    if (epoch != _epoch) return false;
    if (!allowed) {
      _outsideServicesOff();
      return false;
    }
    _servicesOff = false;
    return true;
  }

  /// Outside services are off. Nothing more is sent: a turn being written is
  /// interrupted on the server, and its stream is no longer read, so no
  /// further words appear. Only turning them back on reopens the
  /// conversation — which [open] notices on the farmer's next visit.
  void _outsideServicesOff() {
    _servicesOff = true;
    final wasOpen = _api != null && _conversationId != null;
    final run = _run;
    if (run != null) {
      run.cancel();
      unawaited(_interruptOnServer(run.turnId));
      _end(run.turnId, const TurnInterrupted(outsideServicesOffCode));
    }
    final pending = state.pendingMessage;
    state = state.copyWith(
      stage: AssistantStage.outsideServicesOff,
      outsideServicesTurnedOff: wasOpen || state.outsideServicesTurnedOff,
      cropQuestion: () => null,
      pendingMessage: () => null,
    );
    // A message held for the crop question goes back in the box.
    if (pending != null) _giveBack(pending);
  }

  Future<void> _interruptOnServer(String turnId) async {
    final api = _api;
    final conversation = _conversationId;
    if (api == null || conversation == null) return;
    try {
      await api.interrupt(conversation, turnId).timeout(_timing.request);
    } on Object {
      // The server may not have heard; closing the stream interrupts the
      // turn there too. Its snapshot is not shown: no more words appear.
    }
  }

  /// Checks again after an offline or not-available answer.
  Future<void> retryOpen() async {
    _api = null;
    state = state.copyWith(stage: AssistantStage.starting);
    await open();
  }

  // ------------------------------------------------------------------ consent

  /// The farmer's Allow tap. Sends back exactly the notice and model shown.
  Future<void> allow() async {
    final shown = state.consent;
    final id = _conversationId;
    if (shown == null || id == null || state.consentBusy) return;
    final epoch = _epoch;
    state = state.copyWith(consentBusy: true, consentProblem: () => null);
    try {
      final granted = await _api!
          .grantConsent(id, shown)
          .timeout(_timing.request);
      if (epoch != _epoch) return;
      _declined = false;
      state = state.copyWith(
        consent: granted,
        consentBusy: false,
        withdrawn: false,
        stage: granted.granted
            ? AssistantStage.ready
            : AssistantStage.needsConsent,
      );
    } on Object catch (e) {
      if (epoch != _epoch) return;
      await _consentFailed(e, id, epoch);
    }
  }

  Future<void> _consentFailed(Object e, String id, int epoch) async {
    final problem = e is AssistantException
        ? e.problem
        : AssistantProblem.offline;
    if (problem == AssistantProblem.signedOut) {
      state = state.copyWith(
        consentBusy: false,
        stage: AssistantStage.signedOut,
      );
      return;
    }
    // A changed notice or model: show the current one and ask again.
    AssistantConsent? current;
    if (problem == AssistantProblem.consentRequired) {
      try {
        current = await _api!.consent(id).timeout(_timing.request);
      } on Object {
        current = null;
      }
    }
    if (epoch != _epoch) return;
    state = state.copyWith(
      consent: current,
      consentBusy: false,
      consentProblem: () => problem,
    );
  }

  /// The farmer's Not now. Nothing is sent to the server or the model.
  void decline() {
    if (state.stage != AssistantStage.needsConsent) return;
    _declined = true;
    state = state.copyWith(stage: AssistantStage.declined, withdrawn: false);
  }

  /// From the declined state, back to the question.
  void askAgain() {
    if (state.stage != AssistantStage.declined) return;
    _declined = false;
    state = state.copyWith(stage: AssistantStage.needsConsent);
  }

  /// Withdraws permission. The server also stops any answer being written.
  Future<void> withdraw() async {
    final id = _conversationId;
    if (id == null || state.consentBusy) return;
    final epoch = _epoch;
    state = state.copyWith(consentBusy: true, consentProblem: () => null);
    try {
      final after = await _api!.withdrawConsent(id).timeout(_timing.request);
      if (epoch != _epoch) return;
      _declined = true;
      state = state.copyWith(
        consent: after,
        consentBusy: false,
        withdrawn: true,
        stage: AssistantStage.declined,
      );
    } on Object catch (e) {
      if (epoch != _epoch) return;
      await _consentFailed(e, id, epoch);
    }
  }

  // -------------------------------------------------------------------- turns

  /// Sends [raw], unless a crop name in it needs asking about first.
  ///
  /// True once the message is taken — sent, or held for the crop question —
  /// so the box is cleared only then. False leaves the farmer's words where
  /// they typed them. It does not wait for the answer.
  Future<bool> send(String raw) async {
    final message = raw.trim();
    if (message.isEmpty || message.length > maxMessageLength) return false;
    if (state.stage != AssistantStage.ready || state.writing) return false;
    final question = cropQuestionFor(message);
    if (question != null) {
      state = state.copyWith(
        cropQuestion: () => question,
        pendingMessage: () => message,
      );
      return true;
    }
    return _admit(newUuid(), message);
  }

  /// The farmer's answer to the crop question: a crop, or null for "keep
  /// what I typed".
  Future<void> answerCrop(ServerCrop? crop) async {
    final question = state.cropQuestion;
    final pending = state.pendingMessage;
    if (question == null || pending == null) return;
    final epoch = _epoch;
    state = state.copyWith(
      cropQuestion: () => null,
      pendingMessage: () => null,
    );
    final resolved = crop == null
        ? pending
        : resolveCropQuestion(pending, question, crop);
    // Unchanged words would only ask the same question again.
    final taken = resolved == pending
        ? await _admit(newUuid(), pending)
        : await send(resolved);
    // The box was cleared when the question was asked. Not sent after all
    // (outside services turned off meanwhile, or the crop's name took it past
    // the limit): the words go back, with the choice made if they still fit.
    if (!taken && epoch == _epoch) {
      _giveBack(resolved.length <= maxMessageLength ? resolved : pending);
    }
  }

  /// Hands [words] back to the box — see [AssistantChatState.returnedDraft].
  void _giveBack(String words) {
    final earlier = state.returnedDraft;
    state = state.copyWith(
      returnedDraft: () => earlier == null ? words : '$earlier\n$words',
    );
  }

  /// The words to put back in the box, once; null when there are none.
  String? takeReturnedDraft() {
    final words = state.returnedDraft;
    if (words != null) state = state.copyWith(returnedDraft: () => null);
    return words;
  }

  /// Drops the crop question and hands the message back for editing.
  String? editPending() {
    final pending = state.pendingMessage;
    state = state.copyWith(
      cropQuestion: () => null,
      pendingMessage: () => null,
    );
    return pending;
  }

  /// Sends a turn that did not finish again.
  ///
  /// As the *same* turn when the server may not have it — never admitted, or
  /// lost on the way — so it is never generated twice: the server replays
  /// what it saved, or admits it now. A turn the server recorded as ended is
  /// asked again as a new turn; its id would only replay that ending.
  Future<void> retry(String turnId) async {
    if (state.stage != AssistantStage.ready || state.writing) return;
    final entry = state.entries.whereType<ReplyEntry>().where(
      (e) => e.turnId == turnId,
    );
    if (entry.isEmpty) return;
    final reply = entry.first;
    if (reply.admitted && reply.status != ReplyStatus.lost) {
      await _admit(newUuid(), reply.message);
    } else {
      await _admit(turnId, reply.message, again: true);
    }
  }

  /// The one way into [_start]: checks the farmer's outside-services choice
  /// as it is now, not as it was when the conversation opened. True when the
  /// turn was started; it does not wait for the answer.
  Future<bool> _admit(
    String turnId,
    String message, {
    bool again = false,
  }) async {
    if (_admitting || _servicesOff) return false;
    final epoch = _epoch;
    _admitting = true;
    final bool allowed;
    try {
      allowed = await _outsideServicesOn(epoch);
    } finally {
      _admitting = false;
    }
    if (!allowed || epoch != _epoch) return false;
    if (state.stage != AssistantStage.ready || state.writing) return false;
    _start(turnId, message, again: again);
    return true;
  }

  /// The farmer's Stop tap.
  Future<void> stop() async {
    final run = _run;
    if (run == null) return;
    run.cancel();
    try {
      final snapshot = await _api!
          .interrupt(_conversationId!, run.turnId)
          .timeout(_timing.request);
      if (run.epoch != _epoch) return;
      _applySnapshot(snapshot);
      // An answer that finished as Stop was tapped stays finished.
      _end(run.turnId, snapshot.ended ?? TurnInterrupted(snapshot.error));
    } on Object {
      if (run.epoch != _epoch) return;
      // The server may not have heard; closing the stream interrupts the turn
      // there too. Either way it ends here, visibly.
      _end(run.turnId, const TurnInterrupted('stopped_by_farmer'));
    }
  }

  void _start(String turnId, String message, {bool again = false}) {
    final api = _api!;
    final conversation = _conversationId!;
    final reply = ReplyEntry(turnId, message: message);
    state = state.copyWith(
      entries: again
          ? [
              for (final e in state.entries)
                if (e is ReplyEntry && e.turnId == turnId) reply else e,
            ]
          : [...state.entries, FarmerLine(turnId, message), reply],
    );

    final run = _Run(turnId, _epoch);
    _run = run;

    void watchdog() {
      if (run.closed) return;
      run.cancel();
      unawaited(_settleFromSnapshot(turnId, AssistantProblem.offline));
    }

    run.overall = Timer(_timing.overall, watchdog);
    run.idle = Timer(_timing.idle, watchdog);
    run.subscription = api
        .sendTurn(
          conversationId: conversation,
          turnId: turnId,
          message: message,
        )
        .listen(
          (event) {
            if (run.closed || run.epoch != _epoch) return;
            run.idle?.cancel();
            run.idle = Timer(_timing.idle, watchdog);
            _onEvent(run, event);
          },
          onError: (Object e) {
            if (run.closed || run.epoch != _epoch) return;
            run.cancel();
            _onStreamError(turnId, e);
          },
          onDone: () {
            if (run.closed || run.epoch != _epoch) return;
            run.cancel();
            // Ended with no terminal event: the snapshot says how it ended.
            unawaited(_settleFromSnapshot(turnId, AssistantProblem.offline));
          },
          cancelOnError: true,
        );
  }

  void _onEvent(_Run run, TurnEvent event) {
    // Any event at all means the server admitted the turn: a refusal before
    // that is an HTTP error, not an event.
    _updateReply(run.turnId, (r) => r.copyWith(admitted: true));
    switch (event) {
      case TurnAccepted(:final snapshot):
        if (snapshot != null) _applySnapshot(snapshot);
      case TurnText(:final text):
        _updateReply(run.turnId, (r) => r.copyWith(text: r.text + text));
      case TurnTool(:final result):
        _updateReply(
          run.turnId,
          (r) => r.copyWith(tools: [...r.tools, result]),
        );
        _noteTool(result);
      case TurnFailed(code: 'turn_in_progress'):
        // A replay of a turn still being written. Its snapshot will finish.
        run.cancel();
        unawaited(_settleFromSnapshot(run.turnId, AssistantProblem.busy));
      case TurnEnded():
        run.cancel();
        _end(run.turnId, event);
    }
  }

  void _onStreamError(String turnId, Object e) {
    final problem = e is AssistantException
        ? e.problem
        : AssistantProblem.offline;
    switch (problem) {
      case AssistantProblem.offline || AssistantProblem.unknown:
        // It may or may not have reached the server. Ask.
        unawaited(_settleFromSnapshot(turnId, problem));
      case AssistantProblem.consentRequired:
        _end(
          turnId,
          TurnFailed(e is AssistantException ? e.code : null),
          problem: problem,
        );
        state = state.copyWith(stage: AssistantStage.needsConsent);
      case AssistantProblem.signedOut:
        _end(turnId, const TurnFailed('invalid_session'), problem: problem);
        state = state.copyWith(stage: AssistantStage.signedOut);
      default:
        _end(
          turnId,
          TurnFailed(e is AssistantException ? e.code : null),
          problem: problem,
        );
    }
  }

  /// Reads the durable snapshot a bounded number of times, then ends the
  /// turn whatever it found.
  Future<void> _settleFromSnapshot(
    String turnId,
    AssistantProblem fallback,
  ) async {
    final epoch = _epoch;
    final api = _api;
    final conversation = _conversationId;
    if (api == null || conversation == null) return;
    for (var attempt = 0; attempt < _timing.snapshotAttempts; attempt++) {
      if (attempt > 0) await Future<void>.delayed(_timing.snapshotGap);
      if (epoch != _epoch) return;
      try {
        final snapshot = await api
            .turn(conversation, turnId)
            .timeout(_timing.request);
        if (epoch != _epoch) return;
        final ended = snapshot.ended;
        if (ended != null) {
          _applySnapshot(snapshot);
          _end(turnId, ended);
          return;
        }
      } on AssistantException catch (e) {
        if (epoch != _epoch) return;
        if (e.problem == AssistantProblem.notFound) {
          // Never admitted: the question did not reach the assistant.
          _end(turnId, TurnFailed(e.code), problem: fallback);
          return;
        }
        if (e.problem == AssistantProblem.signedOut) {
          _end(turnId, const TurnFailed('invalid_session'), problem: e.problem);
          state = state.copyWith(stage: AssistantStage.signedOut);
          return;
        }
      } on Object {
        // No answer this time; the loop is bounded.
      }
    }
    if (epoch != _epoch) return;
    _end(turnId, null, problem: fallback);
  }

  void _applySnapshot(TurnSnapshot snapshot) {
    _updateReply(
      snapshot.id,
      (r) => r.copyWith(
        text: snapshot.reply,
        tools: snapshot.tools,
        admitted: true,
      ),
    );
    for (final tool in snapshot.tools) {
      _noteTool(tool);
    }
  }

  void _noteTool(ToolResult tool) {
    if (tool is! PlanPreviewResult) return;
    final hash = tool.preview.snapshotHash;
    if (state.decisions.containsKey(hash)) return;
    state = state.copyWith(
      decisions: {
        ...state.decisions,
        hash: PlanDecision(preview: tool.preview, planId: newUuid()),
      },
    );
  }

  /// Ends [turnId]'s reply. [ended] null means the snapshot never settled it.
  void _end(String turnId, TurnEnded? ended, {AssistantProblem? problem}) {
    final run = _run;
    if (run != null && run.turnId == turnId) {
      run.cancel();
      _run = null;
    }
    _updateReply(turnId, (r) {
      if (r.status != ReplyStatus.writing) return r;
      return switch (ended) {
        TurnDone() => r.copyWith(status: ReplyStatus.done),
        TurnInterrupted(:final code) => r.copyWith(
          status: ReplyStatus.stopped,
          code: code,
          problem: problem ?? _problemForCode(code),
        ),
        TurnFailed(:final code) => r.copyWith(
          status: ReplyStatus.failed,
          code: code,
          problem: problem ?? _problemForCode(code),
        ),
        null => r.copyWith(status: ReplyStatus.lost, problem: problem),
      };
    });
  }

  AssistantProblem? _problemForCode(String? code) =>
      code == null ? null : problemFor(0, code);

  void _updateReply(String turnId, ReplyEntry Function(ReplyEntry) change) {
    state = state.copyWith(
      entries: [
        for (final e in state.entries)
          if (e is ReplyEntry && e.turnId == turnId) change(e) else e,
      ],
    );
  }

  List<ChatEntry> _entriesFor(TurnSnapshot t) {
    final erased = t.contentDeletedAt != null;
    final ended = t.ended;
    return [
      FarmerLine(t.id, t.message, erased: erased),
      ReplyEntry(
        t.id,
        message: t.message,
        text: t.reply,
        tools: t.tools,
        erased: erased,
        status: switch (ended) {
          null => ReplyStatus.writing,
          TurnDone() => ReplyStatus.done,
          TurnInterrupted() => ReplyStatus.stopped,
          TurnFailed() => ReplyStatus.failed,
        },
        code: t.error,
        problem: _problemForCode(t.error),
        admitted: true,
      ),
    ];
  }

  // ------------------------------------------------------------------ plans

  void selectCandidate(String key, String candidateId) {
    final d = state.decisions[key];
    if (d == null) return;
    const open = {
      DecisionStage.choosing,
      DecisionStage.reviewing,
      DecisionStage.changed,
    };
    if (!open.contains(d.stage)) return;
    if (!d.preview.candidates.any((c) => c.id == candidateId)) return;
    // After a "changed" answer the same option is a new request too: its ids
    // were refused, and sending them again is refused again.
    final next =
        d.candidateId == candidateId && d.stage != DecisionStage.changed
        ? d
        : _newContent(d);
    _setDecision(
      key,
      next.copyWith(
        candidateId: () => candidateId,
        stage: DecisionStage.choosing,
        problem: () => null,
      ),
    );
  }

  /// Different content is a different request to the server: a new mutation
  /// id, and — if the last confirmation may have landed — a new plan id, with
  /// the old one kept to be checked before anything else is sent. The same
  /// plan id with a new mutation id is what the server answers with
  /// `revision_conflict`, for a plan it may already have saved.
  PlanDecision _newContent(PlanDecision d) => d.maybeSent
      ? d.copyWith(
          planId: newUuid(),
          mutationId: () => null,
          maybeSent: false,
          earlierPlanIds: [...d.earlierPlanIds, d.planId],
        )
      : d.copyWith(mutationId: () => null);

  /// Shows the confirm step for the chosen candidate. Sends nothing.
  void review(String key) {
    final d = state.decisions[key];
    if (d == null || d.candidate == null) return;
    if (d.stage != DecisionStage.choosing) return;
    _setDecision(
      key,
      d.copyWith(
        stage: DecisionStage.reviewing,
        mutationId: () => d.mutationId ?? newUuid(),
      ),
    );
  }

  void cancelReview(String key) {
    final d = state.decisions[key];
    if (d == null || d.stage != DecisionStage.reviewing) return;
    _setDecision(key, d.copyWith(stage: DecisionStage.choosing));
  }

  /// The farmer's Confirm tap — the one path to `planning/confirm`.
  ///
  /// When the answer does not settle whether the plan was saved (no reply,
  /// or a conflict on a plan id this phone minted), the plan's history on the
  /// server decides what the card says — never a guess.
  Future<void> confirm(String key) async {
    final d = state.decisions[key];
    final farm = _farmId;
    final api = _api;
    final candidate = d?.candidate;
    if (d == null || farm == null || api == null || candidate == null) return;
    if (d.stage != DecisionStage.reviewing || d.mutationId == null) return;
    final epoch = _epoch;
    _setDecision(
      key,
      d.copyWith(stage: DecisionStage.saving, problem: () => null),
    );

    // An earlier confirmation may have landed. Know before sending another.
    for (final earlier in d.earlierPlanIds) {
      final found = await _lookUp(api, farm, earlier);
      if (epoch != _epoch) return;
      if (found.saved != null) {
        _showSaved(key, earlier, found.saved!);
        return;
      }
      if (!found.known) {
        _setDecision(
          key,
          state.decisions[key]!.copyWith(
            stage: DecisionStage.reviewing,
            problem: () => AssistantProblem.offline,
          ),
        );
        return;
      }
    }
    if (d.earlierPlanIds.isNotEmpty) {
      _setDecision(key, state.decisions[key]!.copyWith(earlierPlanIds: []));
    }

    // Written down before it can reach the server, so a reopened chat can
    // still ask about it.
    await _rememberSent(key, d.planId);
    if (epoch != _epoch) return;
    _setDecision(key, state.decisions[key]!.copyWith(maybeSent: true));
    try {
      final saved = await api
          .confirm(
            farmId: farm,
            preview: d.preview,
            candidateId: candidate.id,
            planId: d.planId,
            mutationId: d.mutationId!,
          )
          .timeout(_timing.request);
      if (epoch != _epoch) return;
      _setDecision(
        key,
        state.decisions[key]!.copyWith(
          stage: DecisionStage.saved,
          saved: saved,
        ),
      );
      try {
        final history = await api
            .planHistory(farm, saved.id)
            .timeout(_timing.request);
        if (epoch != _epoch) return;
        final mine = history.where((r) => r.version == saved.version);
        if (mine.isNotEmpty) {
          _setDecision(
            key,
            state.decisions[key]!.copyWith(revision: mine.first),
          );
        }
      } on Object {
        // The plan is saved; its history line is extra.
      }
    } on Object catch (e) {
      if (epoch != _epoch) return;
      final problem = e is AssistantException
          ? e.problem
          : AssistantProblem.offline;
      final code = e is AssistantException ? e.code : null;
      if (_outcomeUnknown(problem, code)) {
        final found = await _lookUp(api, farm, d.planId);
        if (epoch != _epoch) return;
        if (found.saved != null) {
          _showSaved(key, d.planId, found.saved!);
          return;
        }
        if (problem != AssistantProblem.planChanged || !found.known) {
          // Not found, or no answer: it may have arrived, or still may.
          // Same ids, so Confirm again is a retry the server recognises.
          _setDecision(
            key,
            state.decisions[key]!.copyWith(
              stage: DecisionStage.reviewing,
              problem: () => AssistantProblem.offline,
            ),
          );
          return;
        }
      }
      _setDecision(
        key,
        state.decisions[key]!.copyWith(
          stage: switch (problem) {
            AssistantProblem.planStale => DecisionStage.stale,
            AssistantProblem.planChanged => DecisionStage.changed,
            _ => DecisionStage.reviewing,
          },
          // The server answered, so this attempt was not saved — but an
          // earlier one with this id may have been, and a changed plan's id
          // is taken. Either way the next choice gets a fresh id.
          maybeSent: d.maybeSent || problem == AssistantProblem.planChanged,
          problem: () => problem,
        ),
      );
      if (problem == AssistantProblem.signedOut) {
        state = state.copyWith(stage: AssistantStage.signedOut);
      }
    }
  }

  /// No reply, a server that failed part-way, or a conflict that only makes
  /// sense if an earlier confirmation with this plan id was saved.
  static bool _outcomeUnknown(AssistantProblem problem, String? code) =>
      problem == AssistantProblem.offline ||
      problem == AssistantProblem.unknown ||
      problem == AssistantProblem.notAvailable ||
      code == 'revision_conflict' ||
      code == 'mutation_conflict';

  /// Reads [planId]'s history: saved (with its confirmation), known not
  /// saved (the server has no such plan), or not known (no answer).
  Future<({PlanRevision? saved, bool known})> _lookUp(
    AssistantApi api,
    String farm,
    String planId,
  ) async {
    try {
      final history = await api
          .planHistory(farm, planId)
          .timeout(_timing.request);
      if (history.isEmpty) return (saved: null, known: false);
      final confirmation = history.where(
        (r) => r.origin == 'planner_confirmation',
      );
      return (
        saved: confirmation.isEmpty ? history.first : confirmation.first,
        known: true,
      );
    } on AssistantException catch (e) {
      return (saved: null, known: e.problem == AssistantProblem.notFound);
    } on Object {
      return (saved: null, known: false);
    }
  }

  /// The server's history says [planId] was saved: show it as saved, with
  /// the candidate it actually saved.
  void _showSaved(String key, String planId, PlanRevision revision) {
    final d = state.decisions[key]!;
    final savedCandidate = revision.candidateId;
    _setDecision(
      key,
      d.copyWith(
        planId: planId,
        stage: DecisionStage.saved,
        candidateId:
            savedCandidate != null &&
                d.preview.candidates.any((c) => c.id == savedCandidate)
            ? () => savedCandidate
            : null,
        saved: ConfirmedPlan(
          id: planId,
          version: revision.version,
          approvedAt: revision.recordedAt,
          replayed: true,
        ),
        revision: revision,
        earlierPlanIds: [],
        problem: () => null,
      ),
    );
  }

  /// A reopened card whose preview this phone sent a confirmation for.
  Future<void> _settleRestored(String key) async {
    final d = state.decisions[key];
    final farm = _farmId;
    final api = _api;
    if (d == null || farm == null || api == null) return;
    final epoch = _epoch;
    for (final planId in d.earlierPlanIds) {
      final found = await _lookUp(api, farm, planId);
      if (epoch != _epoch) return;
      if (found.saved != null) {
        _showSaved(key, planId, found.saved!);
        return;
      }
      if (!found.known) {
        // No answer. The ids stay, and Confirm checks them again first.
        _setDecision(
          key,
          state.decisions[key]!.copyWith(stage: DecisionStage.choosing),
        );
        return;
      }
    }
    _setDecision(
      key,
      state.decisions[key]!.copyWith(
        stage: DecisionStage.choosing,
        earlierPlanIds: [],
      ),
    );
  }

  Future<void> _rememberSent(String key, String planId) async {
    final user = _userId;
    final farm = _farmId;
    final conversation = _conversationId;
    if (user == null || farm == null || conversation == null) return;
    await ref
        .read(assistantConversationStoreProvider)
        .rememberPlan(
          userId: user,
          farmId: farm,
          conversationId: conversation,
          snapshotHash: key,
          planId: planId,
        );
  }

  /// After a stale answer: a fresh preview of the same request. Read-only.
  Future<void> refresh(String key) async {
    final d = state.decisions[key];
    final farm = _farmId;
    final api = _api;
    if (d == null || farm == null || api == null) return;
    if (d.stage != DecisionStage.stale) return;
    final epoch = _epoch;
    _setDecision(key, d.copyWith(stage: DecisionStage.refreshing));
    try {
      final fresh = await api
          .preview(farm, d.preview.request)
          .timeout(_timing.request);
      if (epoch != _epoch) return;
      _setDecision(
        key,
        _newContent(state.decisions[key]!).copyWith(
          preview: fresh,
          stage: DecisionStage.choosing,
          candidateId: () => null,
          problem: () => null,
        ),
      );
    } on Object catch (e) {
      if (epoch != _epoch) return;
      _setDecision(
        key,
        state.decisions[key]!.copyWith(
          stage: DecisionStage.stale,
          problem: () =>
              e is AssistantException ? e.problem : AssistantProblem.offline,
        ),
      );
    }
  }

  void _setDecision(String key, PlanDecision decision) {
    state = state.copyWith(decisions: {...state.decisions, key: decision});
  }
}

/// One turn in flight: its stream and its two clocks.
class _Run {
  final String turnId;
  final int epoch;
  StreamSubscription<TurnEvent>? subscription;
  Timer? idle;
  Timer? overall;
  bool closed = false;

  _Run(this.turnId, this.epoch);

  /// Stops listening. Closing the stream also tells the server to stop.
  void cancel() {
    if (closed) return;
    closed = true;
    idle?.cancel();
    overall?.cancel();
    unawaited(subscription?.cancel());
  }
}
