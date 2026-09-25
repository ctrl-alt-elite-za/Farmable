/// Runs the sync queue for whoever is signed in, and for nobody else.
///
/// The outbox, runner and transport already exist; this decides *when* they
/// run. It opens a runner for the signed-in account's farm once one is known,
/// feeds it the three conditions the runner insists on — a network, the app in
/// the foreground, a session — and stops it, awaiting any send in flight,
/// before a different account's work could be touched.
///
/// Every transition runs one at a time through [_serial], so a logout that
/// lands while a login is still fetching its farm cannot leave the first
/// account's runner open under the second account's session.
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';

import '../../domain/auth/auth_models.dart';
import '../auth/api_auth_service.dart';
import '../local/database.dart';
import '../local/offline_photos.dart';
import '../local/sync_outbox.dart';
import '../local/sync_runner.dart';
import 'account_workspace.dart';
import 'api_sync_transport.dart';

/// Whether the phone reports any network. Not proof the API is reachable —
/// the runner still treats every failed send as a failed send — only a reason
/// not to spend retries while in airplane mode.
abstract interface class NetworkStatus {
  Future<bool> current();
  Stream<bool> get changes;
}

class DeviceNetworkStatus implements NetworkStatus {
  final _connectivity = Connectivity();

  static bool _online(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  @override
  Future<bool> current() async {
    try {
      return _online(await _connectivity.checkConnectivity());
    } on Object {
      // A platform that cannot say is treated as online: sends then fail and
      // back off on their own, which is safe; never sending is not.
      return true;
    }
  }

  @override
  Stream<bool> get changes => _connectivity.onConnectivityChanged
      .map(_online)
      .handleError((Object _) {});
}

typedef PhotoStore = Future<OfflinePhotos> Function({
  required String ownerId,
  required String farmId,
});

class SyncController {
  SyncController({
    required this.db,
    required this.auth,
    required this.network,
    required this.onScope,
    PhotoStore? photos,
    DateTime Function()? now,
    this.sendTimeout = const Duration(minutes: 3),
    this.onError,
    this.storage,
  }) : photos = photos ?? OfflinePhotos.onDevice,
       now = now ?? DateTime.now;

  final AlmanacDatabase db;
  final ApiAuthService auth;
  final NetworkStatus network;

  /// Told which farm the screens should show whenever that changes.
  final void Function(FarmScope scope) onScope;
  final PhotoStore photos;
  final DateTime Function() now;

  /// One send, including a photo's upload and processing, must finish inside
  /// this. Generous, because a 5 MB photo on a weak 3G signal is slow.
  final Duration sendTimeout;

  /// Fixed diagnostic codes only — never a record, token, URL or path.
  final void Function(String code)? onError;

  /// The object-storage client; the transport's own by default.
  final Dio? storage;

  StreamSubscription<bool>? _networkSub;
  Future<void> _tail = Future.value();
  bool _online = true, _foreground = true, _disposed = false;

  AuthUser? _user;
  int? _generation;

  /// The account most recently asked for, set the moment the standing
  /// changes rather than when [_apply] gets to it.
  String? _wanted;
  FarmScope? _scope;
  SyncRunner? _runner;
  SyncOutbox? _outbox;
  OfflinePhotos? _photos;
  StreamSubscription<List<SyncMutation>>? _outboxSub;
  bool _releasing = false;

  /// The account whose runner is open, if any. For tests and diagnostics.
  String? get runningFor => _runner == null ? null : _scope?.ownerId;

  /// Completes once every transition asked for so far has finished.
  Future<void> get idle => _tail;

  Future<void> start() async {
    _online = await network.current();
    _networkSub = network.changes.listen(setOnline);
  }

  /// The farmer's standing changed: signed in, out, or as someone else.
  ///
  /// The previous account's farm leaves the screen now, not once the queued
  /// transition reaches it: stopping a runner waits for any send in flight,
  /// and the farm on screen must never outlast the session it belongs to.
  Future<void> standing(AuthStanding? standing) {
    final user = standing is SignedIn ? standing.session.user : null;
    _wanted = user?.id;
    final shown = _scope;
    if (shown != null && shown.isAccount && shown.ownerId != user?.id) {
      _setScope(FarmScope.demo);
    }
    return _serial(() => _apply(user));
  }

  void setOnline(bool online) {
    if (online == _online) return;
    _online = online;
    _conditions();
    if (online) unawaited(_regained());
  }

