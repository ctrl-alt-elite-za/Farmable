/// Verify your account — guide §10.
///
/// ONE flow with TWO steps: phone, then email. Never two OTP fields side by
/// side — the guide says so and it is right; two identical six-box rows on one
/// screen is a design that cannot be got through without reading it twice.
///
/// The six boxes are [OtpSlots], which is six painted slots over a single
/// logical input, so a pasted code and an Android SMS autofill both land
/// whole. See that file for why six real fields is the wrong build.
///
/// Nothing in here logs a code. The controller holds it, the view model
/// forwards it, and neither writes it anywhere — not to a route parameter,
/// not into an error string, not at debug level.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/app_motion.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.g.dart';
import '../../core/ui/buttons.dart';
import '../../core/ui/fields.dart';
import '../../core/ui/flow_controls.dart';
import '../../core/ui/otp_slots.dart';
import '../../domain/auth/auth_models.dart';
import '../../domain/auth/contact_details.dart';
import 'auth_view_model.dart';
import 'widgets/auth_scaffold.dart';

/// How long before a new code can be asked for. Guide §10 shows the countdown
/// in the copy, so the number and the label come from one place.
const Duration resendWindow = Duration(seconds: 60);

class VerifyScreen extends ConsumerStatefulWidget {
  const VerifyScreen({super.key});

  @override
  ConsumerState<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends ConsumerState<VerifyScreen> {
  final _code = TextEditingController();

  Timer? _ticker;
  int _secondsLeft = resendWindow.inSeconds;

  bool _busy = false;
  bool _invalid = false;
  AuthFailure? _failure;

  /// Set while the tick is on screen, between a code being accepted and the
  /// flow moving on. Guide §10: a success tick, then continue automatically —
  /// no button for the farmer to find.
  bool _succeeded = false;

  /// The step the tick belongs to.
  ///
  /// The last code accepted clears the pending signup, so by the time the
  /// tick is drawn there is no [AwaitingVerification] left to read. Without
  /// this the screen fell through to its "there is no sign-up waiting"
  /// state for the length of the hold — the farmer saw the flow tell them
  /// their sign-up had vanished, a beat before landing on Home. Caught on the
  /// device.
  PendingSignup? _lastPending;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _ticker?.cancel();
    setState(() => _secondsLeft = resendWindow.inSeconds);
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) timer.cancel();
    });
  }

  Future<void> _submit(String code) async {
    if (_busy || _succeeded) return;
    setState(() {
      _busy = true;
      _invalid = false;
      _failure = null;
    });

    final before = ref.read(authViewModelProvider).value;
    final failure = await ref
        .read(authViewModelProvider.notifier)
        .submitCode(code);
    if (!mounted) return;

    if (failure != null) {
      setState(() {
        _busy = false;
        _invalid = true;
        _failure = failure;
      });
      // The wrong code is cleared rather than left for the farmer to edit:
      // six boxes with four right digits in them invite hunting for the wrong
      // one, and the code is single-use anyway.
      _code.clear();
      return;
    }

    setState(() {
      _busy = false;
      _succeeded = true;
    });

    // Long enough to read the tick, short enough not to be a wait. Reduced
    // motion still pauses — the tick is information, not decoration, and
    // skipping it entirely would move the screen out from under them.
    final hold = AppMotion.of(context).reduced
        ? const Duration(milliseconds: 300)
        : const Duration(milliseconds: 750);
    await Future<void>.delayed(hold);
    if (!mounted) return;

    final after = ref.read(authViewModelProvider).value;
    if (after is SignedIn) {
      context.go('/home');
      return;
    }

    // Phone proved, email still owed: same screen, second step, fresh field
    // and a fresh countdown.
    if (before is AwaitingVerification && after is AwaitingVerification) {
      setState(() => _succeeded = false);
      _code.clear();
      _startCountdown();
    }
  }

  Future<void> _resend() async {
    if (_secondsLeft > 0 || _busy) return;
    setState(() => _busy = true);
    final failure = await ref.read(authViewModelProvider.notifier).resendCode();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failure = failure;
      _invalid = false;
    });
    _code.clear();
    _startCountdown();
  }

  /// Start again — throw away the half-made account and go back to sign-up.
  ///
  /// Only moves on if the account was actually removed. Sending the farmer to
  /// sign-up after a failed abandonment is the worst of both: the pending
  /// account is still there, so the same email comes back as `accountExists`,
  /// and they are now on a screen with no way to reach the code they were
  /// sent. They would be stuck, having been told the opposite.
  Future<void> _startAgain() async {
    if (_busy) return;
    setState(() => _busy = true);
    final failure = await ref
        .read(authViewModelProvider.notifier)
        .abandonSignup();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failure = failure;
    });
    if (failure == null) context.go('/auth/signup');
  }

  @override
  Widget build(BuildContext context) {
    final standing = ref.watch(authViewModelProvider).value;
    if (standing is AwaitingVerification) _lastPending = standing.pending;

    // Arrived here with nothing to verify — a deep link, or a signup that was
    // abandoned. A calm way back, not a blank screen. The tick outranks it:
    // a code that was just accepted is not "nothing to verify".
    if (standing is! AwaitingVerification && !_succeeded) {
      return AuthScaffold(
        title: 'Verify your account',
        subtitle: 'There is no sign-up waiting on this phone.',
        onBack: backOr(context, '/auth'),
        children: [
          AppPrimaryButton(
            label: 'Create an account',
            onPressed: () => context.go('/auth/signup'),
          ),
          const SizedBox(height: AlmanacDimens.sp3),
          AppSecondaryButton(
            label: 'Log in instead',
            onPressed: () => context.go('/auth/login'),
          ),
        ],
      );
    }

    final pending = _lastPending!;
    final onPhone = pending.nextStep == VerificationChannel.phone;

    return AuthScaffold(
      title: 'Verify your account',
      onBack: backOr(context, '/auth'),
      children: [
        FlowStepper(
          steps: const [FlowStep('Phone'), FlowStep('Email')],
          currentIndex: onPhone ? 0 : 1,
        ),
        _Destination(
          onPhone: onPhone,
          masked: onPhone ? maskPhone(pending.phone) : maskEmail(pending.email),
        ),
        const SizedBox(height: AlmanacDimens.sp5),
        if (_succeeded)
          const _SuccessTick()
        else ...[
          OtpSlots(
            // Keyed by the step, so moving from phone to email builds a fresh
            // OtpSlots and its `autofocus` fires again. Without this the
            // keyboard drops the moment the first code is accepted and the
            // farmer has to tap the slots to get it back — visible on the
            // device, invisible in a widget test, which has no keyboard.
            key: ValueKey(pending.nextStep),
            controller: _code,
            enabled: !_busy,
            invalid: _invalid,
            onCompleted: _submit,
            // Typing again after a rejected code clears the red, so the
            // screen is not still complaining about a code that is gone.
            onChanged: (_) {
              if (_invalid) setState(() => _invalid = false);
            },
          ),
          if (_failure != null) ...[
            const SizedBox(height: AlmanacDimens.sp3),
            FieldHelper(message: authAdvice(_failure!), tone: FieldTone.error),
          ],
          const SizedBox(height: AlmanacDimens.sp5),
          _ResendRow(
            secondsLeft: _secondsLeft,
            enabled: _secondsLeft <= 0 && !_busy,
            onResend: _resend,
          ),
        ],
        const SizedBox(height: AlmanacDimens.sp6),
        _CodeNote(onPhone: onPhone),
        const SizedBox(height: AlmanacDimens.sp4),
        AuthFooterLink(
          leading: 'Wrong number or address?',
          linkLabel: 'Start again',
          onTap: _startAgain,
        ),
      ],
    );
  }
}

