import 'dart:async';

import 'package:easy_socket/easy_socket.dart';
import 'package:flutter/material.dart';

import '../chat_controller.dart';
import '../chat_message.dart';
import 'playground.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.controller});

  /// An already-joined controller. The screen takes ownership and disposes it.
  final ChatController controller;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  ChatController get chat => widget.controller;
  late final StreamSubscription<ChatError> _errorSub;
  bool _leaving = false;
  final _input = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _errorSub = chat.errors.listen((error) {
      if (!mounted || _leaving) return;
      if (error.code == ChatError.nameTaken) {
        // Only after a reconnect: someone took the name while we were away.
        // Back to the join screen, which shows this under the name field.
        _leaving = true;
        Navigator.of(context).pop('That name is already in use. Try another.');
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.message)));
    });
  }

  @override
  void dispose() {
    _errorSub.cancel();
    chat.dispose();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send() {
    chat.send(_input.text);
    _input.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: chat,
      builder: (context, _) {
        final width = MediaQuery.sizeOf(context).width;
        final wide = width >= 720;
        final playgroundBeside = width >= 1100;
        final sidebar = _Sidebar(
          chat: chat,
          onPicked: wide ? null : () => Navigator.pop(context),
        );
        return Scaffold(
          appBar: AppBar(
            title: Text('# ${chat.room}'),
            actions: [
              _ConnectionChip(state: chat.connection),
              if (!playgroundBeside)
                Builder(
                  builder: (context) => IconButton(
                    key: const Key('openPlayground'),
                    tooltip: 'Playground',
                    icon: const Icon(Icons.science_outlined),
                    onPressed: () => Scaffold.of(context).openEndDrawer(),
                  ),
                ),
              IconButton(
                tooltip: 'Leave',
                icon: const Icon(Icons.logout),
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 8),
            ],
          ),
          drawer: wide ? null : Drawer(child: SafeArea(child: sidebar)),
          endDrawer: playgroundBeside
              ? null
              : Drawer(
                  width: 340,
                  child: SafeArea(child: Playground(chat: chat)),
                ),
          body: Row(
            children: [
              if (wide) ...[
                SizedBox(width: 240, child: sidebar),
                const VerticalDivider(width: 1),
              ],
              Expanded(
                child: Column(
                  children: [
                    if (chat.rejection case final rejected?)
                      _Banner(
                        icon: Icons.block,
                        text:
                            'The server refused the connection (code '
                            '${rejected.code}${rejected.reason?.isNotEmpty == true ? ': ${rejected.reason}' : ''}). '
                            'easy_socket stopped retrying.',
                        action: 'Reconnect',
                        onAction: chat.goOnline,
                      )
                    else if (chat.offline)
                      _Banner(
                        icon: Icons.wifi_off,
                        text:
                            "You're offline. Messages you send wait in "
                            'the queue.',
                        action: 'Go online',
                        onAction: chat.goOnline,
                      )
                    else if (chat.connection != SocketState.connected)
                      const _Banner(
                        icon: Icons.sync,
                        text:
                            'Connection lost. Reconnecting… Messages you '
                            'send will go out when it’s back.',
                      ),
                    Expanded(
                      child: _MessageList(
                        messages: chat.messages,
                        me: chat.name,
                      ),
                    ),
                    _TypingLine(names: chat.typing),
                    _Composer(
                      controller: _input,
                      focusNode: _focus,
                      onChanged: chat.onTextChanged,
                      onSend: _send,
                    ),
                  ],
                ),
              ),
              if (playgroundBeside) ...[
                const VerticalDivider(width: 1),
                SizedBox(width: 340, child: Playground(chat: chat)),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.chat, this.onPicked});
  final ChatController chat;
  final VoidCallback? onPicked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget header(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 1,
        ),
      ),
    );

    return ListView(
      children: [
        header('ROOMS'),
        for (final room in chat.rooms)
          ListTile(
            dense: true,
            leading: const Icon(Icons.tag, size: 18),
            title: Text(room),
            selected: room == chat.room,
            onTap: () {
              chat.switchRoom(room);
              onPicked?.call();
            },
          ),
        header('ONLINE — ${chat.users.length}'),
        for (final user in chat.users)
          ListTile(
            dense: true,
            leading: _Avatar(name: user, radius: 12),
            title: Text(user == chat.name ? '$user (you)' : user),
          ),
      ],
    );
  }
}

class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip({required this.state});
  final SocketState state;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      SocketState.connected => ('Live', Colors.green),
      SocketState.idle ||
      SocketState.connecting => ('Connecting', Colors.amber),
      SocketState.reconnecting => ('Reconnecting', Colors.orange),
      SocketState.closed => ('Offline', Colors.red),
    };
    return Chip(
      avatar: Icon(Icons.circle, size: 10, color: color),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.text,
    this.action,
    this.onAction,
  });
  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 18, color: scheme.onTertiaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: scheme.onTertiaryContainer),
              ),
            ),
            if (action != null)
              TextButton(onPressed: onAction, child: Text(action!)),
          ],
        ),
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({required this.messages, required this.me});
  final List<ChatMessage> messages;
  final String me;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return Center(
        child: Text(
          'No messages yet. Say hi!',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: messages.length,
      itemBuilder: (context, i) {
        final index = messages.length - 1 - i;
        final message = messages[index];
        final previous = index > 0 ? messages[index - 1] : null;
        return _Bubble(
          message: message,
          mine: message.name == me,
          showName: previous?.name != message.name,
        );
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.mine,
    required this.showName,
  });

  final ChatMessage message;
  final bool mine;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final time =
        '${message.sentAt.hour.toString().padLeft(2, '0')}:'
        '${message.sentAt.minute.toString().padLeft(2, '0')}';

    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 480),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: mine ? scheme.primary : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        message.text,
        style: TextStyle(color: mine ? scheme.onPrimary : scheme.onSurface),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(top: showName ? 12 : 3),
      child: Row(
        mainAxisAlignment: mine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!mine) ...[
            showName ? _Avatar(name: message.name) : const SizedBox(width: 32),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: mine
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (showName && !mine)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 2),
                    child: Text(
                      message.name,
                      style: theme.textTheme.labelMedium,
                    ),
                  ),
                Opacity(opacity: message.pending ? 0.55 : 1, child: bubble),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
                  child: Text(
                    message.pending ? 'sending…' : time,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.radius = 16});
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final hue = (name.codeUnits.fold(0, (a, b) => a * 31 + b) % 360).toDouble();
    return CircleAvatar(
      radius: radius,
      backgroundColor: HSLColor.fromAHSL(1, hue, 0.55, 0.55).toColor(),
      child: Text(
        name.isEmpty ? '?' : name[0].toUpperCase(),
        style: TextStyle(
          color: Colors.white,
          fontSize: radius * 0.9,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _TypingLine extends StatelessWidget {
  const _TypingLine({required this.names});
  final Set<String> names;

  @override
  Widget build(BuildContext context) {
    final list = names.toList()..sort();
    final text = switch (list.length) {
      0 => '',
      1 => '${list[0]} is typing…',
      2 => '${list[0]} and ${list[1]} are typing…',
      _ => 'Several people are typing…',
    };
    return Container(
      height: 22,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontStyle: FontStyle.italic,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('composer'),
                controller: controller,
                focusNode: focusNode,
                autofocus: true,
                onChanged: onChanged,
                onSubmitted: (_) => onSend(),
                textInputAction: TextInputAction.send,
                decoration: InputDecoration(
                  hintText: 'Message',
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Send',
              onPressed: onSend,
              icon: const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
