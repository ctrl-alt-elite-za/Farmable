import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.g.dart';

/// One choice in a setup chip row — the design's `.chip` / `.chip-ok`.
///
/// Selected is told three ways, like every status here: the container fill,
/// a tick, and the screen reader's "selected". A full 48dp tall target.
class SetupChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const SetupChip({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;
    final foreground = selected ? c.onPrimaryContainer : c.onSurface;

    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AlmanacDimens.rPill),
        child: AnimatedContainer(
          duration: AppMotion.of(context).micro,
          curve: AlmanacMotion.easeStandard,
          constraints: const BoxConstraints(minHeight: AlmanacDimens.touchMin),
          padding: const EdgeInsets.symmetric(horizontal: AlmanacDimens.sp4),
          decoration: BoxDecoration(
            color: selected ? c.primaryContainer : c.surface,
            borderRadius: BorderRadius.circular(AlmanacDimens.rPill),
            border: Border.all(
              color: selected ? c.primaryContainer : c.outlineVariant,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Icon(LucideIcons.check, size: 16, color: foreground),
                const SizedBox(width: 6),
              ],
              Text(label, style: text.labelMedium?.copyWith(color: foreground)),
            ],
          ),
        ),
      ),
    );
  }
}
