import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/config.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.g.dart';
import '../../core/ui/badges.dart';
import '../../core/ui/buttons.dart';
import '../../core/ui/layout.dart';
import '../../data/device/location_service.dart';
import '../../domain/device/permission_copy.dart';
import '../../domain/device/self_test.dart';
import 'self_test_controller.dart';

/// Checks, on a real phone, the device capabilities later features depend on
/// — camera, depth, AR surfaces, microphone, the detector and location — and
/// says for each one: works, does not work, or this phone does not have it.
///
/// Nothing is asked for until the person taps Run. The permission prompts
/// arrive one at a time, as the check that needs each one starts, after the
/// screen has said in plain words what each is for.
class SelfTestScreen extends StatefulWidget {
  /// Replaced in tests. Defaults to the phone's real hardware.
  final SelfTestDevices? devices;

  const SelfTestScreen({super.key, this.devices});

  @override
  State<SelfTestScreen> createState() => _SelfTestScreenState();
}

class _SelfTestScreenState extends State<SelfTestScreen>
    with WidgetsBindingObserver {
  late final SelfTestController _controller = SelfTestController(
    widget.devices ?? SelfTestDevices.onDevice(),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  /// Leaving the app mid-test stops it. The OS takes the camera and the
  /// microphone from a backgrounded app anyway, and a test that carried on
  /// would record, prompt or report on things the person never saw.
  ///
  /// Only hidden/paused, not inactive: a permission prompt makes the app
  /// inactive, and the test is waiting on exactly that prompt.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _controller.cancel(
        'Stopped because Almanac was left mid-test. Run it again to finish.',
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Leaving the screen stops the run too; see SelfTestController.dispose.
    _controller.dispose();
    super.dispose();
  }

  void _back() {
    final router = GoRouter.maybeOf(context);
    if (router == null) return;
    if (router.canPop()) {
      router.pop();
    } else {
      router.go('/status');
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.semantic;

    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) {
            final ctl = _controller;
            return ListView(
              padding: const EdgeInsets.fromLTRB(
                AlmanacDimens.gutter,
                AlmanacDimens.sp3,
                AlmanacDimens.gutter,
                AlmanacDimens.sp8,
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    tooltip: 'Back',
                    onPressed: _back,
                    icon: const Icon(LucideIcons.arrowLeft),
                  ),
                ),
                Text('Device self-test', style: text.headlineMedium),
                const SizedBox(height: AlmanacDimens.sp2),
                Text(
                  'Checks the parts of this phone Almanac relies on. It '
                  'takes about a minute, and the result stays on this phone.',
                  style: text.bodyMedium?.copyWith(color: c.onSurfaceVariant),
                ),
                if (testMode) ...[
                  const SizedBox(height: AlmanacDimens.sp4),
                  const ConstraintChip(
                    icon: LucideIcons.film,
                    text:
                        'Test mode: the camera check plays recorded frames, '
                        'not the live camera.',
                    tone: ChipTone.warn,
                  ),
                ],
                const SizedBox(height: AlmanacDimens.sp5),
                const _PermissionsCard(),
                const SizedBox(height: AlmanacDimens.sp5),
                Semantics(
                  identifier: 'self-test-run',
                  child: AppPrimaryButton(
                    label: ctl.phase == SelfTestPhase.done
                        ? 'Run again'
                        : 'Run self-test',
                    busyLabel: ctl.isRunning ? 'Testing…' : null,
                    icon: LucideIcons.play,
                    onPressed: ctl.isRunning ? null : ctl.run,
                  ),
                ),
                if (ctl.stoppedReason case final reason?) ...[
                  const SizedBox(height: AlmanacDimens.sp3),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      reason,
                      key: const Key('self-test-stopped'),
                      style: text.bodyMedium,
                    ),
                  ),
                ],
                _LivePanel(controller: ctl),
                const SizedBox(height: AlmanacDimens.sp3),
                for (final item in SelfTestItem.values)
                  _ResultRow(
                    item: item,
                    result: ctl.results[item],
                    running: ctl.active.contains(item),
                  ),
                if (ctl.fix case final fix?) _FixMap(fix: fix),
                if (ctl.report case final report?)
                  _ReportCard(
                    report: report,
                    savedPath: ctl.savedPath,
                    saveProblem: ctl.saveProblem,
                  ),
                const SizedBox(height: AlmanacDimens.sp5),
                // docs/sideload.md has testers record this against each phone.
                Text(
                  'Build $buildSha',
                  style: text.labelSmall?.copyWith(color: c.onSurfaceVariant),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Says what each permission is for before any prompt appears. On Android
/// this is the only place the farmer sees the reason — the system prompt
/// carries no app text.
class _PermissionsCard extends StatelessWidget {
  const _PermissionsCard();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.semantic;
    Widget row(IconData icon, String name, String why) => Padding(
      padding: const EdgeInsets.only(top: AlmanacDimens.sp3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: c.primary),
          const SizedBox(width: AlmanacDimens.sp3),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '$name — ', style: text.labelLarge),
                  TextSpan(text: why, style: text.bodyMedium),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return AlmanacCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('It will ask to use', style: text.titleMedium),
          row(LucideIcons.camera, 'Camera', PermissionCopy.camera),
          row(LucideIcons.mic, 'Microphone', PermissionCopy.microphone),
          row(LucideIcons.mapPin, 'Location', PermissionCopy.location),
        ],
      ),
    );
  }
}

