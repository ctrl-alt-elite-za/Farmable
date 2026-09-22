import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'router.dart';
import 'theme/app_theme.dart';

class AlmanacApp extends ConsumerStatefulWidget {
  const AlmanacApp({super.key});

  @override
  ConsumerState<AlmanacApp> createState() => _AlmanacAppState();
}

class _AlmanacAppState extends ConsumerState<AlmanacApp> {
  // Built once. A router rebuilt on every frame loses its navigation stack,
  // which shows up as a back button that sometimes does nothing.
  late final _router = buildRouter();

  @override
  Widget build(BuildContext context) {
    // Planted here rather than on Home, because the app does not always open
    // on Home. Every route is reachable directly — by `INITIAL_ROUTE`, and by
    // the deep links `router.dart` is built around — and a screen that arrives
    // first at a section id finds no farm at all unless the seed is the app's
    // concern rather than one screen's. Nothing waits on this: the screens
    // subscribe to storage and render whatever is on disk, including nothing.
    ref.watch(seedProvider);

    return MaterialApp.router(
      title: 'Almanac',
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
      theme: almanacLightTheme(),
      darkTheme: almanacDarkTheme(),
      // The design ships both themes; the farmer's device decides. Dark is not
      // a preference here so much as a response to working at dawn and in sheds.
      themeMode: ThemeMode.system,
    );
  }
}
