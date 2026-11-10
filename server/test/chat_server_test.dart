import 'dart:async';

import 'package:easy_socket/easy_socket.dart';
import 'package:server/chat_server.dart';
import 'package:test/test.dart';

void main() {
  late ChatServer server;
  final sockets = <EasySocket>[];

  EasySocket client() {
    final s = EasySocket('ws://localhost:${server.port}');
    sockets.add(s);
    return s;
  }

  Future<Object?> next(
    EasySocket s,
    String event, [
    bool Function(Map<String, dynamic> data)? where,
  ]) {
    final c = Completer<Object?>();
    late final void Function() stop;
    stop = s.on(event, (data) {
      if (where != null && !where(data as Map<String, dynamic>)) return;
      stop();
      if (!c.isCompleted) c.complete(data);
    });
    return c.future.timeout(const Duration(seconds: 3));
  }

  setUp(() async {
    server = ChatServer();
    await server.start(port: 0);
  });

  tearDown(() async {
    for (final s in sockets) {
      await s.dispose();
    }
    sockets.clear();
    await server.stop();
  });

  test('welcome lists rooms', () async {
    final data = await next(client(), 'welcome') as Map;
    expect(data['rooms'], ChatServer.rooms);
  });

  test('two users chat and see presence', () async {
    final ada = client();
    final bob = client();
    final adaJoined = next(ada, 'joined');
    ada.emit('join', {'name': 'Ada', 'room': 'general'});
    await adaJoined;

    final adaPresence = next(
      ada,
      'presence',
      (d) => (d['users'] as List).length == 2,
    );
    final bobJoined = next(bob, 'joined');
    bob.emit('join', {'name': 'Bob', 'room': 'general'});
    expect((await bobJoined as Map)['users'], ['Ada', 'Bob']);
    expect((await adaPresence as Map)['users'], ['Ada', 'Bob']);

    final adaGets = next(ada, 'message');
    bob.emit('message', {'name': 'Bob', 'room': 'general', 'text': 'hi'});
    final msg = await adaGets as Map;
    expect(msg['name'], 'Bob');
    expect(msg['text'], 'hi');
  });

  test('typing is sent to others only', () async {
    final ada = client();
    final bob = client();
    for (final (s, n) in [(ada, 'Ada'), (bob, 'Bob')]) {
      final joined = next(s, 'joined');
      s.emit('join', {'name': n, 'room': 'random'});
      await joined;
    }
    var bobSawOwnTyping = false;
    bob.on('typing', (_) => bobSawOwnTyping = true);
    final adaSees = next(ada, 'typing');
    bob.emit('typing', {'isTyping': true});
    expect(await adaSees, {'room': 'random', 'name': 'Bob', 'isTyping': true});
    expect(bobSawOwnTyping, isFalse);
  });

  test('history is sent on join', () async {
    final ada = client();
    final sent = next(ada, 'message');
    ada.emit('message', {'name': 'Ada', 'room': 'flutter', 'text': 'first'});
    await sent;

    final bob = client();
    final joined = next(bob, 'joined');
    bob.emit('join', {'name': 'Bob', 'room': 'flutter'});
    final history = (await joined as Map)['history'] as List;
    expect(history.single['text'], 'first');
  });

  test('message sent before joining joins implicitly', () async {
    final ada = client();
    final joined = next(ada, 'joined');
    final got = next(ada, 'message');
    ada.emit('message', {'name': 'Ada', 'room': 'general', 'text': 'early'});
    expect((await joined as Map)['room'], 'general');
    expect((await got as Map)['text'], 'early');
  });

  test('rejects a name that is already in use', () async {
    final ada = client();
    final joined = next(ada, 'joined');
    ada.emit('join', {'name': 'Ada', 'room': 'general'});
    await joined;

    final copy = client();
    final error = next(copy, 'error');
    copy.emit('join', {'name': 'ada', 'room': 'random'});
    expect((await error as Map)['code'], 'name_taken');

    // The name is free again once Ada leaves.
    await ada.close();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final copyJoined = next(copy, 'joined');
    copy.emit('join', {'name': 'Ada', 'room': 'random'});
    expect((await copyJoined as Map)['users'], ['Ada']);
  });

  test('rejects unknown rooms', () async {
    final ada = client();
    final error = next(ada, 'error');
    ada.emit('join', {'name': 'Ada', 'room': 'nope'});
    expect((await error as Map)['message'], contains('Unknown room'));
  });

  group('demo features', () {
    EasySocket withQuery(Map<String, String> query, {ChatServer? on}) {
      final s = EasySocket(
        'ws://localhost:${(on ?? server).port}',
        queryParameters: () => query,
        minReconnectDelay: const Duration(milliseconds: 10),
      );
      sockets.add(s);
      return s;
    }

    for (final format in ['envelope', 'event', 'array']) {
      test('chats in the $format format', () async {
        final s = withQuery({'format': format});
        final raw = <Object?>[];
        s.onAny((e) => raw.add(e.raw));
        s.emit('join', {'name': 'Ada', 'room': 'general'});
        await next(s, 'joined');
        s.emit('message', {'name': 'Ada', 'room': 'general', 'text': 'hi'});
        final message = await next(s, 'message') as Map;
        expect(message['text'], 'hi');
        final first = raw.first as String;
        expect(first, switch (format) {
          'event' => startsWith('{"event":"welcome"'),
          'array' => startsWith('["welcome"'),
          _ => startsWith('{"type":"welcome"'),
        });
      });
    }

    test('a wrong token is rejected with 4401 and not retried', () async {
      final guarded = ChatServer(token: 'demo');
      await guarded.start(port: 0);
      addTearDown(guarded.stop);
      final errors = <Object>[];
      final s = withQuery({'token': 'nope'}, on: guarded)..onError(errors.add);
      s.connect().ignore();
      await s.onStateChange
          .firstWhere((x) => x == SocketState.closed)
          .timeout(const Duration(seconds: 3));
      // easy_socket 0.1.0 reports the error just after the state change.
      await Future<void>.delayed(Duration.zero);
      expect((errors.single as SocketRejectedException).code, 4401);

      final ok = withQuery({'token': 'demo'}, on: guarded);
      ok.emit('join', {'name': 'Ada', 'room': 'general'});
      await next(ok, 'joined');
    });

    test('ping is answered with pong', () async {
      final s = client();
      s.emit('ping');
      await next(s, 'pong');
    });

    test('drop closes the connection and the client comes back', () async {
      final s = client();
      await s.connect();
      s.emit('drop');
      await s.onStateChange
          .firstWhere((x) => x == SocketState.connected)
          .timeout(const Duration(seconds: 3));
      expect(s.closeCode, 1001);
    });

    test('kick closes with 1008 and the client stays closed', () async {
      final errors = <Object>[];
      final s = client()..onError(errors.add);
      await s.connect();
      s.emit('kick');
      await s.onStateChange
          .firstWhere((x) => x == SocketState.closed)
          .timeout(const Duration(seconds: 3));
      // easy_socket 0.1.0 reports the error just after the state change.
      await Future<void>.delayed(Duration.zero);
      expect((errors.single as SocketRejectedException).code, 1008);
    });
  });

  group('sessions', () {
    test(
      'the same session reclaims its name from a stale connection',
      () async {
        final old = client();
        old.emit('join', {'name': 'Ada', 'room': 'general', 'sessionId': 's1'});
        await next(old, 'joined');

        // The old connection is still open, as it would be behind a proxy.
        final fresh = client();
        fresh.emit('join', {
          'name': 'Ada',
          'room': 'general',
          'sessionId': 's1',
        });
        final joined = await next(fresh, 'joined') as Map;
        expect(joined['users'], ['Ada']);

        await old.onStateChange
            .firstWhere((x) => x != SocketState.connected)
            .timeout(const Duration(seconds: 3));
        expect(old.closeCode, 1000);
      },
    );

    test('a different session still gets name_taken', () async {
      final ada = client();
      ada.emit('join', {'name': 'Ada', 'room': 'general', 'sessionId': 's1'});
      await next(ada, 'joined');

      final other = client();
      other.emit('join', {'name': 'ada', 'room': 'general', 'sessionId': 's2'});
      final error = await next(other, 'error') as Map;
      expect(error['code'], 'name_taken');
      expect(ada.isConnected, isTrue);
    });

    test('queued messages from a reclaimed session are delivered', () async {
      final watcher = client();
      watcher.emit('join', {'name': 'Bob', 'room': 'general'});
      await next(watcher, 'joined');
      final old = client();
      old.emit('join', {'name': 'Ada', 'room': 'general', 'sessionId': 's1'});
      await next(old, 'joined');

      final fresh = client();
      fresh.emit('message', {
        'name': 'Ada',
        'room': 'general',
        'sessionId': 's1',
        'text': 'sent while offline',
      });
      final message = await next(watcher, 'message') as Map;
      expect(message['text'], 'sent while offline');
    });
  });
}
