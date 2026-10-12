import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/async_view.dart';
import '../../data/github/models/models.dart';
import '../auth/auth_controller.dart';
import '../repo/ref_picker.dart';
import 'actions_providers.dart';
import 'run_screen.dart';
import 'workflow_dispatch.dart';

/// GitHub's "Run workflow" form: pick a workflow and a branch, fill in the
/// workflow's inputs. Returns the workflow once GitHub accepted it.
Future<GhWorkflow?> showRunWorkflowSheet(
  BuildContext context, {
  required RepoRef repo,
  required String gitRef,
  required List<GhWorkflow> workflows,
  int? initialWorkflowId,
}) => showModalBottomSheet<GhWorkflow>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) =>
      RunWorkflowSheet(repo: repo, gitRef: gitRef, workflows: workflows, initialWorkflowId: initialWorkflowId),
);

class RunWorkflowSheet extends ConsumerStatefulWidget {
  const RunWorkflowSheet({
    super.key,
    required this.repo,
    required this.gitRef,
    required this.workflows,
    this.initialWorkflowId,
  });

  final RepoRef repo;
  final String gitRef;
  final List<GhWorkflow> workflows;
  final int? initialWorkflowId;

  @override
  ConsumerState<RunWorkflowSheet> createState() => _RunWorkflowSheetState();
}

class _RunWorkflowSheetState extends ConsumerState<RunWorkflowSheet> {
  /// Only workflows with a file can have a `workflow_dispatch` trigger.
  late final _choices = widget.workflows.where((w) => w.hasFile && w.isActive).toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  late GhWorkflow? _workflow =
      _choices.where((w) => w.id == widget.initialWorkflowId).firstOrNull ?? _choices.firstOrNull;
  late String _ref = widget.gitRef;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final w = _workflow;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Run workflow', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: w?.id,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Workflow', border: OutlineInputBorder()),
                items: [
                  for (final c in _choices)
                    DropdownMenuItem(
                      value: c.id,
                      child: Text(c.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (id) => setState(() => _workflow = _choices.firstWhere((c) => c.id == id)),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text('Run on', style: theme.textTheme.bodyMedium),
                  const SizedBox(width: 8),
                  Flexible(
                    child: RefPickerButton(
                      repo: widget.repo,
                      current: _ref,
                      onSelected: (r) => setState(() => _ref = r),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (w != null)
                AsyncView(
                  value: ref.watch(workflowDispatchProvider((repo: widget.repo, path: w.path, ref: _ref))),
                  onRetry: () => ref.invalidate(workflowDispatchProvider((repo: widget.repo, path: w.path, ref: _ref))),
                  error: (e) => _Note(
                    e is FormatException
                        ? "Couldn't read ${w.path} on $_ref. ${e.message}"
                        : "Couldn't load ${w.path} on $_ref: ${actionError(e)}",
                  ),
                  data: (dispatch) => dispatch == null
                      ? _Note(
                          "${w.name} can't be started by hand on $_ref: its file there has no "
                          'workflow_dispatch trigger.',
                        )
                      : _DispatchForm(
                          // A fresh form (and its defaults) per workflow and branch.
                          key: ValueKey('${w.id}@$_ref'),
                          repo: widget.repo,
                          workflow: w,
                          gitRef: _ref,
                          dispatch: dispatch,
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
  );
}

class _DispatchForm extends ConsumerStatefulWidget {
  const _DispatchForm({
    super.key,
    required this.repo,
    required this.workflow,
    required this.gitRef,
    required this.dispatch,
  });

  final RepoRef repo;
  final GhWorkflow workflow;
  final String gitRef;
  final WorkflowDispatch dispatch;

  @override
  ConsumerState<_DispatchForm> createState() => _DispatchFormState();
}

class _DispatchFormState extends ConsumerState<_DispatchForm> {
  late final _values = {for (final i in widget.dispatch.inputs) i.name: i.initialValue};
  late final _controllers = {
    for (final i in widget.dispatch.inputs)
      if (_isText(i)) i.name: TextEditingController(text: i.initialValue),
  };
  var _errors = <String, String>{};
  var _busy = false;
  String? _error;

  static bool _isText(DispatchInput i) => i.type != DispatchInputType.boolean && i.type != DispatchInputType.choice;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run() async {
    final errors = widget.dispatch.errors(_values);
    setState(() {
      _errors = errors;
      _error = null;
    });
    if (errors.isNotEmpty) return;
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    try {
      await ref
          .read(githubApiProvider)
          .dispatchWorkflow(
            widget.repo,
            widget.workflow.id,
            ref: widget.gitRef,
            inputs: widget.dispatch.payload(_values),
          );
      navigator.pop(widget.workflow);
    } on Object catch (e) {
      if (mounted) setState(() => _error = actionError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(DispatchInput i) {
    final label = i.required ? '${i.name} *' : i.name;
    final help = i.description.isEmpty ? null : i.description;
    return switch (i.type) {
      DispatchInputType.boolean => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(i.name),
        subtitle: help == null ? null : Text(help),
        value: _values[i.name] == 'true',
        onChanged: (v) => setState(() => _values[i.name] = '$v'),
      ),
      DispatchInputType.choice => DropdownButtonFormField<String>(
        initialValue: i.options.contains(_values[i.name]) ? _values[i.name] : null,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          helperText: help,
          helperMaxLines: 3,
          errorText: _errors[i.name],
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final o in i.options)
            DropdownMenuItem(
              value: o,
              child: Text(o, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) => setState(() => _values[i.name] = v ?? ''),
      ),
      _ => TextField(
        controller: _controllers[i.name],
        keyboardType: i.type == DispatchInputType.number
            ? const TextInputType.numberWithOptions(decimal: true, signed: true)
            : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          helperText: i.type == DispatchInputType.environment ? help ?? 'Environment name' : help,
          helperMaxLines: 3,
          errorText: _errors[i.name],
          border: const OutlineInputBorder(),
        ),
        onChanged: (v) => _values[i.name] = v,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final i in widget.dispatch.inputs) Padding(padding: const EdgeInsets.only(top: 12), child: _field(i)),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ),
        const SizedBox(height: 16),
        FilledButton.icon(
          icon: _busy
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.play_arrow),
          label: const Text('Run workflow'),
          onPressed: _busy ? null : _run,
        ),
      ],
    );
  }
}
