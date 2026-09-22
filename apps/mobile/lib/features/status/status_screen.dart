import 'package:flutter/material.dart';

import '../../app/config.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.g.dart';
import '../../data/health_service.dart';

/// The app's first screen while the real Home dashboard is being built.
///
/// It exists to prove one thing the product depends on: the app opens and
/// reports its connectivity honestly, and an unreachable API reads as a calm
/// state rather than a failure. `e2e/mobile/*.yaml` drive exactly this.
class StatusScreen extends StatefulWidget {
  final HealthService? healthService;

  const StatusScreen({super.key, this.healthService});

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  late final HealthService _health = widget.healthService ?? HealthService();
  Reachability _status = Reachability.checking;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _status = Reachability.checking);
    final result = await _health.check();
    if (mounted) setState(() => _status = result);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AlmanacDimens.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AlmanacDimens.sp6),
              Text('Almanac', style: text.displayLarge),
              const SizedBox(height: AlmanacDimens.sp2),
              Text(
                'Farm decision support for South African smallholders.',
                style: text.bodyMedium?.copyWith(
                  color: context.semantic.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AlmanacDimens.sp7),
              _ConnectivityChip(status: _status),
              const SizedBox(height: AlmanacDimens.sp6),
              FilledButton(
                onPressed: _status == Reachability.checking ? null : _refresh,
                child: const Text('Check again'),
              ),
              const Spacer(),
              Text(
                'Build $buildSha',
                style: text.labelSmall?.copyWith(
                  color: context.semantic.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Status is carried by icon *and* text *and* colour — never colour alone.
///
/// Offline uses the reserved neutral-slate ramp, which is unreachable from the
/// error red by design, so an offline phone can never be mistaken for a broken
/// one at a glance in bright sun.
class _ConnectivityChip extends StatelessWidget {
  final Reachability status;

  const _ConnectivityChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;

    final (label, icon, foreground, background) = switch (status) {
      Reachability.checking => (
        'Checking',
        Icons.sync_rounded,
        c.onConnOfflineContainer,
        c.connOfflineContainer,
      ),
      Reachability.online => (
        'Online',
        Icons.cloud_done_rounded,
        c.onStatusOnTrackContainer,
        c.statusOnTrackContainer,
      ),
      Reachability.offline => (
        'Offline',
        Icons.cloud_off_rounded,
        c.onConnOfflineContainer,
        c.connOfflineContainer,
      ),
    };

    return Semantics(
      // Maestro matches this as the element id; e2e/mobile/*.yaml assert on it.
      identifier: 'api-status',
      // Merge into a single node so a screen reader announces the chip once,
      // reading the visible text rather than repeating it after a label.
      container: true,
      child: Container(
        key: const Key('api-status'),
        constraints: const BoxConstraints(minHeight: AlmanacDimens.touchMin),
        padding: const EdgeInsets.symmetric(
          horizontal: AlmanacDimens.sp5,
          vertical: AlmanacDimens.sp3,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AlmanacDimens.rPill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: foreground),
            const SizedBox(width: AlmanacDimens.sp2),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: foreground),
            ),
          ],
        ),
      ),
    );
  }
}
