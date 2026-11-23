import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app/app.dart';
import 'app/settings.dart';
import 'core/theme.dart';
import 'data/remote/background_sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_ANON_KEY');
  if (url.isEmpty || key.isEmpty) {
    runApp(const _MissingConfigApp());
    return;
  }
  await Supabase.initialize(url: url, anonKey: key);
  final prefs = await SharedPreferences.getInstance();
  await registerLedgerLensBackgroundSync();
  runApp(ProviderScope(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    child: const LedgerLensApp(),
  ));
}

class _MissingConfigApp extends StatelessWidget {
  const _MissingConfigApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(Brightness.light),
        home: const Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.settings_suggest_rounded, size: 64),
                  SizedBox(height: 16),
                  Text('Configuration needed', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  SizedBox(height: 8),
                  Text(
                    'Build the app with SUPABASE_URL and SUPABASE_ANON_KEY, for example:\n\nflutter run --dart-define-from-file=.env.json',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
