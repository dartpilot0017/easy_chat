import 'dart:async';
import 'dart:io';

import 'package:easy_socket/easy_socket.dart';

/// A chat bot built on easy_socket, so you have someone to talk to.
///
/// `dart run bin/bot.dart [url] [room]`
void main(List<String> args) {
  final url = args.isNotEmpty ? args[0] : 'ws://localhost:8080';
  final room = args.length > 1 ? args[1] : 'general';
  const name = 'EchoBot';

  final socket = EasySocket(url);

  // Re-join on every (re)connection; the server forgets us when we drop.
  socket.on(
    'welcome',
    (_) => socket.emit('join', {'name': name, 'room': room}),
  );
  socket.on('joined', (_) => print('$name joined #$room on $url'));
  socket.on('error', (data) {
    final error = data as Map<String, dynamic>;
    print('server: ${error['message']}');
    if (error['code'] == 'name_taken') {
      print('Another $name is already running. Exiting.');
      socket.dispose().then((_) => exit(1));
    }
  });
  socket.onStateChange.listen((s) => print('connection: ${s.name}'));

  socket.on('message', (data) {
    final msg = data as Map<String, dynamic>;
    if (msg['name'] == name) return;
    socket.emit('typing', {'isTyping': true});
    Timer(const Duration(milliseconds: 900), () {
      socket.emit('message', {
        'name': name,
        'room': room,
        'text': '${msg['name']} said: "${msg['text']}"',
      });
    });
  });
}
