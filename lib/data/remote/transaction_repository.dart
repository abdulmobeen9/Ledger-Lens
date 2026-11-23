import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../local/app_database.dart';

enum SyncPhase { idle, syncing, synced, error }

class SyncStatus {
  const SyncStatus(this.phase, {this.lastSuccess});
  final SyncPhase phase;
  final DateTime? lastSuccess;
}

class DuplicateCategoryException implements Exception {
  const DuplicateCategoryException(this.name);
  final String name;
  @override
  String toString() => 'A category named "$name" already exists.';
}

class TransactionRepository {
  TransactionRepository(this.db, this.client, {bool listenConnectivity = true}) {
    if (listenConnectivity) {
      _connectivitySubscription =
          Connectivity().onConnectivityChanged.listen((_) => unawaited(syncPending()));
    }
  }

  StreamSubscription<dynamic>? _connectivitySubscription;
  final AppDatabase db;
  final SupabaseClient client;
  final _uuid = const Uuid();
  final _statusController = StreamController<SyncStatus>.broadcast();
  SyncStatus _status = const SyncStatus(SyncPhase.idle);
  bool _syncing = false;
  int _retryAttempt = 0;

  SyncStatus get status => _status;
  Stream<SyncStatus> get statusStream => _statusController.stream;

  Future<void> dispose() async {
    await _connectivitySubscription?.cancel();
    await _statusController.close();
  }

  void _setStatus(SyncPhase phase, {DateTime? lastSuccess}) {
    _status = SyncStatus(phase, lastSuccess: lastSuccess ?? _status.lastSuccess);
    if (!_statusController.isClosed) _statusController.add(_status);
  }

  String get userId => client.auth.currentUser?.id ?? (throw StateError('Sign in required'));

  Stream<List<Transaction>> watch() => db.transactionDao.watchAll(userId);
  Stream<List<LocalCategory>> watchCategories() => db.categoryDao.watchForUser(userId);
  Future<Transaction?> getById(String id) => db.transactionDao.byId(id);

  Future<String> save({
    String? id,
    required String type,
    required double amount,
    required String currency,
    required DateTime date,
    String? name,
    String? method,
    String? reference,
    String? receiving,
    String? notes,
    String? categoryId,
    String? imageUrl,
    String? rawText,
    double? confidence,
    String? source,
  }) async {
    final uid = userId;
    var now = DateTime.now();
    final txnId = id ?? _uuid.v4();
    final existing = id == null ? null : await db.transactionDao.byId(id);
    // Keep updated_at strictly increasing so a slow device clock can never lose an edit to an older server stamp.
    if (existing != null && !now.isAfter(existing.updatedAt)) {
      now = existing.updatedAt.add(const Duration(seconds: 1));
    }
    await db.transactionDao.upsert(TransactionsCompanion.insert(
      id: txnId,
      userId: uid,
      type: type,
      amount: amount,
      amountMinor: Value(amountToMinorUnits(amount, currency)),
      currency: Value(currency),
      txnDate: date,
      counterpartyName: Value(name),
      transferMethod: Value(method),
      referenceNo: Value(reference),
      receivingNumber: Value(receiving),
      notes: Value(notes),
      categoryId: Value(categoryId),
      imageUrl: Value(imageUrl),
      ocrRawText: Value(rawText ?? existing?.ocrRawText),
      ocrConfidence: Value(confidence ?? existing?.ocrConfidence),
      extractionSource: Value(source ?? existing?.extractionSource ?? 'manual'),
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      pendingSync: const Value(true),
    ));
    unawaited(syncPending());
    return txnId;
  }

  Future<void> delete(String id) async {
    final uid = userId;
    // The tombstone is committed in the same SQLite transaction as the delete, so an offline delete is durable.
    await db.transaction(() async {
      await db.tombstoneDao.add(id, uid);
      await db.transactionDao.remove(id);
    });
    unawaited(syncPending());
  }

