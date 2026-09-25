/// Camera, microphone and location on Profile: where each stands, what it is
/// for, and the one thing the farmer can do about it.
///
/// Opening this asks for nothing. It only reads the states, which never
/// prompts; a prompt appears only when the farmer taps Allow or Ask again.
/// Where the phone will not prompt any more, the action is Open settings, and
/// the states are read again when the farmer comes back from there.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.g.dart';
import '../../core/ui/buttons.dart';
import '../../core/ui/layout.dart';
import '../../data/device/device_permissions.dart';
import '../../domain/device/device_permissions.dart';

/// Built on first read, which is when Profile is first shown — and building it
/// touches nothing on the phone.
final permissionServiceProvider = Provider<PermissionService>(
  (ref) => HandlerPermissionService(),
);

class PermissionControls extends ConsumerStatefulWidget {
  const PermissionControls({super.key});

  @override
  ConsumerState<PermissionControls> createState() => _PermissionControlsState();
}

class _PermissionControlsState extends ConsumerState<PermissionControls> {
  final _states = <DevicePermission, PermissionState>{};

  /// The permission whose prompt or settings page is open, if any.
  DevicePermission? _busy;
  late final AppLifecycleListener _lifecycle;

  PermissionService get _service => ref.read(permissionServiceProvider);

  @override
  void initState() {
    super.initState();
    // Back from the phone's settings, or from any other app that may have
    // changed them.
    _lifecycle = AppLifecycleListener(onResume: _refresh);
    _refresh();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    for (final permission in DevicePermission.values) {
      final PermissionState state;
      try {
        state = await _service.check(permission);
      } on Object {
        // A phone that cannot say shows no state rather than a wrong one.
        continue;
      }
      if (!mounted) return;
      setState(() => _states[permission] = state);
    }
  }

  Future<void> _act(DevicePermission permission, PermissionState state) async {
    if (_busy != null) return;
    setState(() => _busy = permission);
    try {
      if (state.canAsk) {
        final answer = await _service.request(permission);
        if (mounted) setState(() => _states[permission] = answer);
      } else {
        // The new state arrives through onResume.
        await _service.openSettings();
      }
    } on Object {
      // Nothing changed on the phone; the row stays as it was.
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) => AlmanacCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final permission in DevicePermission.values)
          _PermissionRow(
            key: Key('permission-${permission.name}'),
            permission: permission,
            state: _states[permission],
            busy: _busy == permission,
            last: permission == DevicePermission.values.last,
            onAction: _busy == null
                ? () => _act(permission, _states[permission]!)
                : null,
          ),
      ],
    ),
  );
}

class _PermissionRow extends StatelessWidget {
  final DevicePermission permission;

  /// Null until read, or when the phone could not say.
  final PermissionState? state;
  final bool busy;
  final bool last;
  final VoidCallback? onAction;

  const _PermissionRow({
    super.key,
    required this.permission,
    required this.state,
    required this.busy,
    required this.last,
    required this.onAction,
  });

  static IconData _icon(DevicePermission p) => switch (p) {
    DevicePermission.camera => LucideIcons.camera,
    DevicePermission.microphone => LucideIcons.mic,
    DevicePermission.location => LucideIcons.mapPin,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;
    final state = this.state;

    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : AlmanacDimens.sp4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // One node for TalkBack: "Camera, To scan your crops and animals,
          // Allowed".
          MergeSemantics(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_icon(permission), size: 20, color: c.onSurface),
                const SizedBox(width: AlmanacDimens.sp4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(permission.label, style: text.bodyLarge),
                      Text(
                        permission.reason,
                        style: text.bodySmall?.copyWith(
                          color: c.onSurfaceVariant,
                        ),
                      ),
                      if (state != null) ...[
                        const SizedBox(height: AlmanacDimens.sp2),
                        _StateLine(state),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (state != null && state != PermissionState.allowed) ...[
            const SizedBox(height: AlmanacDimens.sp3),
            Padding(
              padding: const EdgeInsets.only(left: 20 + AlmanacDimens.sp4),
              child: AppSecondaryButton(
                label: _actionLabel(state, busy),
                icon: state.canAsk ? null : LucideIcons.settings,
                onPressed: onAction,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _actionLabel(PermissionState state, bool busy) => switch (state) {
    _ when busy => state.canAsk ? 'Asking…' : 'Opening settings…',
    PermissionState.notAsked => 'Allow ${permission.label.toLowerCase()}',
    PermissionState.refused => 'Ask again',
    PermissionState.settingsOnly || PermissionState.allowed => 'Open settings',
  };
}

/// The state as a glyph, a word and a colour — never colour alone.
class _StateLine extends StatelessWidget {
  final PermissionState state;

  const _StateLine(this.state);

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final (icon, colour, words) = switch (state) {
      PermissionState.allowed => (
        LucideIcons.circleCheckBig,
        c.statusOnTrack,
        'Allowed',
      ),
      PermissionState.notAsked => (
        LucideIcons.circleHelp,
        c.onSurfaceVariant,
        'Not asked yet',
      ),
      PermissionState.refused => (
        LucideIcons.circleX,
        c.statusNeedsAttention,
        'Refused',
      ),
      PermissionState.settingsOnly => (
        LucideIcons.lock,
        c.statusActionRequired,
        'Blocked. Only the phone settings can change this.',
      ),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 15, color: colour),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            words,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: colour),
          ),
        ),
      ],
    );
  }
}
