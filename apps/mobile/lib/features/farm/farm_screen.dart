/// The Farm tab (designs 18a and 18b): every section, as a list or as a map.
///
/// Like Home it renders from local storage and nothing else — the farm, its
/// sections and their shapes are all on the phone. The one thing here that
/// can reach a server is the street map under the shapes, and that waits for
/// the farmer to say yes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.g.dart';
import '../../core/ui/badges.dart';
import '../../core/ui/buttons.dart';
import '../../core/ui/flow_controls.dart';
import '../../core/ui/layout.dart';
import '../../domain/farm_records.dart';
import '../home/home_view_model.dart';
import '../shell/almanac_scaffold.dart';
import '../shell/bottom_nav_island.dart';
import 'farm_actions.dart';
import 'farm_map_data.dart';
import 'widgets/farm_map.dart';
import 'widgets/farm_sections.dart';

enum FarmTabMode { map, sections }

/// `/farm` opens on the sections, which is what Home's "See all" promises;
/// `/farm?view=map` opens on the map.
class FarmScreen extends ConsumerWidget {
  final FarmTabMode initialMode;

  const FarmScreen({super.key, this.initialMode = FarmTabMode.sections});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The same first-launch seeding Home starts, for a farmer who arrives
    // here first. Nothing waits on it.
    ref.watch(seedProvider);
    final view = ref.watch(homeViewProvider);

    return AlmanacScaffold(
      destination: NavDestination.farm,
      body: view.when(
        // One frame while SQLite answers. No spinner, as on Home.
        loading: () => const SizedBox.shrink(),
        error: (_, _) =>
            FarmCouldNotOpen(onRetry: () => ref.invalidate(farmProvider)),
        data: (view) => view == null
            ? const FarmNotSetUp()
            : _FarmTab(view: view, initialMode: initialMode),
      ),
    );
  }
}

class _FarmTab extends ConsumerStatefulWidget {
  final HomeView view;
  final FarmTabMode initialMode;

  const _FarmTab({required this.view, required this.initialMode});

  @override
  ConsumerState<_FarmTab> createState() => _FarmTabState();
}

class _FarmTabState extends ConsumerState<_FarmTab> {
  late var _mode = widget.initialMode;
  String? _selectedId;

  @override
  void didUpdateWidget(covariant _FarmTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialMode != widget.initialMode) {
      _mode = widget.initialMode;
    }
  }

  void _open(SectionSummary section) =>
      context.push('/farm/zone/${section.id}');

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final farm = view.farm;
    final boundaries = ref.watch(sectionBoundariesProvider);

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AlmanacDimens.gutter,
          AlmanacDimens.sp4,
          AlmanacDimens.gutter,
          BottomNavIsland.bottomInset,
        ),
        children: [
          FarmHeader(view: view),
          const SizedBox(height: AlmanacDimens.sp4),
          AppSegmentedControl<FarmTabMode>(
            options: const [
              SegmentOption(
                value: FarmTabMode.map,
                label: 'Map',
                icon: LucideIcons.map,
              ),
              SegmentOption(
                value: FarmTabMode.sections,
                label: 'Sections',
                icon: LucideIcons.layers,
              ),
            ],
            value: _mode,
            onChanged: (mode) => setState(() => _mode = mode),
          ),
          const SizedBox(height: AlmanacDimens.sp4),
          if (farm.sections.isEmpty)
            const _NoSectionsYet()
          else if (_mode == FarmTabMode.sections)
            ..._sections(view)
          else
            ..._map(view, boundaries),
        ],
      ),
    );
  }

  List<Widget> _sections(HomeView view) => [
    for (final section in view.farm.sections) ...[
      SectionRow(
        key: ValueKey('section-${section.id}'),
        section: section,
        today: view.today,
        onOpen: () => _open(section),
      ),
      const SizedBox(height: AlmanacDimens.sp3),
    ],
    const SizedBox(height: AlmanacDimens.sp1),
    AppPrimaryButton(
      label: 'Add section',
      icon: LucideIcons.plus,
      onPressed: () => showAddSection(context),
    ),
  ];

  List<Widget> _map(HomeView view, Map<String, List<LatLng>> boundaries) {
    final c = context.semantic;
    final sections = view.farm.sections;
    final mapped = sections.where((s) => boundaries.containsKey(s.id)).toList();
    final unmapped = sections
        .where((s) => !boundaries.containsKey(s.id))
        .toList();
    final selected = mapped.where((s) => s.id == _selectedId).firstOrNull;
    final tiles = ref.watch(farmMapTilesConsentProvider);

    return [
      Container(
        height: 300,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.surfaceContainer,
          borderRadius: BorderRadius.circular(AlmanacDimens.rXl),
          border: Border.all(color: c.outlineVariant),
        ),
        child: mapped.isEmpty
            ? const _NothingMappedYet()
            : Stack(
                children: [
                  Positioned.fill(
                    child: FarmMap(
                      sections: mapped,
                      boundaries: boundaries,
                      selectedId: _selectedId,
                      onSelect: (s) => setState(() => _selectedId = s.id),
                    ),
                  ),
                  // Drawn from the phone — true whether or not a street map
                  // is loading underneath, and true with no signal at all.
                  if (!tiles || view.offline)
                    const Positioned(
                      top: AlmanacDimens.sp3,
                      left: AlmanacDimens.sp3,
                      child: OfflineBadge(label: 'Offline map'),
                    ),
                ],
              ),
      ),
      const SizedBox(height: AlmanacDimens.sp3),
      if (selected != null)
        SectionPreviewCard(section: selected, onOpen: () => _open(selected))
      else if (mapped.isNotEmpty)
        Text(
          'Tap a section on the map to see how it is doing.',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: c.onSurfaceVariant),
        ),
      if (mapped.isNotEmpty) ...[
        const SizedBox(height: AlmanacDimens.sp3),
        const StreetMapConsent(),
      ],
      const SizedBox(height: AlmanacDimens.sp3),
      Wrap(
        spacing: AlmanacDimens.sp2,
        runSpacing: AlmanacDimens.sp2,
        children: [
          AppTonalButton(
            label: 'Map farm',
            icon: LucideIcons.crosshair,
            block: false,
            onPressed: () => showBoundaryWalking(context),
          ),
          if (mapped.isNotEmpty) ...[
            AppTonalButton(
              label: 'Edit boundaries',
              icon: LucideIcons.pencil,
              block: false,
              onPressed: () => showBoundaryWalking(context, edit: true),
            ),
            AppTonalButton(
              label: 'Full map',
              icon: LucideIcons.maximize2,
              block: false,
              onPressed: () => context.push('/farm/map'),
            ),
          ],
        ],
      ),
      if (unmapped.isNotEmpty) ...[
        SectionHeader(
          title: 'Not mapped yet',
          subtitle: unmapped.length == 1
              ? '1 section with no boundary'
              : '${unmapped.length} sections with no boundary',
        ),
        UnmappedSections(sections: unmapped, onOpen: _open),
      ],
    ];
  }
}

