import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/routes.dart';

import 'auth_controller.dart';

/// Optional sign-in: paste a GitHub personal access token.
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
    setState(() {
      _busy = true;
      _error = null;
    });
    // Taken before signing in: the auth change refreshes the router, which
    // rebuilds this page, so this State may be gone by the time we navigate.
    final router = GoRouter.of(context);
    try {
      await ref.read(authTokenProvider.notifier).signIn(_ctrl.text);
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
                    'Paste a personal access token. It is stored in the device keystore and only sent to '
                    'api.github.com.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
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
