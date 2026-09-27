/// One option among several — a crop, a plan, a farm.
///
/// A real button to assistive technology (role, label, selected state), 48dp
/// tall, with the word always shown. Built only from structured data: the
/// label is chosen by the app from a fixed list or from server-computed
/// fields, never taken from model text.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.g.dart';

class ChoiceButton extends StatelessWidget {
  final String label;

  /// A second line under the label, for figures.
  final String? detail;

  /// The whole accessible name, when it should say more than [label] and
  /// [detail] do — "Plan option 1 of 3: …".
  final String? semanticLabel;

  /// Null for a plain choice; true or false to show a selection mark.
  final bool? selected;
  final VoidCallback? onPressed;

  const ChoiceButton({
    super.key,
    required this.label,
    this.detail,
    this.semanticLabel,
    this.selected,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;
    final isSelected = selected ?? false;
    final enabled = onPressed != null;

    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: semanticLabel ?? [label, if (detail != null) detail].join('. '),
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AlmanacDimens.touchMin),
        child: Material(
          color: isSelected ? c.primaryContainer : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AlmanacDimens.rMd),
            side: BorderSide(
              color: isSelected ? c.primary : c.outlineVariant,
              width: isSelected ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AlmanacDimens.sp4,
                vertical: AlmanacDimens.sp3,
              ),
              child: Row(
                children: [
                  if (selected != null) ...[
                    Icon(
                      isSelected ? LucideIcons.circleCheck : LucideIcons.circle,
                      size: 20,
                      color: isSelected ? c.primary : c.onSurfaceVariant,
                    ),
                    const SizedBox(width: AlmanacDimens.sp3),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: text.titleSmall?.copyWith(
                            color: enabled
                                ? (isSelected
                                      ? c.onPrimaryContainer
                                      : c.onSurface)
                                : c.onSurfaceVariant,
                          ),
                        ),
                        if (detail != null)
                          Text(
                            detail!,
                            style: text.bodySmall?.copyWith(
                              color: isSelected
                                  ? c.onPrimaryContainer
                                  : c.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
