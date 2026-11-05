// test/navigation_state_machine_test.dart
// Automated unit tests for Kelasagara 26-State Navigation State Machine.

import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/models/journey_state.dart';

void main() {
  group('NavigationStateMachine Transition Matrix Tests', () {
    test('Legal transition: idle -> loadingBooking', () {
      expect(
        NavigationStateMachine.canTransition(
          NavigationState.idle,
          NavigationState.loadingBooking,
        ),
        isTrue,
      );
    });

    test('Legal transition: routeReady -> navigationStarting -> navigating', () {
      expect(
        NavigationStateMachine.canTransition(
          NavigationState.routeReady,
          NavigationState.navigationStarting,
        ),
        isTrue,
      );
      expect(
        NavigationStateMachine.canTransition(
          NavigationState.navigationStarting,
          NavigationState.navigating,
        ),
        isTrue,
      );
    });

    test('Legal transition: navigating -> offRoute -> routeRecalculating -> navigating', () {
      expect(
        NavigationStateMachine.canTransition(
          NavigationState.navigating,
          NavigationState.offRoute,
        ),
        isTrue,
      );
      expect(
        NavigationStateMachine.canTransition(
          NavigationState.offRoute,
          NavigationState.routeRecalculating,
        ),
        isTrue,
      );
      expect(
        NavigationStateMachine.canTransition(
          NavigationState.routeRecalculating,
          NavigationState.navigating,
        ),
        isTrue,
      );
    });

    test('Legal transition: navigating -> approaching -> arrivalPending -> arrived', () {
      expect(
        NavigationStateMachine.canTransition(
          NavigationState.navigating,
          NavigationState.approaching,
        ),
        isTrue,
      );
      expect(
        NavigationStateMachine.canTransition(
          NavigationState.approaching,
          NavigationState.arrivalPending,
        ),
        isTrue,
      );
      expect(
        NavigationStateMachine.canTransition(
          NavigationState.arrivalPending,
          NavigationState.arrived,
        ),
        isTrue,
      );
    });

    test('ILLEGAL transition: idle -> navigating directly without route/start (MUST BE REJECTED)', () {
      expect(
        NavigationStateMachine.canTransition(
          NavigationState.idle,
          NavigationState.navigating,
        ),
        isFalse,
      );
    });

    test('ILLEGAL transition: arrived -> navigating (MUST BE REJECTED)', () {
      expect(
        NavigationStateMachine.canTransition(
          NavigationState.arrived,
          NavigationState.navigating,
        ),
        isFalse,
      );
    });

    test('ILLEGAL transition: loggedOut -> navigating (MUST BE REJECTED)', () {
      expect(
        NavigationStateMachine.canTransition(
          NavigationState.loggedOut,
          NavigationState.navigating,
        ),
        isFalse,
      );
    });

    test('Self transition: state to itself is always legal', () {
      for (final state in NavigationState.values) {
        expect(
          NavigationStateMachine.canTransition(state, state),
          isTrue,
          reason: 'State ${state.name} should transition to itself',
        );
      }
    });
  });
}
