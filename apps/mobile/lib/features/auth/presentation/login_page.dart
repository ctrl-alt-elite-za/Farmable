import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'auth_controller.dart';
import 'auth_scaffold.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});
  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  bool _phone = false;
  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AuthScaffold(
    title: 'Farmable',
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Log in', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 16),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Email')),
              ButtonSegment(value: true, label: Text('Phone')),
            ],
            selected: {_phone},
            onSelectionChanged: (value) => setState(() => _phone = value.first),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _identifier,
            keyboardType: _phone
                ? TextInputType.phone
                : TextInputType.emailAddress,
            autofillHints: [
              _phone ? AutofillHints.telephoneNumber : AutofillHints.username,
            ],
            decoration: InputDecoration(
              labelText: _phone ? 'Phone number' : 'Email',
            ),
            validator: (value) => value == null || value.isEmpty
                ? 'Enter your ${_phone ? 'phone number' : 'email'}'
                : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _password,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            decoration: const InputDecoration(labelText: 'Password'),
            validator: (value) =>
                value == null || value.isEmpty ? 'Enter your password' : null,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: ref.watch(authActionControllerProvider).isLoading
                ? null
                : () async {
                    if (!_form.currentState!.validate()) return;
                    if (await ref
                        .read(authActionControllerProvider.notifier)
                        .login(_identifier.text.trim(), _password.text)) {
                      if (context.mounted) context.go('/home');
                    }
                  },
            child: const Text('Log in'),
          ),
          TextButton(
            onPressed: () => context.go('/auth/signup'),
            child: const Text('Create an account'),
          ),
        ],
      ),
    ),
  );
}
