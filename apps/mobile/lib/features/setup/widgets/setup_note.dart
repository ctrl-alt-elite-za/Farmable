import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.g.dart';

/// The design's muted info card: a glyph and one reassuring sentence.
class SetupNote extends StatelessWidget {
  final IconData icon;
  final String message;

  const SetupNote({super.key, required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AlmanacDimens.sp4,
        vertical: AlmanacDimens.sp3,
      ),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AlmanacDimens.rLg),
        border: Border.all(color: c.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: c.onSurfaceVariant),
          const SizedBox(width: AlmanacDimens.sp3),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: c.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
