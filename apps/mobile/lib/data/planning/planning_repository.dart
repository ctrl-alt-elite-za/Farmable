/// The account planner's data: backend previews, a private phone cache of the
/// last good answer, and the confirmations waiting to be sent (#22).
///
/// The backend owns the calculation (#21). The phone keeps two things:
///
/// * the last preview the backend returned for a question, so the same
///   question asked offline gets that answer back, labelled with its age;
/// * confirmed plan versions, written the moment the farmer confirms and
///   sent when there is a signal, each with its own `mutation_id` so a
///   resend after a dropped reply is replayed by the server, not duplicated.
///
/// Nothing is written before the farmer confirms. A preview is a cached
/// answer to a question, never a plan.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/utils/ids.dart';
import '../../domain/planning/plan_preview.dart';
import '../auth/api_auth_service.dart';

/// Why a planning request got no answer.
class PlanningFailure implements Exception {
  /// The backend's error code (`outlook_unavailable`, `plan_stale`, ...), or
  /// `unreachable` when no answer arrived at all.
  final String code;
  final int? status;

  const PlanningFailure(this.code, {this.status});

  /// A refusal the server made on purpose. Resending the same body will get
  /// the same answer, so a queued confirmation that gets one is rejected
  /// rather than retried. A lapsed session (401) or a rate limit (429) is
  /// neither: those wait.
  bool get isRejection => const {404, 409, 422}.contains(status);

  @override
  String toString() => 'PlanningFailure($code)';
}

class PlanReceipt {
  final String planId;
  final int version;
  final bool replayed;

  const PlanReceipt(this.planId, this.version, {required this.replayed});
}

abstract interface class PlanningClient {
  /// The preview exactly as the server sent it. The repository parses it and
  /// caches these bytes, not a re-serialisation of the phone's reading.
  Future<Map<String, Object?>> preview(String farmId, PlanInputs inputs);
  Future<PlanReceipt> confirm(String farmId, PlanVersion version);
}

class ApiPlanningClient implements PlanningClient {
  final ApiAuthService auth;

  const ApiPlanningClient(this.auth);

  @override
  Future<Map<String, Object?>> preview(String farmId, PlanInputs inputs) =>
      _send('/farms/$farmId/planning/preview', inputs.toJson());

  @override
  Future<PlanReceipt> confirm(String farmId, PlanVersion version) async {
    final data = await _send('/farms/$farmId/planning/confirm', {
      'mutation_id': version.mutationId,
      'plan_id': version.planId,
      'expected_version': version.expectedVersion,
      'confirmed': true,
      'request': version.request.toJson(),
      'snapshot_hash': version.snapshotHash,
      'candidate_id': version.candidateId,
    });
    final id = data['id'];
    final number = data['version'];
    final replayed = data['replayed'];
    if (id is! String || number is! int || replayed is! bool) {
      throw const FormatException('confirmed_plan');
    }
    return PlanReceipt(id, number, replayed: replayed);
  }

  Future<Map<String, Object?>> _send(String path, Object body) async {
    final Object? data;
    final int status;
    try {
      final response = await auth.authorized('POST', path, data: body);
      status = response.statusCode ?? 0;
      data = response.data;
    } on Object {
      throw const PlanningFailure('unreachable');
    }
    if (status < 200 || status >= 300) {
      final error = data is Map ? data['error'] : null;
      final code = error is Map ? error['code'] : null;
      throw PlanningFailure(
        code is String ? code : 'http_$status',
        status: status,
      );
    }
    if (data is! Map) throw const FormatException('planning');
    return data.cast<String, Object?>();
  }
}

enum PlanVersionState { waiting, saved, rejected }

/// One confirmed plan version, as the phone keeps it.
class PlanVersion {
  final String mutationId;
  final String planId;
  final String sectionId;
  final int expectedVersion;
  final PlanInputs request;
  final String snapshotHash;
  final String candidateId;

  /// What the farmer saw when they confirmed, for the history list.
  final String summary;
  final DateTime confirmedAt;
  final PlanVersionState state;

  /// The server's version number once saved.
  final int? savedVersion;

  /// The server's reason, when it refused this version.
  final String? rejection;

