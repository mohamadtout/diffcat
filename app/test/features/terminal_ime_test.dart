import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/features/terminal/terminal_ime.dart';

/// A delta replacing [start]..[end] of [old] with [text].
TextEditingDelta _edit(String old, int start, int end, String text, {TextRange composing = TextRange.empty}) =>
    TextEditingDelta.fromJSON({
      'oldText': old,
      'deltaText': text,
      'deltaStart': start,
      'deltaEnd': end,
      'selectionBase': start + text.length,
      'selectionExtent': start + text.length,
      'composingBase': composing.start,
      'composingExtent': composing.end,
    });

void main() {
  test('typing a letter sends it', () {
    expect(imeKeys(_edit('  ', 2, 2, 'a')), [const ImeText('a')]);
  });

  test('backspace on the idle field sends backspace', () {
    final delta = _edit('  ', 1, 2, '');
    expect(delta, isA<TextEditingDeltaDeletion>());
    expect(imeKeys(delta), [const ImeBackspace(1)]);
  });

  test('a composing word is sent letter by letter as it grows', () {
    final g = _edit('  ', 2, 2, 'g', composing: const TextRange(start: 2, end: 3));
    final gi = _edit('  g', 2, 3, 'gi', composing: const TextRange(start: 2, end: 4));
    final git = _edit('  gi', 2, 4, 'git', composing: const TextRange(start: 2, end: 5));
    expect([g, gi, git].expand(imeKeys), [const ImeText('g'), const ImeText('i'), const ImeText('t')]);
  });

  test('backspace inside a composing word deletes one letter', () {
    expect(imeKeys(_edit('  git', 2, 5, 'gi', composing: const TextRange(start: 2, end: 4))), [const ImeBackspace(1)]);
  });

  test('a correction backspaces to where it differs and types the rest', () {
    expect(imeKeys(_edit('  teh', 2, 5, 'the ')), [const ImeBackspace(2), const ImeText('he ')]);
  });

  test('committing the word as composed sends nothing more', () {
    expect(imeKeys(_edit('  git', 2, 5, 'git')), isEmpty);
  });

  test('line breaks become Enter', () {
    expect(imeKeys(_edit('  ', 2, 2, '\n')), [const ImeEnter()]);
    expect(imeKeys(_edit('  ', 2, 2, 'ls\r\npwd\r')), [
      const ImeText('ls'),
      const ImeEnter(),
      const ImeText('pwd'),
      const ImeEnter(),
    ]);
  });

  test('an emoji is one backspace, counted in code points', () {
    expect(imeKeys(_edit('  😀', 2, 4, '')), [const ImeBackspace(1)]);
  });

  test('a CJK conversion replaces the romanized letters', () {
    expect(imeKeys(_edit('  ni', 2, 4, '你')), [const ImeBackspace(2), const ImeText('你')]);
  });

  test('selection-only changes send nothing', () {
    final delta = TextEditingDelta.fromJSON({
      'oldText': '  ',
      'deltaText': '',
      'deltaStart': -1,
      'deltaEnd': -1,
      'selectionBase': 1,
      'selectionExtent': 1,
    });
    expect(imeKeys(delta), isEmpty);
  });

  test('resets after a finished edit, not mid-word', () {
    expect(imeShouldReset(imeIdle), isFalse);
    expect(imeShouldReset(const TextEditingValue(text: '  a', selection: TextSelection.collapsed(offset: 3))), isTrue);
    expect(imeShouldReset(const TextEditingValue(text: ' ', selection: TextSelection.collapsed(offset: 1))), isTrue);
    const composing = TextEditingValue(
      text: '  gi',
      selection: TextSelection.collapsed(offset: 4),
      composing: TextRange(start: 2, end: 4),
    );
    expect(imeComposing(composing), isTrue);
    expect(imeShouldReset(composing), isFalse);
  });
}
