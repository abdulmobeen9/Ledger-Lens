import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final sharedPrefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError('Override sharedPrefsProvider in main()'));

class AppSettings {
  const AppSettings({this.themeMode = ThemeMode.system, this.defaultCurrency = 'USD', this.hideBalances = false});
  final ThemeMode themeMode;
  final String defaultCurrency;
  final bool hideBalances;

  AppSettings copyWith({ThemeMode? themeMode, String? defaultCurrency, bool? hideBalances}) => AppSettings(
        themeMode: themeMode ?? this.themeMode,
        defaultCurrency: defaultCurrency ?? this.defaultCurrency,
        hideBalances: hideBalances ?? this.hideBalances,
      );
}

class SettingsNotifier extends Notifier<AppSettings> {
  static const _themeKey = 'theme_mode';
  static const _currencyKey = 'default_currency';
  static const _hideKey = 'hide_balances';

  @override
  AppSettings build() {
    final prefs = ref.read(sharedPrefsProvider);
    final theme = switch (prefs.getString(_themeKey)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    return AppSettings(
      themeMode: theme,
      defaultCurrency: prefs.getString(_currencyKey) ?? 'USD',
      hideBalances: prefs.getBool(_hideKey) ?? false,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await ref.read(sharedPrefsProvider).setString(_themeKey, mode.name);
  }

  Future<void> setDefaultCurrency(String currency) async {
    state = state.copyWith(defaultCurrency: currency);
    await ref.read(sharedPrefsProvider).setString(_currencyKey, currency);
  }

  Future<void> setHideBalances(bool hide) async {
    state = state.copyWith(hideBalances: hide);
    await ref.read(sharedPrefsProvider).setBool(_hideKey, hide);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
