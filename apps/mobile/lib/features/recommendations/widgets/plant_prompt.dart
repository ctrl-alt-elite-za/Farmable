/// The way in to "what should I plant here?".
///
/// Sits on Zone Detail for a section with nothing planted in it — the design's
/// North Plot. The assistant sheet is where this conversation will eventually
/// start; until voice exists, the question has to be askable by tapping it,
/// and a farmer standing on empty ground should not have to find a menu.
///
/// It says what it will do before it does it: worked out on the phone, nothing
/// saved until they say so. Both of those are true and both are the reason
/// this flow is safe to offer on a card.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../core/ui/badges.dart';
import '../../../core/ui/buttons.dart';
import '../../../core/ui/layout.dart';

class PlantPromptCard extends StatelessWidget {
  final String sectionName;
  final VoidCallback onAsk;

  const PlantPromptCard({
    super.key,
    required this.sectionName,
    required this.onAsk,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;

    return Semantics(
      identifier: 'plant-prompt',
      container: true,
      child: AlmanacCard(
        padding: const EdgeInsets.all(AlmanacDimens.sp4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: c.primaryContainer,
                    borderRadius: BorderRadius.circular(AlmanacDimens.rSm),
                  ),
                  child: Icon(
                    LucideIcons.sprout,
                    size: 20,
                    color: c.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: AlmanacDimens.sp3),
                Expanded(
                  child: Text('$sectionName is empty', style: text.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: AlmanacDimens.sp3),
            Text(
              'Tell me what you have to spend and I will work out what fits '
              'this land, what it would cost and what it would leave you.',
              style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
            ),
            const SizedBox(height: AlmanacDimens.sp3),
            const Wrap(
              spacing: AlmanacDimens.sp2,
              runSpacing: AlmanacDimens.sp2,
              children: [
                ConstraintChip(
                  icon: LucideIcons.cloudOff,
                  text: 'Works without signal',
                ),
                ConstraintChip(
                  icon: LucideIcons.check,
                  text: 'Nothing saved until you say so',
                ),
              ],
            ),
            const SizedBox(height: AlmanacDimens.sp4),
            AppPrimaryButton(
              label: 'What should I plant here?',
              icon: LucideIcons.sparkles,
              onPressed: onAsk,
            ),
          ],
        ),
      ),
    );
  }
}
