import 'package:easy_chat/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('requires a name and a ws:// address', (tester) async {
    await tester.pumpWidget(const EasyChatApp());

    await tester.ensureVisible(find.text('Join chat'));
    await tester.tap(find.text('Join chat'));
    await tester.pump();
    expect(find.text('Enter a name'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('name')), 'Ada');
    await tester.enterText(find.byKey(const Key('url')), 'http://nope');
    await tester.ensureVisible(find.text('Join chat'));
    await tester.tap(find.text('Join chat'));
    await tester.pump();
    expect(find.text('Enter a name'), findsNothing);
    expect(find.text('Use a ws:// or wss:// address'), findsOneWidget);
  });
}
