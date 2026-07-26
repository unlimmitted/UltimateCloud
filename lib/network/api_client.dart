import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiClient {
  static const String baseUrl = 'https://ulcloud.ru';
  static const String _cookieKey = 'auth_cookie';

  static String? _cookie;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _cookie = prefs.getString(_cookieKey);
  }

  static Future<String?> get cookie async {
    if (_cookie != null && _cookie!.isNotEmpty) {
      return _cookie;
    }

    final prefs = await SharedPreferences.getInstance();
    _cookie = prefs.getString(_cookieKey);
    return _cookie;
  }

  static Future<void> saveCookieFromResponse(http.Response response) async {
    final sessionCookie =
        _extractCookieFromSetCookieHeader(response.headers['set-cookie']) ??
        _extractCookieFromBody(response.body);

    if (sessionCookie == null || sessionCookie.isEmpty) {
      return;
    }

    _cookie = sessionCookie;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cookieKey, sessionCookie);
  }

  static String? _extractCookieFromSetCookieHeader(String? setCookie) {
    if (setCookie == null || setCookie.isEmpty) {
      return null;
    }

    // Spring Session обычно присылает SESSION=...
    // Старый вариант мог присылать JSESSIONID=...
    final match = RegExp(r'(SESSION|JSESSIONID)=([^;,\s]+)').firstMatch(setCookie);
    if (match == null) {
      return null;
    }

    return '${match.group(1)}=${match.group(2)}';
  }

  static String? _extractCookieFromBody(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        return null;
      }

      final sessionCookie = decoded['sessionCookie']?.toString();
      if (sessionCookie != null && sessionCookie.isNotEmpty) {
        return sessionCookie;
      }

      final cookieName = decoded['cookieName']?.toString();
      final sessionId = decoded['sessionId']?.toString();

      if (cookieName != null &&
          cookieName.isNotEmpty &&
          sessionId != null &&
          sessionId.isNotEmpty) {
        return '$cookieName=$sessionId';
      }

      if (sessionId != null && sessionId.isNotEmpty) {
        return 'SESSION=$sessionId';
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearCookie() async {
    _cookie = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cookieKey);
  }

  static Future<Map<String, String>> headers({
    Map<String, String>? headers,
    bool json = false,
  }) async {
    final result = <String, String>{
      if (json) 'Content-Type': 'application/json',
      ...?headers,
    };

    final currentCookie = await cookie;
    if (currentCookie != null && currentCookie.isNotEmpty) {
      result['Cookie'] = currentCookie;
    }

    return result;
  }

  static Uri uri(
    String path, [
    Map<String, String>? queryParameters,
  ]) {
    return Uri.https(
      baseUrl.replaceFirst('https://', '').replaceFirst('http://', ''),
      path,
      queryParameters,
    );
  }

  static Future<http.Response> get(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    return http.get(
      uri,
      headers: await ApiClient.headers(headers: headers),
    );
  }

  static Future<http.Response> post(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    bool jsonBody = false,
  }) async {
    return http.post(
      uri,
      headers: await ApiClient.headers(headers: headers, json: jsonBody),
      body: jsonBody && body is Map ? jsonEncode(body) : body,
    );
  }
}
