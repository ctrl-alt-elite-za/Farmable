/// The full farm map (design 19): the farm edge to edge, panning and zooming,
/// with the sections that have no boundary yet named along the bottom.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.g.dart';
import '../../core/ui/badges.dart';
import '../../core/ui/buttons.dart';
import '../../domain/farm_records.dart';
import '../home/home_view_model.dart';
import '../shell/almanac_scaffold.dart';
import '../shell/bottom_nav_island.dart';
import 'farm_actions.dart';
import 'farm_map_data.dart';
import 'farm_screen.dart';
import 'widgets/farm_map.dart';
import 'widgets/farm_sections.dart';

class FarmMapScreen extends ConsumerWidget {
  const FarmMapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(seedProvider);
    final view = ref.watch(homeViewProvider);

    return AlmanacScaffold(
      destination: NavDestination.farm,
      body: view.when(
        loading: () => const SizedBox.shrink(),
        error: (_, _) =>
            FarmCouldNotOpen(onRetry: () => ref.invalidate(farmProvider)),
        data: (view) =>
            view == null ? const FarmNotSetUp() : _FullMap(view: view),
      ),
    );
  }
}

class _FullMap extends ConsumerStatefulWidget {
  final HomeView view;

  const _FullMap({required this.view});

  @override
  ConsumerState<_FullMap> createState() => _FullMapState();
}

class _FullMapState extends ConsumerState<_FullMap> {
  String? _selectedId;

  void _open(SectionSummary section) =>
      context.push('/farm/zone/${section.id}');

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/farm?view=map');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final view = widget.view;
    final boundaries = ref.watch(sectionBoundariesProvider);
    final tiles = ref.watch(farmMapTilesConsentProvider);
    final sections = view.farm.sections;
    final mapped = sections.where((s) => boundaries.containsKey(s.id)).toList();
    final unmapped = sections
        .where((s) => !boundaries.containsKey(s.id))
        .toList();
    final selected = mapped.where((s) => s.id == _selectedId).firstOrNull;

    return ColoredBox(
      color: c.surfaceContainer,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: mapped.isEmpty
                ? const SizedBox.shrink()
                : FarmMap(
                    sections: mapped,
                    boundaries: boundaries,
                    selectedId: _selectedId,
                    interactive: true,
                    onSelect: (s) => setState(() => _selectedId = s.id),
                    fitPadding: const EdgeInsets.fromLTRB(
                      AlmanacDimens.sp7,
                      96,
                      AlmanacDimens.sp7,
                      200,
                    ),
                  ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AlmanacDimens.gutter,
                  AlmanacDimens.sp3,
                  AlmanacDimens.gutter,
                  0,
                ),
                child: Row(
                  children: [
                    IconOnlyButton(
                      icon: LucideIcons.arrowLeft,
                      semanticLabel: 'Back',
                      onImagery: true,
                      onPressed: _back,
                    ),
                    const Spacer(),
                    if (mapped.isNotEmpty)
                      IconOnlyButton(
                        icon: LucideIcons.layers,
                        semanticLabel: 'Map layers',
                        onImagery: true,
                        onPressed: () => _showLayers(context),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: AlmanacDimens.gutter,
            right: AlmanacDimens.gutter,
            bottom: BottomNavIsland.bottomInset,
            // Never taller than half the screen: at a large text size the
            // cards scroll within that rather than climbing over the toolbar
            // and off the top.
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.5,
              ),
              child: SingleChildScrollView(
                reverse: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: AlmanacDimens.sp2,
                      runSpacing: AlmanacDimens.sp2,
                      children: [
                        if (!tiles || view.offline)
                          const OfflineBadge(label: 'Offline map'),
                        if (sections.isNotEmpty)
                          ScrimBadge(
                            icon: LucideIcons.ruler,
                            text: view.farm.totalArea,
                          ),
                      ],
                    ),
                    const SizedBox(height: AlmanacDimens.sp2),
                    if (selected != null)
                      SectionPreviewCard(
                        section: selected,
                        onOpen: () => _open(selected),
                      )
                    else if (mapped.isEmpty)
                      _NothingToDraw(hasSections: sections.isNotEmpty),
                    if (unmapped.isNotEmpty) ...[
                      const SizedBox(height: AlmanacDimens.sp2),
                      _UnmappedStrip(sections: unmapped, onOpen: _open),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showLayers(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => const SafeArea(
      child: Padding(
        padding: EdgeInsets.all(AlmanacDimens.sp3),
        child: StreetMapConsent(),
      ),
    ),
  );
}

/// Nothing on the farm has a boundary, so there is no land to draw — only
/// the list below, and the way to change that.
class _NothingToDraw extends StatelessWidget {
  final bool hasSections;

  const _NothingToDraw({required this.hasSections});

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AlmanacDimens.sp4),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AlmanacDimens.rXl),
        border: Border.all(color: c.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('No boundaries walked yet', style: text.titleSmall),
          const SizedBox(height: AlmanacDimens.sp1),
          Text(
            hasSections
                ? 'Walk the edge of a section with your phone and its shape '
                      'is drawn here.'
                : 'Your farm has no sections yet. Add one, then walk its '
                      'edge and it is drawn here.',
            style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
          ),
          const SizedBox(height: AlmanacDimens.sp3),
          AppTonalButton(
            label: hasSections ? 'Map farm' : 'Add a section',
            icon: hasSections ? LucideIcons.crosshair : LucideIcons.plus,
            onPressed: () => hasSections
                ? showBoundaryWalking(context)
                : showAddSection(context),
          ),
        ],
      ),
    );
  }
}

/// "Not mapped yet", then each section by name, each one tappable. Scrolls
/// sideways rather than covering the map when there are many.
class _UnmappedStrip extends StatelessWidget {
  final List<SectionSummary> sections;
  final ValueChanged<SectionSummary> onOpen;

  const _UnmappedStrip({required this.sections, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: AlmanacDimens.sp3),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AlmanacDimens.rXl),
        border: Border.all(color: c.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AlmanacDimens.sp4),
            child: Row(
              children: [
                Icon(
                  LucideIcons.mapPinOff,
                  size: 15,
                  color: c.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    sections.length == 1
                        ? 'Not mapped yet · 1 section'
                        : 'Not mapped yet · ${sections.length} sections',
                    style: text.labelSmall?.copyWith(color: c.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AlmanacDimens.sp2),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AlmanacDimens.sp4),
            child: Row(
              children: [
                for (final s in sections) ...[
                  if (s != sections.first)
                    const SizedBox(width: AlmanacDimens.sp2),
                  Semantics(
                    button: true,
                    label: '${s.name}. ${cropAndArea(s)}. Not mapped yet.',
                    excludeSemantics: true,
                    child: Material(
                      color: c.surfaceContainer,
                      shape: const StadiumBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        key: ValueKey('unmapped-${s.id}'),
                        onTap: () => onOpen(s),
                        child: Container(
                          constraints: const BoxConstraints(
                            minHeight: AlmanacDimens.touchMin,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AlmanacDimens.sp4,
                          ),
                          alignment: Alignment.center,
                          child: Text(s.name, style: text.labelMedium),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
