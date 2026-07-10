import 'package:flutter/material.dart';

/// Holds the app-wide light/dark [ThemeMode] and rebuilds descendants when it
/// changes. Kept deliberately simple (an [InheritedWidget] over local state) —
/// theme preference is pure UI, so it stays out of the domain/data layers.
///
/// Read it with `ThemeController.of(context)`; flip it with `.toggle()`.
class ThemeController extends StatefulWidget {
  const ThemeController({required this.child, super.key});

  final Widget child;

  static ThemeControllerState of(BuildContext context) {
    final state = context
        .dependOnInheritedWidgetOfExactType<_ThemeControllerScope>()
        ?.state;
    assert(state != null, 'No ThemeController found in context');
    return state!;
  }

  @override
  State<ThemeController> createState() => ThemeControllerState();
}

class ThemeControllerState extends State<ThemeController> {
  ThemeMode _mode = ThemeMode.light;

  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  void toggle() {
    setState(() {
      _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _ThemeControllerScope(
      state: this,
      mode: _mode,
      child: widget.child,
    );
  }
}

class _ThemeControllerScope extends InheritedWidget {
  const _ThemeControllerScope({
    required this.state,
    required this.mode,
    required super.child,
  });

  final ThemeControllerState state;
  final ThemeMode mode;

  @override
  bool updateShouldNotify(_ThemeControllerScope oldWidget) =>
      oldWidget.mode != mode;
}
