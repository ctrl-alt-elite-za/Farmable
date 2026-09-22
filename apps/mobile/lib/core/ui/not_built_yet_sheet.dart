import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.g.dart';
import 'buttons.dart';

/// Says that a control leads somewhere that is not finished, and what will be
/// there when it is.
///
/// The alternative is a tile that does nothing when tapped, which a farmer
/// reads as the app being broken rather than as the feature being unfinished —
/// and they cannot tell those apart, so they stop trusting the parts that do
/// work. The copy never says "error", "failed" or "unavailable", because none
/// of those is true.
Future<void> showNotBuiltYetSheet(
  BuildContext context, {
  required String title,
  required String body,
}) => showModalBottomSheet<void>(
  context: context,
  backgroundColor: Colors.transparent,
  builder: (context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(AlmanacDimens.sp3),
        padding: const EdgeInsets.all(AlmanacDimens.sp5),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AlmanacDimens.r2xl),
          border: Border.all(color: c.outlineVariant),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: c.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  LucideIcons.sprout,
                  color: c.onPrimaryContainer,
                  size: 24,
                ),
              ),
            ),
            const SizedBox(height: AlmanacDimens.sp4),
            Text(title, style: text.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: AlmanacDimens.sp2),
            Text(
              body,
              style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AlmanacDimens.sp5),
            AppTonalButton(
              label: 'Close',
              icon: LucideIcons.check,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  },
);
