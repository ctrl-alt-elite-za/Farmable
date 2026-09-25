/// A scripted stand-in for the assistant's server, behind the real
/// [AssistantApi] port, and a harness that pumps the real sheet against it.
///
/// Every turn is a [StreamController] the test drives by hand: it decides
/// when text arrives, when a tool result lands, and whether the stream ends
/// properly, breaks, or goes silent. That is what lets a test prove a turn
/// always reaches a visible ending instead of trusting that it does.
library;

import 'dart:async';

import 'package:almanac/app/providers.dart';
import 'package:almanac/app/theme/app_theme.dart';
import 'package:almanac/data/auth/session_storage.dart';
import 'package:almanac/data/local/database.dart';
import 'package:almanac/data/local/seed.dart';
import 'package:almanac/domain/assistant/assistant_api.dart';
import 'package:almanac/domain/assistant/assistant_models.dart';
import 'package:almanac/domain/auth/auth_models.dart';
import 'package:almanac/features/assistant/assistant_controller.dart';
import 'package:almanac/features/assistant/assistant_sheet.dart';
import 'package:almanac/features/auth/auth_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'harness.dart' show phoneSize, pinnedToday;

const farmId = '11111111-1111-4111-8111-111111111111';
const sectionId = '22222222-2222-4222-8222-222222222222';
const notice = 'Allow this conversation to be sent to Google Gemini.';

String hex(String c) => List.filled(64, c).join();

/// A `preview_planting_plan` result as the backend's tool returns it.
Map<String, Object?> previewJson({
  String hash = 'a',
  bool feasible = true,
  List<Map<String, Object?>>? candidates,
}) => {
  'engine_version': 'test',
  'request': {
    'section_id': sectionId,
    'planting_date': '2026-10-01',
    'budget_cents': 500000,
    'money_basis_year': 2025,
    'crops': [
      {'crop': 'cabbage', 'minimum_percent': 0, 'promised_kg': '0'},
    ],
    'block_count': 4,
    'max_results': 3,
    'planting_cost_percent': 30,
    'market_commission_bps': 500,
    'agent_commission_bps': 0,
    'cash_deadline': null,
    'goal_margin_cents': null,
  },
  'section_version': 1,
  'area_m2': '400.00',
  'source': {
    'forecast_as_of': '2026-09-01',
    'data_kind': 'synthetic',
    'warning': 'Sample data, not a real forecast.',
  },
  'comparisons': [],
  'candidates':
      candidates ??
      (feasible
          ? [
              _candidate(hex('1'), cabbage: 4, margin: 1200000, cash: 400000),
              _candidate(hex('2'), cabbage: 3, margin: 900000, cash: 300000),
            ]
          : []),
  'feasible': feasible,
  'change_needed': feasible
      ? null
      : {
          'code': 'budget_too_low',
          'minimum_budget_cents': 750000,
          'message': 'Increase starting cash.',
        },
  'assumptions': ['Yield is the source estimate.'],
  'snapshot_hash': hex(hash),
};

Map<String, Object?> _candidate(
  String id, {
  required int cabbage,
  required int margin,
  required int cash,
}) => {
  'id': id,
  'allocations': [
    {
      'crop': 'cabbage',
      'blocks': cabbage,
      'area_m2': '100',
      'quantity_kg': '800',
      'production_cost_cents': 1,
      'sales_cents': 1,
      'commission_cents': 1,
      'margin_cents': margin,
      'harvest_date': '2027-01-10',
      'payment_date': '2027-01-17',
      'break_even_price_per_kg': '1',
      'price_only_break_even_chance_bounds': ['0.1', '0.2'],
      'cost_schedule': [],
    },
  ],
  'unplanted_blocks': 4 - cabbage,
  'margin_cents': margin,
  'required_cash_cents': cash,
  'cash_timeline': [],
};

TurnTool previewTool([Map<String, Object?>? json]) => TurnTool(
  ToolResult.fromJson({
    'name': 'preview_planting_plan',
    'args': const <String, Object?>{},
    'result': json ?? previewJson(),
  }),
);

