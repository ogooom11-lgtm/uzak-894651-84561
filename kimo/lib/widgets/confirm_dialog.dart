import 'package:flutter/material.dart';

/// Central confirmation hook.
///
/// The mobile app now works in direct-action mode: taps execute immediately
/// without an extra confirmation dialog, as requested. Keeping this function
/// lets older screens use the same call sites while avoiding UI friction.
bool get kDirectActionMode => true;

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'تأكيد',
  bool danger = false,
}) async {
  if (kDirectActionMode) return true;

  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                )
              : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
