import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/features/console/command_line.dart';
import 'package:git_reviewer/features/console/console_models.dart';

void main() {
  group('tokenize', () {
    test('splits on whitespace and honours quotes', () {
      expect(tokenize('log -n 5 -- "my dir/file.txt"'), ['log', '-n', '5', '--', 'my dir/file.txt']);
      expect(tokenize("cat 'a b'  c"), ['cat', 'a b', 'c']);
      expect(tokenize(r'cat a\ b'), ['cat', 'a b']);
    });

    test('rejects unterminated quotes', () {
      expect(() => tokenize('cat "oops'), throwsA(isA<ConsoleUsageError>()));
    });
  });

  group('parseCommand', () {
    test('strips git prefix and parses options', () {
      final c = parseCommand('git log main -n 10 --stat -- lib/a.dart');
      expect(c.name, 'log');
      expect(c.positionals, ['main']);
      expect(c.intOpt('n', 20), 10);
      expect(c.flag('stat'), isTrue);
      expect(c.paths, ['lib/a.dart']);
    });

    test('supports -N, --max-count=N and aliases', () {
      expect(parseCommand('log -5').opt('n'), '5');
      expect(parseCommand('log --max-count=7').opt('n'), '7');
      expect(parseCommand('cat x -r dev').opt('ref'), 'dev');
    });

    test('valued option without value is an error', () {
      expect(() => parseCommand('log -n'), throwsA(isA<ConsoleUsageError>()));
    });

    test('non-numeric -n is an error', () {
      expect(() => parseCommand('log -n abc').intOpt('n', 1), throwsA(isA<ConsoleUsageError>()));
    });
  });
}