  Future<void> saveCategory({
    String? id,
    required String name,
    required String type,
    String icon = 'category',
    String color = '#64748B',
  }) async {
    final uid = userId;
    final trimmed = name.trim();
    final existing = await db.categoryDao.getForUser(uid);
    final clash = existing.any((c) =>
        c.id != id && c.type == type && c.name.trim().toLowerCase() == trimmed.toLowerCase());
    // The server enforces unique(user_id, name, type); a clash here would otherwise fail every sync.
    if (clash) throw DuplicateCategoryException(trimmed);
    final categoryId = id ?? _uuid.v4();
    await db.categoryDao.upsert(LocalCategoriesCompanion.insert(
      id: categoryId,
      userId: uid,
      name: trimmed,
      type: Value(type),
      icon: Value(icon),
      color: Value(color),
      pendingSync: const Value(true),
    ));
    unawaited(syncPending());
  }

  Future<void> deleteCategory(String id) async {
    final uid = userId;
    await db.transaction(() async {
      await db.tombstoneDao.add(id, uid, entityType: 'categories');
      await db.transactionDao.detachCategory(uid, id);
      await db.budgetDao.deleteForCategory(uid, id);
      await db.categoryDao.deleteById(id);
    });
    unawaited(syncPending());
  }

  Future<void> syncPending() async {
    if (_syncing || client.auth.currentUser == null) return;
    _syncing = true;
    _setStatus(SyncPhase.syncing);
    var failed = false;
    try {
      final uid = userId;

      // 1. Replay local deletes first so a deleted row is never re-imported.
      for (final tombstone in await db.tombstoneDao.all(uid)) {
        try {
          await client.from('sync_deletions').upsert({
            'id': tombstone.id,
            'user_id': uid,
            'entity_type': tombstone.entityType,
            'deleted_at': tombstone.deletedAt.toUtc().toIso8601String(),
          });
          if (tombstone.entityType == 'categories') {
            await client.from('categories').delete().eq('id', tombstone.id).eq('user_id', uid);
          } else {
            await client.from('transactions').delete().eq('id', tombstone.id).eq('user_id', uid);
          }
          await db.tombstoneDao.remove(tombstone.id);
        } catch (_) {
          failed = true;
        }
      }

      // 2. Apply the cloud deletion journal so deletes propagate across devices.
      try {
        final deletions = await client.from('sync_deletions').select().eq('user_id', uid);
        for (final deletion in deletions) {
          final id = deletion['id'] as String;
          if (deletion['entity_type'] == 'categories') {
            await db.categoryDao.deleteById(id);
          } else {
            await db.transactionDao.remove(id);
          }
        }
      } catch (_) {
        failed = true;
      }

      // 3. Push categories BEFORE transactions: a transaction that references a brand-new
      //    local category would otherwise be rejected by the server's foreign key.
      for (final category in await db.categoryDao.pending(uid)) {
        try {
          await client.from('categories').upsert({
            'id': category.id,
            'user_id': uid,
            'name': category.name,
            'type': category.type,
            'icon': category.icon,
            'color': category.color,
          });
          await db.categoryDao.markSynced(category.id);
        } catch (_) {
          failed = true;
        }
      }

      // 4. Push local transaction edits. One bad row no longer blocks the rest.
      for (final row in await db.transactionDao.pending(uid)) {
        try {
          final remote =
              await client.from('transactions').select('updated_at').eq('id', row.id).maybeSingle();
          final remoteTime = remote == null ? null : DateTime.tryParse(remote['updated_at'] as String);
          if (remoteTime != null && remoteTime.isAfter(row.updatedAt)) {
            // Remote wins only when strictly newer.
            final full = await client.from('transactions').select().eq('id', row.id).single();
            await db.transactionDao.upsert(_fromRemote(full, uid));
          } else {
            final saved = await client
                .from('transactions')
                .upsert(_toRemote(row))
                .select('updated_at')
                .single();
            await db.transactionDao.markSynced(
              row.id,
              serverUpdatedAt: DateTime.parse(saved['updated_at'] as String).toLocal(),
            );
          }
        } catch (_) {
          failed = true;
        }
      }

      // 5. Pull categories, then transactions.
      try {
        final tombstones = await db.tombstoneDao.all(uid);
        final deletedCategories =
            tombstones.where((t) => t.entityType == 'categories').map((t) => t.id).toSet();
        final remoteCategories = await client.from('categories').select().eq('user_id', uid);
        final pendingCategoryIds = (await db.categoryDao.pending(uid)).map((c) => c.id).toSet();
        for (final c in remoteCategories) {
          final id = c['id'] as String;
          if (deletedCategories.contains(id) || pendingCategoryIds.contains(id)) continue;
          await db.categoryDao.upsert(LocalCategoriesCompanion.insert(
            id: id,
            userId: uid,
            name: c['name'] as String,
            type: Value((c['type'] as String?) ?? 'both'),
            icon: Value((c['icon'] as String?) ?? 'category'),
            color: Value((c['color'] as String?) ?? '#64748B'),
            pendingSync: const Value(false),
          ));
        }
      } catch (_) {
        failed = true;
      }

      try {
        // Deliberately a full pull: simple and free of incremental-cursor gaps for v1.
        final remoteRows = await client.from('transactions').select().eq('user_id', uid);
        final localById = {for (final row in await db.transactionDao.getAll(uid)) row.id: row};
        final tombstoneIds = (await db.tombstoneDao.all(uid)).map((t) => t.id).toSet();
        for (final map in remoteRows) {
          final id = map['id'] as String;
          if (tombstoneIds.contains(id)) continue;
          final remote = _fromRemote(map, uid);
          final local = localById[id];
          if (local == null || (!local.pendingSync && remote.updatedAt.value.isAfter(local.updatedAt))) {
            await db.transactionDao.upsert(remote);
          }
        }
      } catch (_) {
        failed = true;
      }

      if (failed) {
        _setStatus(SyncPhase.error);
        _scheduleRetry();
      } else {
        _retryAttempt = 0;
        _setStatus(SyncPhase.synced, lastSuccess: DateTime.now());
      }
    } catch (_) {
      _setStatus(SyncPhase.error);
      _scheduleRetry();
    } finally {
      _syncing = false;
    }
  }

