import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier, kIsWeb;
import 'package:genui/genui.dart';
import 'package:http/http.dart' as http;

/// a2ui v0.9 ContentGenerator
///
/// 1. server.py /api/generate 호출 → A2UI v0.9 스펙 JSON 수신
/// 2. v0.9 스펙 → GenUI SDK 형식 변환 (createSurface→beginRendering 등)
/// 3. GenUI A2uiMessageProcessor에 전달

class A2uiContentGenerator implements ContentGenerator {
  final _a2uiController = StreamController<A2uiMessage>.broadcast();
  final _textController = StreamController<String>.broadcast();
  final _errorController = StreamController<ContentGeneratorError>.broadcast();
  final _isProcessing = ValueNotifier<bool>(false);
  String? lastRawJson;

  static String get _baseUrl {
    if (kIsWeb) {
      final uri = Uri.base;
      return '${uri.scheme}://${uri.host}:3002';
    }
    return 'http://localhost:3002';
  }

  @override
  Stream<A2uiMessage> get a2uiMessageStream => _a2uiController.stream;

  @override
  Stream<String> get textResponseStream => _textController.stream;

  @override
  Stream<ContentGeneratorError> get errorStream => _errorController.stream;

  @override
  ValueListenable<bool> get isProcessing => _isProcessing;

  @override
  Future<void> sendRequest(
    ChatMessage message, {
    Iterable<ChatMessage>? history,
    A2UiClientCapabilities? clientCapabilities,
  }) async {
    if (message is! UserMessage) return;

    final userText = message.parts
        .whereType<TextPart>()
        .map((p) => p.text)
        .join(' ');
    if (userText.isEmpty) return;

    _isProcessing.value = true;

    try {
      final historyJson = <Map<String, String>>[];
      if (history != null) {
        for (final msg in history) {
          if (msg is UserMessage) {
            final t = msg.parts.whereType<TextPart>().map((p) => p.text).join(' ');
            if (t.isNotEmpty) historyJson.add({'role': 'user', 'content': t});
          } else if (msg is AiTextMessage) {
            historyJson.add({'role': 'assistant', 'content': msg.text});
          }
        }
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/api/generate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'message': userText,
          'history': historyJson,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final spokenText = data['spoken_text'] as String? ?? '';
        final a2uiMessages = data['a2ui'] as List<dynamic>? ?? [];

        // Raw JSON 저장 (v0.9 스펙 원본)
        lastRawJson = const JsonEncoder.withIndent('  ').convert(data);

        // 텍스트 응답
        if (spokenText.isNotEmpty) {
          _textController.add(spokenText);
        }

        // v0.9 스펙 JSON → GenUI SDK 형식으로 변환 후 전달
        print('[A2UI] Processing ${a2uiMessages.length} v0.9 messages');
        for (final msgJson in a2uiMessages) {
          try {
            final sdkMsg = _convertV09ToSdk(Map<String, dynamic>.from(msgJson as Map));
            if (sdkMsg != null) {
              final a2uiMsg = A2uiMessage.fromJson(sdkMsg);
              print('[A2UI] Converted & parsed: ${a2uiMsg.runtimeType}');
              _a2uiController.add(a2uiMsg);
            }
          } catch (e, st) {
            print('[A2UI] Parse error: $e');
            print('[A2UI] Original JSON: $msgJson');
          }
        }
      } else {
        _errorController.add(ContentGeneratorError(
          'Server error: ${response.statusCode}',
        ));
      }
    } catch (e, st) {
      _errorController.add(ContentGeneratorError(e, st));
    } finally {
      _isProcessing.value = false;
    }
  }

