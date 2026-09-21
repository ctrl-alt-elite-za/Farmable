import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/auth_models.dart';
import 'auth_controller.dart';
import 'auth_scaffold.dart';

class SignUpPage extends ConsumerStatefulWidget {
  const SignUpPage({super.key});
  @override
  ConsumerState<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends ConsumerState<SignUpPage> {
  final _form = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _surname = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  @override
  void dispose() {
    for (final controller in [
      _firstName,
      _surname,
      _phone,
      _email,
      _password,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AuthScaffold(
    title: 'Create account',
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Create account',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          _field(_firstName, 'Name', AutofillHints.givenName),
          _field(_surname, 'Surname', AutofillHints.familyName),
          _field(
            _phone,
            'Phone number',
            AutofillHints.telephoneNumber,
            type: TextInputType.phone,
          ),
          _field(
            _email,
            'Email',
            AutofillHints.email,
            type: TextInputType.emailAddress,
          ),
          TextFormField(
            controller: _password,
            obscureText: true,
            autofillHints: const [AutofillHints.newPassword],
            decoration: const InputDecoration(
              labelText: 'Password (15+ characters)',
            ),
            validator: (value) => value == null || value.length < 15
                ? 'Use a passphrase of at least 15 characters'
                : null,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: ref.watch(authActionControllerProvider).isLoading
                ? null
                : () async {
                    if (!_form.currentState!.validate()) return;
                    final userId = await ref
                        .read(authActionControllerProvider.notifier)
                        .signUp(
                          SignUpData(
                            firstName: _firstName.text.trim(),
                            surname: _surname.text.trim(),
                            phone: _phone.text.trim(),
                            email: _email.text.trim(),
                            password: _password.text,
                          ),
                        );
                    if (userId != null && context.mounted) {
                      context.go('/auth/verify/$userId/phone');
                    }
                  },
            child: const Text('Create account'),
          ),
        ],
      ),
    ),
  );
  Widget _field(
    TextEditingController controller,
    String label,
    String hint, {
    TextInputType? type,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      keyboardType: type,
      autofillHints: [hint],
      decoration: InputDecoration(labelText: label),
      validator: (value) => value == null || value.trim().isEmpty
          ? 'Enter your ${label.toLowerCase()}'
          : null,
    ),
  );
}
