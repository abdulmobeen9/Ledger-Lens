# LedgerLens 1.1.0 — fixes and additions

## Errors fixed
1. **CI could not build**: the workflow never created the Android Gradle project. It now runs the bootstrap script when missing.
2. **Biometric lock would crash on Android**: `local_auth` needs `FlutterFragmentActivity` and an AppCompat theme. Bootstrap scripts now patch both.
3. **Test would not compile**: `extraction_validation_test.dart` used an undefined `service` variable. Validation is now a top-level function.
4. **Wrong user's data after switching accounts**: data providers were cached with the first user's id. They now follow the auth stream.
5. **Sync deadlock**: transactions were pushed before categories, so a transaction using a new offline category was rejected forever. Categories now go first, and one failing item no longer blocks the rest.
6. **Duplicate category names** (server has a unique constraint) would fail every sync; blocked locally with a clear message.
7. **Deleting a category** left local transactions pointing at it, which the server then rejected. They are now detached and re-queued.
8. **3-decimal currencies (KWD, BHD, OMR…)** were rounded to 2 decimals on the server: migration `006` widens the column.
9. **Database migration** from very old versions would try to add a column twice.
10. **Lock screen** sat above the Navigator (no Overlay) and stored the PIN in plain text. Rebuilt with a custom keypad, salted-hash PIN, attempt cooldown; old PINs are migrated.
11. **Receipt uploaded before OCR succeeded** (orphan files); now OCR first.
12. Slow-clock edge case in last-write-wins; default currency inconsistency (SAR vs USD); CSV export was plain text and injectable; deprecated `withOpacity`; background-sync registration could crash startup.

## Everything is free now
Receipt scanning no longer uses OpenAI. ML Kit reads the text on the phone and `lib/domain/receipt_parser.dart` extracts amount, date, currency, reference, payee, IBAN, type and payment method with built-in rules. The Edge Function and `OPENAI_API_KEY` are removed. Accuracy is lower than an AI model on messy receipts, so every field stays editable and low-confidence fields are highlighted. Scanned text is Latin-script only (Arabic text is not read by ML Kit; numbers still are).

## Optional free AI (Gemini)
Add your own free Google AI Studio key in Settings → AI receipt reading. When it is on, the scan sends the photo to Gemini, validates every returned field, and fills any gaps from the offline reader; if the AI is unavailable or rate-limited it falls back to offline automatically. The key is stored encrypted on the phone and the model is discovered automatically (model names change often). Privacy: with AI on, the photo goes to Google, and on the free tier Google may use it to improve its products. Without a key nothing leaves the device.
After scanning, every field (amount, currency, type, category, date, method, name, references, notes) is editable before saving, highlighted when not found, and a saved scan can be corrected later from the transaction's Edit screen (the save confirmation has an Edit shortcut).

## Tuned for remittance receipts (Nepal / Saudi / Kuwait)
Based on sample slips (Al Rajhi, Bank Albilad, Western Union, IME, connectIPS, Nepal Bank, Al Muzaini, Hala wallet, MORU): NPR and other currencies added; the AI prompt reads Arabic/English/Nepali, rotated or cropped photos, MTCN and FT/TT/control numbers, fees, exchange rates, purpose and the beneficiary bank; "other amounts" (for example what the receiver gets in NPR) appear as tap-to-use chips; fee, rate, purpose, transfer code and bank are written into an editable notes line. The offline reader now handles label-above-value layouts, picks the receiver (not the sender) account, ignores transaction numbers that only look like IBANs, and no longer guesses an amount when none is shown.

## Duplicate slip detection
After scanning, the app checks your saved transactions. An exact match on the reference number or transfer code (e.g. Western Union MTCN) shows "This slip is already saved" with a **View saved slip** button; a same-amount/date/name match shows "This may already be saved". Tapping Confirm re-checks the edited values and asks View slip / Save anyway / Cancel. The same check runs when adding a new transaction by hand.

## Not verified
This environment had no Flutter SDK or network, so the code could not be compiled or run. Run `flutter pub get`, `dart run build_runner build --delete-conflicting-outputs`, `flutter analyze` and `flutter test` first and send me any errors.
