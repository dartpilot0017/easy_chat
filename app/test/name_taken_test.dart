import 'dart:async';

import 'package:easy_chat/main.dart';
import 'package:easy_chat/screens/join_screen.dart';
import 'package:easy_socket/easy_socket.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:server/chat_server.dart';

/// The join flow against a real server: the app waits for the server's
/// answer on the join screen before opening the chat.
void main() {
  late ChatServer server;
  late EasySocket ada;

  // Real network work has to run outside the test's fake clock.
  Future<void> startServerWithAda(WidgetTester tester) =>
      tester.runAsync(() async {
        server = ChatServer();
        await server.start(port: 0);
        ada = EasySocket('ws://localhost:${server.port}');
        final joined = Completer<void>();
        ada.once('joined', (_) => joined.complete());
        ada.emit('join', {'name': 'Ada', 'room': 'general'});
        await joined.future;
      });

  Future<void> stopServer(WidgetTester tester) => tester.runAsync(() async {
    await ada.dispose();
    await server.stop();
  });

  Future<void> join(WidgetTester tester, String name, String url) async {
    await tester.pumpWidget(const EasyChatApp());
    await tester.enterText(find.byKey(const Key('name')), name);
    await tester.enterText(find.byKey(const Key('url')), url);
    await tester.ensureVisible(find.text('Join chat'));
    await tester.tap(find.text('Join chat'));
    await tester.pump();
  }

  /// Lets real I/O run until [done] or about 3 seconds pass.
  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 60 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      // Not pumpAndSettle: the spinner never settles, and that would run the
      // fake clock past the join timeout.
      await tester.pump(const Duration(milliseconds: 50));
    }
    if (done()) await tester.pumpAndSettle();
  }

  testWidgets('shows a loading state, then opens the chat', (tester) async {
    await startServerWithAda(tester);
    await join(tester, 'Bob', 'ws://localhost:${server.port}');

    expect(find.text('Joining…'), findsOneWidget);
    expect(find.text('# general'), findsNothing);

    await settle(tester, () => find.text('# general').evaluate().isNotEmpty);
    expect(find.text('# general'), findsOneWidget);
    expect(find.text('Bob (you)'), findsOneWidget);

    // Leave so the chat screen disposes its connection.
    await tester.tap(find.byTooltip('Leave'));
    await tester.pumpAndSettle();
    await stopServer(tester);
  });

  testWidgets('a taken name stays on the join screen with an error', (
    tester,
  ) async {
    const message = 'That name is already in use. Try another.';
    await startServerWithAda(tester);
    await join(tester, 'ada', 'ws://localhost:${server.port}');

    await settle(tester, () => find.text(message).evaluate().isNotEmpty);
    expect(find.text(message), findsOneWidget);
    expect(find.text('Join chat'), findsOneWidget);
    expect(find.text('# general'), findsNothing);

    // Typing a new name clears the error.
    await tester.enterText(find.byKey(const Key('name')), 'Bob');
    await tester.pump();
    expect(find.text(message), findsNothing);
    await stopServer(tester);
  });

  testWidgets('an unreachable server shows an error under the address', (
    tester,
  ) async {
    await join(tester, 'Bob', 'ws://localhost:1');
    expect(find.text('Joining…'), findsOneWidget);

    await tester.pump(JoinScreen.joinTimeout);
    await tester.pumpAndSettle();
    expect(find.textContaining("Couldn't reach the server"), findsOneWidget);
    expect(find.text('Join chat'), findsOneWidget);
  });
}
