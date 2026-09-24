/// The form set: text field, phone field, password field, strength meter.
///
/// Built to COMPONENTS.md — 54px shell, `--r-md`, 1.5px `outline-variant`,
/// 2px `primary` on focus, the status ramp for valid and error — with three
/// rules that hold across all of them:
///
/// * **The helper line says what to do.** "Add 4 more characters" rather than
///   "Password too short". A validation message the farmer cannot act on is
///   just the app complaining.
/// * **Never colour alone.** An error is a red border *and* an alert glyph
///   *and* a sentence. Valid is a green border *and* a tick *and* the words
///   "Passwords match".
/// * **48dp of touch.** The shell is 54 and every trailing control inside it
///   is a full 48 square, which is why show/hide is an [IconButton] with its
///   own constraints rather than a tappable [Icon].
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/app_motion.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.g.dart';
import '../../domain/auth/contact_details.dart';
import '../../domain/auth/password_policy.dart';

/// What the shell's border is saying.
enum FieldTone { neutral, valid, error }

/// A labelled input with an optional helper line.
class AppTextField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final IconData? leadingIcon;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final List<String>? autofillHints;
  final String? helper;
  final FieldTone tone;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSubmitted;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;

  /// Sits inside the shell, left of the text, divided by a hairline. Used by
  /// the phone field for its country block.
  final Widget? prefix;

  /// Sits inside the shell, right of the text. Used for show/hide.
  final Widget? suffix;

  final bool obscureText;

  const AppTextField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.leadingIcon,
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.next,
    this.autofillHints,
    this.helper,
    this.tone = FieldTone.neutral,
    this.enabled = true,
    this.onChanged,
    this.onSubmitted,
    this.maxLength,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.prefix,
    this.suffix,
    this.obscureText = false,
  });

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;

    final (border, width) = switch (widget.tone) {
      FieldTone.error => (c.statusActionRequired, 1.5),
      FieldTone.valid => (c.statusOnTrack, 1.5),
      FieldTone.neutral =>
        _focus.hasFocus ? (c.primary, 2.0) : (c.outlineVariant, 1.5),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: AlmanacDimens.sp4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label,
            style: text.labelMedium?.copyWith(color: c.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Container(
            constraints: const BoxConstraints(minHeight: 54),
            padding: EdgeInsets.only(
              left: widget.prefix == null
                  ? AlmanacDimens.sp4
                  : AlmanacDimens.sp3,
              right: widget.suffix == null ? AlmanacDimens.sp4 : 4,
            ),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(AlmanacDimens.rMd),
              border: Border.all(color: border, width: width),
            ),
            child: Row(
              children: [
                if (widget.prefix != null) ...[
                  widget.prefix!,
                  const SizedBox(width: AlmanacDimens.sp3),
                ],
                if (widget.leadingIcon != null) ...[
                  Icon(widget.leadingIcon, size: 18, color: c.onSurfaceVariant),
                  const SizedBox(width: AlmanacDimens.sp3),
                ],
                Expanded(
                  // A stable handle for UI automation. The label is a sibling
                  // Text rather than part of the field's own semantics, so
                  // Maestro has nothing on the input itself to find it by.
                  child: Semantics(
                    container: true,
                    identifier: fieldIdentifier(widget.label),
                    child: TextField(
                      controller: widget.controller,
                      focusNode: _focus,
                      enabled: widget.enabled,
                      obscureText: widget.obscureText,
                      keyboardType: widget.keyboardType,
                      textInputAction: widget.textInputAction,
                      textCapitalization: widget.textCapitalization,
                      autofillHints: widget.autofillHints,
                      inputFormatters: widget.inputFormatters,
                      maxLength: widget.maxLength,
                      maxLengthEnforcement: MaxLengthEnforcement.enforced,
                      onChanged: widget.onChanged,
                      onSubmitted: (_) => widget.onSubmitted?.call(),
                      style: text.bodyLarge,
                      cursorColor: c.primary,
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        counterText: '',
                        hintText: widget.hint,
                        hintStyle: text.bodyLarge?.copyWith(
                          color: c.onSurfaceVariant,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                ),
                if (widget.suffix != null) widget.suffix!,
              ],
            ),
          ),
          if (widget.helper != null) ...[
            const SizedBox(height: 6),
            FieldHelper(message: widget.helper!, tone: widget.tone),
          ],
        ],
      ),
    );
  }
}

