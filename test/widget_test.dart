import 'package:doe_improved/main.dart';
import 'package:doe_improved/views/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App boots to the dashboard header', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: DOEImprovedApp()));
    await tester.pump();
    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(find.text('DOEImproved'), findsWidgets);
  });
}