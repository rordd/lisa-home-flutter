import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier, kIsWeb;
import 'package:genui/genui.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Lisa Gateway WebSocket ContentGenerator
///
/// WebSocket 연결: ws://host:port/app?session_id=xxx
///
/// 프로토콜:
///   session_start → sessionId 저장
///   a2ui          → messages 누적 (아직 emit 안 함)
///   done          → 누적 a2ui 변환+emit, full_response 텍스트 emit, isProcessing=false
///   error         → errorStream emit, isProcessing=false
///
/// 기존 A2uiContentGenerator의 _convertV09ToSdk / _convertComponentToSdk 변환 로직 재사용.

class LisaWsContentGenerator implements ContentGenerator {
  final String _wsUrl;
  late final String _resolvedUrl;
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  String? _sessionId;

  final _a2uiController = StreamController<A2uiMessage>.broadcast();
  final _textController = StreamController<String>.broadcast();
  final _errorController = StreamController<ContentGeneratorError>.broadcast();
  final _isProcessing = ValueNotifier<bool>(false);

  // a2ui 프레임 누적 버퍼 (done 프레임에서 일괄 emit)
  final List<Map<String, dynamic>> _pendingA2ui = [];

  // 재연결
  int _reconnectAttempts = 0;
  static const _maxReconnectAttempts = 5;
  static const _reconnectDelay = Duration(seconds: 3);
  bool _disposed = false;

  String? lastRawJson;

  /// [wsUrl]은 기본 WebSocket URL (예: 'ws://192.168.0.3:42617/app').
  /// 웹에서는 브라우저의 현재 호스트로 자동 대체합니다.
  LisaWsContentGenerator(this._wsUrl) {
    if (kIsWeb) {
      // 브라우저 현재 호스트 사용 (10.x.x.x 등 실제 접속 IP에 맞춤)
      final parsed = Uri.parse(_wsUrl);
      final browserHost = Uri.base.host;
      _resolvedUrl = parsed.replace(host: browserHost).toString();
    } else {
      _resolvedUrl = _wsUrl;
    }
    _connect();
  }

  @override
  Stream<A2uiMessage> get a2uiMessageStream => _a2uiController.stream;

  @override
  Stream<String> get textResponseStream => _textController.stream;

  @override
  Stream<ContentGeneratorError> get errorStream => _errorController.stream;

  @override
  ValueListenable<bool> get isProcessing => _isProcessing;

  // ── WebSocket 연결 ──────────────────────────────

