/// The assistant sheet — a placeholder, and honest about it.
///
/// Voice is not part of this session. What is here is the sheet's shape and
/// surface so the button has somewhere real to go, and one sentence saying
/// plainly that listening is not switched on yet.
///
/// It deliberately does **not** say "error", "failed" or "unavailable". A
/// feature that has not been built is not a fault, and the farmer cannot tell
/// the difference between "broken" and "not finished" from the word alone —
/// they only learn that the app breaks.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/app_motion.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.g.dart';
import '../../core/ui/buttons.dart';

Future<void> showAssistantSheet(BuildContext context) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  barrierColor: context.semantic.backdrop,
  transitionAnimationController: null,
  builder: (context) => const AssistantSheet(),
);

class AssistantSheet extends StatelessWidget {
  const AssistantSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;
    // Read so the sheet respects reduced motion once it animates content.
    AppMotion.of(context);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AlmanacDimens.r2xl),
      ),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          // 70% of the screen. The dashboard stays visible above it, which is
          // what keeps the assistant an overlay on the farm rather than a
          // place the farmer has been taken to.
          height: MediaQuery.sizeOf(context).height * 0.7,
          width: double.infinity,
          decoration: BoxDecoration(
            color: c.glassSurface,
            border: Border(top: BorderSide(color: c.glassHairlineStrong)),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AlmanacDimens.r2xl),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: AlmanacDimens.gutter),
          child: Column(
            children: [
              const SizedBox(height: AlmanacDimens.sp2),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: c.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: AlmanacDimens.sp6),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: c.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  LucideIcons.mic,
                  color: c.onPrimaryContainer,
                  size: 24,
                ),
              ),
              const SizedBox(height: AlmanacDimens.sp4),
              Text(
                'Talking to the assistant is not switched on yet',
                style: text.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AlmanacDimens.sp2),
              Text(
                'When it is, you will hold this button, say what you saw, and '
                'check what it wrote down before it is saved. Nothing is ever '
                'saved without you tapping Confirm.',
                style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              AppTonalButton(
                label: 'Close',
                icon: LucideIcons.check,
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(height: AlmanacDimens.sp6),
            ],
          ),
        ),
      ),
    );
  }
}
