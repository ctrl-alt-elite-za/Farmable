/// The Farm tab's two actions that open their own flows: adding a section,
/// and walking one's boundary.
///
/// Adding a section still says plainly what it will do once built — never a
/// control that does nothing, and never failure language, because nothing
/// has failed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.g.dart';
import '../../core/ui/not_built_yet_sheet.dart';
import '../../domain/farm_records.dart';
import 'farm_map_data.dart';

/// Section setup is issue #89. When it lands, this opens it instead.
Future<void> showAddSection(BuildContext context) => showNotBuiltYetSheet(
  context,
  title: 'Adding a section is coming',
  body:
      'A section is one piece of land you use for one thing — a bed, a row, '
      'a field. Naming one and saying what grows there comes next, and it '
      'will work on this phone with no signal.',
);

/// Walking a boundary (#15): asks which section, then opens the walk. With
/// [edit], only sections that already have a shape are offered, and the
/// screen opens on the saved shape to adjust. One candidate goes straight
/// there without asking.
Future<void> showBoundaryWalking(
  BuildContext context, {
  bool edit = false,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final sections = container.read(farmProvider).value?.sections ?? const [];
  final mapped = container.read(sectionBoundariesProvider);
  final candidates = [
    for (final s in sections)
      if (!edit || mapped.containsKey(s.id)) s,
  ];
  void open(SectionSummary s) =>
      context.push('/farm/zone/${s.id}/boundary${edit ? '?edit=1' : ''}');
  if (candidates.isEmpty) return showAddSection(context);
  if (candidates.length == 1) return open(candidates.single);

  final picked = await showModalBottomSheet<SectionSummary>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) {
      final c = context.semantic;
      final text = Theme.of(context).textTheme;
      return SafeArea(
        child: Container(
          margin: const EdgeInsets.all(AlmanacDimens.sp3),
          padding: const EdgeInsets.all(AlmanacDimens.sp5),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(AlmanacDimens.r2xl),
            border: Border.all(color: c.outlineVariant),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                edit
                    ? 'Which shape to adjust?'
                    : 'Which section are you walking?',
                style: text.titleMedium,
              ),
              const SizedBox(height: AlmanacDimens.sp3),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final s in candidates)
                      ListTile(
                        key: Key('walk-pick-${s.id}'),
                        contentPadding: EdgeInsets.zero,
                        minTileHeight: AlmanacDimens.touchMin,
                        leading: Icon(
                          mapped.containsKey(s.id)
                              ? LucideIcons.map
                              : LucideIcons.mapPinOff,
                          color: c.primary,
                        ),
                        title: Text(s.name),
                        subtitle: Text(
                          mapped.containsKey(s.id)
                              ? 'Walked — walking again replaces the shape'
                              : 'Not mapped yet',
                        ),
                        onTap: () => Navigator.of(context).pop(s),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  if (picked != null && context.mounted) open(picked);
}
