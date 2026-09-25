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

import '../features/account/account_screen.dart';
import '../features/account/delete_account_screen.dart';
import '../features/account/edit_details_screen.dart';
import '../features/account/export_screen.dart';
import '../features/account/privacy_screen.dart';
import '../features/auth/auth_choice_screen.dart';
import '../features/auth/brand_intro_screen.dart';
import '../features/auth/forgot_password_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/onboarding_screen.dart';
import '../features/auth/reset_password_screen.dart';
import '../features/auth/sign_up_screen.dart';
import '../features/auth/verify_screen.dart';
import '../features/farm/farm_map_screen.dart';
import '../features/farm/farm_screen.dart';
import '../features/home/home_screen.dart';
import '../features/placeholder/not_built_yet_screen.dart';
import '../features/recommendations/recommendation_detail_screen.dart';
import '../features/recommendations/recommendations_screen.dart';
import '../features/self_test/self_test_screen.dart';
import '../features/shell/bottom_nav_island.dart';
import '../features/status/status_screen.dart';
import '../features/zone/zone_screen.dart';
import 'config.dart';

/// [initialLocation] is for tests, which pump a screen directly rather than
/// tapping their way to it. A build overrides the same thing with
/// `INITIAL_ROUTE` — see [initialRoute] for why a cold launch still opens on
/// Home.
GoRouter buildRouter({String? initialLocation}) => GoRouter(
  initialLocation: initialLocation ?? initialRoute,
  routes: [
    GoRoute(path: '/', redirect: (_, _) => '/home'),

    // ---------------------------------------------------------------- auth
    //
    // Launch, onboarding and authentication — guide §§4-11. Kept together as
    // one block so it stays easy to read next to the farm routes below, and
    // easy to resolve if two branches add routes at once.
    //
    // NOTHING BELOW THIS BLOCK IS GATED ON A SESSION, and that is deliberate.
    // The seeded demo farm has no user, and Home and Zone Detail have to open
    // without one. Authentication decides which auth screen comes next, never
    // whether the farm is allowed to draw.
    GoRoute(path: '/splash', builder: (_, _) => const BrandIntroScreen()),
    GoRoute(
      path: '/onboarding',
      builder: (context, _) => OnboardingScreen(
        // Skip and Get started go to the same place, per guide §6.
        onFinished: () => GoRouter.of(context).go('/auth'),
      ),
    ),
    GoRoute(
      path: '/auth',
      builder: (_, _) => const AuthChoiceScreen(),
      routes: [
        GoRoute(path: 'signup', builder: (_, _) => const SignUpScreen()),
        GoRoute(path: 'verify', builder: (_, _) => const VerifyScreen()),
        GoRoute(path: 'login', builder: (_, _) => const LoginScreen()),
        GoRoute(
          path: 'forgot-password',
          builder: (_, _) => const ForgotPasswordScreen(),
        ),
        GoRoute(
          path: 'reset-password',
          builder: (_, _) => const ResetPasswordScreen(),
        ),
      ],
    ),
    // ------------------------------------------------------------ end auth

    GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),

    GoRoute(
      path: '/farm',
      // Sections mode by default — what Home's "See all" promises — and map
      // mode at `/farm?view=map`.
      builder: (_, state) => FarmScreen(
        initialMode: state.uri.queryParameters['view'] == 'map'
            ? FarmTabMode.map
            : FarmTabMode.sections,
      ),
      routes: [
        GoRoute(path: 'map', builder: (_, _) => const FarmMapScreen()),
        GoRoute(
          path: 'zone/:zoneId',
          builder: (context, state) =>
              ZoneScreen(sectionId: state.pathParameters['zoneId']!),
          routes: [
            // "What should I plant here?" — deep-linkable like every other
            // screen. The planner is pure and the section is on disk, so
            // arriving cold at this URL with no network still answers.
            GoRoute(
              path: 'plant',
              builder: (context, state) => RecommendationsScreen(
                sectionId: state.pathParameters['zoneId']!,
              ),
              routes: [
                GoRoute(
                  path: ':crop',
                  builder: (context, state) => RecommendationDetailScreen(
                    sectionId: state.pathParameters['zoneId']!,
                    cropName: state.pathParameters['crop']!,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    ),

    GoRoute(
      path: '/insights',
      builder: (_, _) => const NotBuiltYetScreen(
        destination: NavDestination.insights,
        title: 'Insights',
        body:
            'Health, money and market prices over time. Every record you '
            'add now is what these will be built from.',
      ),
    ),
    // Who is signed in, and Log out. Never a gate: it reads the session, it
    // does not require one.
    GoRoute(
      path: '/profile',
      builder: (_, _) => const AccountScreen(),
      routes: [
        GoRoute(path: 'edit', builder: (_, _) => const EditDetailsScreen()),
        GoRoute(path: 'privacy', builder: (_, _) => const PrivacyScreen()),
        GoRoute(path: 'export', builder: (_, _) => const ExportScreen()),
        GoRoute(path: 'delete', builder: (_, _) => const DeleteAccountScreen()),
      ],
    ),

    // Kept, and kept working: `e2e/mobile/*.yaml` drive this screen, and it is
    // the one place the app states plainly whether it can reach its API.
    GoRoute(path: '/status', builder: (_, _) => const StatusScreen()),

    // ------------------------------------------------------------ self-test
    //
    // Issue #4's device self-test. Its own block at the end of the table so a
    // branch adding routes above does not collide with it. Reached from the
    // Status screen, or directly with --dart-define=INITIAL_ROUTE=/self-test.
    // Nothing on it asks for a permission until the person taps Run.
    GoRoute(path: '/self-test', builder: (_, _) => const SelfTestScreen()),
    // -------------------------------------------------------- end self-test
  ],
  errorBuilder: (context, state) => NotBuiltYetScreen(
    destination: NavDestination.home,
    title: 'Nothing here',
    body: 'That link does not go anywhere in this version of the app.',
    onBack: () => GoRouter.of(context).go('/home'),
  ),
);