  void _connect() {
    if (_disposed) return;

    final uri = _sessionId != null
        ? Uri.parse(_resolvedUrl).replace(queryParameters: {'session_id': _sessionId!})
        : Uri.parse(_resolvedUrl);

    print('[LisaWS] Connecting to $uri');

    try {
      _channel = WebSocketChannel.connect(uri);

      // web_socket_channel 3.x: ready future가 완료되어야 실제 연결 성공
      _channel!.ready.then((_) {
        print('[LisaWS] WebSocket ready');
        _reconnectAttempts = 0;
      }).catchError((e) {
        print('[LisaWS] WebSocket ready error: $e');
        _channel = null;
        _scheduleReconnect();
      });

      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );
    } catch (e, st) {
      print('[LisaWS] Connection error: $e');
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      print('[LisaWS] Max reconnect attempts reached');
      _errorController.add(ContentGeneratorError(
        'WebSocket connection failed after $_maxReconnectAttempts attempts',
      ));
      return;
    }
    _reconnectAttempts++;
    print('[LisaWS] Reconnecting in ${_reconnectDelay.inSeconds}s (attempt $_reconnectAttempts/$_maxReconnectAttempts)');
    Future.delayed(_reconnectDelay, _connect);
  }

  void _onError(Object error, [StackTrace? st]) {
    print('[LisaWS] Stream error: $error');
    if (_isProcessing.value) {
      _isProcessing.value = false;
      _pendingA2ui.clear();
      _errorController.add(ContentGeneratorError(error, st));
    }
  }

  void _onDone() {
    print('[LisaWS] Connection closed');
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    if (_isProcessing.value) {
      _isProcessing.value = false;
      _pendingA2ui.clear();
      _errorController.add(ContentGeneratorError('WebSocket connection lost'));
    }
    _scheduleReconnect();
  }

  // ── 수신 메시지 핸들러 ────────────────────────────

  void _onMessage(dynamic raw) {
    if (raw is! String) return;

    Map<String, dynamic> frame;
    try {
      frame = jsonDecode(raw) as Map<String, dynamic>;
    } catch (e) {
      print('[LisaWS] Invalid JSON: $raw');
      return;
    }

    final type = frame['type'] as String? ?? '';

    switch (type) {
      case 'session_start':
        _sessionId = frame['session_id'] as String?;
        final resumed = frame['resumed'] as bool? ?? false;
        final count = frame['message_count'] as int? ?? 0;
        print('[LisaWS] session_start: id=$_sessionId resumed=$resumed messages=$count');

      case 'a2ui':
        // 메시지 누적 — done 프레임에서 일괄 emit
        final messages = frame['messages'] as List<dynamic>? ?? [];
        print('[LisaWS] a2ui: ${messages.length} messages (buffering)');
        for (final msg in messages) {
          if (msg is Map) {
            _pendingA2ui.add(Map<String, dynamic>.from(msg));
          }
        }

      case 'done':
        final fullResponse = frame['full_response'] as String? ?? '';
        print('[LisaWS] done: ${_pendingA2ui.length} buffered a2ui, text=${fullResponse.length} chars');

        // Raw JSON 저장 (디버깅용)
        if (_pendingA2ui.isNotEmpty) {
          lastRawJson = const JsonEncoder.withIndent('  ').convert({
            'a2ui': _pendingA2ui,
            'spoken_text': fullResponse,
          });
        }

        // 누적된 a2ui 메시지 변환 + emit
        for (final msgJson in _pendingA2ui) {
          try {
            final sdkMsg = _convertV09ToSdk(msgJson);
            if (sdkMsg != null) {
              final a2uiMsg = A2uiMessage.fromJson(sdkMsg);
              print('[LisaWS] Converted & parsed: ${a2uiMsg.runtimeType}');
              _a2uiController.add(a2uiMsg);
            }
          } catch (e) {
            print('[LisaWS] Parse error: $e');
            print('[LisaWS] Original JSON: $msgJson');
          }
        }
        _pendingA2ui.clear();

        // 텍스트 응답
        if (fullResponse.isNotEmpty) {
          _textController.add(fullResponse);
        }

        _isProcessing.value = false;

      case 'error':
        final message = frame['message'] as String? ?? 'Unknown error';
        print('[LisaWS] error: $message');
        _pendingA2ui.clear();
        _isProcessing.value = false;
        _errorController.add(ContentGeneratorError(message));

      case 'connected':
        print('[LisaWS] connected: ${frame['message']}');

      default:
        print('[LisaWS] Unknown frame type: $type');
    }
  }

  // ── 송신 ──────────────────────────────────────

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
    _pendingA2ui.clear();

    final payload = jsonEncode({
      'type': 'message',
      'content': userText,
    });

    print('[LisaWS] Sending: $payload');

    if (_channel == null) {
      _isProcessing.value = false;
      _errorController.add(ContentGeneratorError('WebSocket not connected'));
      return;
    }

    try {
      _channel!.sink.add(payload);
    } catch (e, st) {
      _isProcessing.value = false;
      _errorController.add(ContentGeneratorError(e, st));
    }
  }

  /// A2UI 액션 전송 (카드 인터랙션)
  void sendAction({
    required String surfaceId,
    required String name,
    String? sourceComponentId,
    Map<String, dynamic>? context,
    Map<String, dynamic>? dataModel,
  }) {
    final payload = <String, dynamic>{
      'surfaceId': surfaceId,
      'name': name,
      if (sourceComponentId != null) 'sourceComponentId': sourceComponentId,
      if (context != null) 'context': context,
      if (dataModel != null) 'dataModel': dataModel,
    };

    final frame = jsonEncode({
      'type': 'a2ui_action',
      'payload': payload,
    });

    print('[LisaWS] Sending action: $frame');

    _isProcessing.value = true;
    _pendingA2ui.clear();

    if (_channel == null) {
      _isProcessing.value = false;
      _errorController.add(ContentGeneratorError('WebSocket not connected'));
      return;
    }

    try {
      _channel!.sink.add(frame);
    } catch (e, st) {
      _isProcessing.value = false;
      _errorController.add(ContentGeneratorError(e, st));
    }
  }

  // ── v0.9 → SDK 변환 (A2uiContentGenerator 동일 로직) ────

  // v0.9 catalogId → SDK catalogId 매핑
  static const _catalogMap = {
    'https://a2ui.org/specification/v0_9/basic_catalog.json': 'a2ui.org:standard_catalog_0_8_0',
    // TV catalog — ID 동일하므로 그대로 통과
  };

  static String? _mapCatalogId(String? id) {
    if (id == null) return null;
    return _catalogMap[id] ?? id;
  }

  static Map<String, dynamic>? _convertV09ToSdk(Map<String, dynamic> msg) {
    // createSurface → beginRendering
    if (msg.containsKey('createSurface')) {
      final cs = Map<String, dynamic>.from(msg['createSurface'] as Map);
      return {
        'beginRendering': {
          'surfaceId': cs['surfaceId'],
          'root': 'root',
          if (cs['catalogId'] != null) 'catalogId': _mapCatalogId(cs['catalogId'] as String?),
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

    // 이미 SDK 형식인 경우 그대로 통과
    if (msg.containsKey('beginRendering') || msg.containsKey('surfaceUpdate') ||
        msg.containsKey('dataModelUpdate') || msg.containsKey('deleteSurface')) {
      return msg;
    }

    print('[LisaWS] Unknown message type: ${msg.keys}');
    return null;
  }

  static Map<String, dynamic> _convertComponentToSdk(Map<String, dynamic> comp) {
    final id = comp['id'] as String;
    final component = comp['component'];
    final weight = comp['weight'] as int?;

    // 이미 SDK 형식 (component가 Map)
    if (component is Map) {
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
              'context': (fc['args'] as Map).entries.map((e) =>
                  {'key': e.key, 'value': e.value}).toList(),
          };
        } else if (!action.containsKey('name')) {
          // action에 name이 없으면 기본값
          props['action'] = {'name': 'action'};
        }
      }

      return {
        'id': id,
        'component': {component: props},
        if (weight != null) 'weight': weight,
      };
    }

    return comp;
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    _channel?.sink.close();
    _a2uiController.close();
    _textController.close();
    _errorController.close();
  }
}
