# TV A2UI Implementation Specification

이 문서만 보고 앱 전체를 처음부터 재구현할 수 있도록 작성된 상세 스펙.

---

## 1. 앱 개요

webOS TV에서 실행되는 AI 어시스턴트 오버레이 앱.
TV 시청 중 투명 레이어로 떠 있다가 사용자 호출 시 AI가 생성한 카드(GenUI)를 표시.
카드 내 액션(유튜브 재생, 앱 실행 등)을 TV 네이티브로 전달.

| 항목 | 값 |
|------|-----|
| 프레임워크 | Flutter (Dart 3.2+) |
| 타겟 플랫폼 | webOS TV (ARM, floating window) + Web (개발용) |
| 백엔드 | ZeroClaw (Rust daemon, WebSocket) |
| 프로토콜 | A2UI v0.9 (참조: A2UI_V09_SPEC.md) |
| 디자인 | 다크 테마, 55" TV / 3m 시청 최적화 (참조: DESIGN.md) |
| 앱 ID | dev.lge.tv.a2ui |
| 윈도우 타입 | floating (투명, needFocus 동적 전환) |

---

## 2. 아키텍처

### 2.1 전체 흐름

```
사용자 입력 (텍스트/음성)
  |
  v
HomeScreen._sendMessage()
  |
  v
GenUiConversation.sendRequest(UserMessage)
  |
  v
LisaWsContentGenerator --- WebSocket ---> ZeroClaw daemon
                                              |
                                              v
                                         OpenAI GPT (Azure)
                                              |
                                              v
                                         A2UI v0.9 JSON 응답
  <--- WebSocket (a2ui frames) ---
  |
  v
LisaWsContentGenerator._convertV09ToSdk()
  |
  v
A2uiMessage.fromJson() --> GenUiConversation 콜백
  |
  v
onSurfaceAdded/Updated --> _addRenderedCard()
  |
  v
CatalogItem.widgetBuilder() --> Flutter Widget
  |
  v
Spotlight 표시 --> 사용자 dismiss --> Widget Shelf 저장
```

### 2.2 의존성 (pubspec.yaml)

```yaml
dependencies:
  flutter: {sdk: flutter}
  http: ^1.2.0
  provider: ^6.1.1
  flutter_animate: ^4.3.0
  google_fonts: ^6.1.0
  shimmer: ^3.0.0
  speech_to_text: ^6.6.0
  flutter_tts: ^4.0.2
  uuid: ^4.2.1
  shared_preferences: ^2.2.2
  url_launcher: ^6.2.0
  flutter_widget_from_html: ^0.15.2
  web_socket_channel: ^3.0.0
  genui:
    path: vendor/genui
  webos_service_bridge:
    git:
      url: ssh://wall.lge.com:29448/module/flutter-webos-plugins
      path: packages/webos_service_bridge/
      ref: master

dependency_overrides:
  genai_primitives:
    path: vendor/genai_primitives
  json_schema_builder:
    path: vendor/json_schema_builder
  flutter_markdown_plus:
    path: vendor/flutter_markdown_plus
```

빌드 플래그: `--no-tree-shake-icons` 필수 (json_schema_builder의 IconTreeShaker 실패 방지).

### 2.3 vendor 라이브러리

| 패키지 | 역할 |
|--------|------|
| genui | A2UI SDK: GenUiConversation, ContentGenerator, A2uiMessage, CatalogItem, UiDefinition 등 |
| genai_primitives | AI 모델 기본 타입 (ChatMessage, UserMessage, TextPart 등) |
| json_schema_builder | A2UI 컴포넌트 JSON 스키마 빌드/검증 |
| flutter_markdown_plus | 마크다운 렌더링 |

---

## 3. 파일 구조

```
lib/
  main.dart                          # 진입점: LS2 등록, 전체화면, 가로 고정
  screens/
    home_screen.dart                 # 메인 화면 (~1950줄): 상태머신, 레이아웃, 인터랙션 전체
  catalog/
    tv_catalog.dart                  # TV 커스텀 카드 카탈로그 (~2500줄): 20+ 카드 타입
  services/
    lisa_ws_content_generator.dart   # WebSocket ContentGenerator (ZeroClaw 통신)
    a2ui_content_generator.dart      # HTTP ContentGenerator (레거시, 미사용)
    gpt_service.dart                 # 직접 GPT 호출 (레거시, 미사용)
    app_provider.dart                # Provider 상태관리 (레거시, 미사용)
  models/
    models.dart                      # 레거시 데이터 모델 (UICard, ChatMessage 등)
  theme/
    tv_theme.dart                    # TVTheme (Material ThemeData) + FluidGlassConfig
  widgets/
    chat_overlay.dart                # 채팅 오버레이 (레거시)
    tv_card.dart                     # 단일 카드 위젯 (레거시)
    voice_button.dart                # STT 음성 버튼

webos/
  meta/appinfo.json                  # webOS 앱 매니페스트 (floating, transparent)
  runner/main.cc                     # 네이티브 진입점
  runner/flutter_window.cc           # 윈도우 관리
  sysbus/                            # Luna 서비스 퍼미션 템플릿
  CMakeLists.txt                     # webOS CMake 빌드 설정
```

