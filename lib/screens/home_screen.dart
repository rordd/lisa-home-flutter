import 'dart:async';
import 'dart:convert';
import 'dart:ui' show ImageFilter;
import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:webos_service_bridge/webos_service_bridge.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:genui/genui.dart';
import '../catalog/tv_catalog.dart';
import '../services/lisa_ws_content_generator.dart';
import '../theme/tv_theme.dart';

/// LLM 텍스트에서 HTML 태그를 제거하는 헬퍼
String _stripHtmlTags(String text) {
  return text.replaceAll(RegExp(r'<[^>]*>'), '').trim();
}

/// a2ui v0.9 — 하이브리드 UI
/// 평소: 하단 토스트 바 (음성/텍스트 입력 + 1줄 응답)
/// 대화: 오버레이 팝업 (show_chat=true)

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final LisaWsContentGenerator _contentGenerator;
  late final A2uiMessageProcessor _processor;
  late final GenUiConversation _conversation;

  // 카드 렌더링
  final List<_RenderedCard> _renderedCards = [];
  final List<String> _surfaceIds = [];
  double _availableHeight = 0;
  int _gridPage = 0;

  // 토스트
  String _toastText = '';
  bool _toastVisible = false;
  Timer? _toastTimer;
  bool _cardUpdatedRecently = false;

  // 오버레이 팝업 (대화형)
  bool _popupVisible = false;

  // 입력
  bool _inputVisible = false;
  final _inputController = TextEditingController();
  final _inputFocus = FocusNode();

  // 타이머
  int _elapsedSeconds = 0;
  Timer? _elapsedTimer;

  // Ghost/Error 카드
  static const _ghostSurfaceId = '__ghost__';
  static const _errorSurfaceId = '__error__';
  String? _newestSurfaceId;  // 최신 카드 추적
  Timer? _newestDimTimer;    // dim 해제 타이머
  String? _lastUserMessage;  // 에러 시 재시도용

  // Spotlight 모드 (새 카드 전면 표시)
  Widget? _spotlightCard;       // 전면에 크게 표시할 카드
  String? _spotlightSurfaceId;  // spotlight 카드의 surfaceId
  String _spotlightText = '';   // AI 코멘트 텍스트
  _GridSpan? _spotlightSpan;    // spotlight 카드의 원래 span
  String? _spotlightTypeName;   // spotlight 카드의 타입명

  // 위젯 선반
  final List<_RenderedCard> _widgetCards = [];
  bool _widgetVisible = false;
  bool _overlayFromWidget = false;

  // Shake 감지 (좌우 방향키 빠른 연속)
  int _shakeCount = 0;
  DateTime? _lastShakeTime;

  static const _webosSystemChannel = MethodChannel('webos/system');

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      WidgetsBinding.instance.addObserver(this);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _setInputCapture('edge');
      });
    }
    _contentGenerator = LisaWsContentGenerator('ws://10.157.89.194:42618/app');

    final basicCatalog = CoreCatalogItems.asCatalog();
    final tvCatalog = Catalog(
      [...CoreCatalogItems.asCatalog().items, ...tvCatalogItems()],
      catalogId: 'https://a2ui.tv/catalogs/tv_home_v1.json',
    );
    _processor = A2uiMessageProcessor(catalogs: [basicCatalog, tvCatalog]);

    _conversation = GenUiConversation(
      contentGenerator: _contentGenerator,
      a2uiMessageProcessor: _processor,
      onSurfaceAdded: (update) {
        print('[HOME] Surface ADDED: ${update.surfaceId}');
        _surfaceIds.add(update.surfaceId);
        // Added 시점에서도 definition 체크
        final def = _conversation.host.getSurfaceNotifier(update.surfaceId).value;
        if (def != null && def.components.isNotEmpty) {
          print('[HOME] Definition available at add time, building cards');
          _cardUpdatedRecently = true;
          _renderedCards.removeWhere((c) => c.surfaceId == update.surfaceId);
          _addRenderedCard(update.surfaceId, def);
        }
      },
      onSurfaceDeleted: (update) {
        print('[HOME] Surface DELETED: ${update.surfaceId}');
        _surfaceIds.remove(update.surfaceId);
        _renderedCards.removeWhere((c) => c.surfaceId == update.surfaceId);
        setState(() {});
      },
      onSurfaceUpdated: (update) {
        print('[HOME] Surface UPDATED: ${update.surfaceId}');
        _cardUpdatedRecently = true;
        final def = _conversation.host.getSurfaceNotifier(update.surfaceId).value;
        if (def != null) {
          _renderedCards.removeWhere((c) => c.surfaceId == update.surfaceId);
          _addRenderedCard(update.surfaceId, def);
        }
      },
      onTextResponse: (text) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (!mounted) return;
          if (text.trim().isNotEmpty) {
            // 카드가 방금 업데이트됐으면 텍스트로 spotlight을 덮지 않음
            if (_cardUpdatedRecently) {
              _cardUpdatedRecently = false;
              if (text.length >= 50) {
                _spotlightText = text;
                setState(() {});
              }
              return;
            }
            _cardUpdatedRecently = false;
            // 50자 미만은 TTS로만 읽고 카드 표시 안 함
            if (text.length < 50) return;
            // 카드 없이 텍스트만 온 경우 LISA 코멘트를 단독 spotlight으로 표시
            _renderedCards.removeWhere((c) => c.typeName == '_AiCommentCard');
            if (_spotlightCard == null || _spotlightSurfaceId == _ghostSurfaceId) {
              _spotlightCard = _AiCommentCard(text: text);
              _spotlightSurfaceId = '__text__';
              _spotlightSpan = _GridSpan.m;
              _spotlightTypeName = '_AiCommentCard';
              if (!kIsWeb) _setInputCapture('full');
            } else {
              // 실제 카드가 spotlight에 있으면 옆에 코멘트 표시
              _spotlightText = text;
            }
            setState(() {});
          } else {
            _cardUpdatedRecently = false;
          }
        });
      },
      onError: (error) {
        // Error Card를 spotlight에 표시
        _spotlightCard = _ErrorCard(
          onRetry: () {
            _spotlightCard = null;
            _spotlightSurfaceId = null;
            _spotlightText = '';
            setState(() {});
            if (_lastUserMessage != null) {
              _conversation.sendRequest(UserMessage.text(_lastUserMessage!));
            }
          },
          onDismiss: () {
            _spotlightCard = null;
            _spotlightSurfaceId = null;
            _spotlightText = '';
            setState(() {});
            if (!kIsWeb) _setInputCapture(_widgetVisible ? 'full' : 'edge');
          },
        );
        _spotlightSurfaceId = _errorSurfaceId;
        _spotlightSpan = _GridSpan.s;
        _spotlightTypeName = '_ErrorCard';
        _spotlightText = '오류가 발생했어요.';
        setState(() {});
        if (!kIsWeb) _setInputCapture('full');
      },
    );

    _conversation.isProcessing.addListener(_onProcessingChanged);
    HardwareKeyboard.instance.addHandler(_handleKeyShake);
    // inputRegions는 앱 시작 직후 Wayland surface가 준비된 후에만 호출 가능.
    // 초기 상태는 embedder 기본값(full capture) 유지.
    // 패널 닫힘/spotlight 해제 시점에 edge로 전환.

    // 기기 세부카드 콜백
    onDeviceDetailRequested = (device) {
      final detailWidget = DeviceDetailWidget(device: device);
      _widgetCards.insert(0, _RenderedCard(
        surfaceId: 'detail_${device['id'] ?? 'unknown'}',
        typeName: 'DeviceDetailCard',
        span: _GridSpan.s,
        widget: detailWidget,
      ));
      _trimWidgetCards();
      setState(() {});
    };
  }

  void _onProcessingChanged() {
    if (_conversation.isProcessing.value) {
      _elapsedSeconds = 0;
      _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _elapsedSeconds++);
      });
      // Ghost Card를 spotlight 위치에 표시 + 전체 input 캡처
      _spotlightCard = const _GhostCard();
      _spotlightSurfaceId = _ghostSurfaceId;
      _spotlightSpan = _GridSpan.s;
      _spotlightTypeName = '_GhostCard';
      _spotlightText = '';
      if (!kIsWeb) _setInputCapture('full');
    } else {
      _elapsedTimer?.cancel();
      _elapsedTimer = null;
      // Ghost spotlight은 실제 카드가 도착하면 자동 교체됨
      if (_spotlightSurfaceId == _ghostSurfaceId) {
        _spotlightCard = null;
        _spotlightSurfaceId = null;
        if (!kIsWeb && !_widgetVisible) _setInputCapture('edge');
      }
    }
    setState(() {});
  }

  void _removeSpecialCards() {
    _renderedCards.removeWhere((c) =>
        c.surfaceId == _ghostSurfaceId ||
        c.surfaceId == _errorSurfaceId);
    // spotlight이 ghost면 클리어
    if (_spotlightSurfaceId == _ghostSurfaceId) {
      _spotlightCard = null;
      _spotlightSurfaceId = null;
    }
  }

  /// Spotlight 모드에서 카드를 위젯 선반으로 내리기
  void _dismissSpotlight() {
    if (_spotlightCard == null) return;
    // ghost/error/text-only는 저장 안 함
    final isSpecial = _spotlightSurfaceId == _ghostSurfaceId ||
        _spotlightSurfaceId == _errorSurfaceId ||
        _spotlightSurfaceId == '__text__';
    if (!isSpecial) {
      _widgetCards.insert(0, _RenderedCard(
        surfaceId: _spotlightSurfaceId ?? 'spotlight',
        typeName: _spotlightTypeName ?? 'Unknown',
        span: _spotlightSpan ?? _GridSpan.s,
        widget: _spotlightCard!,
      ));
      _trimWidgetCards();
    }
    _spotlightCard = null;
    _spotlightSurfaceId = null;
    _spotlightText = '';
    _spotlightSpan = null;
    _spotlightTypeName = null;
    // 위젯에서 요청한 카드면 위젯 뷰로 복귀
    final returnToWidget = _overlayFromWidget;
    if (_overlayFromWidget) _widgetVisible = true;
    _overlayFromWidget = false;
    setState(() {});
    // input region: 위젯 복귀 시 full, 아니면 edge
    _setInputCapture(returnToWidget || _widgetVisible ? 'full' : 'edge');
  }

  @override
  void dispose() {
    if (!kIsWeb) {
      WidgetsBinding.instance.removeObserver(this);
    }
    _conversation.isProcessing.removeListener(_onProcessingChanged);
    HardwareKeyboard.instance.removeHandler(_handleKeyShake);
    _elapsedTimer?.cancel();
    _toastTimer?.cancel();
    _newestDimTimer?.cancel();
    _inputController.dispose();
    _inputFocus.dispose();
    _conversation.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('[LIFECYCLE] $state');
    if (kIsWeb) return;
    if (state == AppLifecycleState.resumed) {
      _setInputCapture(_widgetVisible || _spotlightCard != null ? 'full' : 'edge');
    }
  }

  Future<void> _setInputCapture(String mode) async {
    try {
      final List<int> regions;
      if (mode == 'full') {
        regions = [0, 0, 1920, 1080];
      } else if (mode == 'edge') {
        regions = [1904, 480, 1920, 600];
      } else {
        regions = [];
      }
      await _webosSystemChannel.invokeMethod('inputRegions', {"regions": regions});
      // edge: 뒤 카드 앱이 키 받음 / full: 이 앱이 키 받음
      _webosSystemChannel.invokeMethod('windowProperty',
          {'property': 'needFocus', 'value': mode == 'full' ? 'true' : 'false'}).catchError((_) {});
      print('[WIN] inputRegions=$mode needFocus=${mode == 'full'}');
    } catch (e) {
      print('[WIN] inputRegions failed: $e');
    }
  }

  /// 앱 런칭 후 edge 상태로 축소
  void _collapseToEdge() {
    _dismissSpotlight();
    setState(() {
      _widgetVisible = false;
      _inputVisible = false;
    });
    _setInputCapture('edge');
  }

  /// back/escape 공통 동작 (키보드 + 마우스 우클릭 공용)
  void _handleBackAction() {
    if (_widgetVisible) {
      _toggleWidgetPanel(); // 패널 닫기 → edge
    } else if (_spotlightCard != null) {
      _dismissSpotlight(); // spotlight 해제 → edge
    }
    // 이미 edge 상태: 아무것도 안 함 (floatingui는 always-on-top)
  }

  /// 위젯 패널 열기/닫기 토글 (물리 RED 키 or 엣지 핸들)
  void _toggleWidgetPanel() {
    if (!mounted) return;
    if (_widgetVisible) {
      // 닫기: 엣지 핸들 영역만 유지 → TV가 나머지 입력 받음
      setState(() {
        _widgetVisible = false;
        _inputVisible = false;
      });
      _setInputCapture(_spotlightCard != null ? 'full' : 'edge');
    } else {
      // 열기: 전체화면 캡처, 키보드는 안 띄움 (마이크 버튼으로 대체)
      setState(() {
        _widgetVisible = true;
        _inputVisible = false;
      });
      _setInputCapture('full');
    }
  }

  /// HardwareKeyboard 글로벌 핸들러
  /// - RED 키(F1 or 빨간 버튼) → 위젯 패널 토글
  /// - 좌우 방향키 4회 800ms 내 → spotlight dismiss
  bool _handleKeyShake(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    // webOS: 알 수 없는 키는 keyId를 로깅 (디버그)
    final key = event.logicalKey;
    final keyId = key.keyId;
    print('[KEY] logicalKey=$key keyId=0x${keyId.toRadixString(16)} physical=${event.physicalKey}');

    // RED 키: webOS Magic Remote 빨간 버튼
    // LGE webOS 에서는 KEY_RED(398)가 F1 또는 keyId=0x10600000020로 매핑될 수 있음
    final isRedKey = key == LogicalKeyboardKey.f1 ||
        keyId == 0x10600000020 || // webOS KEY_RED custom
        keyId == 398;             // Linux keycode fallback
    if (isRedKey) {
      _toggleWidgetPanel();
      return true;
    }

    // BACK / ESC 키: webOS X버튼, Back키
    // → 패널/spotlight 닫기. 이미 edge 상태면 앱 종료 없이 그대로 유지.
    final isBackKey = key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        keyId == 0x00100000305; // webOS KEY_BACK
    if (isBackKey) {
      _handleBackAction();
      return true; // 이벤트 소비 — Flutter 기본 종료 동작 방지
    }

    // 좌우 방향키 4회 이내 800ms → spotlight dismiss
    if (_spotlightCard == null) return false;
    final isLR = key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight;
    if (!isLR) return false;
    final now = DateTime.now();
    if (_lastShakeTime == null ||
        now.difference(_lastShakeTime!) > const Duration(milliseconds: 800)) {
      _shakeCount = 1;
    } else {
      _shakeCount++;
    }
    _lastShakeTime = now;
    if (_shakeCount >= 4) {
      _shakeCount = 0;
      _lastShakeTime = null;
      _dismissSpotlight();
      return true;
    }
    return false;
  }

  // ── 카드 이벤트 처리 (퀴즈 답변, URL 열기, 앱 런칭 등) ─────────
  void _handleCardEvent(UiEvent event, String typeName) {
    if (event is! UserActionEvent) return;
    switch (event.name) {
      case 'answer':
        final choice = event.context['choice'] as String? ?? '';
        print('[ACTION] $typeName answer: $choice');
        _conversation.sendRequest(UserMessage.text(choice));
      case 'openUrl':
        final url = event.context['url'] as String?;
        print('[ACTION] $typeName openUrl: $url');
        if (url != null) {
          openUrl(url);
          _collapseToEdge();
        }
      case 'launchApp':
        final appId = event.context['appId'] as String?;
        final params = Map<String, dynamic>.from(
            event.context['params'] as Map? ?? {});
        print('[ACTION] $typeName launchApp: $appId params=$params');
        if (appId == null) break;
        if (appId.startsWith('http')) {
          openUrl(appId);
        } else if (!kIsWeb) {
          WebOSServiceBridge.callOneReply(WebOSServiceData(
            'luna://com.palm.applicationManager/launch',
            payload: {'id': appId, if (params.isNotEmpty) 'params': params},
          ));
        }
        _collapseToEdge();
      default:
        print('[ACTION] $typeName unknown: ${event.name} ${event.context}');
    }
  }

  // ── 메시지 전송 ─────────────────────────────
  void _sendMessage(String text) {
    if (text.trim().isEmpty) return;
    _lastUserMessage = text.trim();
    // spotlight 해제 키워드 체크
    final lower = text.trim().toLowerCase();
    final dismissKeywords = ['카드 내려', '알겠어', '내려', '닫아', '확인', '넘어가'];
    if (_spotlightCard != null && dismissKeywords.any((k) => lower.contains(k))) {
      _dismissSpotlight();
      setState(() => _inputVisible = false);
      return;
    }
    // 위젯 뷰에서 요청 시 기록 후 위젯 닫기
    _overlayFromWidget = _widgetVisible;
    if (_widgetVisible) setState(() => _widgetVisible = false);
    // 다음 요청 시 이전 spotlight 자동 해제
    _dismissSpotlight();
    _conversation.sendRequest(UserMessage.text(text.trim()));
    setState(() => _inputVisible = false);
  }

  // ── 토스트 표시 (텍스트 길이에 비례하여 유지) ──
  void _showToast(String text) {
    _toastTimer?.cancel();
    setState(() {
      _toastText = text;
      _toastVisible = true;
    });
    // 글자 수 기반: 최소 4초, 20자당 +1초, 최대 12초
    final duration = (4000 + (text.length / 20 * 1000)).clamp(4000, 12000).toInt();
    _toastTimer = Timer(Duration(milliseconds: duration), () {
      if (mounted) setState(() => _toastVisible = false);
    });
  }

  // 한 번에 하나만 존재해야 하는 카드 타입 (대화형/진행형)
  static const _singletonCardTypes = {'GameCard'};

  // ── 카드 렌더링 ─────────────────────────────
  void _addRenderedCard(String surfaceId, UiDefinition definition) {
    // Ghost/Error 카드 제거
    _removeSpecialCards();
    _newestSurfaceId = surfaceId;
    // 3초 후 dim 해제 (모든 카드 동일 밝기로 복원)
    _newestDimTimer?.cancel();
    _newestDimTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _newestSurfaceId = null);
    });
    final allItems = [...tvCatalogItems(), ...CoreCatalogItems.asCatalog().items];

    // root 컴포넌트의 타입 확인
    final rootComp = definition.components['root'];
    final rootTypeName = rootComp?.componentProperties.keys.firstOrNull ?? '';
    print('[RENDER] root type=$rootTypeName, total components=${definition.components.length}');

    // TV 커스텀 카탈로그인지 Basic 카탈로그인지 판별
    final tvItemNames = tvCatalogItems().map((i) => i.name).toSet();
    final isCustomCard = tvItemNames.contains(rootTypeName);

    if (isCustomCard) {
      // TV 커스텀 카드: 기존 방식 (단일 컴포넌트 직접 빌드)
      final allItems = [...tvCatalogItems(), ...CoreCatalogItems.asCatalog().items];
      print('[RENDER] Custom card loop: ${definition.components.length} components');
      for (final entry in definition.components.entries) {
        final props = entry.value.componentProperties;
        print('[RENDER] Component ${entry.key}: props.keys=${props.keys.toList()}, isEmpty=${props.isEmpty}');
        if (props.isEmpty) continue;
        final typeName = props.keys.first;
        if (typeName == 'Column' || typeName == 'Row') continue;

        final cardData = (props[typeName] is Map)
            ? Map<String, dynamic>.from(props[typeName] as Map)
            : <String, dynamic>{};
        print('[RENDER] Building $typeName: cardData.keys=${cardData.keys.toList()}, items=${cardData['items']?.runtimeType}');
        final catalogItem = allItems.where((item) => item.name == typeName).firstOrNull;

        if (catalogItem != null) {
          try {
            final widget = catalogItem.widgetBuilder(CatalogItemContext(
              data: cardData, id: entry.key,
              buildChild: (id, [dc]) => const SizedBox.shrink(),
              dispatchEvent: (event) => _handleCardEvent(event, typeName),
              buildContext: context,
              dataContext: DataContext(DataModel(), '/'),
              getComponent: (cid) => definition.components[cid],
              surfaceId: surfaceId,
            ));
            if (_singletonCardTypes.contains(typeName)) {
              _renderedCards.removeWhere((c) => c.typeName == typeName);
            }
            _spotlightCard = widget;
            _spotlightSurfaceId = surfaceId;
            _spotlightSpan = _gridSpan(typeName, cardData);
            _spotlightTypeName = typeName;
          } catch (e) {
            print('[RENDER] Error building $typeName: $e');
          }
        }
      }
    } else {
      // Basic 카탈로그 조합: Surface 위젯으로 전체 트리 렌더링
      print('[RENDER] Using GenUiSurface for Basic catalog composition');
      // Basic 카탈로그는 Theme.textTheme을 사용하므로 TV용 다크 테마 오버라이드
      final surfaceWidget = Theme(
        data: ThemeData.dark().copyWith(
          cardTheme: CardThemeData(
            color: const Color(0xFF1E1E22),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(TV.radiusMd),
            ),
          ),
          textTheme: ThemeData.dark().textTheme.apply(
            bodyColor: const Color(0xFFF5F5F7),
            displayColor: const Color(0xFFF5F5F7),
          ).copyWith(
            headlineLarge: const TextStyle(fontSize: 40, fontWeight: FontWeight.w700, color: Color(0xFFF5F5F7)),
            headlineMedium: const TextStyle(fontSize: 30, fontWeight: FontWeight.w600, color: Color(0xFFF5F5F7)),
            headlineSmall: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: Color(0xFFF5F5F7)),
            titleLarge: const TextStyle(fontSize: 24, fontWeight: FontWeight.w500, color: Color(0xFFF5F5F7)),
            bodyLarge: const TextStyle(fontSize: 22, color: Color(0xFFB8B8BC)),
            bodyMedium: const TextStyle(fontSize: 22, color: Color(0xFFB8B8BC)),
            bodySmall: const TextStyle(fontSize: 20, color: Color(0xFF6E6E73)),
          ),
          iconTheme: const IconThemeData(color: Color(0xFFF5F5F7), size: 28),
          dividerTheme: DividerThemeData(color: Colors.white.withOpacity(0.1)),
          colorScheme: const ColorScheme.dark(
            surface: Color(0xFF1E1E22),
          ),
        ),
        child: ClipRect(
          child: SingleChildScrollView(
            child: GenUiSurface(
              host: _conversation.host,
              surfaceId: surfaceId,
            ),
          ),
        ),
      );
      _spotlightCard = surfaceWidget;
      _spotlightSurfaceId = surfaceId;
      _spotlightSpan = _GridSpan.m;
      _spotlightTypeName = rootTypeName;
    }
    _trimCardsToFit();
    setState(() {});
    // 카드가 spotlight에 나타났으므로 전체 입력 캡처
    if (!kIsWeb) _setInputCapture('full');
  }

  _GridSpan _gridSpan(String typeName, [Map<String, dynamic>? data]) {
    switch (typeName) {
      case 'WeatherCard':
        final hasForecast = data?['forecast'] is List && (data!['forecast'] as List).isNotEmpty;
        return hasForecast ? _GridSpan.m : _GridSpan.s;  // 예보 있으면 2×1, 없으면 1×1
      case 'MediaRailCard':
        final variant = (data?['variant'] as String?) ?? (data?['usageHint'] as String?) ?? 'youtube';
        return variant == 'movie' ? _GridSpan.wl : _GridSpan.w; // movie=4×2, youtube=4×1
      case 'PlaceRailCard': return _GridSpan.w;   // 4×1 full-width rail
      case 'MapCard': return _GridSpan.l;          // 2×2 지도+장소목록
      case 'HomeControlCard': return _GridSpan.l;    // 2×2 상세
      case 'ArticleListCard': return _GridSpan.m;  // 2×1 표준
      case 'ContextCard':
      case 'ControlCard':
      case 'ReviewSummaryCard':
      case 'ArticleSummaryCard':
      case 'ListCard': return _GridSpan.m;          // 2×1 표준
      case 'DocumentCard': return _GridSpan.xl;        // 2×3 장문 문서
      case 'RecipeCard': return _GridSpan.l;              // 2×2 이미지+상세
      case 'ComparisonCard': return _GridSpan.m;           // 2×1 비교표 (컴팩트)
      case 'GameCard':
      case 'InfoCard':
      case 'WebappCard':
      default: return _GridSpan.s;                   // 1×1 소형
    }
  }

  /// 하드 리밋 (4×3 그리드 = 최대 12셀, 안전장치)
  void _trimCardsToFit() {
    while (_renderedCards.length > 12) {
      _renderedCards.removeLast();
    }
  }

  void _trimWidgetCards() {
    while (_widgetCards.length > 12) {
      _widgetCards.removeLast();
    }
  }

  /// 그리드에 맞지 않는 카드는 _buildCards에서 자동 스킵됨 (별도 trim 불필요)

  // ── JSON 다이얼로그 ─────────────────────────
  void _showJsonDialog() {
    if (_contentGenerator.lastRawJson == null) return;
    showDialog(context: context, builder: (_) => Dialog(
      backgroundColor: const Color(0xFF141416),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(width: 600, height: 500, padding: const EdgeInsets.all(24),
        child: Column(children: [
          Row(children: [
            const Text('A2UI JSON', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white)),
            const Spacer(),
            GestureDetector(onTap: () => Navigator.pop(context),
                child: const Icon(Icons.close_rounded, color: Color(0xFFAAAAAA))),
          ]),
          const SizedBox(height: 16),
          Expanded(child: Container(
            width: double.infinity, padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: TV.bg, borderRadius: BorderRadius.circular(12)),
            child: SingleChildScrollView(child: SelectableText(
                _contentGenerator.lastRawJson!,
                style: const TextStyle(fontSize: 20, fontFamily: 'monospace', color: Colors.white, height: 1.5))),
          )),
        ])),
    ));
  }

  // ═══════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // 백 버튼으로 앱 종료 차단 — edge 모드 유지
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          // 마우스 오른쪽 버튼 = back 동작 (패널/spotlight 닫기 → edge)
          if (event.buttons == kSecondaryMouseButton) _handleBackAction();
        },
        child: Scaffold(
      backgroundColor: Colors.transparent,
      body: SizedBox.expand(
        child: Stack(children: [
          // ── Spotlight 레이어 (새 카드 전면 가운데) ──
          // 바깥 클릭 시 spotlight 해제 (카드를 위젯 선반으로 내림)
          if (_spotlightCard != null)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _dismissSpotlight,
                child: _buildSpotlightLayer(),
              ),
            ),

          // ── 위젯 선반 (저장된 카드 뷰) ──
          if (_widgetVisible)
            Positioned.fill(child: _buildWidgetShelf())
                .animate()
                .fadeIn(duration: 300.ms, curve: Curves.easeOutCubic),

          // 상단 우측: 입력 토글 — spotlight 활성 상태에서만 표시
          // spotlight 활성 시: 우상단 마이크 버튼만 표시
          if (_spotlightCard != null && !_widgetVisible)
            Positioned(
              top: 24, right: 48,
              child: GestureDetector(
                onTap: () => setState(() {
                  _inputVisible = !_inputVisible;
                  if (_inputVisible) Future.delayed(100.ms, () => _inputFocus.requestFocus());
                }),
                child: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: _inputVisible ? TV.accent.withOpacity(0.2) : Colors.white.withOpacity(0.08),
                    shape: BoxShape.circle,
                    border: Border.all(color: _inputVisible ? TV.accent.withOpacity(0.4) : Colors.white.withOpacity(0.1))),
                  child: Icon(Icons.mic_rounded, size: 22,
                      color: _inputVisible ? TV.accent : const Color(0xFFAAAAAA)),
                ),
              ),
            ),

          // ── 하단 입력 바 (spotlight 상태에서만) ───────────────────────
          if (_spotlightCard != null && !_widgetVisible)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 400),
              curve: _inputVisible ? Curves.easeOutBack : Curves.easeIn,
              left: 48, right: 48,
              bottom: _inputVisible ? 24 : -80,
              child: AnimatedOpacity(
                opacity: _inputVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: _buildBottomBar(),
              ),
            ),

          // ── 오버레이 팝업 (대화형) ────────────────
          if (_popupVisible)
            _buildOverlayPopup()
                .animate()
                .fadeIn(duration: 300.ms, curve: Curves.easeOutCubic)
                .scale(
                  begin: const Offset(0.95, 0.95),
                  end: const Offset(1.0, 1.0),
                  duration: 300.ms,
                  curve: Curves.easeOutCubic,
                ),

          // ── 우측 엣지 핸들 (패널 닫힘 시, RED키 또는 탭으로 열기) ──
          if (!_widgetVisible && _spotlightCard == null)
            _buildEdgeHandle(),
        ]),
      ),
    ))); // Listener + PopScope + Scaffold
  }

  /// 우측 가장자리 얇은 탭 — 항상 보이는 최소 UI
  Widget _buildEdgeHandle() {
    final count = _widgetCards.length;
    return Positioned(
      right: 0,
      top: 0,
      bottom: 0,
      child: Align(
        alignment: Alignment.centerRight,
        child: GestureDetector(
          onTap: _toggleWidgetPanel,
          child: Container(
            width: 16,
            height: 120,
            decoration: BoxDecoration(
              color: count > 0
                  ? TV.accent.withOpacity(0.55)
                  : Colors.white.withOpacity(0.15),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                bottomLeft: Radius.circular(8),
              ),
            ),
            child: count > 0
                ? RotatedBox(
                    quarterTurns: 1,
                    child: Text(
                      '$count',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }

  // ── 카드 레이아웃 — 4컬럼 × 3로우 그리드 (페이지네이션) ──
  Widget _buildCards({List<_RenderedCard>? cards}) {
    final cardList = cards ?? _renderedCards;
    return LayoutBuilder(builder: (context, constraints) {
      _availableHeight = constraints.maxHeight;
      final totalW = constraints.maxWidth;
      final totalH = constraints.maxHeight;
      const gap = 16.0;
      const cols = 4;
      const rows = 3;
      print('[GRID] constraints: ${totalW}x$totalH, cards: ${cardList.length}');
      final cellW = (totalW - gap * (cols - 1)) / cols;
      final cellH = (totalH - gap * (rows - 1)) / rows;

      // 카드를 페이지별로 분배
      final pages = <List<_RenderedCard>>[];
      var remaining = List<_RenderedCard>.from(cardList);

      while (remaining.isNotEmpty) {
        final grid = List.generate(rows, (_) => List.filled(cols, false));
        final pageCards = <_RenderedCard>[];
        final nextRemaining = <_RenderedCard>[];

        for (final card in remaining) {
          final (spanCols, spanRows) = _spanSize(card.span);
          final pos = _findSlot(grid, cols, rows, spanCols, spanRows);
          if (pos != null) {
            _markGrid(grid, pos.$1, pos.$2, spanCols, spanRows);
            pageCards.add(card);
          } else {
            nextRemaining.add(card);
          }
        }
        if (pageCards.isEmpty) break; // 무한루프 방지
        pages.add(pageCards);
        remaining = nextRemaining;
      }

      // 페이지 범위 보정
      final maxPage = pages.length - 1;
      if (_gridPage > maxPage) _gridPage = maxPage;
      if (_gridPage < 0) _gridPage = 0;

      if (pages.isEmpty) return const SizedBox.shrink();

      // 현재 페이지 렌더
      final currentCards = pages[_gridPage];
      final grid = List.generate(rows, (_) => List.filled(cols, false));
      final positioned = <Widget>[];

      for (final card in currentCards) {
        final (spanCols, spanRows) = _spanSize(card.span);
        final pos = _findSlot(grid, cols, rows, spanCols, spanRows);
        print('[GRID] ${card.typeName} span=${spanCols}x$spanRows pos=$pos');
        if (pos == null) continue;
        _markGrid(grid, pos.$1, pos.$2, spanCols, spanRows);

        final x = pos.$2 * (cellW + gap);
        final y = pos.$1 * (cellH + gap);
        final w = cellW * spanCols + gap * (spanCols - 1);
        final h = cellH * spanRows + gap * (spanRows - 1);

        final isNewest = card.surfaceId == _newestSurfaceId;
        final isSpecial = card.surfaceId == _ghostSurfaceId ||
            card.surfaceId == _errorSurfaceId;
        // 최신 카드가 있을 때 기존 카드는 dim 처리
        final shouldDim = _newestSurfaceId != null &&
            !isNewest && !isSpecial &&
            cardList.any((c) => c.surfaceId == _newestSurfaceId);

        final isWidgetShelf = cardList == _widgetCards;
        positioned.add(Positioned(
          left: x, top: y, width: w, height: h,
          child: AnimatedOpacity(
            opacity: shouldDim ? 0.6 : 1.0,
            duration: const Duration(milliseconds: 500),
            child: Stack(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: isNewest
                    ? Focus(autofocus: true, child: card.widget)
                    : card.widget,
              ),
              // 위젯 선반에서만 삭제 버튼
              if (isWidgetShelf)
                Positioned(
                  top: 6, right: 6,
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _widgetCards.remove(card));
                    },
                    child: Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded, size: 16, color: Colors.white70),
                    ),
                  ),
                ),
            ]),
          ),
        ));
      }

      // 페이지 화살표
      if (pages.length > 1) {
        // 왼쪽 화살표
        if (_gridPage > 0)
          positioned.add(Positioned(
            left: 0, top: totalH / 2 - 28, child: _gridArrow(Icons.chevron_left_rounded, () => setState(() => _gridPage--)),
          ));
        // 오른쪽 화살표
        if (_gridPage < maxPage)
          positioned.add(Positioned(
            right: 0, top: totalH / 2 - 28, child: _gridArrow(Icons.chevron_right_rounded, () => setState(() => _gridPage++)),
          ));
        // 페이지 인디케이터
        positioned.add(Positioned(
          bottom: 0, left: 0, right: 0,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (int i = 0; i <= maxPage; i++)
              Container(
                width: i == _gridPage ? 24 : 8, height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: i == _gridPage ? Colors.white.withOpacity(0.8) : Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
          ]),
        ));
      }

      return Stack(clipBehavior: Clip.hardEdge, children: positioned);
    });
  }

  Widget _gridArrow(IconData icon, VoidCallback onTap) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerUp: (_) => onTap(),
        child: Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.6),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.15)),
          ),
          child: Icon(icon, size: 32, color: Colors.white.withOpacity(0.9)),
        ),
      ),
    );
  }

  /// (spanCols, spanRows) 반환
  (int, int) _spanSize(_GridSpan span) => switch (span) {
    _GridSpan.s => (1, 1),   // 1col × 1row
    _GridSpan.m => (2, 1),   // 2col × 1row
    _GridSpan.l => (2, 2),   // 2col × 2row
    _GridSpan.w => (4, 1),   // 4col × 1row
    _GridSpan.wl => (4, 2),  // 4col × 2row
    _GridSpan.xl => (2, 3),  // 2col × 3row
  };

  (int, int)? _findSlot(List<List<bool>> grid, int cols, int rows, int spanCols, int spanRows) {
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c <= cols - spanCols; c++) {
        bool fits = true;
        for (int dr = 0; dr < spanRows && fits; dr++) {
          for (int dc = 0; dc < spanCols && fits; dc++) {
            if (r + dr >= rows || grid[r + dr][c + dc]) fits = false;
          }
        }
        if (fits) return (r, c);
      }
    }
    return null;
  }

  void _markGrid(List<List<bool>> grid, int row, int col, int spanCols, int spanRows) {
    for (int dr = 0; dr < spanRows; dr++) {
      for (int dc = 0; dc < spanCols; dc++) {
        grid[row + dr][col + dc] = true;
      }
    }
  }

  // ── Spotlight 레이어 (카드 좌 + AI 코멘트 우) ──
  Widget _buildSpotlightLayer() {
    final isGhost = _spotlightSurfaceId == _ghostSurfaceId;
    return Stack(children: [
      // 반투명 블러 배경 — ghost(로딩) 중에는 투명 유지
      if (!isGhost)
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(color: Colors.black.withOpacity(0.55)),
          ),
        ),
      LayoutBuilder(builder: (context, constraints) {
      final screenW = constraints.maxWidth;
      final screenH = constraints.maxHeight;
      final hasComment = _spotlightText.isNotEmpty;

      // 카드 크기
      final (spanCols, spanRows) = _spanSize(_spotlightSpan ?? _GridSpan.s);
      final cardW = hasComment
          ? (screenW * 0.4).clamp(300.0, screenW * 0.45)  // 코멘트 있으면 좌측 40%
          : (screenW * 0.5 * spanCols / 2).clamp(300.0, screenW * 0.55); // 없으면 가운데
      final cardH = (screenH * 0.78 * spanRows.clamp(1, 2) / 2).clamp(300.0, screenH * 0.8);

      // ghost(로딩)이면 투명, 실제 카드면 불투명 배경
      Widget spotlightCardWrapped = GestureDetector(
        onTap: () {},
        child: isGhost
          ? SizedBox(width: cardW, height: cardH, child: _spotlightCard!)
          : Container(
              decoration: BoxDecoration(
                color: const Color(0xFF141416),
                borderRadius: BorderRadius.circular(TV.radiusMd),
                border: Border.all(color: Colors.white.withOpacity(0.12)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.6),
                    blurRadius: 40,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(TV.radiusMd),
                child: SizedBox(width: cardW, height: cardH, child: _spotlightCard!),
              ),
            ),
      );

      // 코멘트 없으면 카드만 가운데
      if (!hasComment) {
        return Center(
          child: SizedBox(
            width: cardW, height: cardH,
            child: spotlightCardWrapped,
          ),
        )
            .animate()
            .fadeIn(duration: 400.ms, curve: Curves.easeOutCubic)
            .scale(begin: const Offset(0.9, 0.9), end: const Offset(1, 1),
                duration: 400.ms, curve: Curves.easeOutBack);
      }

      // 코멘트 있으면 좌(카드) + 우(코멘트)
      final commentW = (screenW * 0.35).clamp(250.0, 500.0);

      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: (screenW - cardW - commentW - 24) / 2,
          vertical: (screenH - cardH) / 2,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 좌: 카드
            SizedBox(
              width: cardW, height: cardH,
              child: spotlightCardWrapped,
            )
                .animate()
                .fadeIn(duration: 400.ms, curve: Curves.easeOutCubic)
                .scale(begin: const Offset(0.9, 0.9), end: const Offset(1, 1),
                    duration: 400.ms, curve: Curves.easeOutBack),
            const SizedBox(width: 24),
            // 우: AI 코멘트
            GestureDetector(
              onTap: () {}, // 내부 탭 흡수
              child: SizedBox(
              width: commentW, height: cardH,
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: const Color(0xFF141416),
                  borderRadius: BorderRadius.circular(TV.radiusMd),
                  border: Border.all(color: Colors.white.withOpacity(0.12)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.6),
                      blurRadius: 40,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                          color: TV.accent.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.smart_toy_rounded, size: 16, color: TV.accent),
                      ),
                      const SizedBox(width: 10),
                      const Text('LISA', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TV.accent)),
                    ]),
                    const SizedBox(height: 16),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Text(
                          _stripHtmlTags(_spotlightText),
                          style: const TextStyle(fontSize: 24, color: Colors.white, height: 1.6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ))
                .animate()
                .fadeIn(duration: 500.ms, delay: 200.ms, curve: Curves.easeOutCubic)
                .slideX(begin: 0.05, end: 0, duration: 500.ms, delay: 200.ms),
          ],
        ),
      );
    }),
  ]);
  }

  // ── 위젯 선반 버튼 (상단 우측 Row에 삽입) ──
  Widget _buildWidgetButton() {
    final count = _widgetCards.length;
    return GestureDetector(
      onTap: _toggleWidgetPanel,
      child: Container(
        width: 44, height: 44,
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: count > 0 ? TV.accent.withOpacity(0.15) : Colors.white.withOpacity(0.08),
          shape: BoxShape.circle,
          border: Border.all(
            color: count > 0 ? TV.accent.withOpacity(0.4) : Colors.white.withOpacity(0.1),
          ),
        ),
        child: Stack(children: [
          Center(child: Icon(
            Icons.widgets_rounded,
            size: 22,
            color: count > 0 ? TV.accent : const Color(0xFFAAAAAA),
          )),
          if (count > 0)
            Positioned(
              top: 2, right: 2,
              child: Container(
                width: 16, height: 16,
                decoration: const BoxDecoration(color: TV.accent, shape: BoxShape.circle),
                child: Center(child: Text(
                  '$count',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.black),
                )),
              ),
            ),
        ]),
      ),
    );
  }

  // ── 위젯 선반 (저장된 카드 전체 화면 패널) ──
  Widget _buildWidgetShelf() {
    return Stack(children: [
      // 블러 배경
      Positioned.fill(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(color: Colors.black.withOpacity(0.78)),
        ),
      ),
      // 카드 그리드
      Positioned(
        left: 48, top: 72, right: 48, bottom: 100,
        child: _widgetCards.isEmpty
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.widgets_outlined, size: 56, color: Colors.white.withOpacity(0.18)),
                const SizedBox(height: 16),
                Text('저장된 카드 없음',
                    style: TextStyle(fontSize: 22, color: Colors.white.withOpacity(0.3))),
              ]))
            : _buildCards(cards: _widgetCards),
      ),
      // 하단 입력 바 (마이크 버튼으로 토글)
      if (_inputVisible)
        Positioned(
          left: 48, right: 48, bottom: 24,
          child: _buildBottomBar(),
        ),
      // 우상단: 마이크 + 닫기
      Positioned(
        top: 20, right: 48,
        child: Row(children: [
          GestureDetector(
            onTap: () => setState(() {
              _inputVisible = !_inputVisible;
              if (_inputVisible) Future.delayed(100.ms, () => _inputFocus.requestFocus());
            }),
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: _inputVisible ? TV.accent.withOpacity(0.2) : Colors.white.withOpacity(0.08),
                shape: BoxShape.circle,
                border: Border.all(
                    color: _inputVisible ? TV.accent.withOpacity(0.4) : Colors.white.withOpacity(0.1))),
              child: Icon(Icons.mic_rounded, size: 22,
                  color: _inputVisible ? TV.accent : const Color(0xFFAAAAAA)),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _toggleWidgetPanel,
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(0.1))),
              child: const Icon(Icons.close_rounded, size: 22, color: Colors.white),
            ),
          ),
        ]),
      ),
    ]);
  }

  // ── AI 말풍선 (레거시, 미사용) ──────────────────
  Widget _buildSpeechBubble() {
    return Padding(
      padding: const EdgeInsets.only(left: 20, bottom: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
            bottomLeft: Radius.circular(24),
            bottomRight: Radius.circular(6),
          ),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: TV.accent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.smart_toy_rounded, size: 16, color: TV.accent),
              ),
              const SizedBox(width: 10),
              const Text('LISA', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TV.accent)),
            ]),
            const SizedBox(height: 14),
            Text(
              _toastText,
              style: const TextStyle(fontSize: 22, color: Colors.white, height: 1.5),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 400.ms, curve: Curves.easeOutCubic)
        .slideX(begin: 0.1, end: 0, duration: 400.ms, curve: Curves.easeOutCubic);
  }

  // ── 하단 바 (입력) ────────────────────────────
  Widget _buildBottomBar() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(TV.radiusLg),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xF0141416),
            borderRadius: BorderRadius.circular(TV.radiusLg),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: _buildInputRow(),
        ),
      ),
    );
  }

  Widget _buildToastRow() {
    return Row(children: [
      Icon(Icons.smart_toy_rounded, size: 20, color: TV.accent.withOpacity(0.8)),
      const SizedBox(width: 12),
      Expanded(
        child: Text(_toastText, style: const TextStyle(fontSize: 22, color: Colors.white, height: 1.4),
            maxLines: 2, overflow: TextOverflow.ellipsis),
      ),
      const SizedBox(width: 12),
      // 대화 계속하기 버튼
      GestureDetector(
        onTap: () => setState(() { _inputVisible = true; Future.delayed(100.ms, () => _inputFocus.requestFocus()); }),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20)),
          child: const Text('답장', style: TextStyle(fontSize: 22, color: TV.accent)),
        ),
      ),
    ]);
  }

  Widget _buildInputRow() {
    return Row(children: [
      const Icon(Icons.mic_rounded, size: 22, color: TV.accent),
      const SizedBox(width: 12),
      Expanded(
        child: TextField(
          controller: _inputController,
          focusNode: _inputFocus,
          style: const TextStyle(color: Colors.white, fontSize: 22),
          decoration: const InputDecoration(
            hintText: '무엇이든 말씀하세요...',
            hintStyle: TextStyle(color: Color(0xFF666666), fontSize: 22),
            border: InputBorder.none, isDense: true,
            contentPadding: EdgeInsets.symmetric(vertical: 8),
          ),
          onSubmitted: (t) { _sendMessage(t); _inputController.clear(); },
        ),
      ),
      const SizedBox(width: 12),
      Semantics(
        label: '전송',
        button: true,
        child: GestureDetector(
        onTap: () { _sendMessage(_inputController.text); _inputController.clear(); },
        child: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(color: TV.accent, borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.arrow_upward_rounded, size: 20, color: Colors.white),
        ),
      )),
      const SizedBox(width: 8),
      Semantics(
        label: '닫기',
        button: true,
        child: GestureDetector(
        onTap: () => setState(() => _inputVisible = false),
        child: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.close_rounded, size: 18, color: Color(0xFFAAAAAA)),
        ),
      )),
    ]);
  }

  // ── 오버레이 팝업 (show_chat=true일 때) ────────
  Widget _buildOverlayPopup() {
    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() => _popupVisible = false),
        child: Container(
          color: Colors.black.withOpacity(0.5),
          child: Center(
            child: GestureDetector(
              onTap: () {}, // 팝업 내부 클릭 시 닫기 방지
              child: Container(
                width: 500, constraints: const BoxConstraints(maxHeight: 500),
                decoration: BoxDecoration(
                  color: TV.bgCard,
                  borderRadius: BorderRadius.circular(TV.radiusLg),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 40)],
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  // 헤더
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 12, 12),
                    child: Row(children: [
                      const Icon(Icons.smart_toy_rounded, size: 20, color: TV.accent),
                      const SizedBox(width: 10),
                      const Text('LISA', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Colors.white)),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => setState(() => _popupVisible = false),
                        child: Container(width: 36, height: 36,
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), shape: BoxShape.circle),
                          child: const Icon(Icons.close_rounded, size: 18, color: Color(0xFFAAAAAA))),
                      ),
                    ]),
                  ),
                  // 대화 내용
                  Flexible(
                    child: ValueListenableBuilder<List<ChatMessage>>(
                      valueListenable: _conversation.conversation,
                      builder: (_, messages, __) {
                        final textMsgs = messages.where((m) => m is UserMessage || m is AiTextMessage).toList();
                        return ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                          itemCount: textMsgs.length,
                          itemBuilder: (_, i) {
                            final m = textMsgs[i];
                            final isUser = m is UserMessage;
                            String text = '';
                            if (m is UserMessage) text = m.parts.whereType<TextPart>().map((p) => p.text).join(' ');
                            else if (m is AiTextMessage) text = m.text;
                            if (text.isEmpty) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(
                                mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                                children: [
                                  Flexible(child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: isUser ? TV.accent : Colors.white.withOpacity(0.06),
                                      borderRadius: BorderRadius.circular(14)),
                                    child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 22)),
                                  )),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  // 입력
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Row(children: [
                      Expanded(child: Container(
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(12)),
                        child: TextField(
                          style: const TextStyle(color: Colors.white, fontSize: 22),
                          decoration: const InputDecoration(
                            hintText: '입력...', hintStyle: TextStyle(color: Color(0xFF666666), fontSize: 22),
                            border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
                          onSubmitted: (t) { _sendMessage(t); },
                        ),
                      )),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {},
                        child: Container(width: 40, height: 40,
                          decoration: BoxDecoration(color: TV.accent, borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.arrow_upward_rounded, size: 18, color: Colors.white)),
                      ),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── 데이터 모델 ──────────────────────────────

/// 4컬럼 × 3로우 그리드 — iOS 위젯 스타일
/// S=1×1, M=2×1, L=2×2, W=4×1, WL=4×2, XL=2×3
enum _GridSpan {
  s,   // 1×1 (1col, 1row)
  m,   // 2×1 (2col, 1row)
  l,   // 2×2 (2col, 2row)
  w,   // 4×1 (4col, 1row)
  wl,  // 4×2 (4col, 2row) — MoviePosterGrid
  xl,  // 2×3 (2col, 3row) — DocumentCard
}

class _RenderedCard {
  final String surfaceId;
  final String typeName;
  final _GridSpan span;
  final Widget widget;
  _RenderedCard({required this.surfaceId, required this.typeName, required this.span, required this.widget});
}

// ── Fluid Glass 카드 래퍼 ─────────────────────
// 포커스: scale 1.10 + glow shadow + border
// Stack 없이 구현 — 카드 내부 GestureDetector 탭 이벤트 보장
class _FluidGlassCard extends StatefulWidget {
  final Widget child;
  final int index;
  const _FluidGlassCard({required this.child, this.index = 0});
  @override
  State<_FluidGlassCard> createState() => _FluidGlassCardState();
}

class _FluidGlassCardState extends State<_FluidGlassCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final disable = FluidGlassConfig.disableAllAnimations ||
        MediaQuery.of(context).disableAnimations;

    if (disable) return widget.child;

    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.select) {
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: RepaintBoundary(
        child: AnimatedScale(
          scale: _focused ? 1.10 : 1.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutBack,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(TV.radiusMd),
              border: _focused
                  ? Border.all(color: Colors.white.withOpacity(0.4), width: 2)
                  : null,
              boxShadow: _focused
                  ? [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 32,
                        offset: const Offset(0, 10),
                      ),
                      BoxShadow(
                        color: Colors.white.withOpacity(0.08),
                        blurRadius: 20,
                        spreadRadius: 4,
                      ),
                    ]
                  : [],
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

// ── AI Comment Card (AI 코멘트, 일정 시간 후 자동 사라짐) ──
class _AiCommentCard extends StatelessWidget {
  final String text;
  const _AiCommentCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(TV.radiusMd),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // AI 헤더
            Row(children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: TV.accent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.smart_toy_rounded, size: 16, color: TV.accent),
              ),
              const SizedBox(width: 10),
              const Text('LISA', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TV.accent)),
            ]),
            const SizedBox(height: 12),
            // 텍스트 (HTML 태그 strip)
            Text(
              _stripHtmlTags(text),
              style: const TextStyle(fontSize: 22, color: Colors.white, height: 1.5),
            ),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 400.ms, curve: Curves.easeOutCubic)
        .slideY(begin: 0.05, end: 0, duration: 400.ms, curve: Curves.easeOutCubic);
  }
}

