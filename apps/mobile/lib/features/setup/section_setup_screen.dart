/// First section setup — design screen 16 — and the one screen that adds a
/// section, wherever it is opened from.
///
/// Its own route, `/setup/section`, so the Farm tab's "Add section" can open
/// it too. `?next=/farm` says where to go once the section is saved; with no
/// `next` it goes to Home, which is where first setup ends.
///
/// The section is created through `FarmRepository.createSection`, which saves
/// it on the phone and queues it for the server — so this works with no
/// signal, and the farmer can record against the section straight away.
///
/// Area is typed. Walking the boundary with the camera is issue #15; a farmer
/// who knows their plot is "about half a hectare" should not have to wait for
/// it. What the design shows that this does not — what the section is used
/// for, the current crop, a photo — are plantings and media, which are
/// recorded from the section once it exists.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.g.dart';
import '../../core/ui/buttons.dart';
import '../../core/ui/fields.dart';
import '../../core/ui/flow_controls.dart';
import '../../core/utils/ids.dart';
import '../../domain/farm_repository.dart';
import '../auth/widgets/auth_scaffold.dart';
import 'setup_providers.dart';
import 'widgets/farm_on_its_way.dart';
import 'widgets/setup_note.dart';

enum AreaUnit { hectares, squareMetres }

/// The typed area as the API's `area_m2` — a decimal string with two places
/// — or null if it is not a usable area.
///
/// Takes a comma as the decimal mark as readily as a point: South African
/// phones default to the comma, and "0,5" is how a farmer here writes half.
String? areaM2From(String typed, AreaUnit unit) {
  final value = double.tryParse(typed.trim().replaceAll(',', '.'));
  if (value == null || !value.isFinite) return null;
  final m2 = unit == AreaUnit.hectares ? value * 10000 : value;
  // The server keeps two places and refuses zero. Anything larger than a
  // hundred thousand hectares is a typing slip, not a smallholding section.
  if (m2 < 0.01 || m2 > 1e9) return null;
  return m2.toStringAsFixed(2);
}

class SectionSetupScreen extends ConsumerStatefulWidget {
  /// Where to go once the section is saved. Home when null.
  final String? next;

  const SectionSetupScreen({super.key, this.next});

  @override
  ConsumerState<SectionSetupScreen> createState() => _SectionSetupScreenState();
}

class _SectionSetupScreenState extends ConsumerState<SectionSetupScreen> {
  final _name = TextEditingController();
  final _area = TextEditingController();
  AreaUnit _unit = AreaUnit.hectares;
  bool _busy = false;
  bool _nameMissing = false;
  bool _areaInvalid = false;
  String? _notice;

  /// One per section this screen adds, reused for every retry of it — the
  /// contract `createSection` asks for, so a retried save never makes two.
  String? _mutationId;

  @override
  void dispose() {
    _name.dispose();
    _area.dispose();
    super.dispose();
  }

  /// Leaves for [SectionSetupScreen.next] — and, whether a section was
  /// added or the farmer chose to skip, first setup is no longer owed.
  void _leave() {
    final scope = ref.read(farmScopeProvider);
    if (scope.isAccount) {
      unawaited(
        ref.read(setupOwedProvider).settle(scope.ownerId, scope.farmId),
      );
    }
    context.go(widget.next ?? '/home');
  }

