/// Turning what the on-screen keyboard does into terminal keystrokes.
///
/// The keyboard edits a small hidden text field; each edit arrives as a
/// [TextEditingDelta] and is sent to the shell right away, as typed text,
/// backspaces or Enter. A word the keyboard is still composing counts as typed:
/// the shell sees every letter as it appears on screen, so the cursor moves
/// with it and Tab completes it. When the keyboard later changes that word (the
/// next letter, a backspace, a correction) the change arrives as a replacement
/// and is sent as backspaces plus the new ending. See D16 in docs/decisions.md.
library;

import 'package:flutter/services.dart';

/// The hidden field between keystrokes: two spaces with the cursor at the end,
/// so backspace always has something to delete (iOS ignores backspace in an
/// empty field, and Android keyboards differ on it).
const imeIdle = TextEditingValue(text: '  ', selection: TextSelection.collapsed(offset: 2));

/// One thing to send to the terminal.
sealed class ImeKey {
  const ImeKey();
}

/// Characters to type, without line breaks.
final class ImeText extends ImeKey {
  const ImeText(this.text);
  final String text;

  @override
  bool operator ==(Object other) => other is ImeText && other.text == text;
  @override
  int get hashCode => text.hashCode;
  @override
  String toString() => 'text($text)';
}

/// [count] presses of backspace.
final class ImeBackspace extends ImeKey {
  const ImeBackspace(this.count);
  final int count;

  @override
  bool operator ==(Object other) => other is ImeBackspace && other.count == count;
  @override
  int get hashCode => count.hashCode;
  @override
  String toString() => 'backspace($count)';
}

final class ImeEnter extends ImeKey {
  const ImeEnter();

  @override
  bool operator ==(Object other) => other is ImeEnter;
  @override
  int get hashCode => 0;
  @override
  String toString() => 'enter';
}

/// The keystrokes [delta] stands for. Edits are assumed to happen at the
/// cursor, which is where keyboards make them in a field this short.
List<ImeKey> imeKeys(TextEditingDelta delta) => switch (delta) {
  TextEditingDeltaInsertion(:final textInserted) => _retype('', textInserted),
  TextEditingDeltaDeletion(:final textDeleted) => _retype(textDeleted, ''),
  TextEditingDeltaReplacement(:final oldText, :final replacedRange, :final replacementText) => _retype(
    replacedRange.textInside(oldText),
    replacementText,
  ),
  _ => const [],
};

/// Turns [before] into [after] at the cursor: backspaces back to where they
/// differ, then the rest of [after]. Counted in code points, as the shell
/// deletes them.
List<ImeKey> _retype(String before, String after) {
  final a = before.runes.toList();
  final b = after.runes.toList();
  var same = 0;
  while (same < a.length && same < b.length && a[same] == b[same]) {
    same++;
  }
  final typed = String.fromCharCodes(b.skip(same)).replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  return [
    if (a.length > same) ImeBackspace(a.length - same),
    for (final (i, line) in typed.split('\n').indexed) ...[
      if (i > 0) const ImeEnter(),
      if (line.isNotEmpty) ImeText(line),
    ],
  ];
}

/// Whether the keyboard is in the middle of a word (or an accented letter, or
/// a CJK conversion).
bool imeComposing(TextEditingValue value) => value.composing.isValid && !value.composing.isCollapsed;

/// Whether the field should go back to [imeIdle]: after every finished edit,
/// so the keyboard has no earlier word to correct and backspace never runs
/// dry. Not while composing, which would cut the keyboard off mid-word.
bool imeShouldReset(TextEditingValue value) =>
    !imeComposing(value) && (value.text != imeIdle.text || value.selection != imeIdle.selection);
