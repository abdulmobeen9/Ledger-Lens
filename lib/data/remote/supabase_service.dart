import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  SupabaseService(this.client);
  final SupabaseClient client;

  /// Uploads a receipt image to the private `receipts` bucket (included in Supabase's free tier).
  Future<String> uploadReceipt(String userId, String filePath) async {
    final lower = filePath.toLowerCase();
    final ext = lower.endsWith('.png') ? 'png' : (lower.endsWith('.webp') ? 'webp' : 'jpg');
    final name = '$userId/${DateTime.now().microsecondsSinceEpoch}.$ext';
    await client.storage.from('receipts').upload(name, File(filePath));
    return name;
  }
}
