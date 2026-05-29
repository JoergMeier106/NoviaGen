import 'dart:async';

import 'package:flutter/material.dart';


class FullscreenStatusChip extends StatelessWidget {
  const FullscreenStatusChip({
    super.key,
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return FullscreenChrome(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }
}

class FullscreenIconActionButton extends StatelessWidget {
  const FullscreenIconActionButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      widthFactor: 1,
      child: FullscreenChrome(
        interactive: true,
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          waitDuration: const Duration(milliseconds: 500),
          child: SizedBox(
            width: 20,
            height: 20,
            child: Center(child: Icon(icon, color: Colors.white, size: 20)),
          ),
        ),
      ),
    );
  }
}

class FullscreenHoldActionButton extends StatelessWidget {
  const FullscreenHoldActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressedStateChanged,
  });

  final IconData icon;
  final String label;
  final FutureOr<void> Function(bool) onPressedStateChanged;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => onPressedStateChanged(true),
      onPointerUp: (_) => onPressedStateChanged(false),
      onPointerCancel: (_) => onPressedStateChanged(false),
      child: FullscreenChrome(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

class FullscreenChrome extends StatelessWidget {
  const FullscreenChrome({
    super.key,
    required this.child,
    this.interactive = false,
    this.onTap,
  });

  final Widget child;
  final bool interactive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: child,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: interactive
          ? Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: onTap,
                child: content,
              ),
            )
          : content,
    );
  }
}
