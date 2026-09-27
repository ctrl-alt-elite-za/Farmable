/// Walk a section's edge, review the shape on a map, and save it (#15).
///
/// One screen, four steps:
///
/// 1. **Before** — what to do, and what this phone measures with.
/// 2. **Walking** — the path drawn as it is walked, the area so far, corners
///    marked on a tap. When AR loses the ground a banner says so and AR
///    drawing pauses; GPS carries on.
/// 3. **Can't start** — location off or refused, with the way to fix it.
/// 4. **Review** — the shape on a map with every corner draggable, the area
///    recalculated as it moves, AR against GPS with a warning above 15%, and a
///    shape that crosses itself refused with the reason shown before Save is
///    allowed.
///
/// Saving writes to the phone and queues the change for sync (#17), so it
/// works with no signal. Soil data for the new shape is fetched by the server
/// after sync (#11); the screen says it is pending, and never waits for it.
///
/// `/farm/zone/:id/boundary` walks; `?edit=1` opens straight on review with
/// the saved shape.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.g.dart';
import '../../core/ui/buttons.dart';
import '../../core/ui/layout.dart';
import '../../core/utils/ids.dart';
import '../../domain/farm_records.dart';
import '../../domain/farm_repository.dart';
import '../../domain/mapping/geometry.dart';
import '../../domain/mapping/walk.dart';
import '../farm/farm_map_data.dart';
import 'boundary_providers.dart';
import 'widgets/boundary_review_map.dart';
import 'widgets/walk_trace.dart';

/// The backend's limits on a section boundary (`demo_api/geometry.py`).
const _minAreaM2 = 1.0;
const _maxAreaM2 = 1000000.0;

class BoundaryScreen extends ConsumerWidget {
  final String sectionId;

  /// Open on review with the saved shape rather than walking a new one.
  final bool edit;

  const BoundaryScreen({super.key, required this.sectionId, this.edit = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(sectionProvider(sectionId));
    final c = context.semantic;
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: section.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const _Missing(),
          data: (s) => s == null
              ? const _Missing()
              : _BoundaryFlow(section: s, edit: edit),
        ),
      ),
    );
  }
}

enum _Step { before, walking, cannotStart, review }

class _BoundaryFlow extends ConsumerStatefulWidget {
  final SectionSummary section;
  final bool edit;

  const _BoundaryFlow({required this.section, required this.edit});

  @override
  ConsumerState<_BoundaryFlow> createState() => _BoundaryFlowState();
}

class _BoundaryFlowState extends ConsumerState<_BoundaryFlow> {
  _Step _step = _Step.before;
  late final WalkSource _source;
  WalkRecording _recording = WalkRecording();
  StreamSubscription<WalkSample>? _subscription;
  int _revision = 0;
  WalkUnavailable? _unavailable;
  String? _walkNotice;

  WalkResult? _result;
  List<LatLng> _corners = const [];
  List<LatLng> _frame = const [];
  bool _saving = false;
  String? _saveNotice;
  String? _mutationId;

  /// The section's version when this screen opened. [widget.section] follows
  /// the live row, so a sync that pulls another phone's edit would otherwise
  /// move it forward and let the save overwrite that edit unannounced.
  late final int _baseRevision;

  @override
  void initState() {
    super.initState();
    _baseRevision = widget.section.section.version;
    _source = ref.read(walkSourceProvider);
    final saved = boundaryFromGeoJson(widget.section.boundary);
    if (widget.edit && saved != null) {
      _corners = saved;
      _frame = saved;
      _step = _Step.review;
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_source.stop());
    super.dispose();
  }

  // ------------------------------------------------------------- walking

