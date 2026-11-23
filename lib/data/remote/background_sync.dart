import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';
import '../local/app_database.dart';
import 'transaction_repository.dart';

const _syncTask = 'ledgerlens.periodic.sync';

@pragma('vm:entry-point')
void ledgerLensBackgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    const url = String.fromEnvironment('SUPABASE_URL');
    const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
    if (url.isEmpty || anonKey.isEmpty) return false;
    try {
      await Supabase.initialize(url: url, anonKey: anonKey);
      final db = AppDatabase();
      final repository = TransactionRepository(db, Supabase.instance.client, listenConnectivity: false);
      try {
        await repository.syncPending();
      } finally {
        await repository.dispose();
        await db.close();
      }
      return true;
    } catch (_) {
      return false;
    }
  });
}

/// Background sync is a convenience; a failure to register it must never stop the app from starting.
Future<void> registerLedgerLensBackgroundSync() async {
  try {
    await Workmanager().initialize(ledgerLensBackgroundDispatcher, isInDebugMode: false);
    await Workmanager().registerPeriodicTask(
      'ledgerlens-periodic-sync',
      _syncTask,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.keep,
    );
  } catch (_) {
    // Foreground sync (connectivity changes, pull-to-refresh, Sync now) still works.
  }
}
