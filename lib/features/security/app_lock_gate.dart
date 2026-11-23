import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';
import 'app_lock_service.dart';

/// Covers the app with a lock screen whenever it returns from the background.
/// The keypad is custom (no TextField) because this widget sits above the Navigator and has no Overlay.
class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.child});
  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  bool _ready = false, _locked = false, _hasPin = false, _biometric = false, _authBusy = false;
  int _pinLength = 4;
  String _entered = '';
  int _failures = 0;
  DateTime? _lockedUntil;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load() async {
    await AppLockService.migrateLegacyPin();
    final enabled = await AppLockService.isEnabled();
    _hasPin = await AppLockService.hasPin();
    _biometric = await AppLockService.biometricEnabled();
    _pinLength = await AppLockService.pinLength();
    if (!mounted) return;
    setState(() {
      _locked = enabled;
      _ready = true;
    });
    if (enabled) await _tryBiometric();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _relock();
    } else if (state == AppLifecycleState.resumed && _locked) {
      _tryBiometric();
    }
  }

  Future<void> _relock() async {
    if (_authBusy || !_ready) return;
    final enabled = await AppLockService.isEnabled();
    if (!mounted || !enabled) return;
    _hasPin = await AppLockService.hasPin();
    _biometric = await AppLockService.biometricEnabled();
    _pinLength = await AppLockService.pinLength();
    if (!mounted) return;
    setState(() {
      _locked = true;
      _entered = '';
      _message = null;
    });
  }

  Future<void> _tryBiometric() async {
    if (_authBusy || !_biometric) return;
    _authBusy = true;
    try {
      if (await AppLockService.biometricsAvailable()) {
        final ok = await AppLockService.authenticate('Unlock LedgerLens');
        if (ok && mounted) setState(() => _locked = false);
      }
    } finally {
      _authBusy = false;
    }
  }

  bool get _coolingDown => _lockedUntil != null && DateTime.now().isBefore(_lockedUntil!);

  Future<void> _press(String digit) async {
    if (_coolingDown) {
      setState(() => _message = 'Too many attempts. Try again shortly.');
      return;
    }
    if (_entered.length >= _pinLength) return;
    HapticFeedback.selectionClick();
    setState(() {
      _entered += digit;
      _message = null;
    });
    // Verify exactly once per attempt, when the stored PIN length is reached, so every wrong PIN is counted.
    if (_entered.length == _pinLength) await _verifyEntered();
  }

  Future<void> _verifyEntered() async {
    final ok = await AppLockService.verifyPin(_entered);
    if (!mounted) return;
    if (ok) {
      setState(() {
        _locked = false;
        _entered = '';
        _failures = 0;
        _lockedUntil = null;
      });
      return;
    }
    _failures++;
    HapticFeedback.heavyImpact();
    setState(() {
      _entered = '';
      if (_failures >= 5) {
        _lockedUntil = DateTime.now().add(const Duration(seconds: 30));
        _failures = 0;
        _message = 'Too many attempts. Try again in 30 seconds.';
      } else {
        _message = 'Incorrect PIN';
      }
    });
  }

  void _backspace() {
    if (_entered.isEmpty) return;
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const ColoredBox(color: Color(0xFF0B1020), child: Center(child: CircularProgressIndicator()));
    }
    return Stack(
      children: [
        ExcludeSemantics(excluding: _locked, child: IgnorePointer(ignoring: _locked, child: widget.child)),
        if (_locked) Positioned.fill(child: _buildLockScreen(context)),
      ],
    );
  }

  Widget _buildLockScreen(BuildContext context) {
    return Material(
      color: const Color(0xFF0B1020),
      child: Container(
        decoration: const BoxDecoration(gradient: AppColors.drawerGradient),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_rounded, size: 48, color: Colors.white),
                    const SizedBox(height: 14),
                    const Text('LedgerLens is locked',
                        style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text(
                      _hasPin ? 'Enter your PIN to continue' : 'Use biometrics to continue',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 22),
                    if (_hasPin) ...[
                      SizedBox(
                        height: 18,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (var i = 0; i < _pinLength; i++)
                              Container(
                                margin: const EdgeInsets.symmetric(horizontal: 6),
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: i < _entered.length ? Colors.white : Colors.white24,
                                ),
                              ),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: 28,
                        child: Center(
                          child: Text(_message ?? '', style: const TextStyle(color: Color(0xFFFCA5A5), fontWeight: FontWeight.w600)),
                        ),
                      ),
                      _keypad(),
                    ],
                    if (_biometric) ...[
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: _tryBiometric,
                        icon: const Icon(Icons.fingerprint_rounded, color: Colors.white),
                        label: const Text('Use biometrics', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _keypad() {
    Widget key(String label, {VoidCallback? onTap, IconData? icon}) => Padding(
          padding: const EdgeInsets.all(6),
          child: SizedBox(
            width: 72,
            height: 72,
            child: Material(
              color: Colors.white.withValues(alpha: 0.10),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: Center(
                  child: icon != null
                      ? Icon(icon, color: Colors.white)
                      : Text(label, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ),
        );

    Widget row(List<String> digits) => Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [for (final d in digits) key(d, onTap: () => _press(d))],
        );

    return Column(
      children: [
        row(['1', '2', '3']),
        row(['4', '5', '6']),
        row(['7', '8', '9']),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            key('', icon: Icons.backspace_outlined, onTap: _backspace),
            key('0', onTap: () => _press('0')),
            const SizedBox(width: 84, height: 84),
          ],
        ),
      ],
    );
  }
}