class SentTurn {
  final String turnId;
  final String message;
  final StreamController<TurnEvent> events;
  SentTurn(this.turnId, this.message, this.events);
}

class ConfirmCall {
  final PlanPreview preview;
  final String candidateId;
  final String planId;
  final String mutationId;
  ConfirmCall(this.preview, this.candidateId, this.planId, this.mutationId);
}

class FakeAssistantApi implements AssistantApi {
  List<ServerFarm> farmList = [const ServerFarm(farmId, 'My farm')];
  Object? farmsError;
  bool granted;
  final grants = <AssistantConsent>[];
  int withdrawals = 0;
  final opened = <String>[];
  final sent = <SentTurn>[];
  final history_ = <TurnSnapshot>[];

  /// What `GET …/turns/{id}` answers: a snapshot, or an exception to throw.
  final snapshots = <String, Object>{};
  final interrupts = <String>[];
  final confirms = <ConfirmCall>[];
  Object? confirmResult;
  final previews = <Map<String, Object?>>[];
  Object? previewResult;

  FakeAssistantApi({this.granted = false});

  AssistantConsent get _consent => AssistantConsent(
    granted: granted,
    notice: notice,
    noticeVersion: 'gemini-conversation-v3',
    model: 'fixture-model',
    provider: 'google_gemini',
  );

  SentTurn get last => sent.last;

  @override
  Future<List<ServerFarm>> farms() async {
    if (farmsError != null) throw farmsError!;
    return farmList;
  }

  @override
  Future<void> openConversation({
    required String conversationId,
    required String farmId,
  }) async => opened.add(conversationId);

  @override
  Future<AssistantConsent> consent(String conversationId) async => _consent;

  @override
  Future<AssistantConsent> grantConsent(
    String conversationId,
    AssistantConsent shown,
  ) async {
    grants.add(shown);
    granted = true;
    return _consent;
  }

  @override
  Future<AssistantConsent> withdrawConsent(String conversationId) async {
    withdrawals++;
    granted = false;
    return _consent;
  }

  @override
  Stream<TurnEvent> sendTurn({
    required String conversationId,
    required String turnId,
    required String message,
  }) {
    final events = StreamController<TurnEvent>();
    sent.add(SentTurn(turnId, message, events));
    return events.stream;
  }

  @override
  Future<TurnSnapshot> turn(String conversationId, String turnId) async {
    final answer = snapshots[turnId];
    if (answer == null) {
      throw const AssistantException(AssistantProblem.offline);
    }
    if (answer is TurnSnapshot) return answer;
    throw answer;
  }

  @override
  Future<List<TurnSnapshot>> history(String conversationId) async => history_;

  @override
  Future<TurnSnapshot> interrupt(String conversationId, String turnId) async {
    interrupts.add(turnId);
    return snapshot(turnId, TurnStatus.interrupted, reply: 'Partial');
  }

  @override
  Future<PlanPreview> preview(
    String farmId,
    Map<String, Object?> request,
  ) async {
    previews.add(request);
    final result = previewResult;
    if (result is PlanPreview) return result;
    if (result != null) throw result;
    return PlanPreview.fromJson(previewJson(hash: 'b'));
  }

  @override
  Future<ConfirmedPlan> confirm({
    required String farmId,
    required PlanPreview preview,
    required String candidateId,
    required String planId,
    required String mutationId,
  }) async {
    confirms.add(ConfirmCall(preview, candidateId, planId, mutationId));
    final result = confirmResult;
    if (result != null) throw result;
    return ConfirmedPlan(
      id: planId,
      version: 1,
      approvedAt: DateTime.utc(2026, 9, 20),
      replayed: false,
    );
  }

  @override
  Future<List<PlanRevision>> planHistory(String farmId, String planId) async =>
      [
        PlanRevision(
          version: 1,
          origin: 'planner_confirmation',
          recordedAt: DateTime.utc(2026, 9, 20),
        ),
      ];
}

