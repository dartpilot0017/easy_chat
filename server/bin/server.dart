import 'dart:io';

import 'package:server/chat_server.dart';

/// Starts the chat server: `dart run bin/server.dart [port]`.
///
/// Hosting platforms set `PORT`; there it listens on all interfaces. Set
/// `CHAT_TOKEN` to require that token from clients.
Future<void> main(List<String> args) async {
  final env = Platform.environment;
  final hosted = env['PORT'] != null;
  final port = int.parse(
    env['PORT'] ?? (args.isNotEmpty ? args.first : '8080'),
  );
  final server = ChatServer(token: env['CHAT_TOKEN']);
  try {
    await server.start(
      port: port,
      log: !hosted,
      address: hosted ? InternetAddress.anyIPv4 : null,
    );
  } on SocketException catch (e) {
    if (e.osError?.errorCode != 48 && e.osError?.errorCode != 98) rethrow;
    stderr
      ..writeln(
        'Port $port is already in use; another server is probably running.',
      )
      ..writeln('Stop it, or pick another port: dart run bin/server.dart 8081');
    exit(1);
  }
  print('easy_chat server on ws://localhost:${server.port}');
  for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    signal.watch().first.then((_) async {
      await server.stop();
      exit(0);
    });
  }
}
