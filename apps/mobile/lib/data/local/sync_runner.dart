import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'database.dart';
import 'sync_outbox.dart';

enum DeliveryFailure { transient, validation, conflict, auth, missingMedia }

class SyncFailure implements Exception {
  const SyncFailure(this.kind);
  final DeliveryFailure kind;
}

class SyncAcknowledgement {
  const SyncAcknowledgement({
    required this.mutationId,
    required this.recordId,
    required this.ownerId,
    required this.farmId,
    this.cloudMediaId,
  });
  final String mutationId, recordId, ownerId, farmId;
  final String? cloudMediaId;
}

/// The payload is an immutable JSON snapshot; the private local URI is a file
/// handle for upload only, never part of JSON sent to the server.
class SyncDelivery {
  const SyncDelivery(this.mutation, {this.photoUri, this.cloudMediaId});
  final SyncMutation mutation;
  final Uri? photoUri;
  final String? cloudMediaId;
}

class SyncCancellation {
  final _cancelled = Completer<void>();
  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get cancelled => _cancelled.future;
  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }
}

abstract interface class SyncTransport {
  /// Adapters must abort IO on cancellation. A non-cooperative adapter retains
  /// the physical slot until it settles; the runner will not fan out retries.
  Future<SyncAcknowledgement> send(
    SyncDelivery delivery,
    SyncCancellation cancel,
  );
}

Duration retryDelay(int attempt, double random) => Duration(
  milliseconds:
      (min(300000, 2000 * pow(2, min(20, max(0, attempt - 1)))) *
              (0.5 + random.clamp(0, 1) / 2))
          .round(),
);

/// No transport is installed by the demo app. Connectivity alone is not proof
/// that a record was synced. Credentials and lifecycle are explicit inputs.
class SyncRunner {
  SyncRunner._(
    this.outbox, {
    this.transport,
    required this.photoUri,
    DateTime Function()? now,
    double Function()? random,
    this.timeout = const Duration(seconds: 30),
    this.onError,
  }) : now = now ?? DateTime.now,
       random = random ?? Random().nextDouble;

  static final _owners = Expando<SyncRunner>();

  static Future<SyncRunner> open(
    SyncOutbox outbox, {
    SyncTransport? transport,
    required Future<Uri> Function(LocalPhoto) photoUri,
    DateTime Function()? now,
    double Function()? random,
    Duration timeout = const Duration(seconds: 30),
    void Function(String)? onError,
  }) async {
    if (_owners[outbox.db] != null) throw StateError('session_already_open');
    final runner = SyncRunner._(
      outbox,
      transport: transport,
      photoUri: photoUri,
      now: now,
      random: random,
      timeout: timeout,
      onError: onError,
    );
    _owners[outbox.db] = runner;
    try {
      await outbox.recover();
      runner._subscription = outbox.watch().listen(
        (_) => runner.wake(),
        onError: (Object _) => onError?.call('queue_storage_error'),
      );
      return runner;
    } catch (_) {
      _owners[outbox.db] = null;
      rethrow;
    }
  }

  final SyncOutbox outbox;
  final SyncTransport? transport;
  final Future<Uri> Function(LocalPhoto) photoUri;
  final DateTime Function() now;
  final double Function() random;
  final Duration timeout;
  final void Function(String)? onError;
  StreamSubscription<List<SyncMutation>>? _subscription;
  Timer? _timer;
  Future<void>? _running;
  Future<SyncAcknowledgement>? _physical;
  SyncCancellation? _cancel;
  bool _online = false, _foreground = false, _authenticated = false;
  bool _authPaused = false, _stopped = false;
  int _generation = 0;

  bool get _ready =>
      !_stopped &&
      transport != null &&
      _online &&
      _foreground &&
      _authenticated &&
      !_authPaused;

  void setConditions({
    required bool online,
    required bool foreground,
    required bool authenticated,
  }) {
    if (!_authenticated && authenticated) _authPaused = false;
    _online = online;
    _foreground = foreground;
    _authenticated = authenticated;
    if (!_ready) {
      _generation++;
      _cancel?.cancel();
    }
    wake();
  }

  void credentialsUpdated() {
    _authPaused = false;
    wake();
  }

  void wake() {
    _timer?.cancel();
    if (!_ready || _running != null || _physical != null) return;
    _running = _cycle();
  }

