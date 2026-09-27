/// Farm facts used to match funding and procurement opportunities.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/tokens.g.dart';
import '../../core/ui/buttons.dart';
import '../../core/ui/fields.dart';
import '../../core/ui/layout.dart';
import '../../data/auth/api_auth_service.dart';
import '../../domain/auth/auth_models.dart';
import '../auth/widgets/auth_scaffold.dart';

class FarmProfileScreen extends ConsumerStatefulWidget {
  const FarmProfileScreen({super.key});

  @override
  ConsumerState<FarmProfileScreen> createState() => _FarmProfileScreenState();
}

class _FarmProfileScreenState extends ConsumerState<FarmProfileScreen> {
  final _province = TextEditingController();
  final _municipality = TextEditingController();
  final _farmerType = TextEditingController();
  final _businessStatus = TextEditingController();
  final _size = TextEditingController();
  final _turnover = TextEditingController();
  final _crops = TextEditingController();
  final _goals = TextEditingController();
  final _equipment = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in [
      _province,
      _municipality,
      _farmerType,
      _businessStatus,
      _size,
      _turnover,
      _crops,
      _goals,
      _equipment,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final auth = ref.read(authServiceProvider);
    if (auth is! ApiAuthService) {
      setState(() {
        _loading = false;
        _message =
            'Farm profile matching is available when signed in to the server.';
      });
      return;
    }
    try {
      final response = await auth.authorized('GET', '/advisory/farm-profile');
      throwUnlessSuccess(response);
      _fill(_body(response));
    } on Object catch (_) {
      if (mounted) {
        setState(() => _message = 'The farm profile could not be opened.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _fill(Map<String, Object?> value) {
    _province.text = '${value['province'] ?? ''}';
    _municipality.text = '${value['municipality'] ?? ''}';
    _farmerType.text = '${value['farmer_type'] ?? ''}';
    _businessStatus.text = '${value['business_status'] ?? ''}';
    _size.text = '${value['farm_size_ha'] ?? ''}';
    _turnover.text = '${value['annual_turnover_band'] ?? ''}';
    _crops.text = _join(value['crops']);
    _goals.text = _join(value['goals']);
    _equipment.text = _join(value['equipment']);
  }

  String _join(Object? value) => value is List ? value.join(', ') : '';

  List<String> _split(TextEditingController controller) => controller.text
      .split(',')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList();

  Future<void> _save() async {
    final auth = ref.read(authServiceProvider);
    if (auth is! ApiAuthService || _saving) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      final response = await auth.authorized(
        'PATCH',
        '/advisory/farm-profile',
        data: {
          'province': _province.text.trim().isEmpty
              ? null
              : _province.text.trim(),
          'municipality': _municipality.text.trim().isEmpty
              ? null
              : _municipality.text.trim(),
          'farmer_type': _farmerType.text.trim().isEmpty
              ? null
              : _farmerType.text.trim(),
          'business_status': _businessStatus.text.trim().isEmpty
              ? null
              : _businessStatus.text.trim(),
          'farm_size_ha': _size.text.trim().isEmpty
              ? null
              : num.tryParse(_size.text.trim()),
          'annual_turnover_band': _turnover.text.trim().isEmpty
              ? null
              : _turnover.text.trim(),
          'crops': _split(_crops),
          'goals': _split(_goals),
          'equipment': _split(_equipment),
        },
      );
      throwUnlessSuccess(response);
      if (mounted) {
        setState(
          () => _message =
              'Saved. Funding and procurement matches will use these facts.',
        );
        Future<void>.delayed(const Duration(milliseconds: 700), () {
          if (mounted) context.go('/profile');
        });
      }
    } on AuthException catch (error) {
      if (mounted) {
        setState(() => _message = 'Could not save: ${error.failure.name}.');
      }
    } on Object {
      if (mounted) {
        setState(() => _message = 'Could not save the farm profile.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Map<String, Object?> _body(dynamic response) => response.data is Map
      ? (response.data as Map).cast<String, Object?>()
      : {};

  @override
  Widget build(BuildContext context) => AuthScaffold(
    title: 'Farm profile',
    subtitle: 'These facts help match funding and procurement opportunities.',
    onBack: backOr(context, '/profile'),
    children: [
      if (_message != null) AuthNotice(message: _message!),
      if (_loading)
        const Center(child: CircularProgressIndicator())
      else if (ref.read(authServiceProvider) is! ApiAuthService)
        const EmptyState(
          icon: Icons.cloud_off,
          headline: 'Sign in to save farm facts',
          body:
              'The matching database is connected to your server farm account.',
        )
      else ...[
        AppTextField(
          label: 'Province',
          controller: _province,
          enabled: !_saving,
        ),
        AppTextField(
          label: 'Municipality or district',
          controller: _municipality,
          enabled: !_saving,
        ),
        AppTextField(
          label: 'Farmer type',
          controller: _farmerType,
          enabled: !_saving,
          hint: 'smallholder, subsistence, emerging',
        ),
        AppTextField(
          label: 'Business status',
          controller: _businessStatus,
          enabled: !_saving,
          hint: 'informal or registered',
        ),
        AppTextField(
          label: 'Farm size (hectares)',
          controller: _size,
          enabled: !_saving,
          keyboardType: TextInputType.number,
        ),
        AppTextField(
          label: 'Annual turnover band',
          controller: _turnover,
          enabled: !_saving,
          hint: 'under R100k, R100k–R1m',
        ),
        AppTextField(
          label: 'Crops',
          controller: _crops,
          enabled: !_saving,
          hint: 'cabbage, spinach',
        ),
        AppTextField(
          label: 'Goals',
          controller: _goals,
          enabled: !_saving,
          hint: 'inputs, irrigation, market access',
        ),
        AppTextField(
          label: 'Equipment',
          controller: _equipment,
          enabled: !_saving,
          hint: 'irrigation, cold storage',
        ),
        const SizedBox(height: AlmanacDimens.sp4),
        AppPrimaryButton(
          label: 'Save farm profile',
          busyLabel: _saving ? 'Saving…' : null,
          onPressed: _saving ? null : _save,
        ),
      ],
    ],
  );
}
