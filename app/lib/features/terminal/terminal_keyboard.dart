import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:xterm/xterm.dart';

import 'terminal_ime.dart';

/// Connects the on-screen keyboard to [terminal], replacing xterm's own text
/// input (see terminal_ime.dart for why).
///
/// [child] is a [TerminalView] built with `hardwareKeyboardOnly: true` and the
/// same [focusNode]: the view still handles hardware keys, this widget handles
/// the keyboard. A tap on the terminal reopens a dismissed keyboard.
class TerminalKeyboard extends StatefulWidget {
  const TerminalKeyboard({
    super.key,
    required this.terminal,
    required this.focusNode,
    required this.child,
    this.keyboardAppearance = Brightness.dark,
    this.caretRect,
    this.onInput,
  });

  final Terminal terminal;
  final FocusNode focusNode;
  final Brightness keyboardAppearance;

  /// The terminal cursor in global coordinates, for placing the keyboard's
  /// candidate window (CJK input).
  final Rect? Function()? caretRect;

  /// After each keystroke from the keyboard (to scroll to the bottom).
  final VoidCallback? onInput;

  final Widget child;

  @override
  State<TerminalKeyboard> createState() => TerminalKeyboardState();
}

class TerminalKeyboardState extends State<TerminalKeyboard> with TextInputClient, DeltaTextInputClient {
  TextInputConnection? _connection;
  var _value = imeIdle;
  var _geometryQueued = false;
  Offset? _downAt;

  /// Whether the keyboard is mid-word. Hardware key events are left to it
  /// meanwhile, as an editor would.
  bool get composing => imeComposing(_value);

  bool get _attached => _connection?.attached ?? false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_focusChanged);
    widget.terminal.addListener(_queueGeometry);
  }

  @override
  void didUpdateWidget(TerminalKeyboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_focusChanged);
      widget.focusNode.addListener(_focusChanged);
    }
    if (oldWidget.terminal != widget.terminal) {
      oldWidget.terminal.removeListener(_queueGeometry);
      widget.terminal.addListener(_queueGeometry);
    }
    if (oldWidget.keyboardAppearance != widget.keyboardAppearance && _attached) _connection!.updateConfig(_config);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_focusChanged);
    widget.terminal.removeListener(_queueGeometry);
    _close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    // Raw pointer events, outside the gesture arena: the view's own tap
    // callbacks don't fire while the program in it takes mouse input.
    onPointerDown: (e) => _downAt = e.position,
    onPointerUp: (e) {
      final down = _downAt;
      _downAt = null;
      if (down != null && (e.position - down).distance < kTouchSlop) show();
    },
    onPointerCancel: (_) => _downAt = null,
    child: widget.child,
  );

  /// Opens the keyboard, focusing the terminal first if needed.
  void show() {
    if (!widget.focusNode.hasFocus) {
      widget.focusNode.requestFocus(); // the listener opens it
      return;
    }
    if (!_attached) {
      _value = imeIdle;
      _connection = TextInput.attach(this, _config)..setEditingState(_value);
      _queueGeometry();
    }
    _connection!.show();
  }

  /// Ends whatever word the keyboard is composing. Call before sending keys
  /// another way (toolbar, buttons, paste): the keyboard would otherwise
  /// keep editing a word the shell has moved on from.
  void finishComposing() {
    if (_value == imeIdle) return;
    _value = imeIdle;
    if (_attached) _connection!.setEditingState(imeIdle);
  }

  void _focusChanged() {
    // The token is only there when focus was asked for (a tap, autofocus),
    // not when it comes back after a menu or dialog closes.
    if (widget.focusNode.hasFocus && widget.focusNode.consumeKeyboardToken()) {
      show();
    } else if (!widget.focusNode.hasFocus) {
      _close();
    }
  }

  void _close() {
    if (_attached) _connection!.close();
    _connection = null;
  }

  TextInputConfiguration get _config => TextInputConfiguration(
    viewId: View.maybeOf(context)?.viewId,
    // Plain text with suggestions off is a "visible password" field on
    // Android, where keyboards don't compose or predict. (xterm's default,
    // an email field, turned into a "filter" field, where they do.)
    inputType: TextInputType.text,
    inputAction: TextInputAction.newline,
    keyboardAppearance: widget.keyboardAppearance,
    autocorrect: false,
    enableSuggestions: false,
    enableIMEPersonalizedLearning: false,
    // iOS would turn " into “ and -- into —.
    smartDashesType: SmartDashesType.disabled,
    smartQuotesType: SmartQuotesType.disabled,
    enableDeltaModel: true,
  );

  void _send(ImeKey key) {
    final t = widget.terminal;
    switch (key) {
      case ImeText(:final text):
        t.textInput(text);
      case ImeBackspace(:final count):
        for (var i = 0; i < count; i++) {
          t.keyInput(TerminalKey.backspace);
        }
      case ImeEnter():
        t.keyInput(TerminalKey.enter);
    }
    widget.onInput?.call();
  }

  /// Tells the platform where the terminal and its cursor are, after the
  /// next frame (the cursor moves when the shell echoes).
  void _queueGeometry() {
    if (_geometryQueued || !_attached) return;
    _geometryQueued = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _geometryQueued = false;
      final box = mounted ? context.findRenderObject() : null;
      if (!_attached || box is! RenderBox || !box.hasSize) return;
      _connection!.setEditableSizeAndTransform(box.size, box.getTransformTo(null));
      final caret = widget.caretRect?.call();
      if (caret != null) _connection!.setCaretRect(MatrixUtils.inverseTransformRect(box.getTransformTo(null), caret));
    });
  }

  @override
  void updateEditingValueWithDeltas(List<TextEditingDelta> textEditingDeltas) {
    for (final delta in textEditingDeltas) {
      // Applied to the delta's own old text, so it holds even when the
      // keyboard typed before our last reset reached it.
      _value = delta.apply(_value);
      imeKeys(delta).forEach(_send);
    }
    if (imeShouldReset(_value)) {
      _value = imeIdle;
      _connection?.setEditingState(imeIdle);
    }
  }

  // Only deltas arrive (enableDeltaModel).
  @override
  void updateEditingValue(TextEditingValue value) {}

  @override
  void performAction(TextInputAction action) {
    // On iOS the return key also inserts "\n", which already sent Enter.
    if (action == TextInputAction.newline && defaultTargetPlatform == TargetPlatform.iOS) return;
    _send(const ImeEnter());
  }

  @override
  TextEditingValue get currentTextEditingValue => _value;

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void connectionClosed() {
    _connection?.connectionClosedReceived();
    _connection = null;
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}
}
