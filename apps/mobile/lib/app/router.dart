/// The route table.
///
/// Routes follow guide §4 and are deep-linkable — a path is enough to reach a
/// screen, with no state to carry from the one before it. That is a property
/// of the architecture rather than a feature: every screen reads its own data
/// from local storage by id, so arriving cold and arriving by tap are the same
/// code path.
///
/// There is no `StatefulShellRoute`. The design's nav island floats *over*
/// content that scrolls beneath it, and Zone Detail is opened from Home with a
/// hero transition. Both want the screens in one navigator, so the shell is a
/// widget each screen wraps itself in rather than a route that wraps them.
library;

import 'package:go_router/go_router.dart';

import '../features/auth/auth_gate.dart';
import '../features/home/home_screen.dart';
import '../features/placeholder/not_built_yet_screen.dart';
import '../features/shell/bottom_nav_island.dart';
import '../features/status/status_screen.dart';
import '../features/zone/zone_screen.dart';

GoRouter buildRouter() => GoRouter(
  initialLocation: '/home',
  routes: [
    GoRoute(path: '/', redirect: (_, _) => '/home'),
    GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),

    GoRoute(
      path: '/farm',
      builder: (_, _) => const AuthGate(
        child: NotBuiltYetScreen(
          destination: NavDestination.farm,
          title: 'Farm',
          body:
              'The map and the full list of sections live here. For now, open '
              'a section from the carousel on Home.',
        ),
      ),
      routes: [
        GoRoute(
          path: 'map',
          builder: (_, _) => const AuthGate(
            child: NotBuiltYetScreen(
              destination: NavDestination.farm,
              title: 'Farm map',
              body:
                  'Walking your boundaries with the camera is being built. '
                  'Your sections and their areas are already saved on this '
                  'phone.',
            ),
          ),
        ),
        GoRoute(
          path: 'zone/:zoneId',
          builder: (context, state) => AuthGate(
            child: ZoneScreen(sectionId: state.pathParameters['zoneId']!),
          ),
        ),
      ],
    ),

    GoRoute(
      path: '/insights',
      builder: (_, _) => const AuthGate(
        child: NotBuiltYetScreen(
          destination: NavDestination.insights,
          title: 'Insights',
          body:
              'Health, money and market prices over time. Every record you '
              'add now is what these will be built from.',
        ),
      ),
    ),
    GoRoute(
      path: '/profile',
      builder: (_, _) => const AuthGate(
        child: NotBuiltYetScreen(
          destination: NavDestination.profile,
          title: 'Profile',
          body:
              'Your details, your privacy choices and what the app is allowed '
              'to use. Being built.',
        ),
      ),
    ),

    // Kept, and kept working: `e2e/mobile/*.yaml` drive this screen, and it is
    // the one place the app states plainly whether it can reach its API.
    GoRoute(path: '/status', builder: (_, _) => const StatusScreen()),
  ],
  errorBuilder: (context, state) => NotBuiltYetScreen(
    destination: NavDestination.home,
    title: 'Nothing here',
    body: 'That link does not go anywhere in this version of the app.',
    onBack: () => GoRouter.of(context).go('/home'),
  ),
);