  void _scheduleRetry() {
    // Exponential backoff capped at 5 minutes. Pending rows and tombstones survive restarts.
    final seconds = (1 << _retryAttempt.clamp(1, 8).toInt()).clamp(2, 300).toInt();
    _retryAttempt = (_retryAttempt + 1).clamp(1, 8).toInt();
    Future<void>.delayed(Duration(seconds: seconds), () async {
      if (client.auth.currentUser == null) return;
      await syncPending();
    });
  }

  Map<String, dynamic> _toRemote(Transaction r) => {
        'id': r.id,
        'user_id': r.userId,
        'type': r.type,
        'amount': r.preciseAmount,
        'currency': r.currency,
        'txn_date': r.txnDate.toIso8601String().substring(0, 10),
        'counterparty_name': r.counterpartyName,
        'transfer_method': r.transferMethod,
        'reference_no': r.referenceNo,
        'receiving_number': r.receivingNumber,
        'category_id': r.categoryId,
        'notes': r.notes,
        'image_url': r.imageUrl,
        'ocr_raw_text': r.ocrRawText,
        'ocr_confidence': r.ocrConfidence,
        'extraction_source': r.extractionSource,
        'created_at': r.createdAt.toUtc().toIso8601String(),
        'updated_at': r.updatedAt.toUtc().toIso8601String(),
      };

  TransactionsCompanion _fromRemote(Map<String, dynamic> m, String uid) {
    final amount = (m['amount'] as num).toDouble();
    final currency = (m['currency'] as String?) ?? 'USD';
    return TransactionsCompanion.insert(
      id: m['id'] as String,
      userId: uid,
      type: m['type'] as String,
      amount: amount,
      amountMinor: Value(amountToMinorUnits(amount, currency)),
      currency: Value(currency),
      txnDate: DateTime.parse(m['txn_date'] as String),
      counterpartyName: Value(m['counterparty_name'] as String?),
      transferMethod: Value(m['transfer_method'] as String?),
      referenceNo: Value(m['reference_no'] as String?),
      receivingNumber: Value(m['receiving_number'] as String?),
      categoryId: Value(m['category_id'] as String?),
      notes: Value(m['notes'] as String?),
      imageUrl: Value(m['image_url'] as String?),
      ocrRawText: Value(m['ocr_raw_text'] as String?),
      ocrConfidence: Value((m['ocr_confidence'] as num?)?.toDouble()),
      extractionSource: Value((m['extraction_source'] as String?) ?? 'manual'),
      createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      updatedAt: DateTime.parse(m['updated_at'] as String).toLocal(),
      pendingSync: const Value(false),
    );
  }

  Future<String> signedReceiptUrl(String storagePath) =>
      client.storage.from('receipts').createSignedUrl(storagePath, 3600);
}