// ── Ghost Card (로딩 중 shimmer) ──────────────
class _GhostCard extends StatefulWidget {
  const _GhostCard({super.key});
  @override
  State<_GhostCard> createState() => _GhostCardState();
}

class _GhostCardState extends State<_GhostCard> {
  int _seconds = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(TV.radiusMd),
      ),
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 타이머 (우상단)
          Row(children: [
            const SizedBox(width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: TV.accent)),
            const SizedBox(width: 8),
            Text('${_seconds}s',
              style: const TextStyle(fontSize: 22, color: TV.accent, fontWeight: FontWeight.w500)),
            const Spacer(),
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: TV.accent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.smart_toy_rounded, size: 14, color: TV.accent),
            ),
          ]),
          const SizedBox(height: 24),
          // Shimmer bars
          _ShimmerBar(width: 0.85),
          const SizedBox(height: 12),
          _ShimmerBar(width: 0.6),
          const SizedBox(height: 12),
          _ShimmerBar(width: 0.4),
          const SizedBox(height: 24),
          // 하단 텍스트
          Text('생각하는 중...',
            style: TextStyle(fontSize: 22, color: Colors.white.withOpacity(0.4))),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 400.ms, curve: Curves.easeOutCubic)
        .scale(begin: const Offset(0.95, 0.95), end: const Offset(1, 1),
            duration: 400.ms, curve: Curves.easeOutCubic);
  }
}

