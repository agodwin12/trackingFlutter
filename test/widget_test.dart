// test/widget_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracking/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // ✅ FIXED: Removed hasSeenOnboarding parameter
    await tester.pumpWidget(
      const MyApp(),
    );

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}