/// `Siyakhula Farm` · `2.4 ha · 4 sections · KwaMashu`, and where the farm
/// stands with the server — the same chip Home shows.
class FarmHeader extends StatelessWidget {
  final HomeView view;

  const FarmHeader({super.key, required this.view});

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;
    final farm = view.farm;
    final count = farm.sections.length;
    final place = farm.farm.locality?.split(',').first.trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(farm.farm.name, style: text.headlineMedium),
              Text(
                [
                  if (count > 0) farm.totalArea,
                  count == 1 ? '1 section' : '$count sections',
                  if (place != null && place.isNotEmpty) place,
                ].join(' · '),
                style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(width: AlmanacDimens.sp3),
        // At most half the row, so on a narrow phone or at a large text size
        // the chip wraps its own words rather than squeezing the farm's name
        // down to a letter a line.
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.45,
          ),
          child: farm.pendingChanges > 0
              ? SyncIndicator(
                  standing: SyncStanding.pending,
                  pending: farm.pendingChanges,
                )
              : SyncIndicator(
                  standing: view.offline
                      ? SyncStanding.offline
                      : SyncStanding.synced,
                ),
        ),
      ],
    );
  }
}

/// The map card when no section has a boundary. The sections themselves are
/// listed underneath, so this says where they went.
class _NothingMappedYet extends StatelessWidget {
  const _NothingMappedYet();

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AlmanacDimens.sp5),
        child: Column(
          children: [
            Icon(LucideIcons.map, size: 28, color: c.onSurfaceVariant),
            const SizedBox(height: AlmanacDimens.sp3),
            Text(
              'No boundaries walked yet',
              style: text.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AlmanacDimens.sp2),
            Text(
              'Walk the edge of a section with your phone and its shape '
              'appears here. Your sections are listed below.',
              style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Design 45: the farm exists and has no sections in it.
class _NoSectionsYet extends StatelessWidget {
  const _NoSectionsYet();

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: LucideIcons.layers,
    headline: 'Your farm has no sections yet',
    body:
        'A section is one piece of land you use for one thing — a bed, a '
        'row, a field.',
    actionLabel: 'Add a section',
    actionIcon: LucideIcons.plus,
    onAction: () => showAddSection(context),
  );
}

/// No farm on this phone yet — a state, not a failure, worded as Home words
/// it.
class FarmNotSetUp extends StatelessWidget {
  const FarmNotSetUp({super.key});

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(AlmanacDimens.gutter),
      child: EmptyState(
        icon: LucideIcons.sprout,
        headline: 'Set up your farm',
        body:
            'A farm is the land you work, split into sections — a bed, a '
            'row, a field. Everything else in Almanac hangs off it, and all '
            'of it stays on this phone.',
      ),
    ),
  );
}

/// Local storage would not open. Not an offline state, so not worded as one.
class FarmCouldNotOpen extends StatelessWidget {
  final VoidCallback onRetry;

  const FarmCouldNotOpen({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AlmanacDimens.gutter),
      child: EmptyState(
        icon: LucideIcons.refreshCw,
        headline: 'Your farm could not be opened on this phone',
        body:
            'The records are still on the device. Try again, and if it keeps '
            'happening the app needs reinstalling.',
        actionLabel: 'Try again',
        actionIcon: LucideIcons.refreshCw,
        onAction: onRetry,
      ),
    ),
  );
}