class _ShimmerBar extends StatelessWidget {
  final double width;
  const _ShimmerBar({required this.width});
  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: width,
      child: Container(
        height: 14,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(7),
        ),
      )
          .animate(onPlay: (c) => c.repeat())
          .shimmer(duration: 1500.ms, color: Colors.white.withOpacity(0.08)),
    );
  }
}

// ── Error Card (에러 시 재시도) ────────────────
class _ErrorCard extends StatefulWidget {
  final VoidCallback onRetry;
  final VoidCallback onDismiss;
  const _ErrorCard({required this.onRetry, required this.onDismiss});
  @override
  State<_ErrorCard> createState() => _ErrorCardState();
}

class _ErrorCardState extends State<_ErrorCard> {
  Timer? _dismissTimer;
  bool _retryFocused = false;

  @override
  void initState() {
    super.initState();
    // 8초 후 자동 닫기
    _dismissTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(TV.radiusMd),
        border: Border.all(color: TVTheme.tintWarm.withOpacity(0.3)),
      ),
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.warning_amber_rounded, size: 48,
              color: TVTheme.tintWarm.withOpacity(0.8)),
          const SizedBox(height: 16),
          const Text('응답할 수 없어요',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: Colors.white)),
          const SizedBox(height: 8),
          Text('잠시 후 다시 시도해 주세요',
            style: TextStyle(fontSize: 22, color: Colors.white.withOpacity(0.5))),
          const SizedBox(height: 24),
          // 다시 시도 버튼
          Focus(
            autofocus: true,
            onFocusChange: (f) => setState(() => _retryFocused = f),
            child: GestureDetector(
              onTap: widget.onRetry,
              child: AnimatedScale(
                scale: _retryFocused ? 1.10 : 1.0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutBack,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                  decoration: BoxDecoration(
                    color: _retryFocused ? TV.accent : TV.accent.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(14),
                    border: _retryFocused
                        ? Border.all(color: Colors.white.withOpacity(0.4), width: 2)
                        : null,
                    boxShadow: _retryFocused
                        ? [BoxShadow(color: TV.accent.withOpacity(0.3), blurRadius: 16)]
                        : [],
                  ),
                  child: const Text('다시 시도',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ),
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 400.ms, curve: Curves.easeOutCubic)
        .scale(begin: const Offset(0.95, 0.95), end: const Offset(1, 1),
            duration: 400.ms, curve: Curves.easeOutCubic)
        .shake(hz: 2, duration: 400.ms, offset: const Offset(2, 0));
  }
}

// ── TV 월페이퍼 (시간대별 자동 변경) ─────────
class _TVWallpaper extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;

    // 시간대별 이미지 URL
    final String url;
    if (hour >= 6 && hour < 12) {
      // 아침: 일출/아침 풍경
      url = 'https://images.unsplash.com/photo-1470071459604-3b5ec3a7fe05?w=1920&q=80';
    } else if (hour >= 12 && hour < 17) {
      // 낮: 맑은 하늘/자연
      url = 'https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=1920&q=80';
    } else if (hour >= 17 && hour < 20) {
      // 저녁: 노을
      url = 'https://images.unsplash.com/photo-1475924156734-496f6cac6ec1?w=1920&q=80';
    } else {
      // 밤: 야경/별
      url = 'https://images.unsplash.com/photo-1519681393784-d120267933ba?w=1920&q=80';
    }

    return Stack(children: [
      // 선명한 배경 이미지 (블러 없음)
      Positioned.fill(
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [Color(0xFF0a0e1a), Color(0xFF1a1a2e)],
              ),
            ),
          ),
        ),
      ),
      // 하단 그라데이션 (카드 가독성)
      Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black.withOpacity(0.1),
                Colors.black.withOpacity(0.4),
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        ),
      ),
    ]);
  }
}