**활성 코드**: main.dart, home_screen.dart, tv_catalog.dart, lisa_ws_content_generator.dart, tv_theme.dart
**레거시 (미사용)**: a2ui_content_generator.dart, gpt_service.dart, app_provider.dart, models.dart, chat_overlay.dart, tv_card.dart

---

## 4. 진입점 (main.dart)

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    LS2ServiceChannel.registerWith();  // webOS Luna 서비스 브릿지
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([landscapeLeft, landscapeRight]);
  }
  runApp(A2UIApp());
}
```

MaterialApp 설정:
- `debugShowCheckedModeBanner: false`
- `color: Colors.transparent` (floating window 투명)
- `theme: TVTheme.build()` (다크 테마)
- `shortcuts`: 방향키 4개를 DirectionalFocusIntent에 매핑 (TV 리모컨 네비게이션)
- `home: HomeScreen()`

---

## 5. 상태 머신 (HomeScreen)

### 5.1 3가지 모드

```
                   새 카드 도착
    Edge ──────────────────────> Spotlight
     ^                              |
     |  BACK/ESC (카드 없을 때)      | 탭/dismiss/BACK
     |                              v
     +<──── BACK/ESC ────────── Widget Shelf
     +<──── RED 키 (토글) ─────────+
```

| 모드 | 조건 | 화면 | needFocus |
|------|------|------|-----------|
| Edge | `!_widgetVisible && _spotlightCard == null` | 우측 16x120px 핸들 | false (TV가 입력 받음) |
| Spotlight | `_spotlightCard != null && !_widgetVisible` | 카드 전면 + AI 코멘트 | true |
| Widget Shelf | `_widgetVisible` | 저장된 카드 그리드 (3x2) | true |

### 5.2 상태 변수

```dart
// 카드 렌더링 (레거시 그리드, 현재 미사용)
List<_RenderedCard> _renderedCards = [];
List<String> _surfaceIds = [];
int _gridPage = 0;

// Spotlight
Widget? _spotlightCard;        // 전면 카드 위젯
String? _spotlightSurfaceId;   // 카드 surfaceId (__ghost__, __error__, __text__, 또는 실제 ID)
String _spotlightText = '';    // AI 코멘트 텍스트 (카드 옆에 표시)
_GridSpan? _spotlightSpan;     // 카드 크기 (spotlight 레이아웃 계산용)
String? _spotlightTypeName;    // 카드 타입명

// Widget Shelf
List<_RenderedCard> _widgetCards = [];  // 저장된 카드 (최대 12개)
bool _widgetVisible = false;            // 위젯 선반 표시 여부
bool _overlayFromWidget = false;        // 위젯 모드에서 요청했는지

// 입력
bool _inputVisible = false;
TextEditingController _inputController;
FocusNode _inputFocus;

// 특수 카드
static const _ghostSurfaceId = '__ghost__';   // 로딩 중
static const _errorSurfaceId = '__error__';   // 에러
String? _newestSurfaceId;  // 최근 카드 dim 처리용
String? _lastUserMessage;  // 에러 시 재시도용

// Shake 감지
int _shakeCount = 0;         // 방향키 빠른 연속 카운터
DateTime? _lastShakeTime;    // 마지막 shake 시각

