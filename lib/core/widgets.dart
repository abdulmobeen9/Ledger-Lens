import 'package:flutter/material.dart';
import 'category_style.dart';
import 'theme.dart';

class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
    this.gradient,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(22);
    return Container(
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? context.colors.surface) : null,
        gradient: gradient,
        borderRadius: radius,
        border: gradient == null ? Border.all(color: context.borderColor) : null,
        boxShadow: context.isDark
            ? null
            : const [BoxShadow(color: Color(0x0F1E293B), blurRadius: 20, offset: Offset(0, 8))],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.actionLabel, this.onAction});
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Text(title, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          ),
          if (actionLabel != null) TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      );
}

class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });
  final IconData icon;
  final String title, message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: context.colors.primary.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 38, color: context.colors.primary),
              ),
              const SizedBox(height: 18),
              Text(title, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800), textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text(message, style: TextStyle(color: context.mutedText), textAlign: TextAlign.center),
              if (actionLabel != null) ...[
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: onAction,
                  style: FilledButton.styleFrom(minimumSize: const Size(180, 48)),
                  child: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      );
}

class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar({super.key, this.icon, this.colorHex, this.size = 46});
  final String? icon;
  final String? colorHex;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = hexColor(colorHex);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(categoryIcon(icon), color: color, size: size * 0.5),
    );
  }
}

class IconBadge extends StatelessWidget {
  const IconBadge({super.key, required this.icon, required this.color, this.size = 44});
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(size * 0.32),
        ),
        child: Icon(icon, color: color, size: size * 0.5),
      );
}

class ThinProgress extends StatelessWidget {
  const ThinProgress({super.key, required this.value, required this.color, this.height = 8, this.trackColor});
  final double value;
  final Color color;
  final double height;
  final Color? trackColor;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: LinearProgressIndicator(
          value: value.isNaN ? 0 : value.clamp(0.0, 1.0),
          minHeight: height,
          backgroundColor: trackColor ?? color.withValues(alpha: 0.15),
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      );
}

/// Rounded menu button for the upper-left corner. Opens the nearest Scaffold's drawer.
class MenuButton extends StatelessWidget {
  const MenuButton({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 14, top: 8, bottom: 8),
        child: Material(
          color: context.colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: context.borderColor),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Scaffold.of(context).openDrawer(),
            child: const Tooltip(message: 'Menu', child: Icon(Icons.menu_rounded)),
          ),
        ),
      );
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
            minimumSize: const Size(96, 44),
            backgroundColor: destructive ? AppColors.expense : null,
          ),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
