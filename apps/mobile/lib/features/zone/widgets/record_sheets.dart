/// The sheets and dialogs that edit a section's records.
///
/// Every one of them writes to local storage and returns. None of them shows a
/// progress state waiting on a server, because none of them talks to one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../core/ui/buttons.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/ids.dart';
import '../../../domain/farm_records.dart';
import '../../../domain/farm_repository.dart' show RevisionConflict;
import '../observation_draft.dart';
import '../section_draft.dart';
import '../../../data/device/photo_capture.dart';
import '../zone_view_model.dart';

/// Tapping a timeline item opens this: Edit · Mark complete · Reschedule ·
/// Delete, with the destructive item last and on the red ramp.
Future<void> showTimelineActions({
  required BuildContext context,
  required TimelineEntry entry,
  required ZoneActions actions,

  /// The screen's "today", from `clockProvider`. Passed in rather than read
  /// from `DateTime.now()` so this subtitle is computed against the same day
  /// as the timeline row the farmer tapped to get here, and so a test with a
  /// pinned clock can assert what it says.
  required DateTime today,
}) async {
  final done = entry.task.isDone;

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _SheetMenu(
      title: entry.task.title,
      subtitle: whenPhrase(entry.task.dueDate, today),
      items: [
        _MenuItem(
          icon: LucideIcons.pencil,
          label: 'Edit',
          onTap: () async {
            Navigator.of(sheetContext).pop();
            await showTaskEditor(
              context: context,
              actions: actions,
              task: entry.task,
            );
          },
        ),
        _MenuItem(
          icon: done ? LucideIcons.rotateCcw : LucideIcons.check,
          label: done ? 'Mark not done' : 'Mark complete',
          onTap: () async {
            Navigator.of(sheetContext).pop();
            if (done) {
              await actions.reopen(entry.task.id);
            } else {
              await actions.markComplete(entry.task.id);
            }
          },
        ),
        _MenuItem(
          icon: LucideIcons.calendarClock,
          label: 'Reschedule',
          onTap: () async {
            Navigator.of(sheetContext).pop();
            final picked = await _pickDate(context, entry.task.dueDate);
            if (picked != null) await actions.reschedule(entry.task.id, picked);
          },
        ),
        _MenuItem(
          icon: LucideIcons.trash2,
          label: 'Delete',
          destructive: true,
          onTap: () async {
            Navigator.of(sheetContext).pop();
            final confirmed = await confirmDelete(
              context: context,
              what: entry.task.title,
              explanation: 'It will be taken off this section’s timeline.',
            );
            if (confirmed) await actions.removeTask(entry.task.id);
          },
        ),
      ],
    ),
  );
}

/// Tapping an observation opens this: Edit · Delete.
///
/// Fewer options than the timeline's sheet, because an observation is a record
/// of something that happened. It can be corrected or withdrawn; it cannot be
/// rescheduled or marked complete.
Future<void> showObservationActions({
  required BuildContext context,
  required Observation observation,
  required ZoneActions actions,

  /// The screen's "today". See [showTimelineActions].
  required DateTime today,
}) => showModalBottomSheet<void>(
  context: context,
  backgroundColor: Colors.transparent,
  builder: (sheetContext) => _SheetMenu(
    title: observation.type,
    subtitle: observedAt(observation.createdAt, today),
    items: [
      _MenuItem(
        icon: LucideIcons.pencil,
        label: 'Edit',
        onTap: () async {
          Navigator.of(sheetContext).pop();
          await showObservationEditor(
            context: context,
            actions: actions,
            observation: observation,
          );
        },
      ),
      _MenuItem(
        icon: LucideIcons.trash2,
        label: 'Delete',
        destructive: true,
        onTap: () async {
          Navigator.of(sheetContext).pop();
          final confirmed = await confirmDelete(
            context: context,
            what: 'this observation',
            explanation:
                'It will be taken off this section’s history, and the '
                'health state will go back to whatever you recorded before it.',
          );
          if (confirmed) await actions.removeObservation(observation.id);
        },
      ),
    ],
  ),
);

