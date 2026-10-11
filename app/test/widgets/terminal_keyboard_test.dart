import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/features/terminal/terminal_ime.dart';
import 'package:git_reviewer/features/terminal/terminal_keyboard.dart';
import 'package:xterm/xterm.dart';

const _bs = '\x7f';

/// A phone keyboard on the other end of the text input channel: holds the
/// platform's copy of the field and sends edits the way Android IMEs
/// (composing text, commits, surrounding-text deletes) and iOS (insertText,
/// deleteBackward) do. The app's resets only reach it on [sync], so a test can
/// type before one lands.
class _Keyboard {
  _Keyboard(this.tester);

  final WidgetTester tester;
  var field = imeIdle;

  /// The app's last reset arrives.
  void sync() => field = TextEditingValue.fromJSON(tester.testTextInput.editingState!);

  int get _client =>
      (tester.testTextInput.log.lastWhere((c) => c.method == 'TextInput.setClient').arguments as List)[0] as int;

  Future<void> _message(String method, List<Object?> args) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.textInput.name,
      SystemChannels.textInput.codec.encodeMethodCall(MethodCall(method, args)),
      (_) {},
    );
    await tester.pump();
  }

  Future<void> _replace(int start, int end, String text, {TextRange composing = TextRange.empty}) {
    final old = field.text;
    field = TextEditingValue(
      text: old.replaceRange(start, end, text),
      selection: TextSelection.collapsed(offset: start + text.length),
      composing: composing,
    );
    return _message('TextInputClient.updateEditingStateWithDeltas', [
      _client,
      {
        'deltas': [
          {
            'oldText': old,
            'deltaText': text,
            'deltaStart': start,
            'deltaEnd': end,
            'selectionBase': field.selection.baseOffset,
            'selectionExtent': field.selection.extentOffset,
            'composingBase': composing.start,
            'composingExtent': composing.end,
          },
        ],
      },
    ]);
  }

  TextRange get _target => field.composing.isValid && !field.composing.isCollapsed
      ? field.composing
      : TextRange(start: field.selection.start, end: field.selection.end);

  // Android InputConnection calls.
  Future<void> setComposingText(String text) {
    final r = _target;
    if (text.isEmpty) return commitText(text); // what Flutter's adaptor does
    return _replace(
      r.start,
      r.end,
      text,
      composing: TextRange(start: r.start, end: r.start + text.length),
    );
  }

  Future<void> commitText(String text) => _replace(_target.start, _target.end, text);

  Future<void> deleteSurroundingText(int before) {
    final cursor = field.selection.start;
    final start = cursor - before < 0 ? 0 : cursor - before;
    return _replace(start, cursor, '');
  }

  // iOS UITextInput calls.
  Future<void> insertText(String text) => commitText(text);

  Future<void> deleteBackward() async {
    if (field.selection.start == 0) return; // nothing to delete: iOS sends nothing
    await deleteSurroundingText(1);
  }

  Future<void> performAction(TextInputAction action) =>
      _message('TextInputClient.performAction', [_client, action.toString()]);

  Future<void> type(String text, {bool composing = false}) async {
    for (final c in text.split('')) {
      if (composing) {
        final r = _target;
        await setComposingText(r.textInside(field.text) + c);
      } else {
        await commitText(c);
        sync();
      }
    }
  }
}

