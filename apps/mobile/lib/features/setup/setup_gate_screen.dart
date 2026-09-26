/// Where sign-up and login land: decides whether the farmer needs first farm
/// setup (design 14 and 16) or can go straight to Home.
///
/// The server creates a farm at sign-up with a default name and no sections,
/// and an observation must belong to a section — so an account whose farm
/// has no sections cannot record anything yet, and is taken through setup. An
/// account that already has sections, logging in on a new phone, goes to Home.
///
/// It waits for the phone's copy of the account's farm, which the sync
/// controller fetches from `GET /farms` as soon as a session exists, and says
/// so calmly rather than guessing. A farm with sections on the phone goes to
/// Home. A farm with none on the phone goes to setup **only if the server
/// confirms it has none** — the phone saves the farm and pulls its sections
/// as two steps, so a pull lost to a bad signal looks exactly like an empty
/// farm, and setup would rename a real one. Unconfirmed goes to Home. A build
/// that authenticates against the local demo has no account farm at all and
/// goes to Home, as it always has.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../data/auth/api_auth_service.dart';
import '../../data/setup/server_sections.dart';
import '../../domain/auth/auth_models.dart';
import '../auth/auth_view_model.dart';
import 'setup_providers.dart';
import 'widgets/farm_on_its_way.dart';

class SetupGateScreen extends ConsumerStatefulWidget {
  const SetupGateScreen({super.key});

  @override
  ConsumerState<SetupGateScreen> createState() => _SetupGateScreenState();
}

class _SetupGateScreenState extends ConsumerState<SetupGateScreen> {
  bool _left = false;

  /// The server's answer for the farm with this id, once asked. Asked at most
  /// once per farm.
  String? _askedFor;
  bool? _serverEmpty;
  bool _answered = false;

  void _ask(String farmId) {
    if (_askedFor == farmId) return;
    _askedFor = farmId;
    _answered = false;
    final auth = ref.read(authServiceProvider);
    final asking = auth is ApiAuthService
        ? serverFarmHasNoSections(auth, farmId)
        : Future<bool?>.value();
    final scope = ref.read(farmScopeProvider);
    final owed = ref.read(setupOwedProvider);
    unawaited(
      asking.then((empty) async {
        // Owed unless the server said there are sections: confirmed empty
        // goes to setup now, and no answer is asked again on a later launch
        // (setup_resumer.dart) rather than never.
        if (empty == false) {
          await owed.settle(scope.ownerId, farmId);
        } else {
          await owed.owe(scope.ownerId, farmId);
        }
        if (!mounted || _askedFor != farmId) return;
        setState(() {
          _serverEmpty = empty;
          _answered = true;
        });
      }),
    );
  }

  /// Where to go, or null while the answer is still on its way.
  String? _destination() {
    final auth = ref.watch(authViewModelProvider);
    if (!auth.hasValue) return null;
    final standing = auth.value;
    if (standing is! SignedIn) return '/home';
    if (ref.watch(syncControllerProvider) == null) return '/home';
    if (ref.watch(awaitingAccountFarmProvider)) return null;

    final scope = ref.watch(farmScopeProvider);
    final farm = ref.watch(farmProvider).value;
    // The stream re-subscribes when the scope changes; an emission for the
    // previous scope's farm is not an answer about this one.
    if (farm == null || farm.farm.id != scope.farmId) return null;
    if (farm.sections.isNotEmpty) return '/home';

    _ask(scope.farmId);
    if (!_answered) return null;
    return _serverEmpty == true ? '/setup/farm' : '/home';
  }

  @override
  Widget build(BuildContext context) {
    final destination = _destination();
    if (destination == null) return const FarmOnItsWay();
    if (!_left) {
      _left = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go(destination);
      });
    }
    // One plain frame on the way past, rather than a flash of the waiting
    // copy for a farm that was never waited on.
    return Scaffold(backgroundColor: context.semantic.background);
  }
}
