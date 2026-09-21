import 'package:flutter/material.dart';

import 'router.dart';
import 'theme/app_theme.dart';

class AlmanacApp extends StatefulWidget {
  const AlmanacApp({super.key});

  @override
  State<AlmanacApp> createState() => _AlmanacAppState();
}

class _AlmanacAppState extends State<AlmanacApp> {
  // Built once. A router rebuilt on every frame loses its navigation stack,
  // which shows up as a back button that sometimes does nothing.
  late final _router = buildRouter();

  @override
  Widget build(BuildContext context) {
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
