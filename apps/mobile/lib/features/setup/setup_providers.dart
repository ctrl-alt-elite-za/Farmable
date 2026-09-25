/// First launch and first farm setup — issue #89.
///
/// Kept beside the setup screens rather than in `app/providers.dart`, so the
/// whole feature is one folder and nothing it adds has to be merged into a
/// file other branches are editing.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/launch/launch_record.dart';
import '../../domain/auth/auth_models.dart';
import '../auth/auth_view_model.dart';

/// Whether this install has been through the first-launch journey. See
/// `data/launch/launch_record.dart` for where that is kept and why.
final launchRecordProvider = Provider<LaunchRecord>(
  (ref) => LaunchRecord.onDevice(),
);

/// A signed-in farmer whose own farm has not reached this phone yet.
///
/// Only possible in a build that talks to the real API: the sync controller
/// asks `GET /farms` once a session exists, and until it answers the screens
/// still show the demo scope. Nothing may be written in that window — a
/// section created then would land in the demo farm, not the farmer's.
///
/// A build that authenticates against the local demo has no account farm to
/// wait for; it never is in this state.
final awaitingAccountFarmProvider = Provider<bool>((ref) {
  final standing = ref.watch(authViewModelProvider).value;
  if (standing is! SignedIn) return false;
  if (ref.watch(syncControllerProvider) == null) return false;
  final scope = ref.watch(farmScopeProvider);
  return !scope.isAccount || scope.ownerId != standing.session.user.id;
});
