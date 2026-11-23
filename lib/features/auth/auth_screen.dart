import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final formKey = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  bool loading = false, signup = false, obscure = true;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!formKey.currentState!.validate()) return;
    setState(() => loading = true);
    try {
      final auth = Supabase.instance.client.auth;
      if (signup) {
        final res = await auth.signUp(email: email.text.trim(), password: password.text);
        if (res.session == null && mounted) {
          showSnack(context, 'Check your email to confirm your account, then sign in.');
          setState(() => signup = false);
          return;
        }
      } else {
        await auth.signInWithPassword(email: email.text.trim(), password: password.text);
      }
      if (mounted) context.go('/');
    } on AuthException catch (e) {
      if (mounted) showSnack(context, e.message);
    } catch (e) {
      if (mounted) showSnack(context, 'Something went wrong. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> forgotPassword() async {
    final address = email.text.trim();
    if (!address.contains('@')) {
      showSnack(context, 'Enter your email above first.');
      return;
    }
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(address);
      if (mounted) showSnack(context, 'If that account exists, a reset link is on its way.');
    } on AuthException catch (e) {
      if (mounted) showSnack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SingleChildScrollView(
          child: Column(children: [
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: AppColors.heroGradient,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(36)),
              ),
              padding: EdgeInsets.fromLTRB(28, MediaQuery.of(context).padding.top + 48, 28, 44),
              child: const Column(children: [
                Icon(Icons.account_balance_wallet_rounded, size: 60, color: Colors.white),
                SizedBox(height: 16),
                Text('LedgerLens', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                SizedBox(height: 6),
                Text('Your money, clear and in your pocket', style: TextStyle(color: Colors.white70, fontSize: 15)),
              ]),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: formKey,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text(signup ? 'Create your account' : 'Welcome back', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
                        validator: (v) => (v ?? '').trim().contains('@') ? null : 'Enter a valid email',
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: password,
                        obscureText: obscure,
                        autofillHints: const [AutofillHints.password],
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(onPressed: () => setState(() => obscure = !obscure), icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined)),
                        ),
                        validator: (v) => (v ?? '').length >= 6 ? null : 'Use at least 6 characters',
                      ),
                      if (!signup) Align(alignment: Alignment.centerRight, child: TextButton(onPressed: forgotPassword, child: const Text('Forgot password?'))),
                      const SizedBox(height: 8),
                      FilledButton(onPressed: loading ? null : submit, child: Text(loading ? 'Please wait…' : (signup ? 'Create account' : 'Sign in'))),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: loading
                            ? null
                            : () async {
                                try {
                                  await Supabase.instance.client.auth.signInWithOAuth(OAuthProvider.google, redirectTo: 'io.supabase.ledgerlens://login-callback/');
                                } on AuthException catch (e) {
                                  if (mounted) showSnack(context, e.message);
                                }
                              },
                        icon: const Icon(Icons.g_mobiledata_rounded, size: 30),
                        label: const Text('Continue with Google'),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => setState(() => signup = !signup),
                        child: Text(signup ? 'Already have an account? Sign in' : 'New here? Create an account'),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ]),
        ),
      );
}
