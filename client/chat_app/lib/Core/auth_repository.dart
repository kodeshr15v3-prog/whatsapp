import 'package:chat_app/Core/constant.dart';
import 'package:dio/dio.dart';
import '../core/storage.dart';

class AuthRepository {
  final _dio = Dio();

  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final res = await _dio.post(
      '${AppConstants.baseUrl}/signup',
      data: {'name': name, 'email': email, 'password': password},
    );
    final token = res.data['access_token'];
    await AppStorage.saveToken(token);

    final me = await _dio.get(
      '${AppConstants.baseUrl}/me',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    await AppStorage.saveUserId(me.data['id']);
  }

  Future<void> login({
    required String email,
    required String password,
  }) async {
    final res = await _dio.post(
      '${AppConstants.baseUrl}/login',
      data: {'email': email, 'password': password},
    );
    final token = res.data['access_token'];
    await AppStorage.saveToken(token);

    final me = await _dio.get(
      '${AppConstants.baseUrl}/me',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    await AppStorage.saveUserId(me.data['id']);
  }

  Future<void> logout() => AppStorage.clear();
}