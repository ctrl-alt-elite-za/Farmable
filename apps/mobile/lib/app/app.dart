import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/presentation/auth_controller.dart';
import 'router.dart';
import 'theme/app_theme.dart';

class FarmableApp extends StatelessWidget {
  const FarmableApp({super.key});

  @override
  Widget build(BuildContext context) =>
      const ProviderScope(child: _FarmableRoot());
}

class _FarmableRoot extends ConsumerWidget {
  const _FarmableRoot();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    return MaterialApp.router(
      title: 'Farmable',
      theme: AppTheme.light,
      routerConfig: createRouter(session),
    );
  }
}
