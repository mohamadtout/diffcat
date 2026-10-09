import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/core/theme/code_fonts.dart';
import 'package:git_reviewer/features/terminal/shell_integration.dart';
import 'package:git_reviewer/features/terminal/terminal_appearance.dart';
import 'package:git_reviewer/features/terminal/terminal_themes.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('appearance', () {
    test('round-trips through JSON', () {
      const a = TerminalAppearance(
        theme: 'dracula',
        font: CodeFont.firaCode,
        fontSize: 15,
        lineHeight: 1.4,
        cursor: TerminalCursorType.verticalBar,
        background: BackgroundKind.image,
        imagePath: '/x/bg.png',
        backgroundOpacity: 0.5,
        backgroundBlur: 6,
        statusPosition: StatusBarPosition.bottom,
        statusStyle: StatusBarStyle.plain,
        segments: {StatusSegment.branch, StatusSegment.host},
        shellIntegration: true,
        keyToolbar: false,
      );
      final b = TerminalAppearance.fromJson(a.toJson());
      expect(b.toJson(), a.toJson());
    });

    test('bad or out-of-range values fall back instead of throwing', () {
      final a = TerminalAppearance.fromJson({
        'font': 'comic-sans',
        'fontSize': 300,
        'cursor': 'nope',
        'segments': ['branch', 'bogus'],
      });
      expect(a.font, CodeFont.system);
      expect(a.fontSize, TerminalAppearance.maxFontSize);
      expect(a.cursor, TerminalCursorType.block);
      expect(a.segments, {StatusSegment.branch});
    });

    test('a background only shows when it has something to show', () {
      expect(const TerminalAppearance(background: BackgroundKind.image).hasBackground, isFalse);
      expect(const TerminalAppearance(background: BackgroundKind.gradient).hasBackground, isTrue);
      expect(
        const TerminalAppearance(background: BackgroundKind.gradient, backgroundOpacity: 0).hasBackground,
        isFalse,
      );
    });

    test('presets: unknown ids follow the app', () {
      expect(presetFor('dracula', appIsDark: false).id, 'dracula');
      expect(presetFor(followAppPreset, appIsDark: true).id, 'diffcat-dark');
      expect(presetFor('gone', appIsDark: false).id, 'diffcat-light');
      expect(presetFor('solarized-light', appIsDark: true).isDark, isFalse);
      expect({for (final p in terminalPresets) p.id}.length, terminalPresets.length, reason: 'unique ids');
    });
  });

  group('shell integration', () {
    test('OSC 7 folders', () {
      expect(parseOsc7(['file://laptop/home/me/my%20app']), '/home/me/my app');
      expect(parseOsc7(['file:///tmp']), '/tmp');
      expect(parseOsc7(['file://h/a', 'b']), '/a;b', reason: 'xterm splits OSC parameters on ;');
      expect(parseOsc7(['file://h/100%']), '/100%');
      expect(parseOsc7(['https://example.com/x']), isNull);
    });

    test('folders are quoted for the shell', () {
      expect(shellQuote("/it's here"), r"'/it'\''s here'");
      expect(gitStatusCommand(r'/a $(rm -rf ~)'), contains(r"cd -- '/a $(rm -rf ~)'"));
    });

    test('git status --porcelain=v2', () {
      final s = parseGitStatus(
        '# branch.oid 1234567890abcdef\n# branch.head main\n# branch.upstream origin/main\n# branch.ab +2 -1\n'
        '1 .M N... 100644 100644 100644 aaa bbb lib/a.dart\n2 R. N... 100644 100644 100644 c d R100 b\tc\n',
      )!;
      expect(s.branch, 'main');
      expect((s.ahead, s.behind, s.changes), (2, 1, 2));

      final detached = parseGitStatus('# branch.oid 1234567890abcdef\n# branch.head (detached)\n')!;
      expect(detached.detached, isTrue);
      expect(detached.branch, '1234567');
      expect(parseGitStatus(''), isNull);
    });

    test('the hook is one line and needs no single quotes inside eval', () {
      final cmd = shellHookCommand();
      expect(cmd.contains('\n'), isFalse);
      expect(cmd, startsWith(' '), reason: 'kept out of history');
      expect(shellHookSnippet(fish: true), contains('fish_prompt'));
      expect(shellHookSnippet(fish: false), contains('PROMPT_COMMAND'));
    });

    test('the hook works in a real bash', () async {
      final bash = await Process.run('bash', ['-c', 'echo ok']).then((r) => r.exitCode == 0, onError: (_) => false);
      if (!bash) return markTestSkipped('no bash');
      // Run the hook, then what bash does before a prompt.
      final r = await Process.run(
        'bash',
        ['--norc', '-c', '${shellHookCommand()}; cd /tmp && eval "\$PROMPT_COMMAND"'],
        environment: {'HOSTNAME': 'box'},
      );
      final out = r.stdout as String;
      expect(out, contains(hookDoneMarker));
      expect(parseOsc7([RegExp(r'\x1b\]7;([^\x07]*)\x07').firstMatch(out)![1]!]), anyOf('/tmp', '/private/tmp'));
    });
  });

  test('the hook works in a real zsh', () async {
    final zsh = await Process.run('zsh', ['-c', 'echo ok']).then((r) => r.exitCode == 0, onError: (_) => false);
    if (!zsh) return markTestSkipped('no zsh');
    final r = await Process.run('zsh', [
      '-f',
      '-c',
      '${shellHookCommand()}; cd /tmp && for f in \$precmd_functions; do \$f; done',
    ]);
    final out = r.stdout as String;
    expect(out, contains(hookDoneMarker));
    expect(parseOsc7([RegExp(r'\x1b\]7;([^\x07]*)\x07').firstMatch(out)![1]!]), anyOf('/tmp', '/private/tmp'));
  });

  group('EchoHider', () {
    final typed = shellHookCommand();

    test('hides the typed command up to the marker and clears the old prompt', () {
      final h = EchoHider(typed);
      final shown = StringBuffer()
        ..write(h.process('Last login: today\r\nme@box:~\$ '))
        ..write(h.process(typed.substring(0, 10)))
        ..write(h.process('${typed.substring(10)}\r\n$hookDoneMarker'))
        ..write(h.process('\x1b]7;file://box/home/me\x07me@box:~\$ '));
      expect(h.done, isTrue);
      expect(shown.toString(), 'Last login: today\r\nme@box:~\$ \r\x1b[2K\x1b]7;file://box/home/me\x07me@box:~\$ ');
      expect(h.process('ls\r\n'), 'ls\r\n');
    });

    test('output that only looks like the start of the echo is released', () {
      final h = EchoHider(typed);
      // The hook starts with ' [', so that tail waits for the next chunk.
      expect(h.process('prompt ['), 'prompt');
      expect(h.process('x]'), ' [x]');
    });

    test('flush gives back everything when the marker never comes', () {
      final h = EchoHider(typed);
      expect(h.process('\$ $typed\r\nfish: syntax error'), '\$ ');
      expect(h.flush(), '$typed\r\nfish: syntax error');
      expect(h.process('more'), 'more');
    });
  });
}