// 타이머
int _elapsedSeconds = 0;     // 로딩 경과 시간 (GhostCard 표시용)
Timer? _elapsedTimer;
```

### 5.3 특수 Spotlight 상태

| surfaceId | 카드 | 트리거 | 특징 |
|-----------|------|--------|------|
| `__ghost__` | _GhostCard | isProcessing = true | shimmer 로딩, 경과 시간 표시, 실제 카드 도착 시 자동 교체 |
| `__error__` | _ErrorCard | onError 콜백 | 8초 자동 닫힘, 재시도 버튼, dismiss 버튼 |
| `__text__` | _AiCommentCard | 카드 없이 텍스트만 왔을 때 | AI 텍스트를 단독 카드로 표시 |
| 실제 ID | 카탈로그 카드 | onSurfaceAdded/Updated | 정상 카드 |

### 5.4 Spotlight → Widget 전환 로직

`_saveSpotlightAndShowWidget()` (탭/dismiss 버튼):

1. `_spotlightCard == null`이면 return
2. ghost/error/text-only가 아니면 `_widgetCards.insert(0, card)`
3. 하나의 `setState()` 안에서:
   - spotlight 변수 전부 null로 초기화
   - `_widgetVisible = _widgetCards.isNotEmpty`
   - `_inputVisible = false`
4. `_setInputCapture('full' or 'edge')`

`_dismissSpotlight()` (BACK키/방향키4회/음성키워드):
- 동일하게 카드를 widget shelf로 이동
- `_overlayFromWidget = false` 추가 초기화

---

## 6. 입력 캡처 (webOS Window Focus)

```dart
void _setInputCapture(String mode) {
  // mode: 'edge' | 'full'
  _webosSystemChannel.invokeMethod('windowProperty', {
    'property': 'needFocus',
    'value': mode == 'full' ? 'true' : 'false',
  });
}
```

| mode | needFocus | 동작 |
|------|-----------|------|
| edge | false | TV(뒤 앱)가 리모컨 입력 받음. 오버레이 앱은 엣지 영역만 |
| full | true | 오버레이 앱이 리모컨 입력 독점 |

전환 시점:
- edge → full: 새 카드 도착(spotlight), 위젯 패널 열기
- full → edge: spotlight/panel 닫힘, 앱 런칭 후

---

## 7. 키보드/리모컨 매핑

`_handleKeyShake()` (HardwareKeyboard 글로벌 핸들러):

| 키 | 매핑 | 동작 |
|----|------|------|
| F1 / keyId 0x10600000020 / 398 | RED 키 (webOS Magic Remote) | `_toggleWidgetPanel()` |
| Escape / GoBack / keyId 0x00100000305 | BACK 키 | `_handleBackAction()` |
| ArrowLeft/Right x4 (800ms 이내) | Shake | `_dismissSpotlight()` |

`_handleBackAction()`:
1. `_widgetVisible` → `_toggleWidgetPanel()` (패널 닫기)
2. `_spotlightCard != null` → `_dismissSpotlight()` (spotlight 해제)
3. 둘 다 아니면 아무것도 안 함 (edge 상태 유지, 앱 종료 안 함)

마우스 우클릭: `_handleBackAction()` 호출 (Listener onPointerDown, kSecondaryMouseButton)

---

## 8. GenUI 연동

### 8.1 초기화

```dart
_contentGenerator = LisaWsContentGenerator('ws://SERVER_IP:42618/app');

_processor = A2uiMessageProcessor(catalogs: [
  CoreCatalogItems.asCatalog(),           // Basic 카탈로그 (Text, Column, Row...)
  Catalog(
    [...CoreCatalogItems.asCatalog().items, ...tvCatalogItems()],
    catalogId: 'https://a2ui.tv/catalogs/tv_home_v1.json',
  ),
]);

