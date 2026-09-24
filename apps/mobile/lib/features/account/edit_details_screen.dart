/// Edit your details: name, surname, preferred language and farm name.
///
/// Saving always works, signal or not. The change is kept on the phone first
/// and sent when it can be; Profile says plainly when it is still waiting.
///
/// Phone and email are shown but not editable. Changing either needs a fresh
/// code sent to the new number or address, and the backend has no route that
/// starts that yet — so the screen says so rather than offering a field that
/// could only fail.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.g.dart';
import '../../core/ui/buttons.dart';
import '../../core/ui/fields.dart';
import '../../core/ui/layout.dart';
import '../../domain/account/account_models.dart';
import '../../domain/auth/auth_models.dart';
import '../../domain/auth/contact_details.dart';
import '../auth/auth_view_model.dart';
import '../auth/widgets/auth_scaffold.dart';
import 'account_view_model.dart';
import 'widgets/profile_rows.dart';

class EditDetailsScreen extends ConsumerStatefulWidget {
  const EditDetailsScreen({super.key});

  @override
  ConsumerState<EditDetailsScreen> createState() => _EditDetailsScreenState();
}

class _EditDetailsScreenState extends ConsumerState<EditDetailsScreen> {
  final _firstName = TextEditingController();
  final _surname = TextEditingController();
  final _farmName = TextEditingController();
  AppLanguage? _language;

  /// What the form was filled from, so Save sends only what changed.
  AccountSnapshot? _original;
  bool _busy = false;
  AuthFailure? _failure;

  @override
  void dispose() {
    _firstName.dispose();
    _surname.dispose();
    _farmName.dispose();
    super.dispose();
  }

  void _fill(AccountSnapshot account) {
    if (_original != null) return;
    _original = account;
    _firstName.text = account.firstName;
    _surname.text = account.surname;
    _farmName.text = account.farmName ?? '';
    _language = account.language;
  }

  String? _changed(TextEditingController field, String? was) {
    final now = field.text.trim();
    return now == (was ?? '').trim() ? null : now;
  }

  bool get _valid =>
      _firstName.text.trim().isNotEmpty &&
      _surname.text.trim().isNotEmpty &&
      // A farm that has a name keeps one: the server refuses a blank.
      (_original?.farmName == null || _farmName.text.trim().isNotEmpty);

  bool get _dirty {
    final was = _original;
    if (was == null) return false;
    return _changed(_firstName, was.firstName) != null ||
        _changed(_surname, was.surname) != null ||
        _changed(_farmName, was.farmName) != null ||
        _language != was.language;
  }

  Future<void> _save() async {
    final was = _original;
    if (was == null || !_valid || !_dirty || _busy) return;
    setState(() {
      _busy = true;
      _failure = null;
    });

    final farmName = _changed(_farmName, was.farmName);
    final failure = await ref
        .read(accountViewModelProvider.notifier)
        .updateDetails(
          firstName: _changed(_firstName, was.firstName),
          surname: _changed(_surname, was.surname),
          language: _language == was.language ? null : _language,
          farmName: farmName == null || farmName.isEmpty ? null : farmName,
        );

    if (!mounted) return;
    setState(() {
      _busy = false;
      _failure = failure;
    });
    if (failure == null) context.go('/profile');
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(accountViewModelProvider).value;
    if (account != null) _fill(account);
    final text = Theme.of(context).textTheme;
    final c = context.semantic;

    return AuthScaffold(
      title: 'Edit your details',
      subtitle: 'Saved on this phone at once, and sent when you have a signal.',
      onBack: backOr(context, '/profile'),
      children: [
        if (_failure != null) AuthNotice(message: authAdvice(_failure!)),
        if (account == null)
          const EmptyState(
            icon: Icons.person_outline,
            headline: 'Not logged in',
            body: 'Log in from Profile to edit your details.',
          )
        else ...[
          AppTextField(
            label: 'Name',
            controller: _firstName,
            enabled: !_busy,
            maxLength: 100,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
          ),
          AppTextField(
            label: 'Surname',
            controller: _surname,
            enabled: !_busy,
            maxLength: 100,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
          ),
          AppTextField(
            label: 'Farm name',
            controller: _farmName,
            enabled: !_busy,
            maxLength: 200,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AlmanacDimens.sp2),
          Text(
            'Language',
            style: text.labelMedium?.copyWith(color: c.onSurfaceVariant),
          ),
          const SizedBox(height: AlmanacDimens.sp2),
          for (final language in AppLanguage.values)
            ChoiceRow(
              label: language.label,
              selected: _language == language,
              onTap: _busy ? null : () => setState(() => _language = language),
            ),
          const SizedBox(height: AlmanacDimens.sp4),
          DetailRow(label: 'Phone', value: maskPhone(account.phone)),
          DetailRow(
            label: 'Email',
            value: maskEmail(account.email),
            last: true,
          ),
          const SizedBox(height: AlmanacDimens.sp2),
          Text(
            'Changing your phone number or email needs a code sent to the new '
            'one. The app cannot do that yet.',
            style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
          ),
          const SizedBox(height: AlmanacDimens.sp5),
          AppPrimaryButton(
            label: 'Save changes',
            busyLabel: _busy ? 'Saving…' : null,
            onPressed: _valid && _dirty && !_busy ? _save : null,
          ),
        ],
      ],
    );
  }
}