void main() {
  late StringBuffer out;
  late Terminal terminal;
  late FocusNode focus;
  late GlobalKey<TerminalKeyboardState> keyboardKey;

  Future<_Keyboard> open(WidgetTester tester) async {
    out = StringBuffer();
    terminal = Terminal()..onOutput = out.write;
    focus = FocusNode();
    keyboardKey = GlobalKey();
    addTearDown(focus.dispose);
    // Wired as TerminalScreen wires it.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalKeyboard(
            key: keyboardKey,
            terminal: terminal,
            focusNode: focus,
            child: TerminalView(
              terminal,
              focusNode: focus,
              autofocus: true,
              hardwareKeyboardOnly: true,
              onKeyEvent: (_, _) => keyboardKey.currentState?.composing ?? false
                  ? KeyEventResult.skipRemainingHandlers
                  : KeyEventResult.ignored,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.testTextInput.hasAnyClients, isTrue, reason: 'the keyboard opens with the terminal');
    return _Keyboard(tester)..sync();
  }

  testWidgets('asks for a plain field: deltas, no suggestions, no smart punctuation', (tester) async {
    await open(tester);
    final config =
        (tester.testTextInput.log.lastWhere((c) => c.method == 'TextInput.setClient').arguments as List)[1]
            as Map<String, dynamic>;
    expect((config['inputType'] as Map)['name'], 'TextInputType.text');
    expect(config['enableDeltaModel'], isTrue);
    expect(config['enableSuggestions'], isFalse);
    expect(config['autocorrect'], isFalse);
    expect(config['smartQuotesType'], '0');
    expect(config['smartDashesType'], '0');
    expect(tester.testTextInput.editingState!['text'], imeIdle.text);
  });

  testWidgets('a word being composed reaches the shell letter by letter', (tester) async {
    final kb = await open(tester);
    await kb.type('git', composing: true);
    expect(out.toString(), 'git', reason: 'the cursor moves with each letter');
    await kb.setComposingText('gi'); // backspace inside the word
    expect(out.toString(), 'git$_bs');
    await kb.commitText('gi');
    await kb.commitText(' ');
    expect(out.toString(), 'git$_bs ');
  });

  testWidgets('Tab from the toolbar completes the word being composed', (tester) async {
    final kb = await open(tester);
    await kb.type('REA', composing: true);
    // The toolbar's Tab: end the word, then send the key.
    keyboardKey.currentState!.finishComposing();
    terminal.keyInput(TerminalKey.tab);
    await tester.pump();
    expect(out.toString(), 'REA\t');
    // The keyboard starts over (Android restarts input when the app ends its
    // word), so the next word doesn't retype or correct the old one.
    kb.sync();
    await kb.type('x', composing: true);
    expect(out.toString(), 'REA\tx');
  });

  testWidgets('backspace keeps working on an empty line', (tester) async {
    final kb = await open(tester);
    for (var i = 0; i < 5; i++) {
      await kb.deleteSurroundingText(1);
      kb.sync();
    }
    expect(out.toString(), _bs * 5);
  });

  testWidgets('fast backspaces before a reset lands are not doubled', (tester) async {
    final kb = await open(tester);
    await kb.deleteSurroundingText(1); // "  " -> " "; the app resets
    await kb.deleteSurroundingText(1); // " " -> "" before the reset arrives
    expect(out.toString(), _bs * 2);
    kb.sync();
    await kb.deleteSurroundingText(1);
    expect(out.toString(), _bs * 3);
  });

  testWidgets('iOS: letters, backspace on an empty line, one Enter for return', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final kb = await open(tester);
    await kb.type('lx');
    await kb.deleteBackward();
    kb.sync();
    await kb.deleteBackward();
    kb.sync();
    await kb.type('s');
    // UIKit calls performAction(newline) and then inserts "\n".
    await kb.performAction(TextInputAction.newline);
    await kb.insertText('\n');
    expect(out.toString(), 'lx$_bs${_bs}s\r');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Android: an editor action is Enter', (tester) async {
    final kb = await open(tester);
    await kb.performAction(TextInputAction.newline);
    expect(out.toString(), '\r');
  });

  testWidgets('a correction rewrites only what changed', (tester) async {
    final kb = await open(tester);
    await kb.type('teh', composing: true);
    await kb.commitText('the');
    await kb.commitText(' ');
    expect(out.toString(), 'teh$_bs${_bs}he ');
  });

  testWidgets('hardware keys go to the shell, except while the keyboard composes', (tester) async {
    final kb = await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    expect(out.toString(), _bs);
    await kb.type('ab', composing: true);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace); // the keyboard's own
    expect(out.toString(), '${_bs}ab');
  });

  testWidgets('tapping the terminal brings a dismissed keyboard back', (tester) async {
    await open(tester);
    tester.testTextInput.log.clear();
    // Mouse reporting on (lazygit, htop): the view keeps taps to itself.
    terminal.write('\x1b[?1000h');
    await tester.tap(find.byType(TerminalView));
    await tester.pump();
    expect(tester.testTextInput.log.map((c) => c.method), contains('TextInput.show'));
    await tester.pump(const Duration(milliseconds: 400)); // the view's double-tap timer
  });
}
