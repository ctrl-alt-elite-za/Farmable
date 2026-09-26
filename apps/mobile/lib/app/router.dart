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
import '../features/account/security_screen.dart';
import '../features/account/help_screen.dart';
import '../features/auth/auth_choice_screen.dart';
import '../features/auth/brand_intro_screen.dart';
import '../features/auth/forgot_password_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/onboarding_screen.dart';
import '../features/auth/reset_password_screen.dart';
import '../features/auth/sign_up_screen.dart';
import '../features/auth/verify_screen.dart';
import '../features/health/health_screen.dart';
import '../features/crop_scan/crop_scan_screen.dart';
import '../features/farm/farm_map_screen.dart';
import '../features/farm/farm_screen.dart';
import '../features/home/home_screen.dart';
import '../features/insights/insights_screen.dart';
import '../features/insights/market_screen.dart';
import '../features/insights/money_screen.dart';
import '../features/placeholder/not_built_yet_screen.dart';
import '../features/recommendations/recommendation_detail_screen.dart';
import '../features/recommendations/recommendations_screen.dart';
import '../features/self_test/self_test_screen.dart';
import '../features/setup/farm_setup_screen.dart';
import '../features/setup/section_setup_screen.dart';
import '../features/setup/setup_gate_screen.dart';
import '../features/shell/bottom_nav_island.dart';
import '../features/status/status_screen.dart';
import '../features/zone/zone_screen.dart';
import 'config.dart';

/// [initialLocation] is for tests, which pump a screen directly rather than
/// tapping their way to it. A build overrides the same thing with
/// `INITIAL_ROUTE` — see [initialRoute] for how a cold launch is decided.
///
/// [introSeen] answers whether this install has been through the first-launch
/// journey (issue #89). Null — every test that pumps a screen directly —
/// means it has, so `/` goes to Home as it always did.
GoRouter buildRouter({
  String? initialLocation,
  Future<bool> Function()? introSeen,
}) => GoRouter(
  initialLocation: initialLocation ?? initialRoute,
  routes: [
    // A cold launch. A fresh install sees the brand intro, onboarding and
    // auth choice once; every launch after that opens on Home with no taps.
    // Anything that goes wrong reading the answer lands on Home too — the
    // farm opening is the promise, the intro is not.
    GoRoute(
      path: '/',
      redirect: (_, _) async {
        try {
          return await (introSeen?.call() ?? Future.value(true))
              ? '/home'
              : '/splash';
        } on Object {
          return '/home';
        }
      },
    ),

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
    GoRoute(path: '/health/camera', builder: (_, _) => const CropScanScreen()),

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

    GoRoute(path: '/insights', builder: (_, _) => const InsightsScreen()),
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

    // --------------------------------------------------------------- health
    //
    // Issue #92, design screen 25: every section's latest health, worst first.
    // Its own block at the end of the table, like the self-test, so branches
    // adding farm routes above do not collide with it. Reached from Home's
    // "Review health"; reads the farm from disk, so it opens with no signal.
    GoRoute(path: '/health', builder: (_, _) => const HealthScreen()),
    // ----------------------------------------------------------- end health

    // ------------------------------------------------------ insights market
    // Issue #93 first slice: crop outlooks for this account's planted land.
    GoRoute(path: '/insights/market', builder: (_, _) => const MarketScreen()),
    // -------------------------------------------------- end insights market

    // ------------------------------------------------------- insights money
    // Issue #93, design 32: money in and out, from the records on the phone.
    GoRoute(path: '/insights/money', builder: (_, _) => const MoneyScreen()),
    // --------------------------------------------------- end insights money

    // ------------------------------------------------------- issue 94 profile
    GoRoute(
      path: '/profile/security',
      builder: (_, _) => const SecurityScreen(),
    ),
    GoRoute(path: '/profile/help', builder: (_, _) => const HelpScreen()),
    // --------------------------------------------------- end issue 94 profile

    // ---------------------------------------------------------------- setup
    //
    // Issue #89: first farm and first section setup, design 14 and 16. Its own
    // block at the end of the table, like the two above. Sign-up
    // and login land on `/setup`, which sends an account whose farm has no
    // sections through setup and everyone else to Home. `/setup/section` is
    // also the one place a section is added, so the Farm tab can open it —
    // `?next=/farm` says where to return. Nothing here gates the farm.
    //
    // Siblings, not children of `/setup`: a child route would build the gate
    // beneath it, and the gate navigates as soon as it has an answer.
    GoRoute(path: '/setup', builder: (_, _) => const SetupGateScreen()),
    GoRoute(path: '/setup/farm', builder: (_, _) => const FarmSetupScreen()),
    GoRoute(
      path: '/setup/section',
      builder: (_, state) => SectionSetupScreen(
        next: _internalPath(state.uri.queryParameters['next']),
      ),
    ),
    // ------------------------------------------------------------ end setup
  ],
  errorBuilder: (context, state) => NotBuiltYetScreen(
    destination: NavDestination.home,
    title: 'Nothing here',
    body: 'That link does not go anywhere in this version of the app.',
    onBack: () => GoRouter.of(context).go('/home'),
  ),
);

/// [path] if it names a screen in this app, otherwise null. A `next` from a
/// link is never allowed to point anywhere but a route here.
String? _internalPath(String? path) =>
    path != null && path.startsWith('/') && !path.startsWith('//')
    ? path
    : null;
