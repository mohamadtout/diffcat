/// Parses the key notation used by custom SSH buttons, e.g.
/// `git status<enter>` or `<esc>:wq<enter>` or `<c-c>`.
///
/// Supported tokens (case-insensitive):
/// ```text
///   <enter> <cr> <esc> <tab> <s-tab> <bs> <space> <del>
///   <up> <down> <left> <right> <home> <end> <pgup> <pgdn>
///   <f1>…<f12>   <c-x> (Ctrl+x)   <a-x> (Alt+x)   <lt> (literal '<')
/// ```
/// Anything else is sent as literal text. See docs/commands.md.
library;

enum SpecialKey {
  enter,
  escape,
  tab,
  backspace,
  delete,
  up,
  down,
  left,
  right,
  home,
  end,
  pageUp,
  pageDown,
  f1,
  f2,
  f3,
  f4,
  f5,
  f6,
  f7,
  f8,
  f9,
  f10,
  f11,
  f12,
}

sealed class KeyAction {
  const KeyAction();
}

class TextKeys extends KeyAction {
  const TextKeys(this.text);
  final String text;

  @override
  bool operator ==(Object other) => other is TextKeys && other.text == text;
  @override
  int get hashCode => text.hashCode;
  @override
  String toString() => 'Text($text)';
}

class SpecialKeyPress extends KeyAction {
  const SpecialKeyPress(this.key, {this.shift = false});
  final SpecialKey key;
  final bool shift;

  @override
  bool operator ==(Object other) => other is SpecialKeyPress && other.key == key && other.shift == shift;
  @override
  int get hashCode => Object.hash(key, shift);
  @override
  String toString() => 'Key(${key.name}${shift ? '+shift' : ''})';
}

/// Ctrl or Alt combined with a single printable character.
class ChordKeys extends KeyAction {
  const ChordKeys(this.char, {this.ctrl = false, this.alt = false});
  final String char;
  final bool ctrl;
  final bool alt;

  @override
  bool operator ==(Object other) => other is ChordKeys && other.char == char && other.ctrl == ctrl && other.alt == alt;
  @override
  int get hashCode => Object.hash(char, ctrl, alt);
  @override
  String toString() => 'Chord(${ctrl ? 'C-' : ''}${alt ? 'A-' : ''}$char)';
}

const _named = <String, SpecialKey>{
  'enter': SpecialKey.enter,
  'cr': SpecialKey.enter,
  'return': SpecialKey.enter,
  'esc': SpecialKey.escape,
  'tab': SpecialKey.tab,
  'bs': SpecialKey.backspace,
  'del': SpecialKey.delete,
  'up': SpecialKey.up,
  'down': SpecialKey.down,
  'left': SpecialKey.left,
  'right': SpecialKey.right,
  'home': SpecialKey.home,
  'end': SpecialKey.end,
  'pgup': SpecialKey.pageUp,
  'pgdn': SpecialKey.pageDown,
  'f1': SpecialKey.f1,
  'f2': SpecialKey.f2,
  'f3': SpecialKey.f3,
  'f4': SpecialKey.f4,
  'f5': SpecialKey.f5,
  'f6': SpecialKey.f6,
  'f7': SpecialKey.f7,
  'f8': SpecialKey.f8,
  'f9': SpecialKey.f9,
  'f10': SpecialKey.f10,
  'f11': SpecialKey.f11,
  'f12': SpecialKey.f12,
};

final _token = RegExp(r'<([^<>\s]{1,8})>');

List<KeyAction> parseKeySequence(String input) {
  final out = <KeyAction>[];
  final buf = StringBuffer();

  void flushText() {
    if (buf.isNotEmpty) {
      out.add(TextKeys(buf.toString()));
      buf.clear();
    }
  }

  var pos = 0;
  for (final m in _token.allMatches(input)) {
    buf.write(input.substring(pos, m.start));
    pos = m.end;
    final raw = m.group(1)!;
    final name = raw.toLowerCase();
    if (name == 'lt') {
      buf.write('<');
      continue;
    }
    if (name == 'space') {
      buf.write(' ');
      continue;
    }
    final KeyAction? action = switch (name) {
      's-tab' => const SpecialKeyPress(SpecialKey.tab, shift: true),
      _ when _named.containsKey(name) => SpecialKeyPress(_named[name]!),
      _ when name.length == 3 && name.startsWith('c-') => ChordKeys(name[2], ctrl: true),
      _ when name.length == 3 && name.startsWith('a-') => ChordKeys(raw[2], alt: true),
      _ => null,
    };
    if (action == null) {
      buf.write(m.group(0)); // unknown token: send literally
    } else {
      flushText();
      out.add(action);
    }
  }
  buf.write(input.substring(pos));
  flushText();
  return out;
}