  /// A2UI v0.9 스펙 → GenUI SDK 형식 변환
  ///
  /// v0.9 스펙:
  ///   createSurface → beginRendering
  ///   updateComponents → surfaceUpdate
  ///   component: "Text" (문자열) + 속성 flat → component: {"Text": {속성}} (객체)
  ///   children: ["id1"] → children: {"explicitList": ["id1"]}
  static Map<String, dynamic>? _convertV09ToSdk(Map<String, dynamic> msg) {
    // createSurface → beginRendering
    if (msg.containsKey('createSurface')) {
      final cs = Map<String, dynamic>.from(msg['createSurface'] as Map);
      return {
        'beginRendering': {
          'surfaceId': cs['surfaceId'],
          'root': 'root', // v0.9에서는 root가 별도 지정 안 될 수 있음
          if (cs['catalogId'] != null) 'catalogId': cs['catalogId'],
        },
      };
    }

    // updateComponents → surfaceUpdate (+ component 형식 변환)
    if (msg.containsKey('updateComponents')) {
      final uc = Map<String, dynamic>.from(msg['updateComponents'] as Map);
      final components = (uc['components'] as List<dynamic>? ?? [])
          .map((c) => _convertComponentToSdk(Map<String, dynamic>.from(c as Map)))
          .toList();
      return {
        'surfaceUpdate': {
          'surfaceId': uc['surfaceId'],
          'components': components,
        },
      };
    }

    // updateDataModel → dataModelUpdate
    if (msg.containsKey('updateDataModel')) {
      final udm = Map<String, dynamic>.from(msg['updateDataModel'] as Map);
      return {
        'dataModelUpdate': {
          'surfaceId': udm['surfaceId'],
          'path': udm['path'],
          'contents': udm['value'],
        },
      };
    }

    // deleteSurface → 그대로
    if (msg.containsKey('deleteSurface')) {
      return msg;
    }

    // 이미 SDK 형식인 경우 (beginRendering, surfaceUpdate 등) 그대로 통과
    if (msg.containsKey('beginRendering') || msg.containsKey('surfaceUpdate') ||
        msg.containsKey('dataModelUpdate') || msg.containsKey('deleteSurface')) {
      return msg;
    }

    print('[A2UI] Unknown message type: ${msg.keys}');
    return null;
  }

  /// v0.9 component 형식 → SDK 형식
  ///
  /// v0.9: {"id":"card1", "component":"WeatherCard", "city":"Seoul"}
  /// SDK:  {"id":"card1", "component":{"WeatherCard":{"city":"Seoul"}}}
  static Map<String, dynamic> _convertComponentToSdk(Map<String, dynamic> comp) {
    final id = comp['id'] as String;
    final component = comp['component'];
    final weight = comp['weight'] as int?;

    // 이미 SDK 형식 (component가 Map)
    if (component is Map) {
      // children explicitList 변환
      final converted = Map<String, dynamic>.from(component);
      for (final key in converted.keys) {
        if (converted[key] is Map) {
          final inner = Map<String, dynamic>.from(converted[key] as Map);
          if (inner.containsKey('children') && inner['children'] is List) {
            inner['children'] = {'explicitList': inner['children']};
            converted[key] = inner;
          }
        }
      }
      return {
        'id': id,
        'component': converted,
        if (weight != null) 'weight': weight,
      };
    }

    // v0.9 형식 (component가 String)
    if (component is String) {
      // id, component, weight 제외한 나머지가 props
      final props = Map<String, dynamic>.from(comp)
        ..remove('id')
        ..remove('component')
        ..remove('weight');

      // children 배열 → explicitList 변환
      if (props.containsKey('children') && props['children'] is List) {
        props['children'] = {'explicitList': props['children']};
      }

      // v0.9 variant → GenUI usageHint 매핑
      if (props.containsKey('variant') && !props.containsKey('usageHint')) {
        props['usageHint'] = props.remove('variant');
      }

      // GenUI stringReference 필드: plain String → {"literalString": value}
      const stringRefFields = {
        'Text': ['text'],
        'Image': ['url'],
        'Video': ['url'],
        'AudioPlayer': ['url'],
        'TextField': ['text', 'label'],
        'CheckBox': ['label'],
        'Icon': ['name'],
        'DateTimeInput': ['value'],
      };
      final refFields = stringRefFields[component];
      if (refFields != null) {
        for (final field in refFields) {
          if (props[field] is String) {
            props[field] = {'literalString': props[field]};
          }
        }
      }

      // Button action 변환: v0.9 functionCall → GenUI {name, context}
      if (props.containsKey('action') && props['action'] is Map) {
        final action = Map<String, dynamic>.from(props['action'] as Map);
        if (action.containsKey('functionCall') && action['functionCall'] is Map) {
          final fc = Map<String, dynamic>.from(action['functionCall'] as Map);
          props['action'] = {
            'name': fc['call'] as String? ?? 'unknown',
            if (fc['args'] is Map)
              'context': (fc['args'] as Map).entries.map((e) => {
                'key': e.key,
                'value': e.value is String ? {'literalString': e.value}
                       : e.value is num    ? {'literalNumber': e.value}
                       : e.value is bool   ? {'literalBoolean': e.value}
                       : {'literalString': jsonEncode(e.value)},
              }).toList(),
          };
        } else if (!action.containsKey('name')) {
          props['action'] = {'name': 'action'};
        }
      }

      return {
        'id': id,
        'component': {component: props},
        if (weight != null) 'weight': weight,
      };
    }

    // fallback
    return comp;
  }

  @override
  void dispose() {
    _a2uiController.close();
    _textController.close();
    _errorController.close();
  }
}
