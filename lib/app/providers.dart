import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/local/app_database.dart';
import '../data/remote/transaction_repository.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final supabaseProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

final transactionRepositoryProvider = Provider<TransactionRepository>((ref) {
  final repo = TransactionRepository(ref.watch(databaseProvider), ref.watch(supabaseProvider));
  ref.onDispose(repo.dispose);
  return repo;
});

/// Emits the signed-in user's id and every change of it, so data providers re-subscribe on
/// sign-in, sign-out and account switches instead of keeping the previous user's stream alive.
final userIdProvider = StreamProvider<String?>((ref) async* {
  final auth = ref.watch(supabaseProvider).auth;
  yield auth.currentUser?.id;
  await for (final state in auth.onAuthStateChange) {
    yield state.session?.user.id;
  }
});

String? _currentUid(Ref ref) =>
    ref.watch(userIdProvider).valueOrNull ?? ref.watch(supabaseProvider).auth.currentUser?.id;

final transactionsProvider = StreamProvider<List<Transaction>>((ref) {
  final uid = _currentUid(ref);
  if (uid == null) return Stream.value(const <Transaction>[]);
  return ref.watch(databaseProvider).transactionDao.watchAll(uid);
});

final categoriesProvider = StreamProvider<List<LocalCategory>>((ref) {
  final uid = _currentUid(ref);
  if (uid == null) return Stream.value(const <LocalCategory>[]);
  return ref.watch(databaseProvider).categoryDao.watchForUser(uid);
});

final budgetsProvider = StreamProvider<List<Budget>>((ref) {
  final uid = _currentUid(ref);
  if (uid == null) return Stream.value(const <Budget>[]);
  return ref.watch(databaseProvider).budgetDao.watchForUser(uid);
});

final goalsProvider = StreamProvider<List<SavingsGoal>>((ref) {
  final uid = _currentUid(ref);
  if (uid == null) return Stream.value(const <SavingsGoal>[]);
  return ref.watch(databaseProvider).goalDao.watchForUser(uid);
});

final transactionByIdProvider = StreamProvider.family<Transaction?, String>((ref, id) {
  return ref.watch(databaseProvider).transactionDao.watchById(id);
});

final syncStatusProvider = StreamProvider<SyncStatus>((ref) async* {
  final repo = ref.watch(transactionRepositoryProvider);
  yield repo.status;
  yield* repo.statusStream;
});
