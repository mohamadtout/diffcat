/// Knowing which folder (and so which git branch) the shell is in.
///
/// Shells can report their folder with OSC 7 (`ESC ] 7 ; file://host/path BEL`)
/// before each prompt. Some do it already; for bash, zsh and fish the app can
/// type [shellHookCommand] after login (opt-in) or the user can add
/// [shellHookSnippet] to their rc file. The git status itself is read on a
/// separate SSH channel ([gitStatusCommand]), so nothing else is typed into
/// the shell.
library;

/// Private OSC the hook prints once it's installed, so the app can hide the
/// typed command (see [EchoHider]).
const hookDoneMarker = '\x1b]6973;diffcat\x07';

const _osc7 = r'printf "\033]7;file://%s%s\007" "${HOSTNAME:-}" "$PWD"';
const _bashZsh =
    '__diffcat_osc7(){ $_osc7; }; '
    r'if [ -n "$ZSH_VERSION" ]; then precmd_functions+=(__diffcat_osc7); '
    r'else PROMPT_COMMAND="__diffcat_osc7${PROMPT_COMMAND:+;$PROMPT_COMMAND}"; fi';
const _fish = r'function __diffcat_osc7 --on-event fish_prompt; printf "\033]7;file://%s%s\007" (hostname) "$PWD"; end';

/// One line that works when typed into bash, zsh or fish: each shell only
/// runs its own part (the others are strings it never evaluates). The leading
/// space keeps it out of shell history where that's configured.
String shellHookCommand() =>
    " [ -n \"\$BASH_VERSION\$ZSH_VERSION\" ] && eval '$_bashZsh'; "
    "[ -n \"\$FISH_VERSION\" ] && eval '$_fish'; "
    r"printf '\033]6973;diffcat\007'";

/// For ~/.bashrc / ~/.zshrc ([fish] false) or ~/.config/fish/config.fish.
String shellHookSnippet({required bool fish}) => fish
    ? '# Diffcat: report the current folder (OSC 7)\n$_fish\n'
    : '# Diffcat: report the current folder (OSC 7)\n$_bashZsh\n';

/// The folder in an OSC 7 report (`file://host/path`, percent-encoded), or
/// null if it isn't one. [args] are the OSC parameters after the code.
String? parseOsc7(List<String> args) {
  final url = args.join(';');
  if (!url.startsWith('file://')) return null;
  final slash = url.indexOf('/', 'file://'.length);
  if (slash < 0) return null;
  final path = url.substring(slash);
  try {
    return Uri.decodeComponent(path);
  } on ArgumentError {
    return path; // a literal % in the folder name
  }
}

/// [path] quoted for a POSIX shell.
String shellQuote(String path) => "'${path.replaceAll("'", r"'\''")}'";

/// Status of the repo containing [cwd], on its own SSH channel. Optional
/// locks off, so it never fights the user's own git commands over the index
/// lock; untracked files skipped, which is slow in big repos.
String gitStatusCommand(String cwd) =>
    'cd -- ${shellQuote(cwd)} 2>/dev/null && '
    'GIT_OPTIONAL_LOCKS=0 git status --porcelain=v2 --branch --untracked-files=no 2>/dev/null | head -n 1000';

class GitStatus {
  const GitStatus({required this.branch, this.detached = false, this.ahead = 0, this.behind = 0, this.changes = 0});

  /// Branch name, or the short sha when [detached].
  final String branch;
  final bool detached;
  final int ahead;
  final int behind;

  /// Changed (staged or not) files, not counting untracked ones.
  final int changes;
}

/// Parses `git status --porcelain=v2 --branch`. Null when it isn't a repo
/// (empty output).
GitStatus? parseGitStatus(String out) {
  String? head;
  String? oid;
  var ahead = 0, behind = 0, changes = 0;
  for (final line in out.split('\n')) {
    if (line.startsWith('# branch.head ')) {
      head = line.substring('# branch.head '.length).trim();
    } else if (line.startsWith('# branch.oid ')) {
      oid = line.substring('# branch.oid '.length).trim();
    } else if (line.startsWith('# branch.ab ')) {
      final m = RegExp(r'\+(\d+) -(\d+)').firstMatch(line);
      if (m != null) {
        ahead = int.parse(m[1]!);
        behind = int.parse(m[2]!);
      }
    } else if (line.isNotEmpty && !line.startsWith('#')) {
      changes++;
    }
  }
  if (head == null) return null;
  final detached = head == '(detached)';
  return GitStatus(
    branch: detached ? (oid == null || oid.length < 7 ? 'detached' : oid.substring(0, 7)) : head,
    detached: detached,
    ahead: ahead,
    behind: behind,
    changes: changes,
  );
}

/// Hides the echo of a command the app typed into the shell, from where the
/// echo starts up to [hookDoneMarker], so the user only sees a fresh prompt.
///
/// Output before the echo passes through. If the echo or the marker doesn't
/// show up (another shell, a slow host), [flush] releases everything held
/// back: it fails open, never swallowing real output.
class EchoHider {
  EchoHider(String typed) : _start = typed.substring(0, typed.length < 24 ? typed.length : 24);

  final String _start;
  var _buffer = '';
  var _state = _State.waiting;

  bool get done => _state == _State.done;

  /// What to show of [chunk].
  String process(String chunk) {
    if (_state == _State.done) return chunk;
    _buffer += chunk;
    if (_state == _State.waiting) {
      final i = _buffer.indexOf(_start);
      if (i < 0) {
        // Show everything but a tail that could be the start of the echo.
        var keep = _start.length - 1;
        while (keep > 0 && !_buffer.endsWith(_start.substring(0, keep))) {
          keep--;
        }
        final out = _buffer.substring(0, _buffer.length - keep);
        _buffer = _buffer.substring(_buffer.length - keep);
        return out;
      }
      final before = _buffer.substring(0, i);
      _buffer = _buffer.substring(i);
      _state = _State.hiding;
      return before + process('');
    }
    final j = _buffer.indexOf(hookDoneMarker);
    if (j < 0) return '';
    final after = _buffer.substring(j + hookDoneMarker.length);
    _buffer = '';
    _state = _State.done;
    // The prompt the command was typed at is redrawn after it: clear its
    // line so the new prompt replaces it instead of appearing twice.
    return '\r\x1b[2K${after.replaceFirst(RegExp(r'^\r?\n'), '')}';
  }

  /// Gives up hiding and returns whatever was held back.
  String flush() {
    final out = _buffer;
    _buffer = '';
    _state = _State.done;
    return out;
  }
}

enum _State { waiting, hiding, done }
