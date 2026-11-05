// lib/core/navigation/app_transitions.dart
// Smooth custom page transitions — drop-in replacements for MaterialPageRoute.
// Zero design changes; adds motion polish only.

import 'package:flutter/material.dart';

/// Slide up from bottom (modals, detail screens)
Route<T> slideUpRoute<T>(Widget page, {Duration duration = const Duration(milliseconds: 320)}) {
  return PageRouteBuilder<T>(
    pageBuilder: (_, __, ___) => page,
    transitionDuration: duration,
    reverseTransitionDuration: const Duration(milliseconds: 240),
    transitionsBuilder: (_, animation, __, child) {
      final tween = Tween(begin: const Offset(0, 0.08), end: Offset.zero)
          .chain(CurveTween(curve: Curves.easeOutCubic));
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: SlideTransition(position: animation.drive(tween), child: child),
      );
    },
  );
}

/// Slide right (drill-down navigation)
Route<T> slideRightRoute<T>(Widget page, {Duration duration = const Duration(milliseconds: 300)}) {
  return PageRouteBuilder<T>(
    pageBuilder: (_, __, ___) => page,
    transitionDuration: duration,
    reverseTransitionDuration: const Duration(milliseconds: 220),
    transitionsBuilder: (_, animation, __, child) {
      final tween = Tween(begin: const Offset(0.06, 0), end: Offset.zero)
          .chain(CurveTween(curve: Curves.easeOutCubic));
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: SlideTransition(position: animation.drive(tween), child: child),
      );
    },
  );
}

/// Fade + slight scale (cards opening to detail)
Route<T> fadeScaleRoute<T>(Widget page, {Duration duration = const Duration(milliseconds: 280)}) {
  return PageRouteBuilder<T>(
    pageBuilder: (_, __, ___) => page,
    transitionDuration: duration,
    reverseTransitionDuration: const Duration(milliseconds: 200),
    transitionsBuilder: (_, animation, __, child) {
      final scaleTween = Tween(begin: 0.96, end: 1.0)
          .chain(CurveTween(curve: Curves.easeOutCubic));
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: ScaleTransition(scale: animation.drive(scaleTween), child: child),
      );
    },
  );
}
