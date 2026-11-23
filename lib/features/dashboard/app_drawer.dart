import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/remote/transaction_repository.dart';
import '../settings/export_service.dart';

/// Opened from the menu button in the dashboard's upper-left corner. Holds every feature of the app.
class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(supabaseProvider).auth.currentUser;
    final email = user?.email ?? 'Signed in';
    final name = email.contains('@') ? email.split('@').first : email;
    final sync = ref.watch(syncStatusProvider).valueOrNull;

    void go(String route) {
      Navigator.pop(context);
      context.push(route);
    }

    return Drawer(
      width: 310,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(gradient: AppColors.drawerGradient),
            padding: EdgeInsets.fromLTRB(22, MediaQuery.of(context).padding.top + 24, 22, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  child: Text(
                    name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 14),
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(email, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 14),
                _SyncPill(status: sync),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              children: [
                _Tile(icon: Icons.dashboard_rounded, label: 'Dashboard', color: AppColors.brand, selected: true, onTap: () => Navigator.pop(context)),
                _Tile(icon: Icons.receipt_long_rounded, label: 'Transactions', color: const Color(0xFF3B82F6), onTap: () => go('/transactions')),
                _Tile(icon: Icons.insights_rounded, label: 'Reports & analytics', color: AppColors.violet, onTap: () => go('/reports')),
                const _Section('QUICK ADD'),
                _Tile(icon: Icons.south_west_rounded, label: 'Add income', color: AppColors.income, onTap: () => go('/add?type=income')),
                _Tile(icon: Icons.north_east_rounded, label: 'Add expense', color: AppColors.expense, onTap: () => go('/add?type=expense')),
                _Tile(icon: Icons.document_scanner_rounded, label: 'Scan receipt', color: const Color(0xFF0EA5E9), onTap: () => go('/scan')),
                const _Section('PLANNING'),
                _Tile(icon: Icons.donut_large_rounded, label: 'Budgets', color: AppColors.warning, onTap: () => go('/budgets')),
                _Tile(icon: Icons.savings_rounded, label: 'Savings goals', color: const Color(0xFF14B8A6), onTap: () => go('/goals')),
                _Tile(icon: Icons.category_rounded, label: 'Categories', color: const Color(0xFFEC4899), onTap: () => go('/categories')),
                const _Section('DATA & SECURITY'),
                _Tile(
                  icon: Icons.sync_rounded,
                  label: 'Sync now',
                  color: AppColors.slate,
                  onTap: () async {
                    Navigator.pop(context);
                    await ref.read(transactionRepositoryProvider).syncPending();
                    if (context.mounted) showSnack(context, 'Sync finished');
                  },
                ),
                _Tile(
                  icon: Icons.file_download_outlined,
                  label: 'Export CSV',
                  color: AppColors.slate,
                  onTap: () async {
                    Navigator.pop(context);
                    await exportTransactionsCsv(context, ref);
                  },
                ),
                _Tile(icon: Icons.settings_rounded, label: 'Settings & security', color: AppColors.slate, onTap: () => go('/settings')),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _Tile(
                icon: Icons.logout_rounded,
                label: 'Sign out',
                color: AppColors.expense,
                onTap: () async {
                  final ok = await confirmDialog(context, title: 'Sign out?', message: 'Your data stays on this device and syncs again when you sign back in.', confirmLabel: 'Sign out');
                  if (!ok) return;
                  await ref.read(supabaseProvider).auth.signOut();
                  if (context.mounted) {
                    Navigator.pop(context);
                    context.go('/auth');
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 6),
        child: Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: context.mutedText)),
      );
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.label, required this.color, required this.onTap, this.selected = false});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Material(
          color: selected ? context.colors.primary.withValues(alpha: 0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                IconBadge(icon: icon, color: color, size: 38),
                const SizedBox(width: 14),
                Expanded(child: Text(label, style: TextStyle(fontWeight: selected ? FontWeight.w800 : FontWeight.w600, fontSize: 15))),
                Icon(Icons.chevron_right_rounded, color: context.mutedText, size: 20),
              ]),
            ),
          ),
        ),
      );
}

class _SyncPill extends StatelessWidget {
  const _SyncPill({required this.status});
  final SyncStatus? status;

  @override
  Widget build(BuildContext context) {
    final phase = status?.phase ?? SyncPhase.idle;
    final (icon, label) = switch (phase) {
      SyncPhase.syncing => (Icons.sync_rounded, 'Syncing…'),
      SyncPhase.synced => (Icons.cloud_done_rounded, 'Synced ${Dates.relative(status?.lastSuccess)}'),
      SyncPhase.error => (Icons.cloud_off_rounded, 'Will retry when online'),
      SyncPhase.idle => (Icons.cloud_queue_rounded, 'Offline-first • saved on device'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: Colors.white),
        const SizedBox(width: 7),
        Flexible(child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}
