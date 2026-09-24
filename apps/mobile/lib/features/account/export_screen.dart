/// Download your data — request, status, and a copy to share.
///
/// The backend answers an export request with the file itself, so "status"
/// here is the three honest states: nothing prepared, preparing, and a copy
/// ready on this phone. The copy is shared through the phone's own share
/// sheet, which is where the farmer chooses where it goes. It expires from
/// the phone after [ExportFile.lifetime].
///
/// No URL and no token is ever shown or logged: the file is fetched with the
/// session, written to app storage, and handed to the share sheet as a file.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.g.dart';
import '../../core/ui/buttons.dart';
import '../../core/ui/layout.dart';
import '../../core/utils/dates.dart';
import '../../domain/account/account_models.dart';
import '../../domain/auth/auth_models.dart';
import '../auth/auth_view_model.dart';
import '../auth/widgets/auth_scaffold.dart';
import 'widgets/profile_rows.dart';

/// Hands a file to the phone's share sheet. Overridden in tests, which have
/// no share sheet.
final shareFileProvider = Provider<Future<void> Function(ExportFile file)>(
  (ref) => (file) async {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: 'My Almanac data'),
    );
  },
);

class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen>
    with WidgetsBindingObserver {
  ExportFormat _format = ExportFormat.json;
  ExportFile? _file;
  bool _loaded = false;
  bool _busy = false;
  AuthFailure? _failure;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    ExportFile? file;
    try {
      file = await ref.read(accountServiceProvider).currentExport();
    } on Object {
      file = null;
    }
    if (mounted) {
      setState(() {
        _file = file;
        _loaded = true;
      });
    }
  }

  Future<void> _prepare() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    AuthFailure? failure;
    ExportFile? file;
    try {
      file = await ref.read(accountServiceProvider).export(_format);
    } on AuthException catch (e) {
      failure = e.failure;
      if (failure == AuthFailure.invalidSession) {
        await ref.read(authViewModelProvider.notifier).recheck();
      }
    } on Object {
      failure = AuthFailure.unknown;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failure = failure;
      if (file != null) _file = file;
    });
  }

  Future<void> _share(ExportFile file) async {
    try {
      // The screen can outlive the copy's expiry (or its account). Never
      // hand a cached path to the share sheet without checking it again.
      final current = await ref.read(accountServiceProvider).currentExport();
      if (!mounted) return;
      setState(() => _file = current);
      if (current == null ||
          current.path != file.path ||
          current.createdAt != file.createdAt) {
        return;
      }
      await ref.read(shareFileProvider)(current);
    } on Object {
      if (mounted) setState(() => _failure = AuthFailure.unknown);
    }
  }

  Future<void> _remove() async {
    await ref.read(accountServiceProvider).removeExport();
    if (mounted) setState(() => _file = null);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.semantic;
    final file = _file;
    final signedIn = ref.watch(authViewModelProvider).value is SignedIn;

    return AuthScaffold(
      title: 'Download your data',
      subtitle: 'A copy of everything on your account.',
      onBack: backOr(context, '/profile'),
      children: [
        if (_failure != null) AuthNotice(message: _advice(_failure!)),
        if (!signedIn)
          const EmptyState(
            icon: Icons.person_outline,
            headline: 'Not logged in',
            body: 'Log in from Profile to download your data.',
          )
        else if (!_loaded)
          const SizedBox.shrink()
        else ...[
          if (_busy)
            _Status(
              icon: LucideIcons.loader,
              headline: 'Preparing your data…',
              body: 'This needs a signal and can take a moment.',
            )
          else if (file != null) ...[
            _Status(
              icon: LucideIcons.circleCheck,
              headline: 'Ready to share',
              body:
                  '${file.format.label}, ${_size(file.bytes)}, prepared '
                  '${_time(file.createdAt)}. It is removed from this phone '
                  '${_time(file.expiresAt)}.',
            ),
            const SizedBox(height: AlmanacDimens.sp4),
            AppPrimaryButton(
              label: 'Share',
              icon: LucideIcons.share2,
              onPressed: () => _share(file),
            ),
            const SizedBox(height: AlmanacDimens.sp3),
            AppSecondaryButton(
              label: 'Remove from this phone',
              onPressed: _remove,
            ),
            const SizedBox(height: AlmanacDimens.sp6),
            Text('Prepare a new copy', style: text.titleMedium),
            const SizedBox(height: AlmanacDimens.sp3),
          ] else
            _Status(
              icon: LucideIcons.fileText,
              headline: 'Nothing prepared yet',
              body:
                  'Prepare a copy, then share it somewhere safe — your email, '
                  'or a computer. Anyone holding it can read your farm '
                  'records.',
            ),
          if (!_busy) ...[
            const SizedBox(height: AlmanacDimens.sp4),
            ChoiceRow(
              label: 'JSON',
              detail: 'One file you can open and read.',
              selected: _format == ExportFormat.json,
              onTap: () => setState(() => _format = ExportFormat.json),
            ),
            ChoiceRow(
              label: 'ZIP',
              detail: 'The same, compressed — smaller to send.',
              selected: _format == ExportFormat.zip,
              onTap: () => setState(() => _format = ExportFormat.zip),
            ),
            const SizedBox(height: AlmanacDimens.sp4),
            AppPrimaryButton(
              label: file == null ? 'Prepare my data' : 'Prepare again',
              onPressed: _prepare,
            ),
            const SizedBox(height: AlmanacDimens.sp3),
            Text(
              'It never includes your password or anyone else\'s records.',
              style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
            ),
          ],
        ],
      ],
    );
  }

  String _advice(AuthFailure failure) => switch (failure) {
    AuthFailure.offline =>
      'Preparing your data needs a signal. Try again when you have one.',
    _ => authAdvice(failure),
  };

  String _size(int bytes) => bytes < 1024
      ? '$bytes bytes'
      : bytes < 1024 * 1024
      ? '${(bytes / 1024).ceil()} KB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  String _time(DateTime at) {
    final local = at.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm on ${shortDate(local)}';
  }
}

class _Status extends StatelessWidget {
  final IconData icon;
  final String headline;
  final String body;

  const _Status({
    required this.icon,
    required this.headline,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.semantic;
    return AlmanacCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: c.primary),
          const SizedBox(width: AlmanacDimens.sp3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(headline, style: text.titleMedium),
                const SizedBox(height: AlmanacDimens.sp1),
                Text(
                  body,
                  style: text.bodyMedium?.copyWith(color: c.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
