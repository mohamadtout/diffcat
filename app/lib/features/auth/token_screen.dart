import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/routing/routes.dart';
import '../../core/theme/app_theme.dart';
import 'auth_controller.dart';
import 'device_flow.dart';

/// Starts a GitHub device-flow sign-in, or null when the build's OAuth
/// client ID is empty (then only pasting a token is offered). Overridden in tests.
final deviceFlowProvider = Provider<DeviceFlow Function()?>(
  (ref) => githubClientId.isEmpty ? null : () => DeviceFlow(clientId: githubClientId),
);

/// Optional sign-in: "Sign in with GitHub" (device flow) when the build has
/// an OAuth client ID, or paste a personal access token.
class TokenScreen extends ConsumerStatefulWidget {
  const TokenScreen({super.key});

  @override
  ConsumerState<TokenScreen> createState() => _TokenScreenState();
}

class _TokenScreenState extends ConsumerState<TokenScreen> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_ctrl.text.trim().isEmpty) return;
    await _signIn(_ctrl.text);
  }

  Future<void> _withGitHub(DeviceFlow Function() flow) async {
    final token = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DeviceCodeDialog(flow: flow()),
    );
    if (token != null && mounted) await _signIn(token);
  }

  Future<void> _signIn(String token) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    // Taken before signing in: the auth change refreshes the router, which
    // rebuilds this page, so this State may be gone by the time we navigate.
    final router = GoRouter.of(context);
    try {
      await ref.read(authTokenProvider.notifier).signIn(token);
      // That refresh re-applies the current stack (it would undo an immediate
      // pop), so navigate once it's done. The router's /setup redirect only
      // covers a direct visit, not this screen pushed on top of another.
      await WidgetsBinding.instance.endOfFrame;
      _leaveWith(router);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _leave() => _leaveWith(GoRouter.of(context));

  static void _leaveWith(GoRouter router) => router.canPop() ? router.pop() : router.go(Routes.repos);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final deviceFlow = ref.watch(deviceFlowProvider);
    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: _leave)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.rate_review_outlined, size: 56, color: theme.colorScheme.primary),
                  const SizedBox(height: 16),
                  Text('Diffcat', textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Signing in is optional. It lets you list your repos, open private ones, and raises '
                    "GitHub's limit from 60 to 5,000 requests an hour.\n\n"
                    '${deviceFlow == null ? 'Paste a personal access token' : 'Sign in with GitHub or paste a personal access token'}. '
                    'The token is stored in the device keystore and only sent to GitHub.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  if (deviceFlow case final flow?) ...[
                    FilledButton.icon(
                      icon: const Icon(Icons.login),
                      label: const Text('Sign in with GitHub'),
                      onPressed: _busy ? null : () => _withGitHub(flow),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text('or paste a token', style: theme.textTheme.bodySmall),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    controller: _ctrl,
                    obscureText: _obscure,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: 'Personal access token',
                      hintText: 'github_pat_… or ghp_…',
                      border: const OutlineInputBorder(),
                      errorText: _error,
                      errorMaxLines: 3,
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Sign in'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(onPressed: _leave, child: const Text('Not now')),
                  const SizedBox(height: 24),
                  Text(
                    'Use a classic token with the "repo" scope. It works for every repo you can access, including '
                    'ones you collaborate on. Fine-grained tokens only reach one account or org. See SETUP.md.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows the one-time code to enter on github.com and waits for approval.
/// Pops with the token, or null when cancelled.
class DeviceCodeDialog extends StatefulWidget {
  const DeviceCodeDialog({super.key, required this.flow});

  final DeviceFlow flow;

  @override
  State<DeviceCodeDialog> createState() => _DeviceCodeDialogState();
}

class _DeviceCodeDialogState extends State<DeviceCodeDialog> {
  DeviceCode? _code;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    widget.flow.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    try {
      final code = await widget.flow.start();
      if (!mounted) return;
      setState(() => _code = code);
      final token = await widget.flow.waitForToken(code);
      if (mounted) Navigator.pop(context, token);
    } on DeviceFlowException catch (e) {
      if (mounted && e.message != 'Cancelled') setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = _code;
    return AlertDialog(
      title: const Text('Sign in with GitHub'),
      scrollable: true,
      content: _error != null
          ? Text(_error!, style: TextStyle(color: theme.colorScheme.error))
          : code == null
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Open GitHub and enter this code:'),
                const SizedBox(height: 12),
                SelectableText(
                  code.userCode,
                  style: theme.textTheme.headlineMedium?.copyWith(fontFamily: AppTheme.monoFamily, letterSpacing: 2),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Copy'),
                      onPressed: () => Clipboard.setData(ClipboardData(text: code.userCode)),
                    ),
                    FilledButton.icon(
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('Open GitHub'),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: code.userCode));
                        await launchUrl(Uri.parse(code.verificationUri), mode: LaunchMode.externalApplication);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 8),
                    Flexible(child: Text('Waiting for approval…', style: theme.textTheme.bodySmall)),
                  ],
                ),
              ],
            ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
    );
  }
}
