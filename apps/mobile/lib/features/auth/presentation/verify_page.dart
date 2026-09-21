import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'auth_controller.dart';
import 'auth_scaffold.dart';

class VerifyPage extends ConsumerStatefulWidget {
  const VerifyPage({required this.userId, required this.channel, super.key});
  final String userId;
  final String channel;
  @override
  ConsumerState<VerifyPage> createState() => _VerifyPageState();
}

class _VerifyPageState extends ConsumerState<VerifyPage> {
  final _code = TextEditingController();

  @override
  void didUpdateWidget(covariant VerifyPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel != widget.channel ||
        oldWidget.userId != widget.userId) {
      _code.clear();
    }
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phone = widget.channel == 'phone';
    return AuthScaffold(
      title: 'Verify your account',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Verify ${phone ? 'phone' : 'email'}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            phone
                ? 'Step 1 of 2. Enter the 6-digit SMS code.'
                : 'Step 2 of 2. Enter the 6-digit email code.',
          ),
          const SizedBox(height: 20),
          Semantics(
            identifier: 'verification-code-input',
            child: TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              maxLength: 6,
              decoration: const InputDecoration(labelText: '6-digit code'),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: ref.watch(authActionControllerProvider).isLoading
                ? null
                : () async {
                    if (_code.text.length != 6) return;
                    if (phone) {
                      final done = await ref
                          .read(authActionControllerProvider.notifier)
                          .verifyPhone(widget.userId, _code.text);
                      if (done && context.mounted) {
                        context.go('/auth/verify/${widget.userId}/email');
                      }
                    } else {
                      final done = await ref
                          .read(authActionControllerProvider.notifier)
                          .verifyEmail(widget.userId, _code.text);
                      if (done && context.mounted) {
                        context.go('/home');
                      }
                    }
                  },
            child: Text(phone ? 'Verify phone' : 'Verify email'),
          ),
          TextButton(
            onPressed: ref.watch(authActionControllerProvider).isLoading
                ? null
                : () => ref
                      .read(authActionControllerProvider.notifier)
                      .resendCode(widget.userId, widget.channel),
            child: const Text('Resend code'),
          ),
        ],
      ),
    );
  }
}
