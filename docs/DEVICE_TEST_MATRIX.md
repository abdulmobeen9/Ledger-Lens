# Device acceptance test matrix

Run on at least one physical Android device and one physical iPhone before store submission.

| Area | Test | Expected result |
|---|---|---|
| Auth | Email signup, confirmation, sign-in, sign-out | Correct session and route changes; no user data shown after sign-out |
| OAuth | Google sign-in and callback | Returns to the app at `io.supabase.ledgerlens://login-callback/` |
| Local DB | Create/edit/delete in airplane mode; force-stop and relaunch | Local rows persist; deletes remain hidden and queued |
| Sync | Restore network after offline writes | Pending rows upload; tombstones propagate; no duplicate rows |
| Conflict | Edit same transaction on two devices with different timestamps | Newer `updated_at` wins; document observed outcome |
| Categories | Add/delete category offline then reconnect | New category uploads; deletion propagates to all devices |
| Search | Query name, notes, reference; type/category/date filters | Combined filters return only matching transactions |
| Analytics | Add expense in multiple currencies and categories | Totals are separated by currency; category chart matches selected currency |
| OCR | Camera, gallery, multiple images, unreadable image | OCR runs on-device; no auto-save; review is editable |
| Receipt | Upload, signed preview, wait for URL expiry | Preview works while URL valid; a newly requested URL restores access |
| Security | Enable Face ID/fingerprint, PIN fallback, background/resume | App locks on background and unlocks only after successful challenge |
| RLS | Sign in as user A, attempt to read user B's transaction/receipt | Supabase denies access |
| Export | Export a ledger with different currencies and special characters | CSV opens correctly and retains currency and text fields |
| Release | Android AAB and iOS IPA/TestFlight install | No debug-only dependencies or missing deep-link/permission configuration |

Record OS version, device model, app build, Supabase project environment, and pass/fail for every row. Do not use production financial records for initial testing.
