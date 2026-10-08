import '../../data/github/models/tree.dart';

class TreeNode {
  TreeNode(this.name, this.path, {required this.isDir, this.size, this.isSubmodule = false});

  final String name;
  final String path;
  final bool isDir;
  final bool isSubmodule;
  final int? size;
  final List<TreeNode> children = [];
}

/// Builds a nested tree from GitHub's flat recursive tree listing.
/// Directories sort before files; names sort case-insensitively.
TreeNode buildTree(List<GhTreeEntry> entries) {
  final root = TreeNode('', '', isDir: true);
  final dirs = <String, TreeNode>{'': root};

  TreeNode dirFor(String path) {
    final existing = dirs[path];
    if (existing != null) return existing;
    final i = path.lastIndexOf('/');
    final parent = dirFor(i < 0 ? '' : path.substring(0, i));
    final node = TreeNode(path.substring(i + 1), path, isDir: true);
    parent.children.add(node);
    return dirs[path] = node;
  }

  for (final e in entries) {
    if (e.type == TreeEntryType.tree) {
      dirFor(e.path);
      continue;
    }
    final i = e.path.lastIndexOf('/');
    final parent = dirFor(i < 0 ? '' : e.path.substring(0, i));
    parent.children.add(
      TreeNode(
        e.path.substring(i + 1),
        e.path,
        isDir: false,
        size: e.size,
        isSubmodule: e.type == TreeEntryType.submodule,
      ),
    );
  }

  void sort(TreeNode n) {
    n.children.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    for (final c in n.children) {
      if (c.isDir) sort(c);
    }
  }

  sort(root);
  return root;
}

/// A row in the flattened, visible tree.
class VisibleNode {
  const VisibleNode(this.node, this.depth, this.label);

  /// For compacted chains (`src/main/java`) this is the deepest directory.
  final TreeNode node;
  final int depth;
  final String label;
}

/// Flattens [root] into visible rows given the set of [expanded] dir paths.
/// Chains of single-child directories are compacted into one row, like
/// GitHub's file browser.
List<VisibleNode> flattenVisible(TreeNode root, Set<String> expanded) {
  final out = <VisibleNode>[];
  void walk(TreeNode dir, int depth) {
    for (var node in dir.children) {
      var label = node.name;
      while (node.isDir && node.children.length == 1 && node.children.first.isDir) {
        node = node.children.first;
        label = '$label/${node.name}';
      }
      out.add(VisibleNode(node, depth, label));
      if (node.isDir && expanded.contains(node.path)) walk(node, depth + 1);
    }
  }

  walk(root, 0);
  return out;
}

/// All file paths containing [query] (case-insensitive), for search.
List<TreeNode> searchFiles(TreeNode root, String query) {
  final q = query.toLowerCase();
  final out = <TreeNode>[];
  void walk(TreeNode n) {
    for (final c in n.children) {
      if (c.isDir) {
        walk(c);
      } else if (c.path.toLowerCase().contains(q)) {
        out.add(c);
      }
    }
  }

  walk(root);
  return out;
}
