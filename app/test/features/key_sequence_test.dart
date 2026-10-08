import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/features/commands/key_sequence.dart';

void main() {
  test('plain text', () {
    expect(parseKeySequence('git status'), [const TextKeys('git status')]);
  });

  test('text followed by enter', () {
    expect(parseKeySequence('git status<enter>'), [
      const TextKeys('git status'),
      const SpecialKeyPress(SpecialKey.enter),
    ]);
  });

  test('named keys are case-insensitive, cr is enter', () {
    expect(parseKeySequence('<ESC>:wq<CR>'), [
      const SpecialKeyPress(SpecialKey.escape),
      const TextKeys(':wq'),
      const SpecialKeyPress(SpecialKey.enter),
    ]);
  });

  test('ctrl, alt and shift-tab chords', () {
    expect(parseKeySequence('<c-c><a-x><s-tab>'), [
      const ChordKeys('c', ctrl: true),
      const ChordKeys('x', alt: true),
      const SpecialKeyPress(SpecialKey.tab, shift: true),
    ]);
  });

  test('<lt> and <space> are literal, unknown tokens pass through', () {
    expect(parseKeySequence('a<lt>b<space>c <foo> d'), [const TextKeys('a<b c <foo> d')]);
  });

  test('shell redirection is not mistaken for a key', () {
    expect(parseKeySequence('cat a > b<enter>'), [
      const TextKeys('cat a > b'),
      const SpecialKeyPress(SpecialKey.enter),
    ]);
  });
}
