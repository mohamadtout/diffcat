import 'package:yaml/yaml.dart';

/// The kinds of `workflow_dispatch` input GitHub's "Run workflow" form has.
enum DispatchInputType { string, boolean, choice, number, environment }

/// One input of a manually started workflow (`on.workflow_dispatch.inputs`).
class DispatchInput {
  const DispatchInput({
    required this.name,
    this.description = '',
    this.required = false,
    this.type = DispatchInputType.string,
    this.defaultValue = '',
    this.options = const [],
  });

  final String name;
  final String description;
  final bool required;
  final DispatchInputType type;

  /// As a string: booleans are `true`/`false`. Empty when there's none.
  final String defaultValue;

  /// The choices of a `choice` input.
  final List<String> options;

  /// What the form starts with: the default, `false` for a boolean without
  /// one, and the first option of a choice without one (as GitHub's form does).
  String get initialValue => switch (type) {
    DispatchInputType.boolean => defaultValue == 'true' ? 'true' : 'false',
    DispatchInputType.choice when !options.contains(defaultValue) => options.firstOrNull ?? '',
    _ => defaultValue,
  };

  /// Why [value] can't be sent, or null when it can.
  String? validate(String value) {
    final v = value.trim();
    if (v.isEmpty) return required && type != DispatchInputType.boolean ? 'Required' : null;
    return switch (type) {
      DispatchInputType.number when num.tryParse(v) == null => 'Must be a number',
      DispatchInputType.choice when options.isNotEmpty && !options.contains(v) => 'Pick one of the options',
      _ => null,
    };
  }
}

/// A workflow's manual trigger. [inputs] is empty when it takes none.
class WorkflowDispatch {
  const WorkflowDispatch(this.inputs);

  final List<DispatchInput> inputs;

  /// The `inputs` to send: every boolean, and the other inputs that have a
  /// value (GitHub fills in the defaults of the ones left out).
  Map<String, String> payload(Map<String, String> values) => {
    for (final i in inputs)
      if (i.type == DispatchInputType.boolean)
        i.name: values[i.name] == 'true' ? 'true' : 'false'
      else if ((values[i.name] ?? '').trim().isNotEmpty)
        i.name: values[i.name]!.trim(),
  };

  /// Field name → problem, for every input whose value can't be sent.
  Map<String, String> errors(Map<String, String> values) => {
    for (final i in inputs) i.name: ?i.validate(values[i.name] ?? ''),
  };
}

/// Reads the manual trigger from a workflow file. Null when the workflow
/// can't be started by hand (no `workflow_dispatch` under `on`).
///
/// Throws [FormatException] when [source] isn't a valid workflow file.
WorkflowDispatch? parseWorkflowDispatch(String source) {
  final Object? doc;
  try {
    doc = loadYaml(source);
  } on YamlException catch (e) {
    throw FormatException('Invalid workflow file: ${e.message}');
  }
  if (doc is! Map) throw const FormatException('Invalid workflow file: not a mapping');
  // YAML 1.1 parsers read a bare `on` as true; this one is 1.2, but GitHub
  // accepts both spellings, so accept both.
  final on = doc['on'] ?? doc[true];
  final Object? trigger;
  switch (on) {
    case 'workflow_dispatch':
      trigger = null;
    case List<dynamic>() when on.contains('workflow_dispatch'):
      trigger = null;
    case Map<dynamic, dynamic>() when on.containsKey('workflow_dispatch'):
      trigger = on['workflow_dispatch'];
    default:
      return null;
  }
  final inputs = trigger is Map ? trigger['inputs'] : null;
  if (inputs is! Map) return const WorkflowDispatch([]);
  return WorkflowDispatch([
    for (final MapEntry(:key, :value) in inputs.entries) _input('$key', value is Map ? value : const {}),
  ]);
}

DispatchInput _input(String name, Map<dynamic, dynamic> j) {
  final type = DispatchInputType.values.asNameMap()['${j['type'] ?? 'string'}'] ?? DispatchInputType.string;
  final d = j['default'];
  return DispatchInput(
    name: name,
    description: '${j['description'] ?? ''}'.trim(),
    required: j['required'] == true || j['required'] == 'true',
    type: type,
    defaultValue: d == null ? '' : '$d',
    options: [for (final o in (j['options'] is List ? j['options'] as List<dynamic> : const [])) '$o'],
  );
}
