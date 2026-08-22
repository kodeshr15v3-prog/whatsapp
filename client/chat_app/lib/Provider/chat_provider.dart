import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chat_app/Core/chat_repository.dart';

final chatRepositoryProvider = Provider((ref) => ChatRepository());

final myChatsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final repo = ref.read(chatRepositoryProvider);
  return repo.getMyChats();
});