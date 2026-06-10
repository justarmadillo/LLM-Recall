import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders a minimal material widget', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('smoke'))),
    );

    expect(find.text('smoke'), findsOneWidget);
  });
}