/// The camera preview while it runs, and an instruction for the checks that
/// need the person to do something.
class _LivePanel extends StatelessWidget {
  final SelfTestController controller;

  const _LivePanel({required this.controller});

  @override
  Widget build(BuildContext context) {
    final camera = controller.camera;
    final hint = switch (controller.phase) {
      SelfTestPhase.camera => camera == null ? 'Opening the camera…' : null,
      SelfTestPhase.ar =>
        'Point the phone at the floor or ground and move it slowly.',
      SelfTestPhase.recording => 'Recording for 3 seconds — say something.',
      SelfTestPhase.playing => 'Playing it back. You should hear yourself.',
      SelfTestPhase.detector => 'Timing the detector on a sample picture…',
      SelfTestPhase.location => 'Finding this phone…',
      SelfTestPhase.saving => 'Saving the result…',
      SelfTestPhase.idle || SelfTestPhase.done => null,
    };

    return Column(
      children: [
        if (camera != null) ...[
          const SizedBox(height: AlmanacDimens.sp4),
          ClipRRect(
            borderRadius: BorderRadius.circular(AlmanacDimens.rXl),
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: ColoredBox(
                color: const Color(0xFF000000),
                child: camera.buildPreview(),
              ),
            ),
          ),
        ],
        if (hint != null) ...[
          const SizedBox(height: AlmanacDimens.sp4),
          Semantics(
            liveRegion: true,
            child: Text(
              hint,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ],
      ],
    );
  }
}

class _ResultRow extends StatelessWidget {
  final SelfTestItem item;
  final CheckResult? result;
  final bool running;

