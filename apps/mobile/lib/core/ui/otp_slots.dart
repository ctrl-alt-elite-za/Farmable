/// Six boxes, one input.
///
/// This is the component the guide is most specific about and the one that is
/// most often built wrong. Six separate `TextField`s look identical and break
/// everything that matters: pasting a code fills only the first box, Android's
/// SMS autofill has no single field to target, backspace across a boundary
/// eats the wrong digit, and a screen reader announces six unlabelled inputs.
///
/// So there is exactly one [EditableText] here. It is transparent and sits
/// under the slots; the slots are painted from its value. Tapping anywhere on
/// the row focuses that one field.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_motion.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.g.dart';

const int otpLength = 6;

class OtpSlots extends StatefulWidget {
  final TextEditingController controller;

  /// Fires once the sixth digit lands. The flow continues on its own from
  /// there — guide §10 asks for a success tick and then automatic
  /// continuation, never a "Submit" the farmer has to find.
  final ValueChanged<String>? onCompleted;

  final ValueChanged<String>? onChanged;

  /// Locks input while the code is being checked, and during the success tick.
  final bool enabled;

  /// Paints every slot on the error ramp. Carried with a message beside it —
  /// the colour is never the only signal.
  final bool invalid;

  final bool autofocus;

  const OtpSlots({
    super.key,
    required this.controller,
    this.onCompleted,
    this.onChanged,
    this.enabled = true,
    this.invalid = false,
    this.autofocus = true,
  });

  @override
  State<OtpSlots> createState() => _OtpSlotsState();
}

class _OtpSlotsState extends State<OtpSlots> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onEdit);
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onEdit);
    _focus.dispose();
    super.dispose();
  }

  void _onEdit() {
    setState(() {});
    final value = widget.controller.text;
    widget.onChanged?.call(value);
    if (value.length == otpLength) widget.onCompleted?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.controller.text;

    return Semantics(
      // One control, named once. Without this the row announces as six
      // decorative containers and the real field has no label at all.
      textField: true,
      label: 'Verification code, $otpLength digits',
      value: value.isEmpty ? 'empty' : '${value.length} of $otpLength entered',
      child: Stack(
        children: [
          Row(
            children: [
              for (var i = 0; i < otpLength; i++) ...[
                if (i > 0) const SizedBox(width: AlmanacDimens.sp2),
                Expanded(
                  child: _Slot(
                    digit: i < value.length ? value[i] : null,
                    active: _focus.hasFocus && i == value.length,
                    invalid: widget.invalid,
                  ),
                ),
              ],
            ],
          ),
          Positioned.fill(
            child: Opacity(
              // Not `Visibility`: a hidden field cannot receive autofill, and
              // a zero-size one cannot receive a paste. It is present, laid
              // out over the slots, and invisible.
              opacity: 0,
              child: TextField(
                controller: widget.controller,
                focusNode: _focus,
                enabled: widget.enabled,
                autofocus: widget.autofocus,
                keyboardType: TextInputType.number,
                // The whole reason this is one field: Android fills it from
                // the SMS, and a long-press paste puts all six digits in.
                autofillHints: const [AutofillHints.oneTimeCode],
                enableSuggestions: false,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(otpLength),
                ],
                showCursor: false,
                style: const TextStyle(height: 4),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  counterText: '',
                ),
              ),
            ),
          ),
          // Sits above the invisible field so a tap anywhere on the row lands
          // on the focus request rather than on whichever slot was hit.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: widget.enabled ? _focus.requestFocus : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _Slot extends StatelessWidget {
  final String? digit;
  final bool active;
  final bool invalid;

  const _Slot({
    required this.digit,
    required this.active,
    required this.invalid,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final filled = digit != null;

    final border = invalid
        ? c.statusActionRequired
        : (filled || active ? c.primary : c.outlineVariant);

    return Container(
      height: 58,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AlmanacDimens.rSm),
        border: Border.all(color: border, width: active ? 2 : 1.5),
      ),
      child: filled
          ? Text(
              digit!,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: AlmanacType.numericL.size,
                height: AlmanacType.numericL.heightFactor,
                fontWeight: FontWeight.w600,
                color: c.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            )
          : (active ? const _Caret() : const SizedBox.shrink()),
    );
  }
}

/// The blinking caret from `app-forms.css`.
///
/// Stops blinking under reduced motion and stays solid instead of vanishing:
/// a steady bar still says "you are typing here", and a 1ms blink is a strobe.
class _Caret extends StatefulWidget {
  const _Caret();

  @override
  State<_Caret> createState() => _CaretState();
}

class _CaretState extends State<_Caret> with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final bar = Container(width: 2, height: 26, color: c.primary);

    if (!AppMotion.of(context).allowsLoops) {
      if (_blink.isAnimating) _blink.stop();
      return bar;
    }

    if (!_blink.isAnimating) _blink.repeat();
    return FadeTransition(
      opacity: _blink.drive(
        TweenSequence([
          TweenSequenceItem(tween: ConstantTween(1.0), weight: 1),
          TweenSequenceItem(tween: ConstantTween(0.0), weight: 1),
        ]),
      ),
      child: bar,
    );
  }
}
