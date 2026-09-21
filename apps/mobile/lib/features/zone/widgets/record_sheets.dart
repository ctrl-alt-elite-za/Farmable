/// The sheets and dialogs that edit a section's records.
///
/// Every one of them writes to local storage and returns. None of them shows a
/// progress state waiting on a server, because none of them talks to one.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../core/ui/buttons.dart';
import '../../../core/utils/dates.dart';
import '../../../domain/farm_records.dart';
import '../observation_draft.dart';
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

  const _Field({
    required this.label,
    required this.controller,
    this.hint,
    this.maxLines = 1,
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
            controller: controller,
            maxLines: maxLines,
            textCapitalization: TextCapitalization.sentences,
            style: text.bodyLarge,
            decoration: InputDecoration(
              hintText: hint,
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

class _ObservationForm extends StatefulWidget {
  final ZoneActions actions;
  final Observation? observation;

  const _ObservationForm({required this.actions, this.observation});

  @override
  State<_ObservationForm> createState() => _ObservationFormState();
}

class _ObservationFormState extends State<_ObservationForm> {
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

  Future<void> _save() async {
    final draft = _draft;
    final existing = widget.observation;
    final navigator = Navigator.of(context);

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
    ],
  );
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