  const _ResultRow({
    required this.item,
    required this.result,
    required this.running,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.semantic;
    final result = this.result;
    final state = running
        ? 'Testing'
        : switch (result?.outcome) {
            null => 'Not run yet',
            CheckOutcome.pass => 'Pass',
            CheckOutcome.fail => 'Fail',
            CheckOutcome.unsupported => 'Not supported on this phone',
          };

    return Semantics(
      identifier: 'self-test-${item.name}',
      // One node per row, so a screen reader — and Maestro, which matches
      // the whole string — reads "Camera preview: Pass" as a unit.
      container: true,
      child: Padding(
        padding: const EdgeInsets.only(top: AlmanacDimens.sp3),
        child: AlmanacCard(
          padding: const EdgeInsets.all(AlmanacDimens.sp4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_icon(item), size: 20, color: c.onSurfaceVariant),
                  const SizedBox(width: AlmanacDimens.sp3),
                  Expanded(child: Text(item.label, style: text.titleSmall)),
                ],
              ),
              const SizedBox(height: AlmanacDimens.sp2),
              OutcomePill(
                key: Key('self-test-${item.name}-outcome'),
                outcome: running ? null : result?.outcome,
                running: running,
                label: state,
              ),
              if (result != null && !running) ...[
                const SizedBox(height: AlmanacDimens.sp2),
                Text(
                  result.detail,
                  style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static IconData _icon(SelfTestItem item) => switch (item) {
    SelfTestItem.camera => LucideIcons.camera,
    SelfTestItem.depth => LucideIcons.layers,
    SelfTestItem.arPlane => LucideIcons.scan,
    SelfTestItem.microphone => LucideIcons.mic,
    SelfTestItem.detector => LucideIcons.timer,
    SelfTestItem.location => LucideIcons.mapPin,
  };
}

/// Pass / Fail / Not supported, told by icon, word and colour together.
///
/// "Not supported" takes the neutral slate, never the error red: a phone
/// without LiDAR is answering the question correctly, not failing it.
class OutcomePill extends StatelessWidget {
  final CheckOutcome? outcome;
  final bool running;
  final String label;

  const OutcomePill({
    super.key,
    required this.outcome,
    required this.running,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final (icon, background, foreground) = running
        ? (LucideIcons.loaderCircle, c.tertiaryContainer, c.onTertiaryContainer)
        : switch (outcome) {
            CheckOutcome.pass => (
              LucideIcons.circleCheckBig,
              c.statusOnTrackContainer,
              c.onStatusOnTrackContainer,
            ),
            CheckOutcome.fail => (
              LucideIcons.circleX,
              c.statusActionRequiredContainer,
              c.onStatusActionRequiredContainer,
            ),
            CheckOutcome.unsupported => (
              LucideIcons.circleMinus,
              c.connOfflineContainer,
              c.onConnOfflineContainer,
            ),
            null => (
              LucideIcons.circleDashed,
              c.surfaceContainerHigh,
              c.onSurface,
            ),
          };

    return Container(
      padding: const EdgeInsets.fromLTRB(9, 5, 11, 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AlmanacDimens.rPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: foreground),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

/// The fix, and — only if the person asks — the fix on a map.
///
/// Map tiles come from OpenStreetMap's servers, and the tiles a map asks for
/// say roughly where the phone is. So nothing is fetched until the person
/// taps "Show on a map", after the screen has said exactly that; until then
/// the self-test sends nothing anywhere, as its intro promises. Once shown,
/// the map carries OpenStreetMap's attribution, which its licence requires.
class _FixMap extends StatefulWidget {
  final LocationFix fix;

  const _FixMap({required this.fix});

  @override
  State<_FixMap> createState() => _FixMapState();
}

class _FixMapState extends State<_FixMap> {
  var _shown = false;

  static final _copyright = Uri.parse(
    'https://www.openstreetmap.org/copyright',
  );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.semantic;

    if (!_shown) {
      return Padding(
        padding: const EdgeInsets.only(top: AlmanacDimens.sp3),
        child: AlmanacCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Showing the map loads map pictures from OpenStreetMap, '
                'which lets their servers see roughly where this phone is. '
                'Nothing else is sent.',
                style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
              ),
              const SizedBox(height: AlmanacDimens.sp3),
              AppSecondaryButton(
                label: 'Show on a map',
                icon: LucideIcons.map,
                onPressed: () => setState(() => _shown = true),
              ),
            ],
          ),
        ),
      );
    }

    final point = LatLng(widget.fix.latitude, widget.fix.longitude);
    return Padding(
      padding: const EdgeInsets.only(top: AlmanacDimens.sp3),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AlmanacDimens.rXl),
        child: SizedBox(
          height: 200,
          child: FlutterMap(
            key: const Key('self-test-map'),
            options: MapOptions(
              initialCenter: point,
              initialZoom: 16,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.none,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                // Identifies the app to OpenStreetMap, as its tile usage
                // policy asks. One fix, fetched once, on request.
                userAgentPackageName: 'za.co.almanac.app',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: point,
                    child: Icon(LucideIcons.mapPin, color: c.primary, size: 32),
                  ),
                ],
              ),
              // Not flutter_map's SimpleAttributionWidget: that is a single
              // row that overflows rather than wraps on a narrow phone or at
              // a large text size. This wraps, and stays tappable.
              Align(
                alignment: Alignment.bottomRight,
                child: Semantics(
                  link: true,
                  child: GestureDetector(
                    onTap: () => launchUrl(
                      _copyright,
                      mode: LaunchMode.externalApplication,
                    ),
                    child: Container(
                      margin: const EdgeInsets.all(AlmanacDimens.sp2),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AlmanacDimens.sp2,
                        vertical: AlmanacDimens.sp1,
                      ),
                      decoration: BoxDecoration(
                        color: c.surface.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(AlmanacDimens.rSm),
                      ),
                      child: Text(
                        '© OpenStreetMap contributors',
                        maxLines: 2,
                        style: text.labelSmall?.copyWith(
                          color: c.onSurface,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final SelfTestReport report;
  final String? savedPath;
  final String? saveProblem;

  const _ReportCard({
    required this.report,
    required this.savedPath,
    required this.saveProblem,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.semantic;
    final passed = report.overall == CheckOutcome.pass;
    final json = const JsonEncoder.withIndent('  ').convert(report.toJson());

    return Padding(
      padding: const EdgeInsets.only(top: AlmanacDimens.sp5),
      child: AlmanacCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Result', style: text.titleMedium),
            const SizedBox(height: AlmanacDimens.sp2),
            Semantics(
              identifier: 'self-test-overall',
              container: true,
              child: OutcomePill(
                outcome: report.overall,
                running: false,
                label: passed
                    ? 'This phone passed'
                    : 'Something on this phone did not work',
              ),
            ),
            const SizedBox(height: AlmanacDimens.sp3),
            Text(
              saveProblem ?? 'Saved on this phone.',
              style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
            ),
            const SizedBox(height: AlmanacDimens.sp1),
            Text(
              'Not sent anywhere yet: the server cannot receive self-test '
              'reports until issue #11 is built. Copy the report to share it.',
              style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
            ),
            const SizedBox(height: AlmanacDimens.sp3),
            AppSecondaryButton(
              label: 'Copy report',
              icon: LucideIcons.copy,
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: json));
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Report copied')));
              },
            ),
          ],
        ),
      ),
    );
  }
}