  Future<void> _cycle() async {
    try {
      await _drain();
      if (_ready && _physical == null) {
        final due = await outbox.nextDue();
        if (due != null && _ready) {
          _timer = Timer(
            Duration(
              milliseconds: due
                  .difference(now())
                  .inMilliseconds
                  .clamp(10, 300000),
            ),
            wake,
          );
        }
      }
    } catch (_) {
      onError?.call('queue_storage_error');
    } finally {
      _running = null;
    }
  }

  Future<void> _drain() async {
    while (_ready && _physical == null) {
      final generation = _generation;
      final row = await outbox.claim(now());
      if (row == null) return;
      try {
        Uri? uri;
        String? cloudId;
        final body = jsonDecode(row.payload!) as Map<String, dynamic>;
        final mediaId = row.recordType == 'media'
            ? row.recordId
            : body['localMediaId'] as String?;
        if (mediaId != null) {
          final media = await outbox.photo(mediaId);
          if (media == null) {
            throw const SyncFailure(DeliveryFailure.missingMedia);
          }
          if (row.recordType == 'media') {
            try {
              uri = await photoUri(media);
            } catch (_) {
              throw const SyncFailure(DeliveryFailure.missingMedia);
            }
          } else {
            cloudId = media.cloudId;
            if (cloudId == null) {
              throw const SyncFailure(DeliveryFailure.validation);
            }
          }
        }
        if (!_ready || generation != _generation) throw const _Cancelled();
        final ack = await _deliver(
          SyncDelivery(row, photoUri: uri, cloudMediaId: cloudId),
        );
        if (!_ready || generation != _generation) throw const _Cancelled();
        if (ack.mutationId != row.mutationId ||
            ack.recordId != row.recordId ||
            ack.ownerId != outbox.ownerId ||
            ack.farmId != outbox.farmId ||
            (row.recordType == 'media' && !isUuid(ack.cloudMediaId ?? ''))) {
          throw const SyncFailure(DeliveryFailure.validation);
        }
        await outbox.acknowledge(row, now(), cloudId: ack.cloudMediaId);
      } catch (error) {
        if (error is _Cancelled || !_ready || generation != _generation) {
          await outbox.release(
            row,
            'pending',
            'cancelled',
            now(),
            refund: true,
          );
          continue;
        }
        final kind = error is SyncFailure
            ? error.kind
            : DeliveryFailure.transient;
        if (kind == DeliveryFailure.auth) {
          _authPaused = true;
          await outbox.release(
            row,
            'pending',
            'auth_required',
            now(),
            refund: true,
          );
        } else {
          final retry =
              kind == DeliveryFailure.transient && row.budgetCount < 8;
          final state = kind == DeliveryFailure.conflict
              ? 'conflict'
              : retry
              ? 'pending'
              : 'failed';
          await outbox.release(
            row,
            state,
            kind.name,
            retry ? now().add(retryDelay(row.budgetCount, random())) : now(),
          );
        }
      }
    }
  }

  Future<SyncAcknowledgement> _deliver(SyncDelivery delivery) async {
    final cancellation = SyncCancellation();
    _cancel = cancellation;
    final deadline = Completer<SyncAcknowledgement>();
    final timer = Timer(timeout, () {
      deadline.completeError(const SyncFailure(DeliveryFailure.transient));
      cancellation.cancel();
    });
    final physical = Future<SyncAcknowledgement>.sync(
      () => transport!.send(delivery, cancellation),
    );
    _physical = physical;
    // Attach both handlers so a late failure is consumed, not an unhandled error.
    void settled() {
      _physical = null;
      if (_stopped && _running == null && identical(_owners[outbox.db], this)) {
        _owners[outbox.db] = null;
      }
      wake();
    }

    unawaited(
      physical.then((_) => settled(), onError: (Object _) => settled()),
    );
    try {
      return await Future.any([
        physical,
        deadline.future,
        cancellation.cancelled.then<SyncAcknowledgement>(
          (_) => throw const _Cancelled(),
        ),
      ]);
    } finally {
      timer.cancel();
      _cancel = null;
    }
  }

  Future<void> stop() async {
    _stopped = true;
    _generation++;
    _timer?.cancel();
    _cancel?.cancel();
    await _subscription?.cancel();
    await _running;
    if (_physical == null && identical(_owners[outbox.db], this)) {
      _owners[outbox.db] = null;
    }
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}
