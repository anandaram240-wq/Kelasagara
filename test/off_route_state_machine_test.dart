import 'package:flutter_test/flutter_test.dart';

enum OffRouteState { onRoute, suspectedOffRoute, confirmedOffRoute, rerouting, backOnRoute }

class OffRouteStateMachineMock {
  OffRouteState state = OffRouteState.onRoute;
  int consecutiveHighDistanceTicks = 0;
  int failedReroutes = 0;

  void processTick(double distance) {
    if (state == OffRouteState.confirmedOffRoute) {
      if (failedReroutes >= 3) return; // Stays in confirmed
    }

    if (state == OffRouteState.rerouting) {
      if (distance < 30) {
        state = OffRouteState.backOnRoute;
        consecutiveHighDistanceTicks = 0;
      }
      return;
    }

    if (distance > 80) {
      consecutiveHighDistanceTicks++;
      if (consecutiveHighDistanceTicks >= 6) {
        state = OffRouteState.confirmedOffRoute;
      } else {
        state = OffRouteState.suspectedOffRoute;
      }
    } else if (distance > 50) {
      state = OffRouteState.suspectedOffRoute;
      consecutiveHighDistanceTicks++;
    } else if (distance < 30) {
      if (state == OffRouteState.suspectedOffRoute || state == OffRouteState.backOnRoute) {
        state = OffRouteState.onRoute;
      }
      consecutiveHighDistanceTicks = 0;
    }
  }

  void triggerReroute() {
    if (state == OffRouteState.confirmedOffRoute) {
      state = OffRouteState.rerouting;
    }
  }
  
  void failReroute() {
    failedReroutes++;
    if (failedReroutes >= 3) {
      state = OffRouteState.confirmedOffRoute;
    }
  }
}

void main() {
  group('Off-Route State Machine Tests', () {
    test('ON_ROUTE -> SUSPECTED: Distance > 50m for first time', () {
      final machine = OffRouteStateMachineMock();
      machine.processTick(60.0);
      expect(machine.state, OffRouteState.suspectedOffRoute);
    });

    test('SUSPECTED -> ON_ROUTE: Distance drops below 30m', () {
      final machine = OffRouteStateMachineMock();
      machine.processTick(60.0); // suspected
      machine.processTick(20.0); // back to onRoute
      expect(machine.state, OffRouteState.onRoute);
    });

    test('SUSPECTED -> CONFIRMED: Distance > 80m for 6 consecutive ticks', () {
      final machine = OffRouteStateMachineMock();
      for (int i = 0; i < 6; i++) {
        machine.processTick(85.0);
      }
      expect(machine.state, OffRouteState.confirmedOffRoute);
    });

    test('CONFIRMED -> REROUTING: Reroute request triggered', () {
      final machine = OffRouteStateMachineMock();
      for (int i = 0; i < 6; i++) {
        machine.processTick(85.0);
      }
      machine.triggerReroute();
      expect(machine.state, OffRouteState.rerouting);
    });

    test('REROUTING -> BACK_ON_ROUTE: New route accepted, distance < 30m', () {
      final machine = OffRouteStateMachineMock();
      for (int i = 0; i < 6; i++) {
        machine.processTick(85.0);
      }
      machine.triggerReroute();
      machine.processTick(20.0);
      expect(machine.state, OffRouteState.backOnRoute);
    });

    test('Grace count prevents false triggers', () {
      final machine = OffRouteStateMachineMock();
      machine.processTick(85.0);
      machine.processTick(85.0);
      machine.processTick(85.0); // 3 ticks
      machine.processTick(20.0); // grace kicks in
      expect(machine.state, OffRouteState.onRoute);
    });

    test('Max reroute attempts handling', () {
      final machine = OffRouteStateMachineMock();
      for (int i = 0; i < 6; i++) {
        machine.processTick(85.0);
      }
      machine.triggerReroute();
      machine.failReroute();
      machine.failReroute();
      machine.failReroute();
      expect(machine.state, OffRouteState.confirmedOffRoute);
      
      // Additional ticks shouldn't change state after max failures
      machine.processTick(85.0);
      expect(machine.state, OffRouteState.confirmedOffRoute);
    });
  });
}
