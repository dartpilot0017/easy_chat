import 'package:easy_socket/easy_socket.dart';
import 'package:flutter/material.dart';

import '../chat_controller.dart';

/// Buttons that make the connection misbehave on purpose, and a live log of
/// what easy_socket does about it.
class Playground extends StatelessWidget {
  const Playground({super.key, required this.chat});
  final ChatController chat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget action({
      required Key key,
      required IconData icon,
      required String label,
      required String hint,
      required VoidCallback? onPressed,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            key: key,
            onPressed: onPressed,
            icon: Icon(icon, size: 18),
            label: Text(label),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
            child: Text(hint, style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );

    return ListenableBuilder(
      listenable: chat,
      builder: (context, _) {
        final connected = chat.connection == SocketState.connected;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('Playground', style: theme.textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'Format: ${_formatLabel(chat.format)} · '
                'token sent with every connection',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  action(
                    key: const Key('drop'),
                    icon: Icons.link_off,
                    label: 'Drop my connection',
                    hint:
                        'The server hangs up. Watch it reconnect and rejoin '
                        'the room by itself.',
                    onPressed: connected ? chat.dropConnection : null,
                  ),
                  chat.offline
                      ? action(
                          key: const Key('online'),
                          icon: Icons.wifi,
                          label: 'Go online',
                          hint:
                              'Queued messages go out as soon as it connects.',
                          onPressed: chat.goOnline,
                        )
                      : action(
                          key: const Key('offline'),
                          icon: Icons.wifi_off,
                          label: 'Go offline',
                          hint:
                              'Then send a few messages: they wait in the queue '
                              'until you come back.',
                          onPressed: chat.goOffline,
                        ),
                  action(
                    key: const Key('kick'),
                    icon: Icons.block,
                    label: 'Get kicked',
                    hint:
                        'The server closes with code 1008 ("not allowed"), so '
                        'the socket stops instead of retrying.',
                    onPressed: connected ? chat.getKicked : null,
                  ),
                ],
              ),
            ),
            const Divider(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Socket log',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  TextButton(
                    onPressed: chat.clearLog,
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),
            Expanded(child: _Log(entries: chat.log)),
          ],
        );
      },
    );
  }

  static String _formatLabel(String format) => switch (format) {
    'event' => '{event, data}',
    'array' => '[name, data]',
    _ => '{type, payload}',
  };
}

class _Log extends StatelessWidget {
  const _Log({required this.entries});
  final List<LogEntry> entries;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Color colorOf(String kind) => switch (kind) {
      'out' => scheme.primary,
      'in' => Colors.teal,
      'state' => Colors.orange,
      'error' => scheme.error,
      _ => scheme.onSurfaceVariant,
    };
    if (entries.isEmpty) {
      return const Center(child: Text('Nothing yet.'));
    }
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final entry = entries[entries.length - 1 - i];
        final t = entry.time;
        final time =
            '${t.hour.toString().padLeft(2, '0')}:'
            '${t.minute.toString().padLeft(2, '0')}:'
            '${t.second.toString().padLeft(2, '0')}';
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: SelectableText.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$time  ',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                TextSpan(
                  text: entry.text,
                  style: TextStyle(color: colorOf(entry.kind)),
                ),
              ],
            ),
            maxLines: 4,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        );
      },
    );
  }
}