  void setForeground(bool foreground) {
    if (foreground == _foreground) return;
    _foreground = foreground;
    _conditions();
    if (foreground) unawaited(_regained());
  }

  Future<void> dispose() async {
    _disposed = true;
    await _networkSub?.cancel();
    await _serial(_close);
  }

  // ------------------------------------------------------------------ guts

  Future<void> _serial(Future<void> Function() work) {
    final next = _tail.then((_) => work()).catchError((Object _) {
      onError?.call('sync_lifecycle_error');
    });
    _tail = next;
    return next;
  }

  Future<void> _apply(AuthUser? user) async {
    final generation = auth.generation;
    final same =
        user != null && user.id == _user?.id && generation == _generation;
    if (same && _runner != null) return;
    if (!same) await _close();
    _user = user;
    _generation = generation;
    if (user == null || _disposed) {
      _setScope(FarmScope.demo);
      return;
    }
    final workspace = _workspace(generation);
    // What this phone already knows opens the account offline; the server is
    // asked only when there is a network to ask it over.
    var scope = await workspace.local(user);
    if (_online) {
      try {
        scope = await workspace.refresh(user) ?? scope;
      } on Object {
        onError?.call('farm_refresh_failed');
      }
    }
    // Signed out, or switched, while the farm was being fetched.
    if (auth.generation != generation || _wanted != user.id || _disposed) {
      return;
    }
    if (scope == null) {
      // No farm known yet: the phone keeps showing the demo, and nothing is
      // queued under this account until the next attempt finds one.
      _setScope(FarmScope.demo);
      return;
    }
    _setScope(scope);
    await _open(scope, generation);
  }

  AccountWorkspace _workspace(int generation) =>
      AccountWorkspace(db, _request(generation), now: now);

  Future<void> _open(FarmScope scope, int generation) async {
    final outbox = SyncOutbox(db, ownerId: scope.ownerId, farmId: scope.farmId);
    final store = await photos(ownerId: scope.ownerId, farmId: scope.farmId);
    await store.recover(now());
    final runner = await SyncRunner.open(
      outbox,
      transport: ApiSyncTransport(
        request: _request(generation),
        outbox: outbox,
        storage: storage,
        now: now,
      ),
      photoUri: store.view,
      now: now,
      timeout: sendTimeout,
      onError: onError,
    );
    _outbox = outbox;
    _photos = store;
    _runner = runner;
    // Every acknowledgement lands in the outbox, so its changes are where a
    // photo the server now holds gets its phone copy released.
    _outboxSub = outbox.watch().listen((_) => unawaited(_release()));
    _conditions();
    unawaited(_release());
  }

  Future<void> _close() async {
    final runner = _runner;
    _runner = null;
    await _outboxSub?.cancel();
    _outboxSub = null;
    _outbox = null;
    _photos = null;
    // Awaited: the previous account's send must settle before anything of
    // the next account's is opened on the same database.
    await runner?.stop();
  }

  void _conditions() => _runner?.setConditions(
    online: _online,
    foreground: _foreground,
    authenticated: true,
  );

  /// Back online or back in front: sends parked for want of a network are
  /// due now, the account's sections are re-read, and an account that had
  /// no farm yet gets another look.
  Future<void> _regained() => _serial(() async {
    final user = _user;
    if (user == null || _disposed || !_online || !_foreground) return;
    if (_runner == null) {
      _generation = null; // Forces a fresh attempt at opening.
      return _apply(user);
    }
    await _outbox?.expedite();
    try {
      await _workspace(_generation!).refresh(user);
    } on Object {
      onError?.call('farm_refresh_failed');
    }
  });

  Future<void> _release() async {
    final outbox = _outbox, store = _photos;
    if (outbox == null || store == null || _releasing) return;
    _releasing = true;
    try {
      await releaseUploaded(outbox, store, now);
    } on Object {
      onError?.call('photo_release_failed');
    } finally {
      _releasing = false;
    }
  }

  void _setScope(FarmScope scope) {
    if (scope == _scope) return;
    _scope = scope;
    onScope(scope);
  }

  AuthorizedRequest _request(int generation) =>
      (method, path, {data, cancelToken}) => auth.authorized(
        method,
        path,
        data: data,
        generation: generation,
        cancelToken: cancelToken,
      );
}
