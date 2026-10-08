import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/data/github/models/tree.dart';
import 'package:git_reviewer/features/files/tree_builder.dart';

GhTreeEntry _blob(String p) => GhTreeEntry(path: p, type: TreeEntryType.blob, sha: p, size: 1);
GhTreeEntry _dir(String p) => GhTreeEntry(path: p, type: TreeEntryType.tree, sha: p);

void main() {
  final entries = [
    _blob('README.md'),
    _dir('src'),
    _dir('src/main'),
    _dir('src/main/java'),
    _blob('src/main/java/App.java'),
    _blob('src/main/java/Util.java'),
    _dir('lib'),
    _blob('lib/b.dart'),
    _blob('lib/A.dart'),
  ];

  test('builds nested tree with dirs first, case-insensitive sort', () {
    final root = buildTree(entries);
    expect(root.children.map((n) => n.name), ['lib', 'src', 'README.md']);
    expect(root.children.first.children.map((n) => n.name), ['A.dart', 'b.dart']);
  });

  test('creates missing parent directories', () {
    final root = buildTree([_blob('x/y/z.txt')]);
    expect(root.children.single.path, 'x');
    expect(root.children.single.children.single.path, 'x/y');
  });

  test('flattenVisible compacts single-child dir chains', () {
    final root = buildTree(entries);
    final collapsed = flattenVisible(root, {});
    expect(collapsed.map((v) => v.label), ['lib', 'src/main/java', 'README.md']);

    final expanded = flattenVisible(root, {'src/main/java'});
    expect(expanded.map((v) => v.label), ['lib', 'src/main/java', 'App.java', 'Util.java', 'README.md']);
    expect(expanded[2].depth, 1);
  });

  test('searchFiles matches anywhere in path', () {
    final root = buildTree(entries);
    expect(searchFiles(root, 'java').map((n) => n.name), ['App.java', 'Util.java']);
    expect(searchFiles(root, 'MAIN/java/app').single.path, 'src/main/java/App.java');
  });
}
