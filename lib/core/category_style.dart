import 'package:flutter/material.dart';

const Map<String, IconData> kCategoryIcons = {
  'category': Icons.category_rounded,
  'payments': Icons.payments_rounded,
  'trending_up': Icons.trending_up_rounded,
  'shopping_basket': Icons.shopping_basket_rounded,
  'directions_car': Icons.directions_car_rounded,
  'bolt': Icons.bolt_rounded,
  'restaurant': Icons.restaurant_rounded,
  'home': Icons.home_rounded,
  'health': Icons.medical_services_rounded,
  'school': Icons.school_rounded,
  'movie': Icons.movie_rounded,
  'flight': Icons.flight_rounded,
  'shopping_bag': Icons.shopping_bag_rounded,
  'savings': Icons.savings_rounded,
  'fitness': Icons.fitness_center_rounded,
  'pets': Icons.pets_rounded,
  'phone': Icons.phone_android_rounded,
  'gift': Icons.card_giftcard_rounded,
  'build': Icons.build_rounded,
  'work': Icons.work_rounded,
};

const List<String> kCategoryColors = [
  '#4F46E5', '#7C3AED', '#EC4899', '#EF4444', '#F59E0B',
  '#10B981', '#14B8A6', '#3B82F6', '#64748B', '#16A34A',
];

const List<Color> kChartPalette = [
  Color(0xFF4F46E5), Color(0xFFEC4899), Color(0xFFF59E0B), Color(0xFF10B981),
  Color(0xFF3B82F6), Color(0xFF8B5CF6), Color(0xFFEF4444), Color(0xFF14B8A6),
];

IconData categoryIcon(String? name) => kCategoryIcons[name] ?? Icons.category_rounded;

Color hexColor(String? hex, {Color fallback = const Color(0xFF64748B)}) {
  if (hex == null) return fallback;
  var h = hex.replaceAll('#', '');
  if (h.length == 6) h = 'FF$h';
  final value = int.tryParse(h, radix: 16);
  return value == null ? fallback : Color(value);
}
