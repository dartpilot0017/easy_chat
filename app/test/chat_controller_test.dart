import 'dart:async';

import 'package:easy_chat/chat_controller.dart';
import 'package:easy_socket/easy_socket.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:server/chat_server.dart';

/// Runs the real controller against the real server over real websockets.
void main() {
  late ChatServer server;
  final controllers = <ChatController>[];

  ChatController connect(String name) {
    final c = ChatController(url: 'ws://localhost:${server.port}', name: name);
    controllers.add(c);
    return c;
  }

  Future<void> until(ChatController c, bool Function() condition) async {
    if (condition()) return;
    final done = Completer<void>();
    void check() {
      if (condition() && !done.isCompleted) done.complete();
    }

    c.addListener(check);
    try {
      await done.future.timeout(const Duration(seconds: 5));
    } finally {
      c.removeListener(check);
    }
  }

  setUp(() async {
    server = ChatServer();
    await server.start(port: 0);
  });

  tearDown(() async {
    for (final c in controllers) {
      c.dispose();
    }
    controllers.clear();
    await server.stop();
  });

  test('joins, chats and confirms pending messages', () async {
    final ada = connect('Ada');
    final bob = connect('Bob');
    await until(ada, () => ada.users.length == 2);

    bob.send('hello Ada');
    expect(bob.messages.single.pending, isTrue);

    await until(ada, () => ada.messages.isNotEmpty);
    expect(ada.messages.single.text, 'hello Ada');
    expect(ada.messages.single.name, 'Bob');

    await until(bob, () => !bob.messages.single.pending);
    expect(bob.messages, hasLength(1), reason: 'echo replaces the pending one');
  });

  test('typing indicator reaches others', () async {
    final ada = connect('Ada');
    final bob = connect('Bob');
    await until(ada, () => ada.users.length == 2);

    bob.onTextChanged('h');
    await until(ada, () => ada.typing.contains('Bob'));
    bob.send('hi');
    await until(ada, () => ada.typing.isEmpty);
  });

  test('switching rooms loads that room only', () async {
    final ada = connect('Ada');
    await until(ada, () => ada.connection == SocketState.connected);
    ada.send('in general');
    await until(ada, () => ada.messages.every((m) => !m.pending));

    ada.switchRoom('flutter');
    await until(ada, () => ada.users.contains('Ada'));
    expect(ada.room, 'flutter');
    expect(ada.messages, isEmpty);

    ada.switchRoom('general');
    await until(ada, () => ada.messages.isNotEmpty);
    expect(ada.messages.single.text, 'in general');
  });

  test('messages sent while offline are delivered after reconnect', () async {
    final ada = connect('Ada');
    await until(ada, () => ada.connection == SocketState.connected);
    final port = server.port;

    await server.stop();
    await until(ada, () => ada.connection == SocketState.reconnecting);
    ada.send('sent while offline');
    expect(ada.messages.last.pending, isTrue);

    server = ChatServer();
    await server.start(port: port);
    await until(
      ada,
      () =>
          ada.messages.any((m) => m.text == 'sent while offline' && !m.pending),
    );
  });

  group('playground', () {
    test('a wrong token is refused and joined fails', () async {
      final guarded = ChatServer(token: ChatController.demoToken);
      await guarded.start(port: 0);
      addTearDown(guarded.stop);
      final c = ChatController(
        url: 'ws://localhost:${guarded.port}',
        name: 'Ada',
        token: 'wrong',
      );
      controllers.add(c);
      await expectLater(
        c.joined,
        throwsA(
          isA<ChatError>().having((e) => e.code, 'code', ChatError.rejected),
        ),
      );
      expect(c.rejection?.code, 4401);
    });

    test('works the same in every server format', () async {
      for (final format in ['envelope', 'event', 'array']) {
        final c = ChatController(
          url: 'ws://localhost:${server.port}',
          name: 'Ada-$format',
          format: format,
        );
        controllers.add(c);
        await c.joined;
        c.send('hello in $format');
        await until(c, () => c.messages.any((m) => !m.pending));
      }
    });

    test('go offline, send, go online delivers the queued message', () async {
      final ada = connect('Ada');
      await ada.joined;
      ada.goOffline();
      await until(ada, () => ada.connection == SocketState.closed);
      ada.send('queued while offline');
      expect(ada.messages.last.pending, isTrue);
      ada.goOnline();
      await until(
        ada,
        () => ada.messages.any(
          (m) => m.text == 'queued while offline' && !m.pending,
        ),
      );
    });

    test('drop reconnects and stays in the room', () async {
      final ada = connect('Ada');
      await ada.joined;
      ada.dropConnection();
      await until(ada, () => ada.connection == SocketState.reconnecting);
      await until(ada, () => ada.connection == SocketState.connected);
      await until(ada, () => ada.users.contains('Ada'));
      expect(ada.rejection, isNull);
    });

    test('kick is refused without retrying, Reconnect recovers', () async {
      final ada = connect('Ada');
      await ada.joined;
      ada.getKicked();
      await until(ada, () => ada.rejection != null);
      expect(ada.rejection!.code, 1008);
      expect(ada.connection, SocketState.closed);
      ada.goOnline();
      await until(ada, () => ada.connection == SocketState.connected);
      expect(ada.rejection, isNull);
      expect(ada.log.any((e) => e.text.contains('token=***')), isTrue);
    });
  });
}
