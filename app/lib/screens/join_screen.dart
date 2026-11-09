import 'dart:async';

import 'package:flutter/material.dart';

import '../chat_controller.dart';

import 'chat_screen.dart';

class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key});

  /// How long to wait for the server before giving up. Generous, because a
  /// free hosted server may need a while to wake up.
  static const joinTimeout = Duration(seconds: 30);

  /// Set at build time with `--dart-define=SERVER_URL=wss://...`.
  static const defaultServer = String.fromEnvironment(
    'SERVER_URL',
    defaultValue: 'ws://localhost:8080',
  );

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  String? _nameError;
  String? _serverError;
  bool _joining = false;
  final _url = TextEditingController(text: JoinScreen.defaultServer);
  String _format = 'envelope';
  bool _wrongToken = false;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    if (_joining) return;
    setState(() {
      _nameError = null;
      _serverError = null;
    });
    if (!_form.currentState!.validate()) return;
    setState(() => _joining = true);

    // Connect and join here, so the chat screen only opens once the server
    // has accepted us.
    final chat = ChatController(
      url: _url.text.trim(),
      name: _name.text.trim(),
      format: _format,
      token: _wrongToken ? 'wrong-token' : ChatController.demoToken,
    );
    String? nameError;
    String? serverError;
    try {
      await chat.joined.timeout(JoinScreen.joinTimeout);
    } on ChatError catch (e) {
      if (e.code == ChatError.nameTaken) {
        nameError = 'That name is already in use. Try another.';
      } else {
        serverError = e.message;
      }
    } on TimeoutException {
      serverError =
          "Couldn't reach the server. Check the address and that "
          "it's running.";
    }

    if (!mounted || nameError != null || serverError != null) {
      chat.dispose();
      if (mounted) {
        setState(() {
          _joining = false;
          _nameError = nameError;
          _serverError = serverError;
        });
      }
      return;
    }

    setState(() => _joining = false);
    // ChatScreen owns the controller from here, and pops with a message if
    // the name is taken after a reconnect.
    final rejection = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => ChatScreen(controller: chat)),
    );
    if (!mounted || rejection == null) return;
    setState(() => _nameError = rejection);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.forum_rounded,
                    size: 56,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'easy_chat',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Live chat powered by easy_socket',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    key: const Key('name'),
                    controller: _name,
                    enabled: !_joining,
                    autofocus: true,
                    textInputAction: TextInputAction.go,
                    decoration: const InputDecoration(
                      labelText: 'Your name',
                      border: OutlineInputBorder(),
                    ),
                    maxLength: 24,
                    forceErrorText: _nameError,
                    onChanged: (_) {
                      if (_nameError != null) setState(() => _nameError = null);
                    },
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                    onFieldSubmitted: (_) => _join(),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: const Key('url'),
                    controller: _url,
                    enabled: !_joining,
                    forceErrorText: _serverError,
                    onChanged: (_) {
                      if (_serverError != null) {
                        setState(() => _serverError = null);
                      }
                    },
                    onFieldSubmitted: (_) => _join(),
                    decoration: const InputDecoration(
                      labelText: 'Server',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final uri = Uri.tryParse(v?.trim() ?? '');
                      return uri != null &&
                              (uri.scheme == 'ws' || uri.scheme == 'wss')
                          ? null
                          : 'Use a ws:// or wss:// address';
                    },
                  ),
                  const SizedBox(height: 16),
                  Text('Try easy_socket', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Text(
                    'Message format the server speaks',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: 'envelope',
                        label: Text('{type, payload}'),
                      ),
                      ButtonSegment(
                        value: 'event',
                        label: Text('{event, data}'),
                      ),
                      ButtonSegment(
                        value: 'array',
                        label: Text('[name, data]'),
                      ),
                    ],
                    selected: {_format},
                    onSelectionChanged: _joining
                        ? null
                        : (v) => setState(() => _format = v.single),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'easy_socket detects whichever one it receives. The app '
                    "code doesn't change.",
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  SwitchListTile(
                    key: const Key('wrongToken'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Send a wrong token'),
                    subtitle: const Text(
                      'See how a refused connection is handled',
                    ),
                    value: _wrongToken,
                    onChanged: _joining
                        ? null
                        : (v) => setState(() => _wrongToken = v),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _joining ? null : _join,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: _joining
                          ? const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                SizedBox(width: 12),
                                Text('Joining…'),
                              ],
                            )
                          : const Text('Join chat'),
                    ),
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