/// `field-confirm-password` for a field labelled "Confirm password". What the
/// Maestro flows in `e2e/mobile/` select inputs by.
String fieldIdentifier(String label) =>
    'field-${label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}';

/// The helper line. Glyph, colour and words — three carriers, always.
class FieldHelper extends StatelessWidget {
  final String message;
  final FieldTone tone;

  const FieldHelper({
    super.key,
    required this.message,
    this.tone = FieldTone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final (icon, colour) = switch (tone) {
      FieldTone.error => (LucideIcons.triangleAlert, c.statusActionRequired),
      FieldTone.valid => (LucideIcons.circleCheckBig, c.statusOnTrack),
      FieldTone.neutral => (null, c.onSurfaceVariant),
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 14, color: colour),
          ),
          const SizedBox(width: 5),
        ],
        Expanded(
          child: Text(
            message,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: colour),
          ),
        ),
      ],
    );
  }
}

/// A phone field with the country block inside the shell.
///
/// The country is a real control, not decoration: guide §8 defaults it to
/// South Africa and requires that it can still be changed. Tapping it opens a
/// sheet rather than a `DropdownButton`, because a dropdown anchored inside a
/// 54px shell on a 360px screen renders its menu over the field being edited.
class AppPhoneField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final DiallingCountry country;
  final ValueChanged<DiallingCountry> onCountryChanged;
  final ValueChanged<String>? onChanged;
  final String? helper;
  final FieldTone tone;
  final bool enabled;
  final TextInputAction textInputAction;
  final VoidCallback? onSubmitted;

  const AppPhoneField({
    super.key,
    required this.label,
    required this.controller,
    required this.country,
    required this.onCountryChanged,
    this.onChanged,
    this.helper,
    this.tone = FieldTone.neutral,
    this.enabled = true,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;

    return AppTextField(
      label: label,
      controller: controller,
      hint: '82 555 0123',
      keyboardType: TextInputType.phone,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      autofillHints: const [AutofillHints.telephoneNumberNational],
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
        LengthLimitingTextInputFormatter(16),
      ],
      onChanged: onChanged,
      helper: helper,
      tone: tone,
      enabled: enabled,
      prefix: _CountryBlock(
        country: country,
        enabled: enabled,
        onChanged: onCountryChanged,
        divider: c.outlineVariant,
      ),
    );
  }
}

class _CountryBlock extends StatelessWidget {
  final DiallingCountry country;
  final bool enabled;
  final ValueChanged<DiallingCountry> onChanged;
  final Color divider;