/// Create or change one task.
Future<void> showTaskEditor({
  required BuildContext context,
  required ZoneActions actions,
  FarmTask? task,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (context) => _TaskForm(actions: actions, task: task),
);

/// Create or change one observation.
Future<void> showObservationEditor({
  required BuildContext context,
  required ZoneActions actions,
  Observation? observation,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (context) =>
      _ObservationForm(actions: actions, observation: observation),
);

/// Rename or re-measure the section.
Future<void> showSectionEditor({
  required BuildContext context,
  required ZoneActions actions,
  required FarmSection section,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (context) => _SectionForm(actions: actions, section: section),
);

/// Asks, naming what goes with the section, and deletes it on a yes.
///
/// Returns whether it was deleted, so the screen can take the farmer home
/// instead of leaving them on a section that is no longer there.
Future<bool> deleteSectionWithConfirmation({
  required BuildContext context,
  required ZoneActions actions,
  required ZoneView view,
}) async {
  // Minted before asking, so the one "yes" is one delete however it is
  // retried.
  final mutationId = newUuid();
  final confirmed = await confirmDelete(
    context: context,
    what: view.section.name,
    explanation: sectionDeleteConsequence(view),
  );
  if (!confirmed) return false;
  await actions.removeSection(mutationId: mutationId);
  return true;
}

/// Names what is being deleted and what that means.
///
/// "Are you sure?" is not a question anyone can answer. The record's own name
/// is in the title and the consequence is in the body.
Future<bool> confirmDelete({
  required BuildContext context,
  required String what,
  required String explanation,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Delete $what?'),
      content: Text(explanation),
      actions: [
        AppTonalButton(
          label: 'Keep it',
          block: false,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppDangerButton(
          label: 'Delete',
          icon: LucideIcons.trash2,
          block: false,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<DateTime?> _pickDate(BuildContext context, DateTime initial) =>
    showDatePicker(
      context: context,
      initialDate: initial,
      // Past dates are allowed on purpose: a farmer recording that they should
      // have weeded last Tuesday is telling the truth, and an app that refuses
      // it teaches them to lie to it.
      firstDate: DateTime(initial.year - 2),
      lastDate: DateTime(initial.year + 3),
    );

// ------------------------------------------------------------------- menu

class _MenuItem {
  final IconData icon;
  final String label;
  final Future<void> Function() onTap;
  final bool destructive;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });
}

class _SheetMenu extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<_MenuItem> items;

  const _SheetMenu({
    required this.title,
    required this.subtitle,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(AlmanacDimens.sp3),
        padding: const EdgeInsets.all(AlmanacDimens.sp4),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AlmanacDimens.r2xl),
          border: Border.all(color: c.outlineVariant),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: c.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AlmanacDimens.sp4),
            Text(title, style: text.titleMedium),
            if (subtitle != null)
              Text(
                subtitle!,
                style: text.labelSmall?.copyWith(color: c.onSurfaceVariant),
              ),
            const SizedBox(height: AlmanacDimens.sp3),
            for (final item in items)
              InkWell(
                onTap: item.onTap,
                borderRadius: BorderRadius.circular(AlmanacDimens.rSm),
                child: SizedBox(
                  height: 52,
                  child: Row(
                    children: [
                      Icon(
                        item.icon,
                        size: 20,
                        color: item.destructive
                            ? c.statusActionRequired
                            : c.onSurface,
                      ),
                      const SizedBox(width: AlmanacDimens.sp3),
                      Text(
                        item.label,
                        style: text.bodyLarge?.copyWith(
                          color: item.destructive
                              ? c.statusActionRequired
                              : c.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ forms

/// Shared sheet chrome: handle, title, scrollable body, action bar.
class _FormSheet extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final String saveLabel;
  final VoidCallback? onSave;

  const _FormSheet({
    required this.title,
    required this.children,
    required this.saveLabel,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AlmanacDimens.r2xl),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(
          AlmanacDimens.gutter,
          AlmanacDimens.sp2,
          AlmanacDimens.gutter,
          AlmanacDimens.sp5,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: AlmanacDimens.sp4),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AlmanacDimens.sp4),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ),
              const SizedBox(height: AlmanacDimens.sp5),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: AppPrimaryButton(
                      label: saveLabel,
                      icon: LucideIcons.check,
                      onPressed: onSave,
                    ),
                  ),
                  const SizedBox(width: AlmanacDimens.sp2),
                  Expanded(
                    child: AppTonalButton(
                      label: 'Cancel',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final String? hint;
  final TextEditingController controller;
  final int maxLines;
  final TextInputType? keyboardType;
  final String? helper;
  final String? error;
  final Key? fieldKey;

  const _Field({
    required this.label,
    required this.controller,
    this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.helper,
    this.error,
    this.fieldKey,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AlmanacDimens.sp4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: text.labelMedium?.copyWith(color: c.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          TextField(
            key: fieldKey,
            controller: controller,
            maxLines: maxLines,
            keyboardType: keyboardType,
            textCapitalization: TextCapitalization.sentences,
            style: text.bodyLarge,
            decoration: InputDecoration(
              hintText: hint,
              helperText: helper,
              errorText: error,
              filled: true,
              fillColor: c.surfaceContainer,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AlmanacDimens.sp4,
                vertical: AlmanacDimens.sp3,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AlmanacDimens.rMd),
                borderSide: BorderSide(color: c.outlineVariant, width: 1.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AlmanacDimens.rMd),
                borderSide: BorderSide(color: c.outlineVariant, width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AlmanacDimens.rMd),
                borderSide: BorderSide(color: c.primary, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ObservationForm extends ConsumerStatefulWidget {
  final ZoneActions actions;
  final Observation? observation;

  const _ObservationForm({required this.actions, this.observation});

  @override
  ConsumerState<_ObservationForm> createState() => _ObservationFormState();
}

class _ObservationFormState extends ConsumerState<_ObservationForm> {
  /// Minted when the form opens, so a second tap on Save is the same
  /// observation and the same photo, never a second of either.
  final _ids = ObservationIds();
  CapturedPhoto? _photo;
  var _saving = false;

  late final TextEditingController _type;
  late final TextEditingController _note;
  late final TextEditingController _action;
  late HealthState _health;

  @override
  void initState() {
    super.initState();
    final existing = widget.observation;
    final draft = existing == null
        ? const ObservationDraft()
        : ObservationDraft.from(existing);
    _type = TextEditingController(text: draft.type);
    _note = TextEditingController(text: draft.note);
    _action = TextEditingController(text: draft.actionTaken);
    _health = draft.health;
    for (final controller in [_type, _note, _action]) {
      controller.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _type.dispose();
    _note.dispose();
    _action.dispose();
    super.dispose();
  }

  ObservationDraft get _draft => ObservationDraft(
    type: _type.text,
    note: _note.text,
    actionTaken: _action.text,
    health: _health,
  );

  Future<void> _takePhoto() async {
    final photo = await ref.read(photoTakerProvider).take(context);
    if (photo != null && mounted) setState(() => _photo = photo);
  }

  Future<void> _save() async {
    if (_saving) return;
    final draft = _draft;
    final existing = widget.observation;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final photo = _photo;

    if (existing == null && photo != null) {
      setState(() => _saving = true);
      try {
        await widget.actions.addObservationWithPhoto(
          ids: _ids,
          type: draft.resolvedType,
          note: draft.resolvedNote,
          health: draft.health,
          actionTaken: draft.resolvedAction,
          photo: photo,
        );
      } on Object {
        // Nothing was saved. The words stay in the form; only the photo has
        // to be taken again.
        if (mounted) setState(() => _saving = false);
        messenger?.showSnackBar(
          const SnackBar(
            content: Text(
              'That photo could not be kept on this phone. Take another one, '
              'or save without it.',
            ),
          ),
        );
        return;
      }
      navigator.pop();
      return;
    }

    if (existing == null) {
      await widget.actions.addObservation(
        type: draft.resolvedType,
        note: draft.resolvedNote,
        health: draft.health,
        actionTaken: draft.resolvedAction,
      );
    } else {
      await widget.actions.editObservation(
        id: existing.id,
        type: draft.resolvedType,
        note: draft.resolvedNote,
        health: draft.health,
        actionTaken: draft.resolvedAction,
      );
    }
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) => _FormSheet(
    title: widget.observation == null
        ? 'Write down what you saw'
        : 'Change this observation',
    saveLabel: widget.observation == null ? 'Save' : 'Save changes',
    onSave: _draft.isValid ? _save : null,
    children: [
      _Field(label: 'What is it', hint: 'Leaf yellowing', controller: _type),
      _Field(
        label: 'What you saw',
        hint: 'Yellow leaves on the south side',
        controller: _note,
        maxLines: 3,
      ),
      _Field(
        label: 'What you did about it',
        hint: 'Watered this morning',
        controller: _action,
        maxLines: 2,
      ),
      Text(
        'How is it doing',
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: context.semantic.onSurfaceVariant),
      ),
      const SizedBox(height: 6),
      _HealthChoice(
        selected: _health,
        onChanged: (state) => setState(() => _health = state),
      ),
      // A photo belongs to the moment it was taken, so only a new
      // observation can carry one.
      if (widget.observation == null) ...[
        const SizedBox(height: AlmanacDimens.sp4),
        _PhotoField(
          photo: _photo,
          onTake: _takePhoto,
          onRemove: () => setState(() => _photo = null),
        ),
      ],
    ],
  );
}

class _PhotoField extends StatelessWidget {
  final CapturedPhoto? photo;
  final VoidCallback onTake;
  final VoidCallback onRemove;

  const _PhotoField({
    required this.photo,
    required this.onTake,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final taken = photo;
    if (taken == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          key: const Key('observation-add-photo'),
          onPressed: onTake,
          icon: const Icon(LucideIcons.camera, size: 18),
          label: const Text('Add a photo'),
        ),
      );
    }
    return Row(
      children: [
        const Icon(LucideIcons.image, size: 18),
        const SizedBox(width: AlmanacDimens.sp2),
        Expanded(
          child: Text(
            // Recorded input is said to be recorded, as on every camera
            // screen in test mode.
            taken.recorded ? 'Photo added (test photo)' : 'Photo added',
            key: const Key('observation-photo-added'),
          ),
        ),
        TextButton(onPressed: onRemove, child: const Text('Remove')),
      ],
    );
  }
}

/// Three choices, each an icon **and** a word. Never three coloured dots.
class _HealthChoice extends StatelessWidget {
  final HealthState selected;
  final ValueChanged<HealthState> onChanged;

  const _HealthChoice({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;

    return Wrap(
      spacing: AlmanacDimens.sp2,
      runSpacing: AlmanacDimens.sp2,
      children: [
        for (final state in const [
          HealthState.onTrack,
          HealthState.needsAttention,
          HealthState.actionRequired,
        ])
          InkWell(
            onTap: () => onChanged(state),
            borderRadius: BorderRadius.circular(AlmanacDimens.rPill),
            child: Container(
              constraints: const BoxConstraints(
                minHeight: AlmanacDimens.touchMin,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AlmanacDimens.sp4,
              ),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: state == selected
                    ? c.primaryContainer
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(AlmanacDimens.rPill),
                border: Border.all(
                  color: state == selected ? c.primary : c.outlineVariant,
                  width: state == selected ? 2 : 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    state == HealthState.onTrack
                        ? LucideIcons.circleCheckBig
                        : LucideIcons.triangleAlert,
                    size: 18,
                    color: state == selected
                        ? c.onPrimaryContainer
                        : c.onSurfaceVariant,
                  ),
                  const SizedBox(width: AlmanacDimens.sp2),
                  Text(
                    state.label,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: state == selected
                          ? c.onPrimaryContainer
                          : c.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _TaskForm extends StatefulWidget {
  final ZoneActions actions;
  final FarmTask? task;

  const _TaskForm({required this.actions, this.task});

  @override
  State<_TaskForm> createState() => _TaskFormState();
}

class _TaskFormState extends State<_TaskForm> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late DateTime _due;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.task?.title ?? '');
    _description = TextEditingController(text: widget.task?.description ?? '');
    _due = widget.task?.dueDate ?? DateTime.now();
    _title.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final navigator = Navigator.of(context);
    final description = _description.text.trim();
    final task = widget.task;

    if (task == null) {
      await widget.actions.addTask(
        title: _title.text.trim(),
        description: description.isEmpty ? null : description,
        dueDate: _due,
      );
    } else {
      await widget.actions.editTask(
        id: task.id,
        title: _title.text.trim(),
        description: description.isEmpty ? null : description,
        dueDate: _due,
      );
    }
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;

    return _FormSheet(
      title: widget.task == null ? 'Add a job' : 'Change this job',
      saveLabel: widget.task == null ? 'Add it' : 'Save changes',
      onSave: _title.text.trim().isEmpty ? null : _save,
      children: [
        _Field(label: 'What needs doing', hint: 'Watering', controller: _title),
        _Field(
          label: 'Anything to remember',
          hint: 'Deep water the south side',
          controller: _description,
          maxLines: 2,
        ),
        Text(
          'When',
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: c.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        AppTonalButton(
          label: '${weekdayName(_due)} ${longDate(_due)}',
          icon: LucideIcons.calendar,
          onPressed: () async {
            final picked = await _pickDate(context, _due);
            if (picked != null) setState(() => _due = picked);
          },
        ),
      ],
    );
  }
}

class _SectionForm extends ConsumerStatefulWidget {
  final ZoneActions actions;
  final FarmSection section;

  const _SectionForm({required this.actions, required this.section});

  @override
  ConsumerState<_SectionForm> createState() => _SectionFormState();
}

class _SectionFormState extends ConsumerState<_SectionForm> {
  /// Minted when the form opens, so a second tap on Save is the same change.
  final _mutationId = newUuid();

  /// The version the farmer was looking at when they started. Moves forward
  /// only when they have been shown what changed underneath them.
  late int _expectedRevision;

  late final TextEditingController _name;
  late final TextEditingController _area;
  var _saving = false;
  String? _conflict;

  /// Validation speaks only after the farmer has touched a field, so the
  /// form does not open already scolding them.
  var _touchedName = false;
  var _touchedArea = false;

  @override
  void initState() {
    super.initState();
    final draft = SectionDraft.from(widget.section);
    _expectedRevision = widget.section.version;
    _name = TextEditingController(text: draft.name)
      ..addListener(() => setState(() => _touchedName = true));
    _area = TextEditingController(text: draft.area)
      ..addListener(() => setState(() => _touchedArea = true));
  }

  @override
  void dispose() {
    _name.dispose();
    _area.dispose();
    super.dispose();
  }

  SectionDraft get _draft => SectionDraft(name: _name.text, area: _area.text);

  Future<void> _save() async {
    final draft = _draft;
    if (_saving || !draft.isValid) return;
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      await widget.actions.editSection(
        mutationId: _mutationId,
        expectedRevision: _expectedRevision,
        name: draft.resolvedName,
        areaM2: draft.resolvedArea!,
      );
    } on RevisionConflict {
      // Someone else's edit got there first. Say what it was, keep what the
      // farmer typed, and let a second Save knowingly replace it.
      final latest = ref
          .read(sectionProvider(widget.section.id))
          .value
          ?.section;
      if (!mounted) return;
      setState(() {
        _saving = false;
        if (latest == null) {
          _conflict = 'This section was changed on another phone.';
        } else {
          _expectedRevision = latest.version;
          final area = latest.areaM2?.asArea ?? 'no area';
          _conflict =
              'This section was changed on another phone while you were '
              'editing. It is now “${latest.name}”, $area. Save again to '
              'use your version instead.';
        }
      });
      return;
    } on Object {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _conflict =
            'Your changes could not be saved on this phone. They are still '
            'here — try Save again.';
      });
      return;
    }
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    final c = context.semantic;

    return _FormSheet(
      title: 'Change this section',
      saveLabel: 'Save changes',
      onSave: draft.isValid && !_saving ? _save : null,
      children: [
        if (_conflict case final message?) ...[
          Container(
            key: const Key('section-conflict'),
            padding: const EdgeInsets.all(AlmanacDimens.sp3),
            decoration: BoxDecoration(
              color: c.surfaceContainer,
              borderRadius: BorderRadius.circular(AlmanacDimens.rMd),
              border: Border.all(color: c.outlineVariant),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.info, size: 20, color: c.onSurface),
                const SizedBox(width: AlmanacDimens.sp2),
                Expanded(child: Text(message)),
              ],
            ),
          ),
          const SizedBox(height: AlmanacDimens.sp4),
        ],
        _Field(
          fieldKey: const Key('section-name'),
          label: 'Name',
          hint: 'North Plot',
          controller: _name,
          error: _touchedName ? draft.nameProblem : null,
        ),
        _Field(
          fieldKey: const Key('section-area'),
          label: 'Area in square metres',
          hint: '6000',
          controller: _area,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          helper: draft.hectares,
          error: _touchedArea ? draft.areaProblem : null,
        ),
      ],
    );
  }
}
