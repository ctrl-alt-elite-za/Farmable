/// Rows the Profile screens are built from.
///
/// Two kinds, and they look different on purpose: a [ProfileRow] goes
/// somewhere (a chevron), a [ChoiceRow] is one answer among several (a check
/// when chosen). Each is one merged semantics node — a button, or a selected
/// option — so TalkBack reads it as one thing and the Maestro flows can find
/// it by its words.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.g.dart';

class ProfileRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  /// Red, for the one row that destroys something.
  final bool danger;

  const ProfileRow({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;
    final colour = danger ? c.statusActionRequired : c.onSurface;

    return MergeSemantics(
      child: Semantics(
        button: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AlmanacDimens.rMd),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AlmanacDimens.touchMin,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AlmanacDimens.sp3),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: colour),
                  const SizedBox(width: AlmanacDimens.sp4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: text.bodyLarge?.copyWith(color: colour),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            style: text.bodySmall?.copyWith(
                              color: c.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    LucideIcons.chevronRight,
                    size: 18,
                    color: c.onSurfaceVariant,
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

class ChoiceRow extends StatelessWidget {
  final String label;
  final String? detail;
  final bool selected;
  final VoidCallback? onTap;

  const ChoiceRow({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AlmanacDimens.sp2),
      child: MergeSemantics(
        child: Semantics(
          button: true,
          selected: selected,
          enabled: onTap != null,
          child: Material(
            color: selected ? c.primaryContainer : c.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AlmanacDimens.rMd),
              side: BorderSide(
                color: selected ? c.primary : c.outlineVariant,
                width: selected ? 2 : 1.5,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: AlmanacDimens.touchMin,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AlmanacDimens.sp4,
                    vertical: AlmanacDimens.sp3,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(label, style: text.bodyLarge),
                            if (detail != null)
                              Text(
                                detail!,
                                style: text.bodySmall?.copyWith(
                                  color: c.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                      // The check carries "chosen" as a shape, not only as
                      // the border colour.
                      if (selected)
                        Icon(LucideIcons.check, size: 20, color: c.primary),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