  const _CountryBlock({
    required this.country,
    required this.enabled,
    required this.onChanged,
    required this.divider,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;

    return InkWell(
      onTap: enabled ? () => _pick(context) : null,
      borderRadius: BorderRadius.circular(AlmanacDimens.rXs),
      child: Container(
        // The full touch minimum, even though the visible block is narrower.
        constraints: const BoxConstraints(minHeight: AlmanacDimens.touchMin),
        padding: const EdgeInsets.only(right: AlmanacDimens.sp3),
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: divider)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(country.flag, style: text.labelLarge),
            const SizedBox(width: 6),
            Text(country.dialCode, style: text.labelLarge),
            Icon(LucideIcons.chevronDown, size: 16, color: c.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final c = context.semantic;
    final chosen = await showModalBottomSheet<DiallingCountry>(
      context: context,
      backgroundColor: c.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AlmanacDimens.r2xl),
        ),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AlmanacDimens.gutter,
                0,
                AlmanacDimens.gutter,
                AlmanacDimens.sp3,
              ),
              child: Text(
                'Country code',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final option in diallingCountries)
                    ListTile(
                      minTileHeight: AlmanacDimens.touchMin,
                      leading: Text(
                        option.flag,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      title: Text(option.name),
                      trailing: Text(
                        option.dialCode,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      selected: option.isoCode == country.isoCode,
                      onTap: () => Navigator.of(context).pop(option),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (chosen != null) onChanged(chosen);
  }
}

/// A password field with a show/hide control that is a real 48dp button.
class AppPasswordField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final String? helper;
  final FieldTone tone;
  final bool enabled;
  final TextInputAction textInputAction;
  final VoidCallback? onSubmitted;

  /// `newPassword` on sign-up and reset so the password manager offers to
  /// generate and save one; `password` on login so it offers to fill.
  final List<String> autofillHints;

  const AppPasswordField({
    super.key,
    required this.label,
    required this.controller,
    this.onChanged,
    this.helper,
    this.tone = FieldTone.neutral,
    this.enabled = true,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.autofillHints = const [AutofillHints.password],
  });

  @override
  State<AppPasswordField> createState() => _AppPasswordFieldState();
}

class _AppPasswordFieldState extends State<AppPasswordField> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;

    return AppTextField(
      label: widget.label,
      controller: widget.controller,
      leadingIcon: LucideIcons.lock,
      obscureText: !_shown,
      keyboardType: TextInputType.visiblePassword,
      textInputAction: widget.textInputAction,
      onSubmitted: widget.onSubmitted,
      autofillHints: widget.autofillHints,
      // Guide §8: allow at least 64. The cap is the policy's, not the
      // widget's, so the two can never disagree.
      maxLength: maxPasswordLength,
      onChanged: widget.onChanged,
      helper: widget.helper,
      tone: widget.tone,
      enabled: widget.enabled,
      suffix: IconButton(
        onPressed: widget.enabled
            ? () => setState(() => _shown = !_shown)
            : null,
        iconSize: 20,
        constraints: const BoxConstraints(
          minWidth: AlmanacDimens.touchMin,
          minHeight: AlmanacDimens.touchMin,
        ),
        // Both words are here for a screen reader; the glyph alone is the
        // exception COMPONENTS.md allows for chrome, and this pays for it.
        tooltip: _shown ? 'Hide password' : 'Show password',
        icon: Icon(
          _shown ? LucideIcons.eyeOff : LucideIcons.eye,
          color: c.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Three segments and a word, per COMPONENTS.md.
///
/// The word is not optional and never shortens to a colour: a farmer with a
/// red-green deficiency reads three grey bars, and the sentence underneath is
/// the whole message.
class PasswordStrengthMeter extends StatelessWidget {
  final PasswordAssessment assessment;

  const PasswordStrengthMeter({super.key, required this.assessment});

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;
    final motion = AppMotion.of(context);

    // An untouched field gets an empty track and a muted hint. It is advice
    // about what to type, not a verdict on what was typed.
    final (filled, colour) = assessment.untouched
        ? (0, c.onSurfaceVariant)
        : switch (assessment.strength) {
            PasswordStrength.weak => (1, c.statusActionRequired),
            PasswordStrength.fair => (2, c.statusNeedsAttention),
            PasswordStrength.strong => (3, c.statusOnTrack),
          };

    return Padding(
      padding: const EdgeInsets.only(bottom: AlmanacDimens.sp4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 5),
                Expanded(
                  child: AnimatedContainer(
                    duration: motion.micro,
                    curve: AlmanacMotion.easeStandard,
                    height: 5,
                    decoration: BoxDecoration(
                      color: i < filled ? colour : c.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            assessment.advice,
            style: text.labelSmall?.copyWith(color: colour),
          ),
        ],
      ),
    );
  }
}