  Future<void> _add() async {
    if (_busy) return;
    final name = _name.text.trim();
    final areaM2 = areaM2From(_area.text, _unit);
    setState(() {
      _nameMissing = name.isEmpty;
      _areaInvalid = areaM2 == null;
      _notice = null;
    });
    if (name.isEmpty || areaM2 == null) return;
    // Checked again at the moment of writing, not only when the screen drew:
    // a section written while the account's farm is still on its way would
    // land in the demo farm instead of the farmer's.
    if (ref.read(awaitingAccountFarmProvider)) return;

    final repository = ref.read(farmRecordsProvider);
    if (repository is! FarmRepository) return;
    setState(() => _busy = true);
    _mutationId ??= newUuid();
    try {
      await (repository as FarmRepository).createSection(
        mutationId: _mutationId!,
        name: name,
        areaM2: areaM2,
      );
    } on SessionExpired {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _notice =
            'There is no farm on this phone to add it to yet. Open Home and '
            'come back once your farm is showing.';
      });
      return;
    } on Object {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _notice =
            'This phone could not save that. Free up some space and try '
            'again.';
      });
      return;
    }
    if (!mounted) return;
    _leave();
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(awaitingAccountFarmProvider)) return const FarmOnItsWay();

    final c = context.semantic;
    final text = Theme.of(context).textTheme;

    return AuthScaffold(
      // First setup opens this with nowhere to go but Home; anywhere else
      // names where to return.
      title: widget.next == null ? 'Add your first section' : 'Add a section',
      subtitle: 'A section is one piece of land you use for one thing.',
      onBack: backOr(context, widget.next ?? '/home'),
      children: [
        AppTextField(
          label: 'Section name',
          controller: _name,
          hint: 'For example, Cabbage Field',
          enabled: !_busy,
          maxLength: 100,
          textCapitalization: TextCapitalization.words,
          tone: _nameMissing ? FieldTone.error : FieldTone.neutral,
          helper: _nameMissing
              ? 'Name it the way you would point it out — "the river beds".'
              : null,
          onChanged: (_) {
            if (_nameMissing) setState(() => _nameMissing = false);
          },
        ),
        Text(
          'Measured in',
          style: text.labelMedium?.copyWith(color: c.onSurfaceVariant),
        ),
        const SizedBox(height: AlmanacDimens.sp2),
        AppSegmentedControl<AreaUnit>(
          options: const [
            SegmentOption(
              value: AreaUnit.hectares,
              label: 'Hectares',
              icon: LucideIcons.map,
            ),
            SegmentOption(
              value: AreaUnit.squareMetres,
              label: 'Square metres',
              icon: LucideIcons.ruler,
            ),
          ],
          value: _unit,
          onChanged: (unit) => setState(() {
            _unit = unit;
            _areaInvalid = false;
          }),
        ),
        const SizedBox(height: AlmanacDimens.sp4),
        AppTextField(
          label: 'Area',
          controller: _area,
          hint: _unit == AreaUnit.hectares
              ? 'For example, 0,5'
              : 'For example, 400',
          enabled: !_busy,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          maxLength: 12,
          tone: _areaInvalid ? FieldTone.error : FieldTone.neutral,
          helper: _areaInvalid
              ? 'Type the size as a number bigger than 0, like 0,5.'
              : _unit == AreaUnit.hectares
              ? 'One hectare is 100 by 100 metres. A guess is fine — you can '
                    'walk it later.'
              : 'A 20 by 20 metre plot is 400 square metres. A guess is '
                    'fine — you can walk it later.',
          onChanged: (_) {
            if (_areaInvalid) setState(() => _areaInvalid = false);
          },
          onSubmitted: _add,
        ),
        const SizedBox(height: AlmanacDimens.sp2),
        if (_notice != null) AuthNotice(message: _notice!),
        AppPrimaryButton(
          label: 'Add section',
          icon: LucideIcons.check,
          busyLabel: _busy ? 'Saving…' : null,
          onPressed: _busy ? null : _add,
        ),
        const SizedBox(height: AlmanacDimens.sp3),
        AppTonalButton(label: 'Skip for now', onPressed: _busy ? null : _leave),
        const SizedBox(height: AlmanacDimens.sp5),
        SetupNote(
          icon: LucideIcons.cloudOff,
          message: ref.watch(farmScopeProvider).isAccount
              ? 'Saved on your phone first. It reaches your account the next '
                    'time you have a signal.'
              : 'Saved on this phone. The demo farm is never sent anywhere.',
        ),
      ],
    );
  }
}
