import 'package:flutter/material.dart';
import 'package:focusdesk/core/constants/app_strings.dart';

class AppTextField extends StatefulWidget {
  const AppTextField({
    required this.label,
    this.hint,
    this.validator,
    this.controller,
    this.initialValue,
    this.isPassword = false,
    this.prefixIcon,
    this.suffixIcon,
    this.keyboardType,
    this.textInputAction = TextInputAction.next,
    this.onChanged,
    this.onFieldSubmitted,
    this.maxLines = 1,
    this.maxLength,
    this.enabled = true,
    this.autofocus = false,
    this.autofillHints,
    super.key,
  }) : assert(controller == null || initialValue == null);

  final String label;
  final String? hint;
  final FormFieldValidator<String>? validator;
  final TextEditingController? controller;
  final String? initialValue;
  final bool isPassword;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  final int maxLines;
  final int? maxLength;
  final bool enabled;
  final bool autofocus;
  final Iterable<String>? autofillHints;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  bool _obscured = true;

  @override
  void didUpdateWidget(covariant AppTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPassword != widget.isPassword) {
      _obscured = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibilityToggle = widget.isPassword
        ? IconButton(
            tooltip: _obscured
                ? AppStrings.showPassword
                : AppStrings.hidePassword,
            onPressed: widget.enabled
                ? () => setState(() => _obscured = !_obscured)
                : null,
            icon: Icon(
              _obscured
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),
          )
        : null;
    final suffix = visibilityToggle == null
        ? widget.suffixIcon
        : widget.suffixIcon == null
        ? visibilityToggle
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [widget.suffixIcon!, visibilityToggle],
          );

    return TextFormField(
      controller: widget.controller,
      initialValue: widget.initialValue,
      validator: widget.validator,
      obscureText: widget.isPassword && _obscured,
      enableSuggestions: !widget.isPassword,
      autocorrect: !widget.isPassword,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onFieldSubmitted,
      maxLines: widget.isPassword ? 1 : widget.maxLines,
      maxLength: widget.maxLength,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      autofillHints: widget.autofillHints,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        prefixIcon: widget.prefixIcon == null ? null : Icon(widget.prefixIcon),
        suffixIcon: suffix,
        errorMaxLines: 3,
      ),
    );
  }
}
