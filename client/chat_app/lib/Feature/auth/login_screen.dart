import 'package:chat_app/Provider/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _obscurePassword = true;

  final emailController    = TextEditingController();
  final passwordController = TextEditingController();

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final success = await ref.read(authProvider.notifier).login(
      emailController.text.trim(),
      passwordController.text.trim(),
    );
    if (success && mounted) context.go('/chats');
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final isLoading = authState.status == AuthStatus.loading;

    return Scaffold(
      backgroundColor: const Color.fromRGBO(236, 236, 236, 1),
      appBar: AppBar(
        title: const Text('Welcome Back'),
        backgroundColor: const Color.fromRGBO(236, 236, 236, 1),
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: SingleChildScrollView(
          child: Column(
            children: [
              Card(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    children: const [
                      Text('Login to your account',
                          style: TextStyle(
                              fontSize: 30, fontWeight: FontWeight.bold)),
                      SizedBox(height: 15),
                      Text('Good to see you again',
                          style: TextStyle(fontSize: 11, color: Colors.grey)),
                      SizedBox(height: 23),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Card(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('EMAIL ADDRESS'),
                      _field(emailController, 'name@gmail.com',
                          type: TextInputType.emailAddress),
                      const SizedBox(height: 28),
                      _label('PASSWORD'),
                      TextFormField(
                        controller: passwordController,
                        obscureText: _obscurePassword,
                        obscuringCharacter: '*',
                        decoration: InputDecoration(
                          hintText: 'Enter your password',
                          filled: true,
                          fillColor: const Color.fromRGBO(235, 235, 235, 1),
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility),
                            onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                          ),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(80),
                              borderSide: BorderSide.none),
                          focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(80),
                              borderSide: BorderSide(
                                  color: Colors.green.shade300, width: 1.5)),
                        ),
                      ),
                      const SizedBox(height: 40),

                      if (authState.status == AuthStatus.error)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(authState.error ?? 'Something went wrong',
                              style: const TextStyle(
                                  color: Colors.red, fontSize: 13),
                              textAlign: TextAlign.center),
                        ),

                      Center(
                        child: ElevatedButton(
                          onPressed: isLoading ? null : _login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade300,
                            fixedSize: const Size(240, 45),
                          ),
                          child: isLoading
                              ? const SizedBox(
                                  width: 20, height: 20,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : const Text('Login',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 20)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () => context.go('/register'),
                child: const Text("Don't have account? Register",
                    style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                        fontWeight: FontWeight.w500)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text('   $text',
            style: const TextStyle(
                color: Colors.grey,
                fontWeight: FontWeight.w500,
                fontSize: 12)),
      );

  Widget _field(TextEditingController ctrl, String hint,
          {TextInputType type = TextInputType.text}) =>
      TextFormField(
        controller: ctrl,
        keyboardType: type,
        decoration: InputDecoration(
          hintText: hint,
          filled: true,
          fillColor: const Color.fromRGBO(235, 235, 235, 1),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(80),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(80),
              borderSide:
                  BorderSide(color: Colors.green.shade300, width: 1.5)),
        ),
      );
}