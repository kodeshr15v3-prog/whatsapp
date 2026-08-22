import 'package:chat_app/Core/constant.dart';
import 'package:dio/dio.dart';
import 'storage.dart';

class ChatRepository {
  final _dio = Dio();

  Future<Map<String, String>> _authHeader() async {
    final token = await AppStorage.getToken();
    return {'Authorization': 'Bearer $token'};
  }

  Future<List<Map<String, dynamic>>> getMyChats() async {
    final res = await _dio.get(
      '${AppConstants.baseUrl}/chats',
      options: Options(headers: await _authHeader()),
    );
    return List<Map<String, dynamic>>.from(res.data);
  }

  Future<String> createChat(String otherEmail) async {
    final res = await _dio.post(
      '${AppConstants.baseUrl}/chats',
      queryParameters: {'other_user_email': otherEmail},
      options: Options(headers: await _authHeader()),
    );
    return res.data['chat_id'];
  }

  Future<List<Map<String, dynamic>>> getAllUsers() async {
    final res = await _dio.get(
      '${AppConstants.baseUrl}/users',
      options: Options(headers: await _authHeader()),
    );
    return List<Map<String, dynamic>>.from(res.data);
  }
}
