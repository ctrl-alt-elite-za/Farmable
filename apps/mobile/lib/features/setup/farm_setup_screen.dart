/// First farm setup — design screen 14.
///
/// Two things now, everything else later: the farm's name, and the language
/// the farmer prefers. Both are saved through the account API
/// (`AccountService.updateDetails`), which writes them to the phone first and
/// sends them when there is a signal — so this screen works in a field with
/// none. The name is also put on the phone's copy of the farm at once, so
/// Home shows it before the server has heard.
///
/// What the design has that this does not, and why:
///
/// * **Map my farm now** is walking the boundary with the camera — issue #15.
///   Until it exists the info card says location and boundary come later.
/// * **Farm photo** has nowhere to go: the farm record has no photo field.
/// * **Location** does not exist on the server yet (#9 / #72), so it is not
///   asked for here — only mentioned as added later.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.g.dart';
import '../../core/ui/buttons.dart';
import '../../core/ui/fields.dart';
import '../../data/setup/account_farm_name.dart';
import '../../domain/account/account_models.dart';
import '../../domain/auth/auth_models.dart';
import '../auth/auth_view_model.dart';
import '../auth/widgets/auth_scaffold.dart';
import 'widgets/setup_chip.dart';
import 'widgets/setup_note.dart';

/// How long Continue waits for the server before moving on regardless.
///
/// The edit is on the phone well before this; what is left is the send, and
/// on a weak signal that can take the client's full timeout. The farmer
/// should not stand in a field watching "Saving…" for the network — the edit
/// goes out on its own, and Profile shows it as waiting until it has.
const farmSetupSendWait = Duration(seconds: 4);

class FarmSetupScreen extends ConsumerStatefulWidget {
  const FarmSetupScreen({super.key});

  @override
  ConsumerState<FarmSetupScreen> createState() => _FarmSetupScreenState();
}

class _FarmSetupScreenState extends ConsumerState<FarmSetupScreen> {
  final _name = TextEditingController();
  AppLanguage _language = AppLanguage.en;
  bool _busy = false;
  bool _nameMissing = false;
  AuthFailure? _failure;

  @override
  void initState() {
    super.initState();
    unawaited(_prefill());
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// The language the account already has — sign-up records one.
  Future<void> _prefill() async {
    try {
      final account = await ref.read(accountServiceProvider).cached();
      if (!mounted || account == null) return;
      setState(() => _language = account.language);
    } on Object {
      // English stays selected; the farmer can change it.
    }
  }

  Future<void> _continue() async {
    if (_busy) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameMissing = true);
      return;
    }
    setState(() {
      _busy = true;
      _failure = null;
    });

    final scope = ref.read(farmScopeProvider);
    final save = ref
        .read(accountServiceProvider)
        .updateDetails(farmName: name, language: _language);
    AuthFailure? failure;
    try {
      await save.timeout(farmSetupSendWait);
    } on TimeoutException {
      // Still sending. See [farmSetupSendWait].
      unawaited(save.then<void>((_) {}, onError: (Object _) {}));
    } on AuthException catch (e) {
      failure = e.failure;
    } on Object {
      failure = AuthFailure.unknown;
    }
    if (!mounted) return;

    if (failure == AuthFailure.invalidSession) {
      // Signed out while this was open — there is no account to set up.
      await ref.read(authViewModelProvider.notifier).recheck();
      if (mounted) context.go('/auth');
      return;
    }
    if (failure != null) {
      setState(() {
        _busy = false;
        _failure = failure;
      });
      return;
    }

    try {
      await nameAccountFarmLocally(ref.read(databaseProvider), scope, name);
    } on Object {
      // The server copy still carries it; Home catches up on the next sync.
    }
    if (!mounted) return;
    setState(() => _busy = false);
    unawaited(context.push('/setup/section'));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;

    return AuthScaffold(
      title: "Let's set up your farm",
      subtitle: 'Two things now. Everything else can wait.',
      children: [
        AppTextField(
          label: 'Farm name',
          controller: _name,
          hint: 'For example, Siyakhula Farm',
          enabled: !_busy,
          maxLength: 200,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          tone: _nameMissing ? FieldTone.error : FieldTone.neutral,
          helper: _nameMissing
              ? 'Give your farm a name — the one you would tell a neighbour.'
              : null,
          onChanged: (_) {
            if (_nameMissing) setState(() => _nameMissing = false);
          },
        ),
        Text(
          'Your language',
          style: text.labelMedium?.copyWith(color: c.onSurfaceVariant),
        ),
        const SizedBox(height: AlmanacDimens.sp2),
        Wrap(
          spacing: AlmanacDimens.sp2,
          runSpacing: AlmanacDimens.sp2,
          children: [
            for (final language in AppLanguage.values)
              SetupChip(
                label: language.label,
                selected: _language == language,
                onTap: _busy
                    ? null
                    : () => setState(() => _language = language),
              ),
          ],
        ),
        const SizedBox(height: AlmanacDimens.sp2),
        Text(
          'Saved to your account. The app itself is in English for now.',
          style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
        ),
        const SizedBox(height: AlmanacDimens.sp6),
        if (_failure != null) AuthNotice(message: authAdvice(_failure!)),
        AppPrimaryButton(
          label: 'Continue',
          icon: LucideIcons.check,
          busyLabel: _busy ? 'Saving…' : null,
          onPressed: _busy ? null : _continue,
        ),
        const SizedBox(height: AlmanacDimens.sp5),
        const SetupNote(
          icon: LucideIcons.info,
          message:
              'Where your farm is, and its boundary, are added later by '
              'walking it. You do not need a title deed or an internet '
              'connection.',
        ),
      ],
    );
  }
}
