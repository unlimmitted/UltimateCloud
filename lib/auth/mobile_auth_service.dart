import 'dart:convert';

import '../network/api_client.dart';

class MobileAuthService {
  Future<bool> hasSavedSession() async {
    final savedCookie = await ApiClient.cookie;
    if (savedCookie == null || savedCookie.isEmpty) {
      return false;
    }

    try {
      final response = await ApiClient.get(
        ApiClient.uri('/api/v1/auth/me'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return true;
      }

      await ApiClient.clearCookie();
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<String?> login({
    required String username,
    required String password,
  }) async {
    try {
      final response = await ApiClient.post(
        ApiClient.uri('/api/v1/auth/login'),
        jsonBody: true,
        body: {
          'username': username,
          'password': password,
        },
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        await ApiClient.saveCookieFromResponse(response);

        final savedCookie = await ApiClient.cookie;
        if (savedCookie == null || savedCookie.isEmpty) {
          return 'Сервер авторизовал, но не вернул SESSION';
        }

        final meResponse = await ApiClient.get(
          ApiClient.uri('/api/v1/auth/me'),
        ).timeout(const Duration(seconds: 10));

        if (meResponse.statusCode != 200) {
          return 'Сессия не сохранилась на сервере (${meResponse.statusCode}), cookie=$savedCookie';
        }

        return null;
      }

      final decoded = utf8.decode(response.bodyBytes);
      final json = jsonDecode(decoded);

      if (json is Map && json['message'] != null) {
        return json['message'].toString();
      }

      return 'Ошибка авторизации';
    } catch (e) {
      return 'Не удалось подключиться к серверу: $e';
    }
  }

  Future<void> logout() async {
    try {
      await ApiClient.post(ApiClient.uri('/api/v1/auth/logout'));
    } catch (_) {
      // ignore
    }

    await ApiClient.clearCookie();
  }
}
