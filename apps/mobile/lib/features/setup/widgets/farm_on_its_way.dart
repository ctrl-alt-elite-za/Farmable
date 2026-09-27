import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/tokens.g.dart';
import '../../../core/ui/buttons.dart';
import '../../auth/widgets/auth_scaffold.dart';
import 'setup_note.dart';

/// Shown while a signed-in farmer's own farm is still on its way to this
/// phone — the one moment setup has to wait for the network.
///
/// It is a calm state, not a failure: it names what is happening, says that
/// this needs a signal only once, and always offers a way on to Home.
///
/// Given [onRetry], the wait has gone on too long to stay quiet about: it
/// says the farm has not arrived and offers to ask again, rather than leaving
/// the farmer on a screen that never changes.
class FarmOnItsWay extends StatelessWidget {
  const FarmOnItsWay({super.key, this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => AuthScaffold(
    title: 'Getting your farm ready',
    subtitle: 'Your farm is coming onto this phone.',
    children: [
      if (onRetry == null)
        const SetupNote(
          icon: LucideIcons.cloudDownload,
          message:
              'This needs a signal once. After that your farm opens on this '
              'phone without one.',
        )
      else ...[
        const SetupNote(
          icon: LucideIcons.cloudAlert,
          message:
              'Your farm has not arrived yet. Check your signal and try '
              'again. Home shows the demo farm until yours arrives.',
        ),
        const SizedBox(height: AlmanacDimens.sp5),
        AppPrimaryButton(label: 'Try again', onPressed: onRetry),
      ],
      const SizedBox(height: AlmanacDimens.sp3),
      AppSecondaryButton(
        label: 'Open Home',
        onPressed: () => context.go('/home'),
      ),
    ],
  );
}
