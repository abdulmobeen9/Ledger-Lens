import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerlens/app/providers.dart';
import 'package:ledgerlens/app/settings.dart';
import 'package:ledgerlens/data/local/app_database.dart';
import 'package:ledgerlens/features/transactions/transaction_form.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Add transaction form shows amount, type and category controls', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        categoriesProvider.overrideWith((ref) => Stream.value(<LocalCategory>[])),
      ],
      child: const MaterialApp(home: TransactionFormScreen(type: 'income')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('New transaction'), findsOneWidget);
    expect(find.text('Income'), findsOneWidget);
    expect(find.text('Expense'), findsOneWidget);
    expect(find.text('Amount'), findsOneWidget);
    expect(find.text('CATEGORY'), findsOneWidget);
    expect(find.text('Save transaction'), findsOneWidget);
  });
}