  void _start() {
    unawaited(_subscription?.cancel());
    setState(() {
      _recording = WalkRecording();
      _revision = 0;
      _unavailable = null;
      _walkNotice = null;
      _step = _Step.walking;
    });
    _subscription = _source.start().listen(
      (sample) {
        if (!mounted) return;
        setState(() {
          _recording.add(sample);
          _revision++;
        });
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _unavailable = e is WalkUnavailable
              ? e
              : WalkUnavailable('Location stopped: $e');
          _step = _Step.cannotStart;
        });
      },
      // A recorded walk ends on its own; a real one ends on Finish.
      onDone: () {
        if (mounted && _step == _Step.walking) _finish();
      },
    );
  }

  void _markCorner() {
    final marked = _recording.markCorner();
    setState(() {
      _revision++;
      _walkNotice = marked
          ? null
          : 'Wait for the first location fix, then mark the corner.';
    });
  }

  void _finish() {
    try {
      final result = _recording.finish();
      unawaited(_subscription?.cancel());
      unawaited(_source.stop());
      final ring = [
        for (final p in result.ring) LatLng(p.latitude, p.longitude),
      ];
      setState(() {
        _result = result;
        _corners = ring;
        _frame = ring;
        _step = _Step.review;
        _saveNotice = null;
      });
    } on GeometryException catch (e) {
      setState(
        () => _walkNotice = e.code == GeometryErrorCode.tooFewPoints
            ? 'Keep walking — the path does not go round any land yet.'
            : 'The path crosses itself. Walk back to where you started, '
                  'staying on the edge, then tap Finish.',
      );
    }
  }

  // -------------------------------------------------------------- review

  ({double? areaM2, Set<int> crossing, String? problem}) get _check {
    if (_corners.length < 3) {
      return (
        areaM2: null,
        crossing: const {},
        problem: 'A shape needs at least three corners.',
      );
    }
    final origin = GpsPoint(_corners.first.latitude, _corners.first.longitude);
    final flat = [
      for (final p in _corners)
        projectGps(GpsPoint(p.latitude, p.longitude), origin),
    ];
    final crossing = firstCrossing(flat);
    if (crossing != null) {
      return (
        areaM2: null,
        crossing: {crossing.first, crossing.second},
        problem:
            'Two sides of the shape cross, shown in red. Drag a corner back '
            'so the edge goes round the land once — a crossed shape cannot '
            'be measured.',
      );
    }
    final double area;
    try {
      area = geodesicArea([
        for (final p in _corners) GpsPoint(p.latitude, p.longitude),
      ]);
    } on GeometryException {
      return (
        areaM2: null,
        crossing: const {},
        problem: 'That shape has no area. Spread the corners out.',
      );
    }
    if (area < _minAreaM2 || area > _maxAreaM2) {
      return (
        areaM2: area,
        crossing: const {},
        problem: 'A section can be from 1 m² up to 100 ha. Check the corners.',
      );
    }
    return (areaM2: area, crossing: const {}, problem: null);
  }

  void _edited(List<LatLng> corners) => setState(() {
    _corners = corners;
    _saveNotice = null;
    // A changed shape is a new action: a new id, so it is not mistaken for
    // a retry of the last save.
    _mutationId = null;
  });

  Future<void> _save() async {
    final check = _check;
    final area = check.areaM2;
    if (_saving || check.problem != null || area == null) return;
    final repository = ref.read(farmRecordsProvider);
    if (repository is! FarmRepository) return;
    setState(() => _saving = true);
    _mutationId ??= newUuid();
    try {
      await (repository as FarmRepository).updateSection(
        mutationId: _mutationId!,
        sectionId: widget.section.id,
        expectedRevision: _baseRevision,
        name: widget.section.name,
        areaM2: areaM2String(area),
        boundary: ringToGeoJson([
          for (final p in _corners) GpsPoint(p.latitude, p.longitude),
        ]),
      );
    } on RevisionConflict {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveNotice =
            'This section was changed on another phone while you walked. '
            'Go back, open it again, and save the shape once more.';
      });
      return;
    } on Object {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveNotice =
            'This phone could not save that. Free up some space and try '
            'again.';
      });
      return;
    }
    if (!mounted) return;
    final account = ref.read(farmScopeProvider).isAccount;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          account
              ? '${widget.section.name} saved on this phone — '
                    '${formatArea(area)}. It syncs when you have a signal.'
              : '${widget.section.name} saved on this phone — '
                    '${formatArea(area)}.',
        ),
      ),
    );
    context.go('/farm?view=map');
  }

  void _leave() {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
    } else {
      router.go('/farm?view=map');
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (_step) {
      _Step.review => 'Check the shape',
      _ => 'Walk ${widget.section.name}',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(title: title, onBack: _leave),
        Expanded(
          child: switch (_step) {
            _Step.before => _Before(
              section: widget.section,
              source: _source,
              onStart: _start,
              onEditSaved: boundaryFromGeoJson(widget.section.boundary) == null
                  ? null
                  : () {
                      final saved = boundaryFromGeoJson(
                        widget.section.boundary,
                      )!;
                      setState(() {
                        _corners = saved;
                        _frame = saved;
                        _result = null;
                        _step = _Step.review;
                      });
                    },
            ),
            _Step.walking => _Walking(
              recording: _recording,
              revision: _revision,
              source: _source,
              notice: _walkNotice,
              onMarkCorner: _markCorner,
              onFinish: _finish,
            ),
            _Step.cannotStart => _CannotStart(
              reason: _unavailable!,
              onRetry: _start,
              onSettings: ref.read(openAppSettingsProvider),
              onBack: _leave,
            ),
            _Step.review => _buildReview(context),
          },
        ),
      ],
    );
  }

  Widget _buildReview(BuildContext context) {
    final check = _check;
    final c = context.semantic;
    final text = Theme.of(context).textTheme;
    final account = ref.watch(farmScopeProvider).isAccount;
    final area = check.areaM2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 5,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AlmanacDimens.gutter,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AlmanacDimens.rXl),
              child: BoundaryReviewMap(
                corners: _corners,
                frame: _frame,
                crossingSides: check.crossing,
                onMove: (i, to) => _edited([..._corners]..[i] = to),
                onInsert: (i) => _edited([
                  ..._corners.sublist(0, i + 1),
                  LatLng(
                    (_corners[i].latitude +
                            _corners[(i + 1) % _corners.length].latitude) /
                        2,
                    (_corners[i].longitude +
                            _corners[(i + 1) % _corners.length].longitude) /
                        2,
                  ),
                  ..._corners.sublist(i + 1),
                ]),
                onRemove: (i) => _edited([..._corners]..removeAt(i)),
              ),
            ),
          ),
        ),
        Expanded(
          flex: 6,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AlmanacDimens.gutter,
              AlmanacDimens.sp4,
              AlmanacDimens.gutter,
              AlmanacDimens.sp6,
            ),
            children: [
              Text(
                'Drag a corner to move it. Tap + to add one; long-press a '
                'corner to remove it.',
                style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
              ),
              const SizedBox(height: AlmanacDimens.sp3),
              Semantics(
                identifier: 'boundary-area',
                label: area == null
                    ? 'Area: cannot be measured'
                    : 'Area: ${formatArea(area)}',
                excludeSemantics: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('Area', style: text.titleSmall),
                    const SizedBox(width: AlmanacDimens.sp3),
                    Text(
                      area == null ? '—' : formatArea(area),
                      key: const Key('boundary-area'),
                      style: text.headlineMedium,
                    ),
                  ],
                ),
              ),
              if (check.problem != null) ...[
                const SizedBox(height: AlmanacDimens.sp3),
                _Callout(
                  key: const Key('boundary-problem'),
                  icon: LucideIcons.triangleAlert,
                  tone: _Tone.bad,
                  message: check.problem!,
                ),
              ],
              const SizedBox(height: AlmanacDimens.sp3),
              _Agreement(result: _result, edited: _result == null),
              const SizedBox(height: AlmanacDimens.sp3),
              _Callout(
                key: const Key('boundary-soil'),
                icon: LucideIcons.sprout,
                tone: _Tone.calm,
                message: account
                    ? 'Soil data: pending. It is looked up for this shape '
                          'once it syncs — you do not need to wait for it.'
                    : 'Soil data: unavailable for the example farm, which '
                          'is never sent anywhere.',
              ),
              const SizedBox(height: AlmanacDimens.sp4),
              if (_saveNotice != null) ...[
                _Callout(
                  icon: LucideIcons.circleAlert,
                  tone: _Tone.bad,
                  message: _saveNotice!,
                ),
                const SizedBox(height: AlmanacDimens.sp3),
              ],
              const SizedBox(height: AlmanacDimens.sp3),
              Row(
                children: [
                  Icon(
                    LucideIcons.cloudOff,
                    size: 16,
                    color: c.onSurfaceVariant,
                  ),
                  const SizedBox(width: AlmanacDimens.sp2),
                  Expanded(
                    child: Text(
                      account
                          ? 'Saved on your phone first. It reaches your '
                                'account the next time you have a signal.'
                          : 'Saved on this phone. The example farm is never '
                                'sent anywhere.',
                      style: text.bodySmall?.copyWith(
                        color: c.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AlmanacDimens.gutter,
            AlmanacDimens.sp2,
            AlmanacDimens.gutter,
            AlmanacDimens.sp3,
          ),
          child: Row(
            children: [
              Expanded(
                child: AppTonalButton(
                  label: 'Walk again',
                  icon: LucideIcons.rotateCcw,
                  onPressed: _saving ? null : _start,
                ),
              ),
              const SizedBox(width: AlmanacDimens.sp3),
              Expanded(
                child: Semantics(
                  identifier: 'boundary-save',
                  child: AppPrimaryButton(
                    key: const Key('boundary-save'),
                    label: 'Save',
                    icon: LucideIcons.check,
                    busyLabel: _saving ? 'Saving…' : null,
                    onPressed: _saving || check.problem != null ? null : _save,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ parts

class _Header extends StatelessWidget {
  final String title;
  final VoidCallback onBack;

  const _Header({required this.title, required this.onBack});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AlmanacDimens.gutter,
      AlmanacDimens.sp3,
      AlmanacDimens.gutter,
      AlmanacDimens.sp3,
    ),
    child: Row(
      children: [
        IconOnlyButton(
          icon: LucideIcons.arrowLeft,
          semanticLabel: 'Back',
          onPressed: onBack,
        ),
        const SizedBox(width: AlmanacDimens.sp3),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

class _Before extends StatelessWidget {
  final SectionSummary section;
  final WalkSource source;
  final VoidCallback onStart;
  final VoidCallback? onEditSaved;

  const _Before({
    required this.section,
    required this.source,
    required this.onStart,
    required this.onEditSaved,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;
    const steps = [
      (LucideIcons.mapPin, 'Stand at one corner of the section.'),
      (LucideIcons.footprints, 'Tap Start and walk its edge at an easy pace.'),
      (
        LucideIcons.flag,
        'Tap Mark corner at each corner. It is optional, and makes the '
            'shape sharper.',
      ),
      (
        LucideIcons.circleCheck,
        'Tap Finish when you are back where you began.',
      ),
    ];
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AlmanacDimens.gutter),
      children: [
        Text(
          'Walk the edge and the phone measures the land inside it. You then '
          'check the shape on a map before anything is saved.',
          style: text.bodyMedium?.copyWith(color: c.onSurfaceVariant),
        ),
        const SizedBox(height: AlmanacDimens.sp4),
        AlmanacCard(
          padding: const EdgeInsets.all(AlmanacDimens.sp4),
          child: Column(
            children: [
              for (final (i, (icon, words)) in steps.indexed) ...[
                if (i > 0) const SizedBox(height: AlmanacDimens.sp3),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 20, color: c.primary),
                    const SizedBox(width: AlmanacDimens.sp3),
                    Expanded(child: Text(words, style: text.bodyMedium)),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AlmanacDimens.sp3),
        _Callout(
          key: const Key('boundary-source'),
          icon: source.hasAr ? LucideIcons.scan : LucideIcons.satellite,
          tone: _Tone.calm,
          message: source.hasAr
              ? '${source.description}. AR measures the ground and GPS '
                    'checks it.'
              : '${source.description}. Each corner is good to a few '
                    'metres — you can drag it right on the map afterwards.',
        ),
        const SizedBox(height: AlmanacDimens.sp5),
        Semantics(
          identifier: 'boundary-start',
          child: AppPrimaryButton(
            key: const Key('boundary-start'),
            label: 'Start walking',
            icon: LucideIcons.footprints,
            onPressed: onStart,
          ),
        ),
        if (onEditSaved != null) ...[
          const SizedBox(height: AlmanacDimens.sp3),
          AppTonalButton(
            label: 'Edit the saved shape instead',
            icon: LucideIcons.pencil,
            onPressed: onEditSaved,
          ),
        ],
        const SizedBox(height: AlmanacDimens.sp6),
      ],
    );
  }
}

class _Walking extends StatelessWidget {
  final WalkRecording recording;
  final int revision;
  final WalkSource source;
  final String? notice;
  final VoidCallback onMarkCorner;
  final VoidCallback onFinish;

  const _Walking({
    required this.recording,
    required this.revision,
    required this.source,
    required this.notice,
    required this.onMarkCorner,
    required this.onFinish,
  });

  @override
  Widget build(BuildContext context) {
    final area = recording.liveAreaM2;
    final fix = recording.lastFix;
    final lost = recording.tracking == ArTracking.lost;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AlmanacDimens.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (lost)
            const _Callout(
              key: Key('boundary-tracking-lost'),
              icon: LucideIcons.scanEye,
              tone: _Tone.warn,
              message:
                  'AR lost sight of the ground, so it has stopped drawing. '
                  'Keep walking — GPS is still recording, and AR carries on '
                  'when it finds the ground again.',
            )
          else if (!source.hasAr)
            const _Callout(
              key: Key('boundary-gps-only'),
              icon: LucideIcons.satellite,
              tone: _Tone.calm,
              message: 'Measuring with GPS only on this phone.',
            ),
          const SizedBox(height: AlmanacDimens.sp3),
          Expanded(
            child: WalkTrace(recording: recording, revision: revision),
          ),
          const SizedBox(height: AlmanacDimens.sp3),
          FarmMetricRow(
            metrics: [
              FarmMetric(
                icon: LucideIcons.ruler,
                label: 'Area so far',
                value: area == null ? '—' : formatArea(area),
              ),
              FarmMetric(
                icon: LucideIcons.footprints,
                label: 'Walked',
                value: '${recording.walkedMetres.round()} m',
              ),
              FarmMetric(
                icon: LucideIcons.flag,
                label: 'Corners',
                value: '${recording.corners.length}',
              ),
              FarmMetric(
                icon: LucideIcons.satellite,
                label: 'GPS',
                value: fix?.accuracyMetres == null
                    ? (fix == null ? 'Waiting' : 'Fixed')
                    : '± ${fix!.accuracyMetres!.round()} m',
              ),
            ],
          ),
          if (notice != null) ...[
            const SizedBox(height: AlmanacDimens.sp3),
            _Callout(
              icon: LucideIcons.info,
              tone: _Tone.warn,
              message: notice!,
            ),
          ],
          const SizedBox(height: AlmanacDimens.sp3),
          Row(
            children: [
              Expanded(
                child: AppTonalButton(
                  key: const Key('boundary-mark-corner'),
                  label: 'Mark corner',
                  icon: LucideIcons.flag,
                  onPressed: onMarkCorner,
                ),
              ),
              const SizedBox(width: AlmanacDimens.sp3),
              Expanded(
                child: AppPrimaryButton(
                  key: const Key('boundary-finish'),
                  label: 'Finish',
                  icon: LucideIcons.check,
                  onPressed: onFinish,
                ),
              ),
            ],
          ),
          const SizedBox(height: AlmanacDimens.sp4),
        ],
      ),
    );
  }
}

class _CannotStart extends StatelessWidget {
  final WalkUnavailable reason;
  final VoidCallback onRetry;
  final Future<bool> Function() onSettings;
  final VoidCallback onBack;

  const _CannotStart({
    required this.reason,
    required this.onRetry,
    required this.onSettings,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListView(
      key: const Key('boundary-cannot-start'),
      padding: const EdgeInsets.symmetric(horizontal: AlmanacDimens.gutter),
      children: [
        Text(
          reason.permissionDenied
              ? 'Location is needed to walk a boundary'
              : 'The walk could not start',
          style: text.titleMedium,
        ),
        const SizedBox(height: AlmanacDimens.sp3),
        _Callout(
          icon: LucideIcons.mapPinOff,
          tone: _Tone.warn,
          message: reason.reason,
        ),
        const SizedBox(height: AlmanacDimens.sp5),
        if (reason.permissionDenied) ...[
          AppPrimaryButton(
            key: const Key('boundary-open-settings'),
            label: 'Open Settings',
            icon: LucideIcons.settings,
            onPressed: () => unawaited(onSettings()),
          ),
          const SizedBox(height: AlmanacDimens.sp3),
        ],
        AppTonalButton(
          label: 'Try again',
          icon: LucideIcons.rotateCcw,
          onPressed: onRetry,
        ),
        const SizedBox(height: AlmanacDimens.sp3),
        AppTonalButton(
          label: 'Back to the farm',
          icon: LucideIcons.arrowLeft,
          onPressed: onBack,
        ),
        const SizedBox(height: AlmanacDimens.sp3),
        Text(
          'The section keeps the area you typed until it is walked.',
          style: text.bodySmall,
        ),
      ],
    );
  }
}

/// AR against GPS — the check the walk runs on itself.
class _Agreement extends StatelessWidget {
  final WalkResult? result;
  final bool edited;

  const _Agreement({required this.result, required this.edited});

  @override
  Widget build(BuildContext context) {
    final r = result;
    if (r == null) {
      return const _Callout(
        key: Key('boundary-agreement'),
        icon: LucideIcons.pencil,
        tone: _Tone.calm,
        message: 'Editing the saved shape. Walk it again to measure afresh.',
      );
    }
    final fraction = r.disagreementFraction;
    if (fraction == null) {
      return _Callout(
        key: const Key('boundary-agreement'),
        icon: LucideIcons.satellite,
        tone: _Tone.calm,
        message:
            'Measured with GPS only, so there is no second measurement to '
            'check it against. Drag any corner that looks off.'
            '${r.poorFixesDropped > 0 ? ' ${r.poorFixesDropped} weak GPS readings were left out.' : ''}',
      );
    }
    final percent = (fraction * 100).round();
    final ar = formatArea(r.arAreaM2!);
    final gps = formatArea(r.gpsAreaM2!);
    return r.agreementWarning
        ? _Callout(
            key: const Key('boundary-agreement'),
            icon: LucideIcons.triangleAlert,
            tone: _Tone.warn,
            message:
                'AR measured $ar and GPS measured $gps — $percent% apart, '
                'more than the 15% they should be within. Check the corners '
                'on the map, or walk it again with a clear view of the sky.',
          )
        : _Callout(
            key: const Key('boundary-agreement'),
            icon: LucideIcons.circleCheck,
            tone: _Tone.good,
            message:
                'AR ($ar) and GPS ($gps) agree to within '
                '${percent < 1 ? '1' : '$percent'}%.',
          );
  }
}

enum _Tone { calm, good, warn, bad }

class _Callout extends StatelessWidget {
  final IconData icon;
  final _Tone tone;
  final String message;

  const _Callout({
    super.key,
    required this.icon,
    required this.tone,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final (background, foreground) = switch (tone) {
      _Tone.calm => (c.surfaceContainer, c.onSurface),
      _Tone.good => (c.statusOnTrackContainer, c.onStatusOnTrackContainer),
      _Tone.warn => (
        c.statusNeedsAttentionContainer,
        c.onStatusNeedsAttentionContainer,
      ),
      _Tone.bad => (
        c.statusActionRequiredContainer,
        c.onStatusActionRequiredContainer,
      ),
    };
    return Container(
      padding: const EdgeInsets.all(AlmanacDimens.sp3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AlmanacDimens.rMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: foreground),
          const SizedBox(width: AlmanacDimens.sp2),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

class _Missing extends StatelessWidget {
  const _Missing();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AlmanacDimens.gutter),
    child: EmptyState(
      icon: LucideIcons.mapPinOff,
      headline: 'That section is not on this phone',
      body: 'It may have been deleted. Go back to the farm and pick another.',
      actionLabel: 'Back to the farm',
      onAction: () => GoRouter.of(context).go('/farm'),
    ),
  );
}
