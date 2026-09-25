/// Help text is bundled with the app so the whole page opens without a signal.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.g.dart';
import '../auth/widgets/auth_scaffold.dart';
import 'widgets/profile_rows.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.semantic;

    Widget answer(String heading, String body) => Padding(
      padding: const EdgeInsets.only(bottom: AlmanacDimens.sp5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(heading, style: text.titleMedium),
          const SizedBox(height: AlmanacDimens.sp2),
          Text(body, style: text.bodyMedium),
        ],
      ),
    );

    return AuthScaffold(
      title: 'Help',
      subtitle: 'Answers you can read without a signal.',
      onBack: backOr(context, '/profile'),
      children: [
        answer(
          'Does Almanac work without airtime?',
          'Yes. Your saved farm, sections and records live on this phone. '
              'You can open them and save changes without a signal. '
              'Information from the server, such as fresh market outlooks, '
              'needs a connection.',
        ),
        answer(
          'What does syncing mean?',
          'When you are logged in and have a signal, Almanac sends changes '
              'saved on this phone to your account and brings back changes '
              'from that account. If you are offline, your changes wait on '
              'this phone. The demo farm is never uploaded.',
        ),
        answer(
          'How do I reach the team?',
          'When you have a connection, open the Farmable project issue '
              'tracker and describe what happened. There is no in-app '
              'support message or phone line yet.',
        ),
        ProfileRow(
          icon: LucideIcons.messageCircle,
          title: 'Open the project issue tracker',
          subtitle: 'Needs a signal',
          onTap: () => launchUrl(
            Uri.https('github.com', '/ctrl-alt-elite-za/Farmable/issues'),
          ),
        ),
        const SizedBox(height: AlmanacDimens.sp4),
        Text('Your privacy', style: text.titleMedium),
        const SizedBox(height: AlmanacDimens.sp2),
        Text(
          'Read what Almanac keeps and choose whether outside services '
          'may process what you send.',
          style: text.bodyMedium?.copyWith(color: c.onSurfaceVariant),
        ),
        ProfileRow(
          icon: LucideIcons.shieldCheck,
          title: 'Privacy notice',
          subtitle: 'Saved in the app',
          onTap: () => context.go('/profile/privacy'),
        ),
      ],
    );
  }
}
