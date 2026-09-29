// ─────────────────────────────────────────────────────────────────────────
//  TEMPORARY — REMOVE BEFORE THE NEXT STORE RELEASE.
//
//  A hidden trigger for checking that crash reporting actually reaches
//  Firebase (project `pelion-order`). Reached by long-pressing the
//  "Postavke uređaja" title in the app bar; delete this file and the
//  GestureDetector around that title in settings_screen.dart to remove it.
//
//  Note it only does anything in a RELEASE (or profile) build: debug builds
//  have Crashlytics collection switched off on purpose, see CrashReporting.
// ─────────────────────────────────────────────────────────────────────────

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/crash_reporting.dart';

/// Offers the two test reports. Results are shown as dialogs, never as
/// snackbars — those aren't readable on the waiters' phones.
Future<void> showCrashTestDialog(BuildContext context) async {
  final ready = CrashReporting.isReady;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      return AlertDialog(
        title: const Text('Test prijave grešaka'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              ready
                  ? 'Crashlytics je aktivan.'
                  : 'Crashlytics NIJE aktivan — Firebase se nije pokrenuo.',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: ready ? null : theme.colorScheme.error,
              ),
            ),
            if (kDebugMode) ...[
              const SizedBox(height: 8),
              Text(
                'Ovo je debug verzija — prijave se ne šalju. Za test je '
                'potrebna release verzija.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: ready
                  ? () {
                      Navigator.of(dialogContext).pop();
                      _sendNonFatal(context);
                    }
                  : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('Testna greška'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: ready
                  ? () => FirebaseCrashlytics.instance.crash()
                  : null,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: theme.colorScheme.error,
              ),
              child: const Text('Testni pad'),
            ),
            const SizedBox(height: 8),
            Text(
              'Testni pad ruši aplikaciju namjerno. Prijava se šalje pri '
              'sljedećem pokretanju.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Zatvori'),
          ),
        ],
      );
    },
  );
}

Future<void> _sendNonFatal(BuildContext context) async {
  var sent = false;
  try {
    await FirebaseCrashlytics.instance.recordError(
      Exception('Testna greška iz Postavki uređaja'),
      StackTrace.current,
      reason: 'Ručni test prijave grešaka',
      fatal: false,
    );
    sent = true;
  } catch (e) {
    debugPrint('Test prijave nije uspio: $e');
  }

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(sent ? 'Poslano' : 'Nije poslano'),
      content: Text(
        sent
            ? 'Testna greška je zabilježena. U Firebase konzoli se pojavljuje '
                  'unutar nekoliko minuta, pod "Crashlytics".'
            : 'Prijava nije uspjela. Provjeri internetsku vezu.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('U redu'),
        ),
      ],
    ),
  );
}
