import 'package:flutter/material.dart';

import '../features/status/status_screen.dart';
import 'theme/app_theme.dart';

class AlmanacApp extends StatelessWidget {
  const AlmanacApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Almanac',
      debugShowCheckedModeBanner: false,
      theme: almanacLightTheme(),
      darkTheme: almanacDarkTheme(),
      // The design ships both themes; the farmer's device decides. Dark is not
      // a preference here so much as a response to working at dawn and in sheds.
      themeMode: ThemeMode.system,
      home: const StatusScreen(),
    );
  }
}
