import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/domain/auth_models.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/auth/presentation/signup_page.dart';
import '../features/auth/presentation/verify_page.dart';
import '../features/shell/presentation/home_shell.dart';

GoRouter createRouter(AsyncValue<LocalSession?> session) => GoRouter(
  initialLocation: '/login',
  redirect: (context, state) {
    if (session.isLoading) {
      return state.matchedLocation == '/splash' ? null : '/splash';
    }
    final signedIn = session.valueOrNull != null;
    final authRoute =
        state.matchedLocation.startsWith('/auth') ||
        state.matchedLocation == '/login';
    if (signedIn && authRoute) {
      return '/home';
    }
    if (!signedIn && state.matchedLocation == '/home') {
      return '/login';
    }
    return null;
  },
  routes: [
    GoRoute(path: '/splash', builder: (_, state) => const _SplashPage()),
    GoRoute(path: '/login', builder: (_, state) => const LoginPage()),
    GoRoute(path: '/auth/signup', builder: (_, state) => const SignUpPage()),
    GoRoute(
      path: '/auth/verify/:userId/:channel',
      builder: (_, state) => VerifyPage(
        userId: state.pathParameters['userId']!,
        channel: state.pathParameters['channel']!,
      ),
    ),
    GoRoute(path: '/home', builder: (_, state) => const HomeShell()),
  ],
);

class _SplashPage extends StatelessWidget {
  const _SplashPage();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('Farmable')));
}