class _Destination extends StatelessWidget {
  final bool onPhone;
  final String masked;

  const _Destination({required this.onPhone, required this.masked});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Text.rich(
      TextSpan(
        style: text.bodyMedium,
        children: [
          TextSpan(
            text: onPhone
                ? 'Enter the 6-digit code sent to '
                : 'Enter the code sent to ',
          ),
          TextSpan(text: masked, style: text.labelLarge),
        ],
      ),
    );
  }
}

class _ResendRow extends StatelessWidget {
  final int secondsLeft;
  final bool enabled;
  final VoidCallback onResend;

  const _ResendRow({
    required this.secondsLeft,
    required this.enabled,
    required this.onResend,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final seconds = secondsLeft.clamp(0, 99).toString().padLeft(2, '0');

    return Row(
      children: [
        Expanded(
          child: Text(
            secondsLeft > 0
                ? 'Resend code in 00:$seconds'
                : 'You can ask for a new code now.',
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: c.onSurfaceVariant),
          ),
        ),
        const SizedBox(width: AlmanacDimens.sp3),
        AppTonalButton(
          label: 'Resend',
          icon: LucideIcons.rotateCw,
          block: false,
          onPressed: enabled ? onResend : null,
        ),
      ],
    );
  }
}

/// The note under the slots.
///
/// On the email step it says what to do if the code has not arrived, which is
/// the moment a farmer gives up. It is deliberately not phrased as a failure.
class _CodeNote extends StatelessWidget {
  final bool onPhone;

  const _CodeNote({required this.onPhone});

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AlmanacDimens.sp4,
        vertical: AlmanacDimens.sp3,
      ),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AlmanacDimens.rLg),
        border: Border.all(color: c.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.info, size: 18, color: c.onSurfaceVariant),
          const SizedBox(width: AlmanacDimens.sp3),
          Expanded(
            child: Text(
              onPhone
                  ? 'The code lasts 10 minutes and works once. This build has '
                        'no SMS behind it yet — any six digits will do.'
                  : 'Not in your inbox? Look in spam, or ask for a new code. '
                        'This build has no mail behind it yet — any six digits '
                        'will do.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: c.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// The success tick. Scales in once and holds.
class _SuccessTick extends StatelessWidget {
  const _SuccessTick();

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final motion = AppMotion.of(context);

    return Center(
      child: Column(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.7, end: 1),
            duration: motion.micro,
            curve: AlmanacMotion.easeEmphasised,
            builder: (context, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: c.statusOnTrackContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                LucideIcons.check,
                size: 28,
                color: c.onStatusOnTrackContainer,
              ),
            ),
          ),
          const SizedBox(height: AlmanacDimens.sp3),
          // The word carries it, not the colour or the glyph.
          Text('Verified', style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}
