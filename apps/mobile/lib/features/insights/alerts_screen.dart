/// Alerts — design 34.
///
/// Worked out on this phone from the farm's own records (`farm_alerts.dart`),
/// so it opens the same with or without a signal. Every alert says what it
/// is, where, and what to do; each opens the section it is about. Nothing here
/// is the only place a warning appears: Home and the section show it too.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.g.dart';
import '../../core/ui/buttons.dart';
import '../../core/ui/layout.dart';
import '../../domain/farm_alerts.dart';
import '../shell/almanac_scaffold.dart';
import '../shell/bottom_nav_island.dart';

/// The farm's alerts, or null when there is no farm on this phone yet.
final farmAlertsProvider = Provider<AsyncValue<List<FarmAlert>?>>((ref) {
  final now = ref.watch(clockProvider);
  return ref
      .watch(farmProvider)
      .whenData((farm) => farm == null ? null : farmAlerts(farm, now()));
});

class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(seedProvider);
    final alerts = ref.watch(farmAlertsProvider);
    final text = Theme.of(context).textTheme;
    final c = context.semantic;

    return AlmanacScaffold(
      destination: NavDestination.insights,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AlmanacDimens.gutter,
            AlmanacDimens.sp4,
            AlmanacDimens.gutter,
            BottomNavIsland.bottomInset,
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconOnlyButton(
                icon: LucideIcons.arrowLeft,
                semanticLabel: 'Back to Insights',
                onPressed: () => context.go('/insights'),
              ),
            ),
            const SectionHeader(title: 'Alerts'),
            Text(switch (alerts) {
              AsyncData(value: final list?) when list.isNotEmpty =>
                list.length == 1
                    ? '1 thing worth knowing'
                    : '${list.length} things worth knowing',
              _ => 'Worked out from your records on this phone.',
            }, style: text.bodyMedium?.copyWith(color: c.onSurfaceVariant)),
            const SizedBox(height: AlmanacDimens.sp4),
            switch (alerts) {
              AsyncData(value: null) => const EmptyState(
                icon: LucideIcons.bell,
                headline: 'No farm on this phone yet',
                body:
                    'Set up your farm and anything that needs you shows here.',
              ),
              AsyncData(value: final list?) =>
                list.isEmpty
                    ? const EmptyState(
                        icon: LucideIcons.bellOff,
                        headline: 'Nothing needs you right now',
                        body:
                            'Late jobs, checks that found a problem and open '
                            'harvest windows show up here.',
                      )
                    : AlmanacCard(
                        child: Column(
                          children: [
                            for (final (i, alert) in list.indexed) ...[
                              if (i > 0)
                                Divider(height: 1, color: c.outlineVariant),
                              _AlertRow(alert: alert),
                            ],
                          ],
                        ),
                      ),
              AsyncError() => EmptyState(
                icon: LucideIcons.refreshCw,
                headline: 'Your farm records could not be opened',
                body: 'They are still saved on this phone. Try again.',
                actionLabel: 'Try again',
                actionIcon: LucideIcons.refreshCw,
                onAction: () => ref.invalidate(farmProvider),
              ),
              _ => const SizedBox.shrink(),
            },
            const SizedBox(height: AlmanacDimens.sp4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.info, size: 18, color: c.onSurfaceVariant),
                const SizedBox(width: AlmanacDimens.sp3),
                Expanded(
                  child: Text(
                    'Anything urgent also shows on Home and on the section it '
                    'affects — you never have to come here to find out.',
                    style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertRow extends StatelessWidget {
  final FarmAlert alert;

  const _AlertRow({required this.alert});

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;
    final (background, foreground, icon) = switch (alert.tone) {
      AlertTone.actionRequired => (
        c.statusActionRequiredContainer,
        c.onStatusActionRequiredContainer,
        LucideIcons.triangleAlert,
      ),
      AlertTone.needsAttention => (
        c.statusNeedsAttentionContainer,
        c.onStatusNeedsAttentionContainer,
        LucideIcons.leaf,
      ),
      AlertTone.worthKnowing => (
        c.primaryContainer,
        c.onPrimaryContainer,
        LucideIcons.sprout,
      ),
    };
    return Semantics(
      identifier: 'alert-${alert.kind.name}-${alert.sectionId}',
      button: true,
      child: InkWell(
        onTap: () => context.push('/farm/zone/${alert.sectionId}'),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AlmanacDimens.touchMin),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AlmanacDimens.sp4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(AlmanacDimens.rSm),
                  ),
                  child: Icon(icon, size: 20, color: foreground),
                ),
                const SizedBox(width: AlmanacDimens.sp3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(alert.title, style: text.titleSmall),
                      const SizedBox(height: AlmanacDimens.sp1),
                      Text(
                        alert.detail,
                        style: text.bodySmall?.copyWith(
                          color: c.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AlmanacDimens.sp2),
                      Text(
                        alert.when,
                        style: text.labelSmall?.copyWith(
                          color: c.onSurfaceVariant,
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
    );
  }
}
