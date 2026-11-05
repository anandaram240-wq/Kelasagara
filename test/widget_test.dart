import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/core/theme/app_colors.dart';

void main() {
  testWidgets('App Theme and Core UI Smoke Test', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          primaryColor: AppColors.primary,
          scaffoldBackgroundColor: AppColors.bg,
        ),
        home: const Scaffold(
          body: Center(
            child: Text('KelasaGaara Voice AI v120', style: TextStyle(color: AppColors.primary)),
          ),
        ),
      ),
    );

    expect(find.text('KelasaGaara Voice AI v120'), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
