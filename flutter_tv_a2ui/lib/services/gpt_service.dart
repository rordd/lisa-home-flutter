import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import '../models/models.dart';

/// a2ui v0.9 — GPT + Stitch 통합 서비스
/// server.py의 /api/generate를 호출하여
/// GPT 의도 파악 + Stitch HTML 생성을 한번에 처리

class GPTService {
  static String get _baseUrl {
    if (kIsWeb) {
      final uri = Uri.base;
      return '${uri.scheme}://${uri.host}:${uri.port}';
    }
    return 'http://localhost:3002';
  }

  /// /api/generate 호출 → GPT 의도 분석 + Stitch HTML 생성
  static Future<StitchResponse> generate(
    String userInput, {
    List<ChatMessage>? history,
  }) async {
    final historyJson = <Map<String, String>>[];
    if (history != null) {
      final recent = history.length > 6
          ? history.sublist(history.length - 6)
          : history;
      for (final msg in recent) {
        if (msg.isLoading) continue;
        historyJson.add({
          'role': msg.role == MessageRole.user ? 'user' : 'assistant',
          'content': msg.content,
        });
      }
    }

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/generate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'message': userInput,
          'history': historyJson,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return StitchResponse(
          spokenText: data['spoken_text'] as String? ?? '',
          html: data['html'] as String? ?? '',
          showChat: data['show_chat'] as bool? ?? false,
        );
      } else {
        return StitchResponse(
          spokenText: '서버 응답 오류가 발생했어요. (${response.statusCode})',
          html: '',
          showChat: true,
        );
      }
    } catch (e) {
      return StitchResponse(
        spokenText: '연결에 문제가 있어요.',
        html: '',
        showChat: true,
      );
    }
  }
}
