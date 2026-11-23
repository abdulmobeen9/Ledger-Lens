import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/theme.dart';
import '../features/auth/auth_screen.dart';
import '../features/budgets/budgets_screen.dart';
import '../features/categories/categories_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/goals/goals_screen.dart';
import '../features/reports/reports_screen.dart';
import '../features/scan/scan_screen.dart';
import '../features/security/app_lock_gate.dart';
import '../features/settings/settings_screen.dart';
import '../features/transactions/transaction_detail.dart';
import '../features/transactions/transaction_form.dart';
import '../features/transactions/transaction_list.dart';
import 'providers.dart';
import 'settings.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefresh(ref);
  ref.onDispose(refresh.dispose);
  final router = GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final signedIn = ref.read(supabaseProvider).auth.currentUser != null;
      final atAuth = state.matchedLocation == '/auth';
      if (!signedIn && !atAuth) return '/auth';
      if (signedIn && atAuth) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => const DashboardScreen()),
      GoRoute(path: '/auth', builder: (_, __) => const AuthScreen()),
      GoRoute(path: '/transactions', builder: (_, __) => const TransactionListScreen()),
      GoRoute(
        path: '/add',
        builder: (_, state) => TransactionFormScreen(
          type: state.uri.queryParameters['type'] ?? 'expense',
          duplicateFromId: state.uri.queryParameters['from'],
        ),
      ),
      GoRoute(path: '/transactions/:id', builder: (_, state) => TransactionDetailScreen(id: state.pathParameters['id']!)),
      GoRoute(
        path: '/transactions/:id/edit',
        builder: (_, state) => TransactionFormScreen(type: 'expense', transactionId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/scan', builder: (_, __) => const ScanScreen()),
      GoRoute(path: '/categories', builder: (_, __) => const CategoriesScreen()),
      GoRoute(path: '/reports', builder: (_, __) => const ReportsScreen()),
      GoRoute(path: '/budgets', builder: (_, __) => const BudgetsScreen()),
      GoRoute(path: '/goals', builder: (_, __) => const GoalsScreen()),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

/// Re-evaluates the router redirect on auth changes and kicks off category seeding and sync after sign-in.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(this._ref) {
    _sub = _ref.read(supabaseProvider).auth.onAuthStateChange.listen((data) {
      final signedInEvent = data.event == AuthChangeEvent.signedIn || data.event == AuthChangeEvent.initialSession;
      if (signedInEvent && data.session != null) unawaited(_afterSignIn());
      notifyListeners();
    });
  }

  final Ref _ref;
  late final StreamSubscription<AuthState> _sub;

  Future<void> _afterSignIn() async {
    try {
      await _ref.read(supabaseProvider).rpc('seed_default_categories');
    } catch (_) {
      // Seeding is idempotent and retried on the next sign-in.
    }
    await _ref.read(transactionRepositoryProvider).syncPending();
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

class LedgerLensApp extends ConsumerWidget {
  const LedgerLensApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));
    return MaterialApp.router(
      title: 'LedgerLens',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      builder: (context, child) => AppLockGate(child: child ?? const SizedBox.shrink()),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