  const PlanVersion({
    required this.mutationId,
    required this.planId,
    required this.sectionId,
    required this.expectedVersion,
    required this.request,
    required this.snapshotHash,
    required this.candidateId,
    required this.summary,
    required this.confirmedAt,
    this.state = PlanVersionState.waiting,
    this.savedVersion,
    this.rejection,
  });

  PlanVersion settled({int? savedVersion, String? rejection}) => PlanVersion(
    mutationId: mutationId,
    planId: planId,
    sectionId: sectionId,
    expectedVersion: expectedVersion,
    request: request,
    snapshotHash: snapshotHash,
    candidateId: candidateId,
    summary: summary,
    confirmedAt: confirmedAt,
    state: rejection != null
        ? PlanVersionState.rejected
        : PlanVersionState.saved,
    savedVersion: savedVersion,
    rejection: rejection,
  );

  Map<String, Object?> toJson() => {
    'mutation_id': mutationId,
    'plan_id': planId,
    'section_id': sectionId,
    'expected_version': expectedVersion,
    'request': request.toJson(),
    'snapshot_hash': snapshotHash,
    'candidate_id': candidateId,
    'summary': summary,
    'confirmed_at': confirmedAt.toUtc().toIso8601String(),
    'state': state.name,
    'saved_version': savedVersion,
    'rejection': rejection,
  };

  factory PlanVersion.fromJson(Map<String, Object?> json) => PlanVersion(
    mutationId: json['mutation_id']! as String,
    planId: json['plan_id']! as String,
    sectionId: json['section_id']! as String,
    expectedVersion: json['expected_version']! as int,
    request: PlanInputs.fromJson(
      (json['request']! as Map).cast<String, Object?>(),
    ),
    snapshotHash: json['snapshot_hash']! as String,
    candidateId: json['candidate_id']! as String,
    summary: json['summary']! as String,
    confirmedAt: DateTime.parse(json['confirmed_at']! as String).toUtc(),
    state: PlanVersionState.values.byName(json['state']! as String),
    savedVersion: json['saved_version'] as int?,
    rejection: json['rejection'] as String?,
  );

  /// What the farmer is told when the server refused this version.
  String get rejectionMessage => switch (rejection) {
    'plan_stale' || 'plan_candidate_unavailable' =>
      'The outlook changed before this reached the server. Ask again and '
          'confirm the new answer.',
    'revision_conflict' || 'plan_state_changed' =>
      'This plan was changed from another phone. Ask again to see the '
          'latest.',
    'outlook_unavailable' =>
      'Planning was unavailable on the server. Ask again later.',
    null => '',
    _ => 'The server did not accept this plan. Ask again to start over.',
  };
}

/// Where the planner keeps its answers. One JSON file per account and kind.
abstract interface class PlanningStore {
  Future<SavedPreview?> readPreview(String accountId, String cacheKey);
  Future<void> writePreview(String accountId, SavedPreview saved);
  Future<List<PlanVersion>> readVersions(String accountId);
  Future<void> writeVersions(String accountId, List<PlanVersion> versions);
  Future<void> forget(String accountId);
}

class SavedPreview {
  final PlanPreview value;

  /// The request exactly as sent, so a cache hit can be checked against it.
  final String cacheKey;
  final Map<String, Object?> raw;
  final DateTime fetchedAt;

  const SavedPreview(this.value, this.cacheKey, this.raw, this.fetchedAt);
}

/// `planning/` under the app's support directory. Listed in
/// `deviceDirectoriesProvider`, so account deletion empties it.
Future<Directory> planningCacheDirectory() async =>
    Directory('${(await getApplicationSupportDirectory()).path}/planning');

class FilePlanningStore implements PlanningStore {
  final Future<Directory> Function() _directory;

  FilePlanningStore({Future<Directory> Function()? directory})
    : _directory = directory ?? planningCacheDirectory;

  Future<Directory> _account(String accountId) async {
    final base = await _directory();
    final key = sha256.convert(utf8.encode(accountId));
    return Directory('${base.path}/$key');
  }

  Future<File> _preview(String accountId, String cacheKey) async {
    final dir = await _account(accountId);
    final key = sha256.convert(utf8.encode(cacheKey));
    return File('${dir.path}/preview-$key.json');
  }

