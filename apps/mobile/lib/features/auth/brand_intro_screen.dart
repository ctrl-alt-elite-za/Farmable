/// The in-app brand intro — guide §5.
///
/// This is deliberately **not** a fake loading page. It runs for about 900ms
/// because that is how long the animation takes, and it leaves the moment two
/// things are true: the animation has settled, and the session has been read
/// off the phone. On a device where reading the session is instant, which is
/// every device, the animation is the only thing anyone waits for.
///
/// The composition continues the native splash rather than replacing it: the
/// mark starts at the size and position the OS splash left it at, so the seam
/// between the two is not visible. The sequence is the guide's, and nothing
/// more: scale 0.92 to 1.0, one soft outward pulse, settle. No bounce, no
/// rotation, no confetti.
///
/// Under reduced motion the mark is simply there, and the screen still routes.
/// Nothing about where the farmer ends up depends on an animation completing.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_motion.dart';
import '../../app/theme/tokens.g.dart';
import '../../core/ui/brand.dart';
import '../../domain/auth/auth_models.dart';
import '../setup/setup_providers.dart';
import 'auth_view_model.dart';

/// The intro's own background. Fixed, not themed — it continues the native
/// splash, and a native splash is one asset whatever the device theme says.
const Color introBackground = Color(0xFF012120);

class BrandIntroScreen extends ConsumerStatefulWidget {
  const BrandIntroScreen({super.key});

  @override
  ConsumerState<BrandIntroScreen> createState() => _BrandIntroScreenState();
}

class _BrandIntroScreenState extends ConsumerState<BrandIntroScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  bool _settled = false;
  bool _left = false;

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _settled = true;
        _leaveWhenReady();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller.isAnimating || _settled) return;
    if (AppMotion.of(context).reduced) {
      _controller.value = 1;
      _settled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _leaveWhenReady());
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Leaves once the animation has settled *and* the session has been read.
  ///
  /// Called from both sides — the animation's completion and the provider
  /// listener — because either can be the last to arrive. [_left] is what
  /// stops the two of them navigating twice.
  void _leaveWhenReady() {
    if (_left || !_settled || !mounted) return;
    final standing = ref.read(authViewModelProvider).value;
    if (standing == null) return;

    _left = true;
    // A farmer already signed in has nothing left to be introduced to.
    if (standing is SignedIn) {
      unawaited(ref.read(launchRecordProvider).markIntroSeen());
    }
    GoRouter.of(context).go(switch (standing) {
      // Guide §5: a returning authenticated farmer skips onboarding and auth
      // entirely. No flash of the auth choice screen on the way past.
      SignedIn() => '/home',
      // Picked up mid-signup, on the step they had reached. This is why the
      // pending signup is persisted rather than held in memory.
      AwaitingVerification() => '/auth/verify',
      SignedOut() => '/onboarding',
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authViewModelProvider, (_, _) => _leaveWhenReady());

    return Scaffold(
      backgroundColor: introBackground,
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final t = _controller.value;

            // 0.92 to 1.0 over the first 65%, then held. The curve is applied
            // to the sub-interval rather than the whole controller so the
            // pulse below is not squeezed into the tail of an eased value.
            final scale =
                0.92 +
                0.08 *
                    Curves.easeOutCubic.transform((t / 0.65).clamp(0.0, 1.0));

            // One soft outward pulse, between 35% and 85%. A ring that grows
            // and fades — the mark itself never moves, which is what keeps it
            // from reading as a bounce.
            final pulse = ((t - 0.35) / 0.5).clamp(0.0, 1.0);

            return Stack(
              alignment: Alignment.center,
              children: [
                if (pulse > 0 && pulse < 1)
                  Opacity(
                    opacity: (1 - pulse) * 0.35,
                    child: Container(
                      width: 96 + 96 * pulse,
                      height: 96 + 96 * pulse,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF82D89A),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                Transform.scale(scale: scale, child: child),
              ],
            );
          },
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BrandMark(size: 96, color: Color(0xFF82D89A)),
              SizedBox(height: AlmanacDimens.sp5),
              Text(
                'Almanac',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 26,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.5,
                  color: Color(0xFFFFFFFF),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
