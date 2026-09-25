/// Where sign-up and login land: decides whether the farmer needs first farm
/// setup (design 14 and 16) or can go straight to Home.
///
/// The server creates a farm at sign-up with a default name and no sections,
/// and an observation must belong to a section — so an account whose farm
/// has no sections cannot record anything yet, and is taken through setup. An
/// account that already has sections, logging in on a new phone, goes to Home.
///
/// It decides from the phone's copy of the account's farm, which the sync
/// controller fetches from `GET /farms` as soon as a session exists. Until
/// that has arrived there is nothing to decide from, and the screen says so
/// calmly rather than guessing. A build that authenticates against the local
/// demo has no account farm at all and goes to Home, as it always has.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/app_theme.dart';
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
    return farm.sections.isEmpty ? '/setup/farm' : '/home';
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
