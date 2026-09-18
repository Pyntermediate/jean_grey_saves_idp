import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_1/main.dart';

void main() {
  testWidgets('Flare app smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const FlareApp());

    // Verify main app title and navigation elements are rendered
    expect(find.text('Flare'), findsOneWidget);
    expect(find.text('Messages'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });
}