TurnSnapshot snapshot(
  String id,
  TurnStatus status, {
  String message = 'Q',
  String reply = '',
  String? error,
  List<ToolResult> tools = const [],
}) => TurnSnapshot(
  id: id,
  status: status,
  message: message,
  reply: reply,
  tools: tools,
  error: error,
  createdAt: DateTime.utc(2026, 9, 20),
);

class _FixedAuth extends AuthViewModel {
  final AuthStanding standing;
  _FixedAuth(this.standing);

  @override
  Future<AuthStanding> build() async => standing;
}

final signedIn = SignedIn(
  AuthSession(
    token: 'secret-access-token-never-printed',
    refreshToken: 'secret-refresh-token-never-printed',
    expiresAt: DateTime.utc(2026, 10, 20),
    user: const AuthUser(
      id: 'user-1',
      firstName: 'Thandi',
      surname: 'Mokoena',
      phone: '+27820000000',
      email: 'thandi@example.com',
      phoneVerified: true,
      emailVerified: true,
    ),
  ),
);

/// Short clocks, so a test of the watchdog does not wait ninety seconds.
const fastTiming = AssistantTiming(
  idle: Duration(seconds: 3),
  overall: Duration(seconds: 10),
  snapshotAttempts: 2,
  snapshotGap: Duration(milliseconds: 200),
  request: Duration(seconds: 5),
);

/// Pumps the real assistant sheet over [api] (null: a build with no server).
///
/// [outsideServicesNow], when given, is read each time the outside-services
/// choice is (re)computed, so a test can turn it off and invalidate
/// `externalProcessingConsentProvider` as Profile → Privacy does.
Future<ProviderContainer> pumpAssistant(
  WidgetTester tester, {
  FakeAssistantApi? api,
  bool noServer = false,
  AuthStanding? standing,
  bool outsideServices = true,
  bool Function()? outsideServicesNow,
  AssistantTiming timing = fastTiming,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = phoneSize;
  addTearDown(tester.view.reset);

  final db = AlmanacDatabase.memory();
  await DemoSeed(db, now: () => pinnedToday).ensureSeeded();

  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(db),
      clockProvider.overrideWithValue(() => pinnedToday),
      assistantApiFactoryProvider.overrideWithValue(
        () => noServer ? null : api,
      ),
      assistantStorageProvider.overrideWithValue(InMemorySessionStorage()),
      assistantTimingProvider.overrideWithValue(timing),
      authViewModelProvider.overrideWith(
        () => _FixedAuth(standing ?? signedIn),
      ),
      externalProcessingConsentProvider.overrideWith(
        (ref) async => outsideServicesNow?.call() ?? outsideServices,
      ),
    ],
  );

  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: Center(
            child: TextButton(
              key: const Key('open-assistant'),
              onPressed: () => showAssistantSheet(context),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/farm/zone/:id/plant',
        builder: (_, state) =>
            Scaffold(body: Text('Planner for ${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/auth/login',
        builder: (_, _) => const Scaffold(body: Text('Login screen')),
      ),
    ],
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        theme: almanacLightTheme(),
      ),
    ),
  );
  await settle(tester);
  await tester.tap(find.byKey(const Key('open-assistant')));
  await settle(tester);

  addTearDown(() async {
    container.dispose();
    await db.close();
  });
  return container;
}

/// Closes the sheet the way the farmer does, leaving the controller alive.
Future<void> closeAssistant(WidgetTester tester) async {
  Navigator.of(tester.element(find.byType(AssistantSheet))).pop();
  await settle(tester);
}

/// Opens the sheet again from the same screen.
Future<void> reopenAssistant(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('open-assistant')));
  await settle(tester);
}

/// Ends every turn the test left open, so its watchdog is not left running.
Future<void> endOpenTurns(WidgetTester tester, FakeAssistantApi api) async {
  for (final turn in api.sent) {
    if (!turn.events.isClosed && turn.events.hasListener) {
      turn.events.add(const TurnDone());
    }
  }
  await settle(tester);
}

/// Pumps until the frame stops changing, bounded. Not `pumpAndSettle`: a
/// turn that is still writing shows a spinner forever by design, and that
/// must not hang the test — the test asserts on it instead.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
}