_conversation = GenUiConversation(
  contentGenerator: _contentGenerator,
  a2uiMessageProcessor: _processor,
  onSurfaceAdded: ...,
  onSurfaceUpdated: ...,
  onSurfaceDeleted: ...,
  onTextResponse: ...,
  onError: ...,
);
```

### 8.2 콜백 동작

**onSurfaceAdded / onSurfaceUpdated**:
1. 기존 같은 surfaceId 카드 제거
2. `_addRenderedCard(surfaceId, definition)` 호출

**onSurfaceDeleted**:
- `_renderedCards`에서 해당 surfaceId 제거

**onTextResponse(text)**:
1. HTML 태그 제거, 이모지 제거, a2ui 태그 필터링
2. raw JSON (시작이 `{` or `[`)이면 무시
3. 50자 미만이면 표시 안 함
4. 카드가 방금 업데이트됐으면 (`_cardUpdatedRecently`):
   - 50자 이상이면 `_spotlightText`에만 설정 (코멘트 텍스트)
5. spotlight 비어있으면 → `_AiCommentCard`로 단독 spotlight
6. spotlight에 카드 있으면 → `_spotlightText`에 코멘트 추가

**onError**:
- `_ErrorCard` 생성 → spotlight에 배치
- retry: 마지막 메시지 재전송
- dismiss: spotlight 해제

### 8.3 isProcessing 변경

**true (요청 시작)**:
1. `_elapsedSeconds = 0`, 1초 타이머 시작
2. `_GhostCard` → spotlight 배치
3. input capture → full

**false (응답 완료)**:
1. 타이머 중지
2. spotlight이 아직 ghost면 → spotlight 해제, edge로 전환
3. 실제 카드가 도착했으면 ghost는 이미 교체됨

---

## 9. 카드 렌더링 파이프라인

### 9.1 _addRenderedCard(surfaceId, definition)

```
UiDefinition
  |
  +--> root 컴포넌트 타입 확인
  |
  +--> TV 커스텀 카드인가?
       |
       YES --> CatalogItem.widgetBuilder(CatalogItemContext) 직접 호출
       |       cardData = flat 속성 Map (JSON에서 추출)
       |       결과 Widget → spotlight 배치
       |
       NO  --> GenUiSurface(host, surfaceId) 사용 (Basic 카탈로그 조합)
               Theme.dark 오버라이드 적용
               SingleChildScrollView + ClipRect 래핑
               결과 Widget → spotlight 배치
```

### 9.2 두 카드 경로의 차이

| | TV 커스텀 카드 | Basic 카탈로그 |
|---|---|---|
| 판별 | `tvCatalogItems().map(i => i.name).contains(rootTypeName)` | 나머지 |
| 렌더링 | `catalogItem.widgetBuilder(context)` 직접 호출 | `GenUiSurface` 위젯 사용 |
| 데이터 | flat 속성 Map (`cardData`) | 데이터 바인딩 (path 참조, DataModel) |
| span | `_gridSpan(typeName, cardData)` | 고정 `_GridSpan.m` |

---

## 10. WebSocket 통신 (LisaWsContentGenerator)

### 10.1 연결

```
ws://SERVER_IP:42618/app[?session_id=xxx]
```

- 웹: 브라우저 현재 호스트로 자동 대체
- 재연결: 최대 5회, 3초 간격
- `web_socket_channel 3.x`: `channel.ready` future 완료 대기

### 10.2 수신 프레임

| type | 데이터 | 동작 |
|------|--------|------|
| `session_start` | session_id, resumed, message_count | 세션 ID 저장 |
| `a2ui` | messages[] | `_pendingA2ui`에 누적 (아직 emit 안 함) |
| `done` | full_response | 누적된 a2ui 변환+emit, 텍스트 emit, isProcessing=false |
| `error` | message | errorStream emit, isProcessing=false |
| `connected` | message | 로그만 |

핵심: `a2ui` 프레임은 바로 emit 안 하고 버퍼링. `done` 프레임에서 일괄 변환+emit.

### 10.3 송신 프레임

**메시지**: `{ "type": "message", "content": "사용자 텍스트" }`

**액션**: `{ "type": "a2ui_action", "payload": { surfaceId, name, sourceComponentId?, context?, dataModel? } }`

### 10.4 v0.9 → SDK 변환

| v0.9 | SDK |
|------|-----|
| createSurface | beginRendering |
| updateComponents | surfaceUpdate |
| updateDataModel | dataModelUpdate |
| deleteSurface | deleteSurface (그대로) |

컴포넌트 변환 (`_convertComponentToSdk`):
- `component`가 String이면 v0.9 형식 → `{ component: { TypeName: { ...props } } }`로 래핑
- `children` 배열 → `{ explicitList: [...] }`
- `variant`: TV 커스텀 카드는 유지, Basic 컴포넌트만 `usageHint`로 rename
- `Text.text`, `Image.url` 등 String → `{ literalString: value }`
- `Button.text` → 자동으로 child Text 컴포넌트 생성
- `Button.action.functionCall` → `{ name, context }` 변환
- TV 커스텀 카드 목록: WeatherCard, MediaRailCard, PlaceRailCard, MapCard, ArticleListCard, ArticleSummaryCard, ReviewSummaryCard, GameCard, ListCard, InfoCard, WebappCard, ControlCard, HomeControlCard, DeviceDetailCard, DocumentCard, ComparisonCard, RecipeCard, ContextCard

---

## 11. Grid 레이아웃 시스템

### 11.1 Span 타입

```dart
enum _GridSpan {
  s,   // 1x1 (1col, 1row)
  m,   // 2x1 (2col, 1row)
  l,   // 2x2 (2col, 2row)
  w,   // 4x1 (4col, 1row) - 풀 와이드
  wl,  // 4x2 (4col, 2row) - 풀 와이드 + 2줄
  xl,  // 2x3 (2col, 3row) - 세로 장문
}
```

### 11.2 카드 타입별 span 매핑

| 카드 | span | 크기 | 조건 |
|------|------|------|------|
| WeatherCard | m 또는 s | 2x1 / 1x1 | forecast 배열 있으면 m |
| MediaRailCard | wl 또는 w | 4x2 / 4x1 | variant=='movie' → wl |
| PlaceRailCard | w | 4x1 | |
| MapCard | l | 2x2 | |
| HomeControlCard | l | 2x2 | |
| ArticleListCard | m | 2x1 | |
| ContextCard, ControlCard, ReviewSummaryCard, ArticleSummaryCard, ListCard | m | 2x1 | |
| DocumentCard | xl | 2x3 | |
| RecipeCard | l | 2x2 | |
| ComparisonCard | m | 2x1 | |
| GameCard, InfoCard, WebappCard, 기타 | s | 1x1 | |

### 11.3 그리드 배치 알고리즘

**Spotlight 모드**: 단일 카드, span 기반으로 크기 계산
- 코멘트 없으면: `화면 50% * spanCols/2` (300~55% 클램프)
- 코멘트 있으면: 좌측 40% (300~45% 클램프)
- 높이: `화면 78% * spanRows/2` (300~80% 클램프)

**Widget Shelf**: 3x2 그리드 (cols=3, rows=2)
**Legacy Grid**: 4x3 그리드 (cols=4, rows=3) — 현재 미사용

배치: top-left first-fit 알고리즘
1. 전체 카드를 페이지 단위로 분배
2. 각 카드의 span에 맞는 빈 슬롯 검색 (행 우선, 좌→우)
3. 맞는 슬롯이 없으면 다음 페이지
4. 페이지 간 좌우 화살표 + dot 인디케이터

카드 하드 리밋: 12개 (renderedCards, widgetCards 각각)

---

## 12. UI 레이어 구조 (build 메서드)

```
PopScope(canPop: false)  // 백 버튼 앱 종료 차단
  Listener(behavior: translucent)  // 마우스 우클릭 → BACK
    Scaffold(backgroundColor: transparent, resizeToAvoidBottomInset: false)
      SizedBox.expand
        Stack[
          // 1. Spotlight 레이어 (조건: _spotlightCard != null && !_widgetVisible)
          Positioned.fill(
            GestureDetector(onTap: _saveSpotlightAndShowWidget)
              _buildSpotlightLayer()
          )

          // 2. Widget Shelf (조건: _widgetVisible)
          Positioned.fill(_buildWidgetShelf())
            .animate().fadeIn(300ms)

          // 3. 우상단 마이크 버튼 (Spotlight 모드에서만)
          Positioned(top:24, right:48) 마이크 아이콘

          // 4. 하단 입력 바 (Spotlight 모드, _inputVisible일 때)
          AnimatedPositioned(bottom: _inputVisible ? 24 : -80)
            _buildBottomBar()

          // 5. 오버레이 팝업 (대화형, _popupVisible)
          _buildOverlayPopup()

          // 6. 디버그 오버레이 (항상)
          Positioned(left:10, bottom:10) 상태 텍스트

          // 7. Edge 핸들 (Edge 모드에서만)
          _buildEdgeHandle()
        ]
```

---

## 13. Spotlight 레이어 상세

`_buildSpotlightLayer()`:

```
Stack[
  LayoutBuilder(
    hasComment 여부에 따라 2가지 레이아웃:

    A) 코멘트 있음 (카드 좌 + 텍스트 우):
       Row[
         카드 (좌측 40%, 세로 중앙)
         AI 코멘트 (우측 35%, 상단)
       ]

    B) 코멘트 없음 (카드만 중앙):
       Center(카드)

    카드 래핑:
    - GestureDetector(onTap: (){}) — 카드 영역 탭 이벤트 소비
    - ghost: SizedBox만
    - 실제 카드: Container(배경 #141416, 둥근 모서리, 그림자) + ClipRRect
    - 아래에 "위젯으로 보내기" 버튼 (GestureDetector → _saveSpotlightAndShowWidget)

    AI 코멘트:
    - 배경: black 60%, 둥근 모서리
    - _buildMarkdownText() 로 **bold**, *italic* 렌더링
    - fadeIn + slideX 애니메이션 (400ms)
  )
]
```

---

## 14. Widget Shelf 상세

`_buildWidgetShelf()`:

```
Stack[
  투명 배경 (Positioned.fill)

  카드 그리드 (조건: _widgetCards.isNotEmpty)
    Positioned(left:48, top:80, right:48, bottom:100)
    _buildCards(cards: _widgetCards)  // 3x2 그리드

  입력 바 (조건: _inputVisible)
    Positioned(left:48, right:48, bottom:24)
    _buildBottomBar()

  우상단 버튼 Row (항상):
    마이크 버튼 (64x64 원형, 토글)
    닫기 버튼 (64x64, _toggleWidgetPanel)
]
```

위젯 선반 카드에는 우상단 삭제 버튼(28x28 X 아이콘) 추가.

---

## 15. Edge 핸들

`_buildEdgeHandle()`:

```
Positioned(right:0, top: 화면중앙-60)
  GestureDetector(onTap: _toggleWidgetPanel)
    Container(
      width: 16, height: 120
      색: 저장된 카드 있으면 accent/12%, 없으면 white/6%
      오른쪽 모서리만 둥글게 (8px)
    )
    배지: _widgetCards.length > 0이면 카운트 표시 (10px 파란 원 + 숫자)
```

---

## 16. 입력 처리

### 16.1 텍스트 입력

`_buildBottomBar()` → `_buildInputRow()`:
- `ClipRRect` + Container (#141416 배경, 보더)
- TextField (자동완성 끔, 한 줄, onSubmitted → `_sendMessage`)
- 전송 버튼 (accent 색 원형)

### 16.2 _sendMessage(text)

1. 빈 문자열 → return
2. dismiss 키워드 체크: '카드 내려', '알겠어', '내려', '닫아', '확인', '넘어가'
   - spotlight에 카드 있고 키워드 매칭 → `_dismissSpotlight()` + 입력 숨기기
3. 위젯 모드에서 요청 시 → `_overlayFromWidget = true`, 위젯 닫기
4. 이전 spotlight 자동 해제 (`_dismissSpotlight()`)
5. `_conversation.sendRequest(UserMessage.text(text))`
6. 입력 숨기기

### 16.3 음성 입력 (VoiceButton, 레거시)

- speech_to_text 플러그인, 한국어 locale
- 15초 리스닝 윈도우, 3초 무음 자동 정지
- 현재는 spotlight 모드의 마이크 버튼으로 대체 (텍스트 입력 토글)

---

## 17. 카드 액션 이벤트

`_handleCardEvent(event, typeName)`:

| 액션 | 동작 |
|------|------|
| `answer` | 퀴즈 답변: `_conversation.sendRequest(choice)` |
| `openUrl` | `openUrl(url)` + `_collapseToEdge()` |
| `launchApp` | URL이면 `openUrl`, 아니면 Luna `applicationManager/launch` + `_collapseToEdge()` |
| `launchCategory` | Luna `launchDefaultApp` + `_collapseToEdge()` |

### openUrl(url) - webOS 네이티브 앱 매핑

```dart
const _urlAppMap = {
  'youtube.com': 'youtube.leanback.v4',
  'youtu.be': 'youtube.leanback.v4',
  'netflix.com': 'netflix',
  'disneyplus.com': 'com.disney.disneyplus-prod',
  'coupangplay.com': 'coupangplay',
  'wavve.com': 'pooq',
  'tving.com': 'cj.eandm',
  'amazon.com/video': 'amazon',
  'primevideo.com': 'amazon',
};
```

매칭되는 앱 있으면: Luna `applicationManager/launch` + params(contentTarget 또는 target)
매칭 없으면: `com.webos.app.browser`로 URL 전달
웹: `url_launcher` 사용

---

## 18. 특수 카드 위젯

### 18.1 _GhostCard (로딩)

- shimmer 3개 바 (길이 다름: 70%, 55%, 40%)
- 경과 시간 표시 (1초 단위)
- 무한 반복 shimmer 애니메이션 (1500ms)
- fade + slideX 애니메이션

### 18.2 _ErrorCard

- 에러 아이콘 + "문제가 발생했어요" 텍스트
- "다시 시도" 버튼 → `onRetry` (마지막 메시지 재전송)
- 8초 후 자동 dismiss → `onDismiss`

### 18.3 _AiCommentCard

- AI 텍스트를 단독 카드로 표시
- 배경 #161618, 좌측 accent 세로선 (3px)
- 마크다운 렌더링 지원

### 18.4 _FluidGlassCard (포커스 래퍼)

- Focus 위젯으로 래핑
- 포커스 시: scale 1.10, 흰색 보더 2px, 글로우 쉐도우
- 비포커스: scale 1.0, 보더 없음
- `FluidGlassConfig.disableAllAnimations`이면 패스스루
- Select 키(OK 버튼): Focus.of(context).requestFocus(primaryFocus?.children.first) 호출

### 18.5 _TVWallpaper

- 시간대별 배경색 그라데이션 (현재 투명이므로 비활성)
- 06-12시: 아침, 12-18시: 낮, 18-22시: 저녁, 22-06시: 밤

---

## 19. TV 카탈로그 카드 상세 (tv_catalog.dart)

### 19.1 디자인 토큰 (TV 클래스)

TVTheme (Material 테마)와 별도로 TV 카탈로그 전용 토큰:

```dart
class TV {
  // 배경
  static const bg = Color(0xFF0A0A0C);
  static const bgCard = Color(0xFF161618);

  // 텍스트
  static const text = Color(0xFFF5F5F7);
  static const textSub = Color(0xFFB8B8BC);
  static const textMuted = Color(0xFF6E6E73);

  // 타이포 (텍스트 쉐도우 포함)
  static h1 = TextStyle(fontSize: 40, fontWeight: w700);
  static h2 = TextStyle(fontSize: 30, fontWeight: w600);
  static body = TextStyle(fontSize: 24, fontWeight: w400);
  static sub = TextStyle(fontSize: 22);
  static caption = TextStyle(fontSize: 20);
  static small = TextStyle(fontSize: 18);

  // 액센트 — 민트
  static const accent = Color(0xFF00D4AA);
  static const green = Color(0xFF30D158);
  static const orange = Color(0xFFFF9F0A);
  static const red = Color(0xFFFF453A);
  static const purple = Color(0xFF5E5CE6);
  static const teal = Color(0xFF64D2FF);

  // Focus
  static const focusScale = 1.05;
  static const focusScaleLarge = 1.10;

  // 레이아웃
  static const padding = 32.0;
  static const radiusXs = 10.0;
  static const radiusSm = 16.0;
  static const radiusMd = 20.0;
  static const radiusLg = 28.0;
}
```

### 19.2 tvCardBox() — 글래스 카드 데코레이션

```dart
BoxDecoration tvCardBox({bool focused = false}) {
  return BoxDecoration(
    color: Colors.black.withOpacity(focused ? 0.75 : 0.55),
    borderRadius: BorderRadius.circular(TV.radiusMd),
    border: focused
        ? Border.all(color: Colors.white.withOpacity(0.5), width: 2)
        : Border.all(color: Colors.white.withOpacity(0.1)),
    boxShadow: focused
        ? [BoxShadow(white 8%, blur 20, spread 4),
           BoxShadow(black 50%, blur 32, offset (0,10))]
        : [BoxShadow(black 25%, blur 12, offset (0,4))],
  );
}
```

### 19.3 카드 타입별 구현

#### WeatherCard
- 도시명 (36px), 날씨 설명 (36px), 아이콘 (72px Material Icon)
- Hero 온도 (96px, w200, letterSpacing -4)
- 상세: 최고/최저/체감/습도 (28px)
- 주간 예보: 가로 Row, 요일 + 아이콘(48px) + 온도
- WMO 코드 → 한국어 + Material Icon 매핑
- span: forecast 있으면 2x1, 없으면 1x1

#### MediaRailCard
- variant: 'youtube' 또는 'movie'
- YouTube: 썸네일 (img.youtube.com/vi/{id}/hqdefault.jpg), 제목, 채널, 시간
- Movie: 영화 포스터 (그라데이션 hue → 색상), 제목, 개봉일, 순위
- _ScrollableRail: 가로 스크롤 + 좌우 화살표
- 클릭: openUrl 액션 dispatch
- span: movie=4x2, youtube=4x1

#### PlaceRailCard
- 장소 리스트 가로 스크롤
- 장소 카드: 이미지/gradient, 이름, 카테고리, 평점, 배지
- 클릭: openUrl

#### MapCard
- Google Static Maps 임베드 + 장소 목록
- 좌측: 지도 이미지, 우측: 장소 리스트

#### HomeControlCard
- 방별 기기 그리드
- 헤더: 제목 + ON/OFF 카운트
- 방 섹션: 방 이름 + 기기 타일
- 기기 타일: 아이콘 + 이름 + ON/OFF 토글
- 클릭 시 DeviceDetailWidget 생성 → widgetCards에 추가

#### ArticleListCard
- 기사 리스트: 태그, 제목, 출처, 시간
- 클릭: openUrl

#### ArticleSummaryCard
- 요약 텍스트 + 섹션 (아이콘 + 제목 + 내용)
- 출처, 시간 표시

#### ReviewSummaryCard
- 평점 별, 리뷰 수, 요약
- 인기 메뉴, 리뷰 인용

#### GameCard
- state: 'question' → 문제 + 선택지
- state: 'feedback' → 정답/오답 + 해설
- 선택지 클릭 → 'answer' 액션 dispatch

#### ListCard
- 체크박스 리스트 (토글 가능)

#### InfoCard, ContextCard
- 제목 + 내용 + 팁/설명

#### DocumentCard
- 장문 텍스트 (2x3 span)
- 스크롤 가능

#### ComparisonCard
- 비교표 형식

#### RecipeCard
- 이미지 + 재료 + 조리법

#### WebappCard
- AI 생성 HTML 임베드 (flutter_widget_from_html)

### 19.4 TVFocusable — 포커스 래퍼

```dart
class TVFocusable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double focusScale; // 기본 TV.focusScale (1.05)
}
```
- AnimatedScale + AnimatedContainer (300ms, easeOutBack)
- 포커스: scale 확대 + 흰색 보더 + 글로우
- Select/Enter 키: onTap 호출

### 19.5 _ScrollableRail — 가로 스크롤

- ScrollController + 좌우 화살표 버튼
- 화살표: 어둑한 원형 배경 + chevron 아이콘
- 스크롤 오프셋으로 화살표 표시/숨김

---

## 20. 마크다운 렌더링

`_buildMarkdownText(raw)`:
1. HTML 태그 제거 (`_stripHtmlTags`)
2. 이모지 제거
3. `**bold**` → TextSpan(fontWeight: w700)
4. `*italic*` → TextSpan(fontStyle: italic)
5. RichText 반환 (fontSize: 24, white, height: 1.6)

---

## 21. webOS 매니페스트 (appinfo.json)

```json
{
  "id": "dev.lge.tv.a2ui",
  "version": "0.9.0",
  "type": "flutter",
  "defaultWindowType": "floating",
  "transparent": true,
  "noSplashOnLaunch": true,
  "spinnerOnLaunch": false,
  "handlesRelaunch": true,
  "uiRevision": 2,
  "trustLevel": "default"
}
```

핵심:
- `floating`: 뒤 앱과 입력 공유 가능
- `transparent`: alpha 블렌딩 (투명 배경)
- `noSplashOnLaunch`: 스플래시 없음

---

## 22. 빌드 및 배포

### 22.1 webOS IPK 빌드

```bash
source ~/starfish-sdk-x86_64/environment-setup-ca9v1-webosmllib32-linux-gnueabi
flutter-webos build webos --ipk --release --no-tree-shake-icons
# 결과: build/webos/arm/release/ipk/dev.lge.tv.a2ui.ipk
```

### 22.2 TV 설치

1. SSH 접속 (포트 2181)
2. devmode 인증서 생성 (재부팅마다 필요)
3. 기존 앱 삭제: Luna 서비스 파일 제거 + ls-control scan
4. IPK 설치: `luna-send ... com.webos.appInstallService/dev/install`
5. ls-control scan-volatile-dirs
6. 실행: `luna-send ... com.webos.applicationManager/launch`

순서 위반 시 `LS::Error: Invalid permissions` 크래시.

### 22.3 서버 실행

```bash
source ~/.zeroclaw/.env
cd ~/work/lisa && ./target/release/zeroclaw daemon
```

daemon 모드 필수. `gateway start`만으로는 Lisa 채널 미동작.

---

## 23. 알려진 제약사항 / 주의사항

1. **최소 폰트 20px**: 55" TV / 3m 거리 기준 가독성 보장
2. **이모지 금지**: 카드에 이모지 대신 Material Icons 사용
3. **BackdropFilter 사용 금지**: TV 하드웨어 성능 이슈
4. **연속 루프 애니메이션 금지**: shimmer는 one-shot
5. **카드 내부 탭 이벤트**: spotlight의 GestureDetector가 translucent 모드이므로, 카드 내부에도 onTap: (){} (빈 핸들러)을 두어 이벤트 소비해야 바깥 탭이 카드 영역에서 트리거되지 않음
6. **GlobalKey 충돌**: spotlight → widget shelf 전환 시 같은 위젯 인스턴스가 이동하므로, 한 프레임에서 unmount 후 다음 mount 필요 (또는 동기 setState로 동시 처리)
7. **webOS needFocus 전환**: floating 윈도우에서 needFocus: false → 뒤 앱이 입력 받음. edge 모드에서만 false
8. **devmode cert**: TV 재부팅마다 재생성 필요
9. **포트**: 8xxx 포트 사용 금지 (사내 방화벽)

---

## 24. 데이터 흐름 예시

### "날씨 알려줘"

```
1. _sendMessage("날씨 알려줘")
2. isProcessing → true → GhostCard spotlight
3. WS → ZeroClaw → GPT → WeatherCard JSON
4. LisaWS: a2ui frame → 버퍼링
5. LisaWS: done frame → _convertV09ToSdk → emit
6. onSurfaceAdded → _addRenderedCard
7. WeatherCard 인스턴스 → spotlight (GhostCard 교체)
8. onTextResponse: "서울은 맑고 18도..." → _spotlightText
9. spotlight: 좌측 날씨 카드 + 우측 AI 코멘트
10. 사용자 탭 → _saveSpotlightAndShowWidget
11. 날씨 카드 → _widgetCards[0]
12. _widgetVisible = true → widget shelf 표시
```

### "유튜브 K-pop 검색"

```
1. _sendMessage("유튜브 K-pop 검색")
2. GhostCard spotlight
3. MediaRailCard (variant: youtube, items: [...]) 도착
4. spotlight: 유튜브 썸네일 가로 스크롤 레일
5. 사용자 영상 클릭 → _handleCardEvent('openUrl', {url: '...'})
6. openUrl: youtube.com 감지 → Luna launch youtube.leanback.v4
7. _collapseToEdge → edge 모드 (TV에서 유튜브 재생)
```

---

## 25. 레거시 코드 (참조용, 현재 미사용)

| 파일 | 설명 | 대체된 것 |
|------|------|----------|
| a2ui_content_generator.dart | HTTP 기반 ContentGenerator | lisa_ws_content_generator.dart |
| gpt_service.dart | HTTP GPT 직접 호출 | ZeroClaw WebSocket |
| app_provider.dart | Provider 상태관리 + TTS | GenUiConversation |
| models.dart | UICard, ChatMessage 등 | GenUI SDK 타입 |
| chat_overlay.dart | 채팅 오버레이 | spotlight + 입력 바 |
| tv_card.dart | 단일 카드 위젯 | CatalogItem.widgetBuilder |
| voice_button.dart | STT FAB | spotlight 마이크 버튼 |
| server.py | Python 프록시 서버 | ZeroClaw daemon |
