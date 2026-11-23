import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../app/settings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'package:flutter/services.dart';
import '../../data/local/ai_key_store.dart';
import '../../data/remote/gemini_service.dart';
import '../security/app_lock_service.dart';
import '../transactions/transaction_widgets.dart';
import 'export_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool biometric = false, hasPin = false, hasAiKey = false;
  String? aiModel;

  @override
  void initState() {
    super.initState();
    _refreshLock();
    _refreshAi();
  }

  Future<void> _refreshAi() async {
    final key = await AiKeyStore.key();
    final model = await AiKeyStore.model();
    if (mounted) setState(() { hasAiKey = key != null && key.isNotEmpty; aiModel = model; });
  }

  Future<void> _editAiKey() async {
    final controller = TextEditingController();
    final entered = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gemini API key'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Get a free key: open aistudio.google.com, sign in with Google and tap "Get API key". No card is needed.', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'Paste your key',
              suffixIcon: IconButton(
                tooltip: 'Paste',
                icon: const Icon(Icons.content_paste_rounded),
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  if (data?.text != null) controller.text = data!.text!.trim();
                },
              ),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(120, 44)), onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Save and test')),
        ],
      ),
    );
    controller.dispose();
    if (entered == null || entered.isEmpty) return;
    try {
      final model = await GeminiService().pickModel(entered);
      await AiKeyStore.save(entered, model);
      await _refreshAi();
      if (mounted) showSnack(context, 'Key works. AI reading is on.');
    } on GeminiException catch (e) {
      if (mounted) showSnack(context, e.message);
    } catch (_) {
      if (mounted) showSnack(context, 'Could not reach Google. Check your connection and try again.');
    }
  }

  Future<void> _refreshLock() async {
    final b = await AppLockService.biometricEnabled();
    final p = await AppLockService.hasPin();
    if (mounted) setState(() { biometric = b; hasPin = p; });
  }

  Future<void> _toggleBiometric(bool on) async {
    if (!on) {
      await AppLockService.disableBiometric();
    } else {
      if (!await AppLockService.biometricsAvailable()) {
        if (mounted) showSnack(context, 'Biometrics are not available or not set up on this device.');
        return;
      }
      if (!await AppLockService.authenticate('Enable LedgerLens protection')) return;
      await AppLockService.enableBiometric();
    }
    await _refreshLock();
  }

  Future<void> _setPin() async {
    final pin = TextEditingController();
    final confirm = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(hasPin ? 'Change PIN' : 'Set a PIN'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: pin, obscureText: true, keyboardType: TextInputType.number, maxLength: 8, decoration: const InputDecoration(labelText: '4–8 digit PIN', counterText: '')),
          const SizedBox(height: 10),
          TextField(controller: confirm, obscureText: true, keyboardType: TextInputType.number, maxLength: 8, decoration: const InputDecoration(labelText: 'Confirm PIN', counterText: '')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(96, 44)), onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    final valid = RegExp(r'^\d{4,8}$').hasMatch(pin.text) && pin.text == confirm.text;
    final value = pin.text;
    pin.dispose();
    confirm.dispose();
    if (ok != true) return;
    if (!valid) {
      if (mounted) showSnack(context, 'PINs must match and contain 4–8 digits.');
      return;
    }
    await AppLockService.setPin(value);
    await _refreshLock();
    if (mounted) showSnack(context, 'PIN lock enabled.');
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final email = ref.watch(supabaseProvider).auth.currentUser?.email ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          SoftCard(
            child: Row(children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: context.colors.primary.withValues(alpha: 0.12),
                child: Text(email.isEmpty ? '?' : email.characters.first.toUpperCase(), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: context.colors.primary)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Signed in as', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  Text(email, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                ]),
              ),
            ]),
          ),
          const FieldLabel('APPEARANCE'),
          SoftCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Theme', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto_rounded)),
                    ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_rounded)),
                    ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_rounded)),
                  ],
                  selected: {settings.themeMode},
                  onSelectionChanged: (s) => notifier.setThemeMode(s.first),
                ),
              ),
            ]),
          ),
          const FieldLabel('MONEY'),
          SoftCard(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(children: [
              ListTile(
                leading: const IconBadge(icon: Icons.currency_exchange_rounded, color: AppColors.brand, size: 40),
                title: const Text('Default currency', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Used for new transactions, budgets and goals'),
                trailing: CurrencyButton(value: settings.defaultCurrency, onChanged: notifier.setDefaultCurrency),
              ),
              SwitchListTile(
                secondary: const IconBadge(icon: Icons.visibility_off_rounded, color: AppColors.violet, size: 40),
                title: const Text('Hide amounts', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Mask balances across the app'),
                value: settings.hideBalances,
                onChanged: notifier.setHideBalances,
              ),
              ListTile(
                leading: const IconBadge(icon: Icons.category_rounded, color: Color(0xFFEC4899), size: 40),
                title: const Text('Manage categories', style: TextStyle(fontWeight: FontWeight.w700)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/categories'),
              ),
            ]),
          ),
          const FieldLabel('AI RECEIPT READING (FREE, OPTIONAL)'),
          SoftCard(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(children: [
              ListTile(
                leading: const IconBadge(icon: Icons.auto_awesome_rounded, color: AppColors.violet, size: 40),
                title: Text(hasAiKey ? 'Gemini key added' : 'Add a free Gemini key', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(hasAiKey ? (aiModel == null ? 'Tap to replace' : 'Model: $aiModel. Tap to replace') : 'More accurate scans, any language'),
                onTap: _editAiKey,
              ),
              if (hasAiKey)
                ListTile(
                  leading: const IconBadge(icon: Icons.key_off_rounded, color: AppColors.expense, size: 40),
                  title: const Text('Remove key', style: TextStyle(fontWeight: FontWeight.w700)),
                  onTap: () async {
                    await AiKeyStore.clear();
                    await _refreshAi();
                  },
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                child: Text(
                  'Your key stays on this phone in encrypted storage. When AI is used, the receipt photo is sent to Google\u2019s Gemini API; on the free tier Google may use it to improve their products. Without a key, scanning stays fully on-device.',
                  style: TextStyle(fontSize: 12, color: context.mutedText),
                ),
              ),
            ]),
          ),
          const FieldLabel('SECURITY'),
          SoftCard(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(children: [
              SwitchListTile(
                secondary: const IconBadge(icon: Icons.fingerprint_rounded, color: AppColors.income, size: 40),
                title: const Text('Biometric lock', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Ask for fingerprint or face when reopening'),
                value: biometric,
                onChanged: _toggleBiometric,
              ),
              ListTile(
                leading: const IconBadge(icon: Icons.password_rounded, color: AppColors.warning, size: 40),
                title: Text(hasPin ? 'Change PIN' : 'Set a PIN', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Stored as a salted hash in encrypted storage'),
                onTap: _setPin,
              ),
              if (hasPin)
                ListTile(
                  leading: const IconBadge(icon: Icons.no_encryption_gmailerrorred_rounded, color: AppColors.expense, size: 40),
                  title: const Text('Remove PIN', style: TextStyle(fontWeight: FontWeight.w700)),
                  onTap: () async {
                    await AppLockService.removePin();
                    await _refreshLock();
                  },
                ),
            ]),
          ),
          const FieldLabel('DATA'),
          SoftCard(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(children: [
              ListTile(
                leading: const IconBadge(icon: Icons.file_download_outlined, color: Color(0xFF3B82F6), size: 40),
                title: const Text('Export transactions (CSV)', style: TextStyle(fontWeight: FontWeight.w700)),
                onTap: () => exportTransactionsCsv(context, ref),
              ),
              ListTile(
                leading: const IconBadge(icon: Icons.sync_rounded, color: AppColors.slate, size: 40),
                title: const Text('Sync now', style: TextStyle(fontWeight: FontWeight.w700)),
                onTap: () async {
                  await ref.read(transactionRepositoryProvider).syncPending();
                  if (context.mounted) showSnack(context, 'Sync finished');
                },
              ),
            ]),
          ),
          const SizedBox(height: 22),
          OutlinedButton.icon(
            onPressed: () async {
              final ok = await confirmDialog(context, title: 'Sign out?', message: 'Your data stays on this device and syncs again when you sign back in.', confirmLabel: 'Sign out');
              if (!ok) return;
              await ref.read(supabaseProvider).auth.signOut();
              if (context.mounted) context.go('/auth');
            },
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.expense),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign out'),
          ),
          const SizedBox(height: 18),
          Center(child: Text('LedgerLens 1.1.0', style: TextStyle(color: context.mutedText, fontSize: 12))),
        ],
      ),
    );
  }
}
