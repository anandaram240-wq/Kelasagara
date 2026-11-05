// test/worker_card_widget_test.dart
// Production-grade widget test for WorkerCard truthful ratings and experience.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/models/user_profile.dart';
import 'package:kelasagaara/widgets/worker_card.dart';

void main() {
  testWidgets('WorkerCard displays truthful rating "No reviews" when totalRatings is 0', (tester) async {
    const worker = UserProfile(
      uid: 'w_test_1',
      displayName: 'Manjunath',
      userId: 'manju_wire',
      role: 'worker',
      skills: ['electrician'],
      dailyRate: 800,
      totalRatings: 0,
      rating: 0.0,
      totalJobs: 0,
      experienceLevel: '3-5 yrs',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkerCard(
            worker: worker,
            onMessage: () {},
            onViewProfile: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Display Name and @userId
    expect(find.text('Manjunath'), findsOneWidget);
    expect(find.text('@manju_wire'), findsOneWidget);

    // Verify Truthful Rating: "No reviews" displayed, NEVER "5.0"
    expect(find.text('No reviews'), findsOneWidget);
    expect(find.textContaining('5.0'), findsNothing);

    // Verify Experience Pill
    expect(find.text('⏱ 3-5 yrs'), findsOneWidget);

    // Verify Daily Rate
    expect(find.text('₹800/day'), findsOneWidget);
  });

  testWidgets('WorkerCard displays actual rating and total count when reviews exist', (tester) async {
    const worker = UserProfile(
      uid: 'w_test_2',
      displayName: 'Shankar Mason',
      userId: 'shankar_mason',
      role: 'worker',
      skills: ['mason'],
      dailyRate: 950,
      totalRatings: 18,
      rating: 4.8,
      totalJobs: 24,
      experienceLevel: '5-10 yrs',
      faceVerified: true,
      skillVerified: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkerCard(
            worker: worker,
            onMessage: () {},
            onViewProfile: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Shankar Mason'), findsOneWidget);
    expect(find.text('4.8 (18)'), findsOneWidget);
    expect(find.text('⏱ 5-10 yrs'), findsOneWidget);
    expect(find.text('24 jobs'), findsOneWidget);
    expect(find.text('✅ Verified'), findsOneWidget);
  });
}
