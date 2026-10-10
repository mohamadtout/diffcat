import 'package:flutter/material.dart';

/// Asks for one line of text and returns it trimmed, or null if cancelled.
/// Empty text is never accepted. [validate] returns an error to show under
/// the field, or null to accept. [plain] turns off autocorrect and
/// suggestions, for names and URLs.
Future<String?> askText(
  BuildContext context, {
  required String title,
  required String action,
  String initial = '',
  String? label,
  String? hint,
  String? helper,
  int? maxLength,
  bool plain = false,
  String? Function(String text)? validate,
}) => showDialog<String>(
  context: context,
  builder: (_) => _TextInputDialog(
    title: title,
    action: action,
    initial: initial,
    label: label,
    hint: hint,
    helper: helper,
    maxLength: maxLength,
    plain: plain,
    validate: validate,
  ),
);

/// Owns its TextEditingController so it is disposed only after the dialog's
/// exit animation finishes.
class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.action,
    required this.initial,
    this.label,
    this.hint,
    this.helper,
    this.maxLength,
    required this.plain,
    this.validate,
  });

  final String title;
  final String action;
  final String initial;
  final String? label;
  final String? hint;
  final String? helper;
  final int? maxLength;
  final bool plain;
  final String? Function(String text)? validate;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  // Starts with the initial text selected, so typing replaces it.
  late final _ctrl = TextEditingController(text: widget.initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.initial.length);
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    final error = widget.validate?.call(text);
    if (error != null) return setState(() => _error = error);
    Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _ctrl,
      autofocus: true,
      maxLength: widget.maxLength,
      autocorrect: !widget.plain,
      enableSuggestions: !widget.plain,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        helperText: widget.helper,
        errorText: _error,
      ),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: _submit, child: Text(widget.action)),
    ],
  );
}
