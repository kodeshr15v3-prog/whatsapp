import 'package:chat_app/Core/storage.dart';
import 'package:chat_app/Feature/Profile/profile_screen.dart';
import 'package:chat_app/Feature/auth/register_screen.dart';
import 'package:chat_app/Feature/auth/login_screen.dart';
import 'package:chat_app/Feature/auth/user_list_screen.dart';
import 'package:chat_app/Feature/chat/chat_list_screen.dart';
import 'package:chat_app/Feature/chat/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

void main() {
  runApp(const ProviderScope(child: MyApp()));
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) async {
      final token = await AppStorage.getToken();
      final isAuth = token != null && token.isNotEmpty;
      final isOnAuth =
          state.matchedLocation == '/login' ||
          state.matchedLocation == '/register';

      if (isAuth && isOnAuth) return '/chats';
      if (!isAuth && !isOnAuth) return '/login';
      return null;
    },

    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      GoRoute(path: '/chats', builder: (_, _) => const ChatListScreen()),
      GoRoute(path: '/users', builder: (_, _) => const UsersListScreen()),
      GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
      GoRoute(
        path: '/chat/:chatId/:name',
        builder: (_, state) => ChatScreen(
          chatId: state.pathParameters['chatId']!,
          name: state.pathParameters['name']!,
        ),
      ),
    ],
  );
});

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'ChatApp',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF25D366)),
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }
}
