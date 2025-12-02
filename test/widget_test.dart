// test/widget_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracking/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app with the MyApp widget
    await tester.pumpWidget(
      const MyApp(hasSeenOnboarding: false),
    );

    // Verify app initialized
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}