  Future<File> _versions(String accountId) async =>
      File('${(await _account(accountId)).path}/versions.json');

  @override
  Future<SavedPreview?> readPreview(String accountId, String cacheKey) async {
    try {
      final file = await _preview(accountId, cacheKey);
      if (!await file.exists()) return null;
      final record = (jsonDecode(await file.readAsString()) as Map)
          .cast<String, Object?>();
      if (record['account_id'] != accountId || record['key'] != cacheKey) {
        return null;
      }
      final raw = (record['preview']! as Map).cast<String, Object?>();
      return SavedPreview(
        PlanPreview.fromJson(raw),
        cacheKey,
        raw,
        DateTime.parse(record['fetched_at']! as String).toUtc(),
      );
    } on Object {
      // A partial or unreadable cache is no answer, never a plan.
      return null;
    }
  }

  @override
  Future<void> writePreview(String accountId, SavedPreview saved) async {
    final file = await _preview(accountId, saved.cacheKey);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'account_id': accountId,
        'key': saved.cacheKey,
        'fetched_at': saved.fetchedAt.toUtc().toIso8601String(),
        'preview': saved.raw,
      }),
      flush: true,
    );
  }

  @override
  Future<List<PlanVersion>> readVersions(String accountId) async {
    final file = await _versions(accountId);
    if (!await file.exists()) return const [];
    final decoded = jsonDecode(await file.readAsString());
    return [
      for (final item in decoded as List)
        PlanVersion.fromJson((item as Map).cast<String, Object?>()),
    ];
  }

  @override
  Future<void> writeVersions(
    String accountId,
    List<PlanVersion> versions,
  ) async {
    final file = await _versions(accountId);
    await file.parent.create(recursive: true);
    // Written to a sibling and renamed, so a kill mid-write leaves the old
    // list rather than half of a new one: this file holds unsent work.
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      jsonEncode([for (final v in versions) v.toJson()]),
      flush: true,
    );
    await temp.rename(file.path);
  }

  @override
  Future<void> forget(String accountId) async {
    final dir = await _account(accountId);
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

enum PreviewSource { fresh, savedOffline, savedAfterRequest, unavailable }

class PreviewResult {
  final SavedPreview? saved;
  final PreviewSource source;

  /// Why there is no fresh answer, when the backend said.
  final String? failure;

  const PreviewResult(this.saved, this.source, {this.failure});

  PlanPreview? get preview => saved?.value;
}

class PlanningRepository {
  final PlanningClient client;
  final PlanningStore store;
  final DateTime Function() now;

  /// The section's plan as last synced from the server, if the phone has
  /// one: its id and version. Used when this phone holds no version of its
  /// own for the section — after sign-out, or on a new phone — so a
  /// confirmation revises that plan instead of starting a second one.
  final Future<({String planId, int version})?> Function(String sectionId)?
  knownPlan;

  PlanningRepository(
    this.client,
    this.store, {
    required this.now,
    this.knownPlan,
  });

  /// Every read-modify-write of the version list runs here, one at a time.
  /// A send waits on the network between reading the list and writing it;
  /// without this, a confirmation made meanwhile would be overwritten.
  Future<void> _versionWrites = Future.value();

  Future<T> _exclusive<T>(Future<T> Function() body) {
    final result = _versionWrites.then((_) => body());
    _versionWrites = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  Future<void> _replace(String accountId, PlanVersion settled) => _exclusive(
    () async {
      final versions = [...await store.readVersions(accountId)];
      final i = versions.indexWhere((v) => v.mutationId == settled.mutationId);
      if (i < 0) return;
      versions[i] = settled;
      await store.writeVersions(accountId, versions);
    },
  );

  Future<PreviewResult> preview({
    required String accountId,
    required String farmId,
    required PlanInputs inputs,
    required bool online,
  }) async {
    String? failure;
    if (online) {
      try {
        final raw = await client.preview(farmId, inputs);
        final value = PlanPreview.fromJson(raw);
        if (value.request.cacheKey != inputs.cacheKey) {
          throw const FormatException('preview_query_mismatch');
        }
        final saved = SavedPreview(value, inputs.cacheKey, raw, now().toUtc());
        try {
          await store.writePreview(accountId, saved);
        } on Object {
          // A full phone still shows the fresh answer on this visit.
        }
        return PreviewResult(saved, PreviewSource.fresh);
      } on PlanningFailure catch (error) {
        failure = error.code;
      } on Object {
        failure = 'unreadable';
      }
    }
    final saved = await store.readPreview(accountId, inputs.cacheKey);
    if (saved == null) {
      return PreviewResult(null, PreviewSource.unavailable, failure: failure);
    }
    return PreviewResult(
      saved,
      online ? PreviewSource.savedAfterRequest : PreviewSource.savedOffline,
      failure: failure,
    );
  }

  /// Records the farmer's confirmation, then tries to send it.
  ///
  /// The version is on disk before any request is made, so a confirmation
  /// made in airplane mode — or one whose reply is lost — is still there on
  /// the next launch. Calling this twice with the same [mutationId] keeps one
  /// version: the second call only retries the send.
  Future<PlanVersion> confirm({
    required String accountId,
    required String farmId,
    required String mutationId,
    required PlanPreview preview,
    required PlanCandidate candidate,
    required String summary,
    required bool online,
  }) async {
    final sectionId = preview.request.sectionId;
    // Read before taking the lock: the synced plan never depends on it.
    final known = knownPlan == null ? null : await knownPlan!(sectionId);
    await _exclusive(() async {
      final versions = [...await store.readVersions(accountId)];
      if (versions.any((v) => v.mutationId == mutationId)) return;
      final previous = versions.reversed
          .where(
            (v) =>
                v.sectionId == sectionId &&
                v.state != PlanVersionState.rejected,
          )
          .firstOrNull;
      // The version this one replaces: the server's number once known, the
      // number a still-waiting predecessor will get when it lands, or the
      // synced plan's version when this phone has none of its own.
      final expected = previous == null
          ? known?.version ?? 0
          : previous.savedVersion ?? previous.expectedVersion + 1;
      versions.add(
        PlanVersion(
          mutationId: mutationId,
          planId: previous?.planId ?? known?.planId ?? newUuid(),
          sectionId: sectionId,
          expectedVersion: expected,
          request: preview.request,
          snapshotHash: preview.snapshotHash,
          candidateId: candidate.id,
          summary: summary,
          confirmedAt: now().toUtc(),
        ),
      );
      await store.writeVersions(accountId, versions);
    });
    await send(accountId: accountId, farmId: farmId, online: online);
    return (await store.readVersions(accountId))
        .firstWhere((v) => v.mutationId == mutationId);
  }

  /// Sends every waiting version, oldest first. Stops at the first one that
  /// gets no answer, so a later version never overtakes an earlier one.
  Future<void> send({
    required String accountId,
    required String farmId,
    required bool online,
  }) async {
    if (!online) return;
    final waiting = [
      for (final v in await store.readVersions(accountId))
        if (v.state == PlanVersionState.waiting) v,
    ];
    for (final version in waiting) {
      PlanVersion settled;
      try {
        final receipt = await client.confirm(farmId, version);
        settled = version.settled(savedVersion: receipt.version);
      } on PlanningFailure catch (error) {
        if (!error.isRejection) break;
        settled = version.settled(rejection: error.code);
      } on Object {
        break;
      }
      // Only this version's entry changes; anything confirmed while the
      // request was out stays in the list.
      await _replace(accountId, settled);
    }
  }

  Future<List<PlanVersion>> history(String accountId, String sectionId) async =>
      [
        for (final v in (await store.readVersions(accountId)).reversed)
          if (v.sectionId == sectionId) v,
      ];

  /// Called on sign-out: drops every saved answer and settled version for
  /// [accountId]. Versions still waiting to be sent are the farmer's unsent
  /// work, kept like the rest of their queue (#17) and sent when they next
  /// sign in; nothing of theirs is ever shown to another account.
  Future<void> signedOut(String accountId) => _exclusive(() async {
    final waiting = [
      for (final v in await store.readVersions(accountId))
        if (v.state == PlanVersionState.waiting) v,
    ];
    await store.forget(accountId);
    if (waiting.isNotEmpty) await store.writeVersions(accountId, waiting);
  });
}
