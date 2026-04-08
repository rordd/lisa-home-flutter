import 'dart:convert';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:genui/genui.dart';
import 'package:url_launcher/url_launcher.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:js' as js;

/// a2ui v0.9 TV 카탈로그 — TV Dark Theme + Focus System

// ── 디자인 토큰 (TV Dark) ────────────────────────
class TV {
  // 배경 — 깊은 다크, 레이어 분리
  static const bg = Color(0xFF0A0A0C);
  static const bgCard = Color(0xFF161618);
  static const bgCardHover = Color(0xFF222224);
  static const bgElevated = Color(0xFF1E1E20);

  // 텍스트 — 순백이 아닌 약간 따뜻한 화이트
  static const text = Color(0xFFF5F5F7);
  static const textSub = Color(0xFFB8B8BC);
  static const textMuted = Color(0xFF6E6E73);

  // 타이포 — 크기 대비 강화, 쉐도우 가볍게
  static const textShadow = [Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1))];
  static TextStyle h1 = const TextStyle(fontSize: 40, fontWeight: FontWeight.w700, color: text, letterSpacing: -0.5, height: 1.15);
  static TextStyle h2 = const TextStyle(fontSize: 30, fontWeight: FontWeight.w600, color: text, letterSpacing: -0.3, height: 1.2);
  static TextStyle body = const TextStyle(fontSize: 24, fontWeight: FontWeight.w400, color: text, height: 1.5);
  static TextStyle sub = const TextStyle(fontSize: 22, color: textSub, height: 1.5);
  static TextStyle caption = const TextStyle(fontSize: 20, color: textMuted, height: 1.4);

  // 액센트 — 정제된 민트 (채도 살짝 낮춤)
  static const accent = Color(0xFF00D4AA);
  static const green = Color(0xFF30D158);
  static const orange = Color(0xFFFF9F0A);
  static const red = Color(0xFFFF453A);
  static const purple = Color(0xFF5E5CE6);
  static const teal = Color(0xFF64D2FF);
  static const qGreen = Color(0xFF4CAF50);

  // Focus
  static const focusBorder = Color(0xFFFFFFFF);
  static const focusScale = 1.05;
  static const focusScaleLarge = 1.10;

  // 레이아웃
  static const padding = 32.0;
  static const radiusXs = 10.0;
  static const radiusSm = 16.0;
  static const radiusMd = 20.0;
  static const radiusLg = 28.0;

  // Opacity — 체계적 투명도 스케일
  static const overlayLight = 0.04;   // 미세한 배경 (비활성 카드, 서브 영역)
  static const overlayMedium = 0.08;  // 보더, 구분선, 배지 배경
  static const overlayStrong = 0.12;  // 호버, 활성 보더
  static const borderLight = 0.06;    // 기본 보더
  static const borderMedium = 0.15;   // 포커스 보더

  // 18px small 텍스트 (장르, 시간, 아주 작은 라벨)
  static TextStyle small = const TextStyle(fontSize: 18, color: textMuted, height: 1.4);
}

/// YouTube URL에서 video ID 추출
/// 지원: youtu.be/ID, youtube.com/watch?v=ID, youtube.com/embed/ID
String? _extractYoutubeId(String url) {
  // youtu.be/VIDEO_ID
  final shortMatch = RegExp(r'youtu\.be/([a-zA-Z0-9_-]{11})').firstMatch(url);
  if (shortMatch != null) return shortMatch.group(1);
  // youtube.com/watch?v=VIDEO_ID
  final watchMatch = RegExp(r'[?&]v=([a-zA-Z0-9_-]{11})').firstMatch(url);
  if (watchMatch != null) return watchMatch.group(1);
  // youtube.com/embed/VIDEO_ID
  final embedMatch = RegExp(r'/embed/([a-zA-Z0-9_-]{11})').firstMatch(url);
  if (embedMatch != null) return embedMatch.group(1);
  return null;
}

void openUrl(String url) {
  // Public: used by home_screen.dart for action dispatch handling
  print('[CATALOG] Opening URL: $url');
  // Flutter 웹에서는 url_launcher 대신 JS interop으로 직접 열기
  if (kIsWeb) {
    _openUrlWeb(url);
  } else {
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}

// Flutter 웹 전용: window.open 직접 호출
void _openUrlWeb(String url) {
  try {
    js.context.callMethod('open', [url, '_blank']);
    print('[CATALOG] Opened via JS: $url');
  } catch (e) {
    print('[CATALOG] JS open error: $e');
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}

/// action 모델 기반 이벤트 디스패치 (openUrl, launchApp 등)
/// action이 없으면 fallbackUrl로 openUrl fallback (하위호환)
void _dispatchAction(dynamic action, String? fallbackUrl,
    void Function(UiEvent) dispatchEvent, String sourceId) {
  if (action is Map<String, dynamic>) {
    final fc = action['functionCall'] as Map?;
    final ev = action['event'] as Map?;
    if (fc != null) {
      dispatchEvent(UserActionEvent(
        name: fc['call'] as String? ?? 'unknown',
        sourceComponentId: sourceId,
        context: Map<String, dynamic>.from(fc['args'] as Map? ?? {}),
      ));
    } else if (ev != null) {
      dispatchEvent(UserActionEvent(
        name: ev['name'] as String? ?? 'event',
        sourceComponentId: sourceId,
        context: Map<String, dynamic>.from(ev['context'] as Map? ?? {}),
      ));
    }
  } else if (fallbackUrl != null) {
    dispatchEvent(UserActionEvent(
      name: 'openUrl',
      sourceComponentId: sourceId,
      context: {'url': fallbackUrl},
    ));
  }
}

/// TV 카드 데코레이션 — 반투명 다크 글래스, 미세한 보더, 부드러운 그림자
/// 그리드에서 뒤 배경이 비치도록 반투명. Spotlight은 별도 불투명 래퍼 사용.
BoxDecoration tvCardBox({bool focused = false}) => BoxDecoration(
  color: focused ? const Color(0xDD1E1E22) : const Color(0xBB141416),
  borderRadius: BorderRadius.circular(TV.radiusMd),
  border: Border.all(
    color: focused
        ? Colors.white.withOpacity(0.35)
        : Colors.white.withOpacity(TV.overlayMedium),
    width: focused ? 1.5 : 0.5,
  ),
  boxShadow: [
    BoxShadow(
      color: Colors.black.withOpacity(focused ? 0.7 : 0.4),
      blurRadius: focused ? 40 : 16,
      offset: Offset(0, focused ? 12 : 6),
    ),
    if (focused)
      BoxShadow(
        color: TV.accent.withOpacity(0.06),
        blurRadius: 24,
        spreadRadius: 2,
      ),
  ],
);

/// 블러 카드 래퍼 — opacity-only glass (BackdropFilter 제거, 성능 우선)
Widget tvBlurCard({required Widget child, bool focused = false}) {
  return RepaintBoundary(
    child: ClipRRect(
      borderRadius: BorderRadius.circular(TV.radiusMd),
      child: Container(
        decoration: tvCardBox(focused: focused),
        child: Stack(
          children: [
            child,
            // 포커스 시 상단 edge highlight (미세한 광택)
            if (focused)
              Positioned(
                top: 0, left: 0, right: 0,
                child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.white.withOpacity(0.3),
                        Colors.white.withOpacity(0.3),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.3, 0.7, 1.0],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Focus 가능한 TV 위젯 래퍼
class TVFocusable extends StatefulWidget {
  final Widget Function(bool focused) builder;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool autofocus;
  final double focusScale;
  final String? semanticLabel;

  const TVFocusable({
    super.key,
    required this.builder,
    this.onTap,
    this.onLongPress,
    this.autofocus = false,
    this.focusScale = 1.05,
    this.semanticLabel,
  });

  @override
  State<TVFocusable> createState() => _TVFocusableState();
}

class _TVFocusableState extends State<TVFocusable> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.select) {
          widget.onTap?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Semantics(
        label: widget.semanticLabel,
        button: widget.onTap != null,
        focused: _focused,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          child: AnimatedScale(
            scale: _focused ? 1.10 : 1.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutBack,
            child: widget.builder(_focused),
          ),
        ),
      ),
    );
  }
}

// glassBox 호환용
BoxDecoration glassBox() => tvCardBox();

/// hue 파싱 — int 또는 색상 이름 문자열 모두 처리
int _parseHue(dynamic value, int fallback) {
  if (value is int) return value % 360;
  if (value is num) return value.toInt() % 360;
  if (value is String) {
    final asInt = int.tryParse(value);
    if (asInt != null) return asInt;
    const nameMap = {
      'red': 0, 'orange': 30, 'yellow': 60, 'green': 120,
      'teal': 170, 'cyan': 180, 'blue': 220, 'indigo': 240,
      'purple': 280, 'pink': 330, 'magenta': 300,
    };
    return nameMap[value.toLowerCase()] ?? fallback;
  }
  return fallback;
}

/// 가로 레일에 좌/우 스크롤 화살표를 추가하는 래퍼
class _ScrollableRail extends StatefulWidget {
  final double height;
  final double itemWidth;
  final int itemCount;
  final EdgeInsets padding;
  final double spacing;
  final Widget Function(BuildContext, int) itemBuilder;
  const _ScrollableRail({
    required this.height, required this.itemWidth, required this.itemCount,
    required this.itemBuilder, this.padding = EdgeInsets.zero, this.spacing = 16,
  });
  @override
  State<_ScrollableRail> createState() => _ScrollableRailState();
}

class _ScrollableRailState extends State<_ScrollableRail> {
  final ScrollController _sc = ScrollController();
  bool _showLeft = false;
  bool _showRight = true;

  @override
  void initState() {
    super.initState();
    _sc.addListener(_updateArrows);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateArrows());
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  void _updateArrows() {
    if (!_sc.hasClients) return;
    setState(() {
      _showLeft = _sc.offset > 10;
      _showRight = _sc.offset < _sc.position.maxScrollExtent - 10;
    });
  }

  void _scroll(double delta) {
    final target = (_sc.offset + delta).clamp(0.0, _sc.position.maxScrollExtent);
    _sc.animateTo(target, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final scrollAmount = widget.itemWidth + widget.spacing;
    return SizedBox(
      height: widget.height,
      child: Stack(
        children: [
          ListView.separated(
            controller: _sc,
            scrollDirection: Axis.horizontal,
            padding: widget.padding,
            separatorBuilder: (_, __) => SizedBox(width: widget.spacing),
            itemCount: widget.itemCount,
            itemBuilder: widget.itemBuilder,
          ),
          // 왼쪽 화살표
          if (_showLeft)
            Positioned(left: 4, top: 0, bottom: 0, child: Center(
              child: _arrowButton(Icons.chevron_left_rounded, () => _scroll(-scrollAmount)),
            )),
          // 오른쪽 화살표
          if (_showRight)
            Positioned(right: 4, top: 0, bottom: 0, child: Center(
              child: _arrowButton(Icons.chevron_right_rounded, () => _scroll(scrollAmount)),
            )),
        ],
      ),
    );
  }

  Widget _arrowButton(IconData icon, VoidCallback onTap) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerUp: (_) => onTap(),
        child: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.6),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(TV.borderMedium)),
          ),
          child: Icon(icon, size: 28, color: Colors.white.withOpacity(0.9)),
        ),
      ),
    );
  }
}

String get _baseUrl {
  if (kIsWeb) {
    final uri = Uri.base;
    return '${uri.scheme}://${uri.host}:${uri.port}';
  }
  return 'http://localhost:3002';
}

// 카테고리별 장소 아이콘
IconData _placeIcon(String cat) {
  final lower = cat.toLowerCase();
  if (lower.contains('한식') || lower.contains('식당') || lower.contains('맛집')) return Icons.restaurant_rounded;
  if (lower.contains('카페') || lower.contains('커피') || lower.contains('디저트')) return Icons.local_cafe_rounded;
  if (lower.contains('일식') || lower.contains('스시') || lower.contains('초밥')) return Icons.set_meal_rounded;
  if (lower.contains('중식') || lower.contains('중국')) return Icons.ramen_dining_rounded;
  if (lower.contains('양식') || lower.contains('파스타') || lower.contains('피자')) return Icons.local_pizza_rounded;
  if (lower.contains('치킨') || lower.contains('프라이드')) return Icons.fastfood_rounded;
  if (lower.contains('고깃') || lower.contains('구이') || lower.contains('돈카츠')) return Icons.outdoor_grill_rounded;
  if (lower.contains('냉면') || lower.contains('면')) return Icons.ramen_dining_rounded;
  if (lower.contains('카레')) return Icons.soup_kitchen_rounded;
  if (lower.contains('공원') || lower.contains('관광')) return Icons.park_rounded;
  if (lower.contains('쇼핑') || lower.contains('몰')) return Icons.shopping_bag_rounded;
  if (lower.contains('술') || lower.contains('바') || lower.contains('주점')) return Icons.local_bar_rounded;
  if (lower.contains('빵') || lower.contains('베이커리')) return Icons.bakery_dining_rounded;
  return Icons.place_rounded;
}

// 기기 클릭 시 세부카드 표시 콜백 (home_screen에서 설정)
typedef DeviceDetailCallback = void Function(Map<String, dynamic> device);
DeviceDetailCallback? onDeviceDetailRequested;

List<CatalogItem> tvCatalogItems() => [
  _comparisonCard(),
  _weatherCard(),
  _contextCard(),
  _homeControlCard(),
  _deviceControlGrid(),
  _deviceDetailCard(),
  _mediaRailCard(),
  _placeRailCard(),
  _mapCard(),
  _articleListCard(),
  _articleSummaryCard(),
  _reviewSummaryCard(),
  _gameCard(),
  _listCard(),
  _infoCard(),
  _webappCard(),
  _documentCard(),
  _recipeCard(),
];

// ══════════════════════════════════════════════════
// 1. WeatherCard (HeroDataCard)
// ══════════════════════════════════════════════════
CatalogItem _weatherCard() => CatalogItem(
  name: 'WeatherCard',
  dataSchema: S.object(properties: {
    'city': S.string(), 'temp_c': S.integer(), 'feels_like_c': S.integer(),
    'desc': S.string(), 'humidity': S.integer(), 'max_c': S.integer(),
    'min_c': S.integer(), 'rain_pct': S.integer(),
    'forecast': S.list(items: S.object(properties: {
      'day': S.string(), 'max_c': S.integer(), 'min_c': S.integer(), 'desc': S.string(),
    })),
  }),
  widgetBuilder: (ctx) {
    final d = ctx.data as Map<String, dynamic>? ?? {};
    return _buildWeatherWidget(d);
  },
);

const _descMap = {'Sunny':'맑음','Clear':'맑음','Partly cloudy':'구름 조금','Partly Cloudy':'구름 조금','Cloudy':'흐림','Overcast':'흐림','Light rain':'가벼운 비','Moderate rain':'비','Heavy rain':'폭우'};
// 날씨 컬러 아이콘 (이모지 대신)
Widget _weatherIcon(String desc, double size) {
  IconData icon; Color color;
  switch (desc) {
    case 'Sunny':         icon = Icons.wb_sunny_rounded;     color = const Color(0xFFFFB300); break;
    case 'Clear':         icon = Icons.wb_sunny_rounded;     color = const Color(0xFFFFCC80); break;
    case 'Partly cloudy':
    case 'Partly Cloudy': icon = Icons.wb_cloudy_rounded;    color = const Color(0xFFFFCC80); break;
    case 'Cloudy':        icon = Icons.cloud_rounded;        color = const Color(0xFFB0BEC5); break;
    case 'Overcast':      icon = Icons.cloud_rounded;        color = const Color(0xFF78909C); break;
    case 'Light rain':    icon = Icons.grain_rounded;        color = const Color(0xFF81D4FA); break;
    case 'Moderate rain': icon = Icons.umbrella_rounded;     color = const Color(0xFF42A5F5); break;
    case 'Heavy rain':    icon = Icons.thunderstorm_rounded; color = const Color(0xFF5C6BC0); break;
    default:              icon = Icons.wb_sunny_rounded;     color = const Color(0xFFFFB300);
  }
  return Icon(icon, size: size, color: color);
}

// 주간 예보용 작은 아이콘
Widget _forecastIcon(String desc) => _weatherIcon(desc, 48);

// 날씨별 그라데이션 배경색
Map<String, List<Color>> _weatherGradients = {
  'Sunny': [const Color(0xFF1E3A5F), const Color(0xFF0F2440)],         // 진한 남색 (깔끔)
  'Clear': [const Color(0xFF1A2744), const Color(0xFF0E1A2E)],         // 밤하늘
  'Partly cloudy': [const Color(0xFF2A3D55), const Color(0xFF1A2A40)], // 중간 톤
  'Partly Cloudy': [const Color(0xFF2A3D55), const Color(0xFF1A2A40)],
  'Cloudy': [const Color(0xFF2D3748), const Color(0xFF1A202C)],        // 회색 톤
  'Overcast': [const Color(0xFF252B32), const Color(0xFF181C22)],
  'Light rain': [const Color(0xFF1E3044), const Color(0xFF142230)],
  'Moderate rain': [const Color(0xFF1A252F), const Color(0xFF0F1820)],
  'Heavy rain': [const Color(0xFF151B24), const Color(0xFF0A0F16)],
};

Widget _buildWeatherWidget(Map<String, dynamic> d) {
  final city = d['city'] as String? ?? 'Seoul';
  final temp = (d['temp_c'] as num?)?.toInt() ?? 0;
  final feels = (d['feels_like_c'] as num?)?.toInt() ?? 0;
  final desc = d['desc'] as String? ?? 'Clear';
  final maxT = (d['max_c'] as num?)?.toInt() ?? 0;
  final minT = (d['min_c'] as num?)?.toInt() ?? 0;
  final rain = (d['rain_pct'] as num?)?.toInt() ?? 0;
  final humidity = (d['humidity'] as num?)?.toInt() ?? 0;
  final forecast = (d['forecast'] as List<dynamic>?)
      ?.map((f) => Map<String, dynamic>.from(f as Map)).toList() ?? [];

  final hasForecast = forecast.isNotEmpty;

  // 1×1 미니: 오늘 날씨만 — 반응형
  if (!hasForecast) {
    return tvBlurCard(
      child: LayoutBuilder(builder: (context, constraints) {
        final h = constraints.maxHeight;
        final s = (h / 200).clamp(0.6, 1.5);
        return Center(
          child: Padding(
            padding: EdgeInsets.all(12 * s),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(city, style: TextStyle(fontSize: 20 * s, color: TV.textMuted, height: 1.2), textAlign: TextAlign.center),
                SizedBox(height: 4 * s),
                _weatherIcon(desc, 28 * s),
                SizedBox(height: 2 * s),
                Text('$temp°', style: TextStyle(fontSize: 44 * s, fontWeight: FontWeight.w200, color: TV.text, height: 1, letterSpacing: -2, shadows: TV.textShadow), textAlign: TextAlign.center),
                SizedBox(height: 4 * s),
                Text('${_descMap[desc] ?? desc}  $maxT°/$minT°', style: TextStyle(fontSize: 20 * s, color: TV.textMuted, height: 1.2), textAlign: TextAlign.center),
              ],
            ),
          ),
        );
      }),
    );
  }

  // 2×1 풀: 오늘 + 주간 예보 — LayoutBuilder로 반응형 폰트
  return tvBlurCard(
    child: LayoutBuilder(builder: (context, constraints) {
      final h = constraints.maxHeight;
      // 기준 높이 420px에서 스케일 1.0, 작으면 축소, 크면 확대 (0.6~1.3 범위)
      final s = (h / 420).clamp(0.6, 1.3);
      final pad = (24 * s).clamp(12.0, 32.0);
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 32 * s, vertical: pad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Row(children: [
              Text(city, style: TextStyle(fontSize: 36 * s, fontWeight: FontWeight.w600, color: TV.text, letterSpacing: -0.3, height: 1.2)),
              const Spacer(),
              Text(_descMap[desc] ?? desc, style: TextStyle(fontSize: 28 * s, color: TV.textSub, height: 1.5)),
            ]),
            Row(children: [
              _weatherIcon(desc, 64 * s),
              SizedBox(width: 14 * s),
              Text('$temp°', style: TextStyle(fontSize: 88 * s, fontWeight: FontWeight.w200, color: TV.text, height: 1, letterSpacing: -3, shadows: TV.textShadow)),
              SizedBox(width: 20 * s),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('최고$maxT°  최저$minT°', style: TextStyle(fontSize: 28 * s, color: TV.textSub, height: 1.5)),
                SizedBox(height: 4 * s),
                Text('체감 $feels°   습도 $humidity%   강수 $rain%', style: TextStyle(fontSize: 24 * s, color: TV.textMuted, height: 1.4)),
              ])),
            ]),
            Container(
              padding: EdgeInsets.only(top: 12 * s),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.white.withOpacity(0.12))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: forecast.take(5).map((f) {
                  final fDesc = f['desc'] as String? ?? 'Clear';
                  final fMax = (f['max_c'] as num?)?.toInt() ?? 0;
                  final fMin = (f['min_c'] as num?)?.toInt() ?? 0;
                  return Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(f['day'] as String? ?? '', style: TextStyle(fontSize: 24 * s, color: TV.textMuted, height: 1.4)),
                    Padding(padding: EdgeInsets.symmetric(vertical: 4 * s),
                        child: _weatherIcon(fDesc, 40 * s)),
                    Text('$fMax°', style: TextStyle(fontSize: 28 * s, fontWeight: FontWeight.w600, color: TV.textSub, height: 1.5)),
                    Text('$fMin°', style: TextStyle(fontSize: 24 * s, color: TV.textMuted, height: 1.4)),
                  ]);
                }).toList(),
              ),
            ),
          ],
        ),
      );
    }),
  );
}

// ══════════════════════════════════════════════════
// 2. ContextCard (오늘 뭐 입지)
// ══════════════════════════════════════════════════
CatalogItem _contextCard() => CatalogItem(
  name: 'ContextCard',
  dataSchema: S.object(properties: {
    'title': S.string(), 'recommendation': S.string(),
    'detail': S.string(), 'tips': S.list(items: S.string()),
    'icon': S.string(),
  }),
  widgetBuilder: (ctx) {
    final d = ctx.data as Map<String, dynamic>? ?? {};
    final icon = d['icon'] as String? ?? 'checkroom';
    return Container(
      decoration: glassBox(), padding: const EdgeInsets.all(TV.padding),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(d['title'] as String? ?? '', style: TV.sub.copyWith(fontWeight: FontWeight.w500)),
        const SizedBox(height: 14),
        Row(children: [
          const Icon(Icons.checkroom_rounded, size: 48, color: TV.accent),
          const SizedBox(width: 20),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d['recommendation'] as String? ?? '', style: TV.body.copyWith(fontWeight: FontWeight.w600)),
            if (d['detail'] != null) Padding(padding: const EdgeInsets.only(top: 6),
                child: Text(d['detail'], style: TV.sub)),
          ])),
        ]),
        if (d['tips'] != null) ...[
          const SizedBox(height: 20),
          Row(children: (d['tips'] as List<dynamic>).map((t) => Expanded(
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white.withOpacity(TV.overlayLight), borderRadius: BorderRadius.circular(TV.radiusSm)),
              child: Text(t.toString(), style: TV.sub),
            ),
          )).toList()),
        ],
      ]),
    );
  },
);

// ══════════════════════════════════════════════════
// 2.5 HomeControlCard (전체 집안 기기 — 큰 카드 1장)
// ══════════════════════════════════════════════════
CatalogItem _homeControlCard() => CatalogItem(
  name: 'HomeControlCard',
  dataSchema: S.object(properties: {
    'title': S.string(),
    'rooms': S.list(items: S.object(properties: {
      'room': S.string(),
      'devices': S.list(items: S.object(properties: {
        'name': S.string(), 'icon': S.string(), 'on': S.boolean(), 'val': S.string(),
      })),
    })),
  }),
  widgetBuilder: (ctx) {
    final data = ctx.data as Map<String, dynamic>? ?? {};
    final title = data['title'] as String? ?? '집안 기기';
    final rooms = (data['rooms'] as List<dynamic>?)
        ?.map((r) => Map<String, dynamic>.from(r as Map)).toList() ?? [];
    return _HomeControlWidget(title: title, rooms: rooms);
  },
);

class _HomeControlWidget extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> rooms;
  const _HomeControlWidget({required this.title, required this.rooms});
  @override
  State<_HomeControlWidget> createState() => _HomeControlWidgetState();
}

class _HomeControlWidgetState extends State<_HomeControlWidget> {
  late List<List<bool>> _roomStates;
  static const _iconMap = <String, IconData>{
    'lightbulb': Icons.lightbulb_rounded, 'ac_unit': Icons.ac_unit_rounded,
    'tv': Icons.tv_rounded, 'air': Icons.air_rounded, 'lock': Icons.lock_rounded,
    'explore': Icons.smart_toy_rounded, 'thermostat': Icons.thermostat_rounded,
    'speaker': Icons.speaker_rounded, 'power_settings_new': Icons.power_settings_new_rounded,
  };

  @override
  void initState() {
    super.initState();
    _roomStates = widget.rooms.map((room) {
      final devices = (room['devices'] as List<dynamic>?) ?? [];
      return devices.map((d) => (d as Map)['on'] == true).toList();
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final totalOn = _roomStates.expand((s) => s).where((s) => s).length;
    final totalDevices = _roomStates.expand((s) => s).length;

    return Container(
      decoration: glassBox(),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 헤더
            Row(children: [
              Text(widget.title, style: TV.h1),
              const Spacer(),
              Text('$totalOn/$totalDevices 작동 중', style: TV.sub),
            ]),
            const SizedBox(height: 24),
            // 구역별 섹션 (넘치면 내부 스크롤)
            Flexible(child: SingleChildScrollView(child: Wrap(
              spacing: 16,
              runSpacing: 20,
              children: widget.rooms.asMap().entries.map((roomEntry) {
                final ri = roomEntry.key;
                final room = roomEntry.value;
                final roomName = room['room'] as String? ?? '';
                final devices = (room['devices'] as List<dynamic>?)
                    ?.map((d) => Map<String, dynamic>.from(d as Map)).toList() ?? [];
                final roomOnCount = _roomStates[ri].where((s) => s).length;

                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(TV.overlayLight),
                    borderRadius: BorderRadius.circular(TV.radiusMd),
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(roomName, style: TV.sub.copyWith(fontWeight: FontWeight.w600, color: TV.text)),
                        const SizedBox(width: 12),
                        Text('$roomOnCount개', style: TV.caption),
                      ]),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: devices.asMap().entries.map((devEntry) {
                          final di = devEntry.key;
                          final d = devEntry.value;
                          final isOn = _roomStates[ri][di];
                          final icon = _iconMap[d['icon']] ?? Icons.power_settings_new_rounded;

                          return GestureDetector(
                            onTap: () => setState(() => _roomStates[ri][di] = !_roomStates[ri][di]),
                            child: Container(
                              width: 120,
                              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
                              decoration: BoxDecoration(
                                color: isOn ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.03),
                                borderRadius: BorderRadius.circular(TV.radiusXs),
                                border: Border.all(
                                  color: isOn ? TV.accent.withOpacity(0.3) : Colors.white.withOpacity(TV.borderLight),
                                ),
                              ),
                              child: Column(mainAxisSize: MainAxisSize.min, children: [
                                Icon(icon, size: 28, color: isOn ? TV.text : TV.textMuted),
                                const SizedBox(height: 8),
                                Text(d['name'] ?? '', style: TV.sub.copyWith(color: TV.text),
                                    maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                                Text(d['val'] ?? '', style: TV.caption,
                                    maxLines: 1, textAlign: TextAlign.center),
                                if (isOn)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text('켜짐', style: TV.sub.copyWith(color: TV.accent)),
                                  ),
                              ]),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ))),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════
// 3. DeviceControlGrid (홈 기기)
// ══════════════════════════════════════════════════
CatalogItem _deviceControlGrid() => CatalogItem(
  name: 'ControlCard',
  dataSchema: S.object(properties: {
    'title': S.string(),
    'devices': S.list(items: S.object(properties: {'name': S.string(), 'icon': S.string(), 'on': S.boolean(), 'val': S.string()})),
  }),
  widgetBuilder: (ctx) {
    final data = ctx.data as Map<String, dynamic>? ?? {};
    return DeviceGridWidget(
      title: data['title'] as String? ?? '홈 기기',
      devices: (data['devices'] as List<dynamic>?)?.map((d) => Map<String, dynamic>.from(d as Map)).toList() ?? [],
    );
  },
);

class DeviceGridWidget extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> devices;
  const DeviceGridWidget({super.key, required this.title, required this.devices});
  @override
  State<DeviceGridWidget> createState() => DeviceGridWidgetState();
}

class DeviceGridWidgetState extends State<DeviceGridWidget> {
  late List<bool> _states;
  static const _iconMap = <String, IconData>{
    'lightbulb': Icons.lightbulb_rounded, 'ac_unit': Icons.ac_unit_rounded, 'tv': Icons.tv_rounded,
    'air': Icons.air_rounded, 'lock': Icons.lock_rounded, 'explore': Icons.smart_toy_rounded,
    'thermostat': Icons.thermostat_rounded, 'speaker': Icons.speaker_rounded,
  };

  @override
  void initState() { super.initState(); _states = widget.devices.map((d) => d['on'] == true).toList(); }

  @override
  Widget build(BuildContext context) {
    final onCount = _states.where((s) => s).length;
    return Container(
      decoration: glassBox(), clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.fromLTRB(TV.padding, 24, TV.padding, 12), child: Row(children: [
          Text(widget.title, style: TV.h1),
          const Spacer(),
          Text('$onCount개 작동 중', style: TV.sub),
        ])),
        Padding(padding: const EdgeInsets.fromLTRB(TV.padding, 6, TV.padding, 28),
          child: Wrap(spacing: 12, runSpacing: 12, children: widget.devices.asMap().entries.map((e) {
            final i = e.key; final d = e.value; final isOn = _states[i];
            return TVFocusable(
              focusScale: TV.focusScaleLarge,
              onTap: () {
                print('[CATALOG] Device tap: ${d['name']}');
                setState(() => _states[i] = !_states[i]);
              },
              onLongPress: () {
                print('[CATALOG] Device detail: ${d['name']}');
                onDeviceDetailRequested?.call({...d, 'on': _states[i]});
              },
              builder: (focused) => AnimatedContainer(duration: const Duration(milliseconds: 200),
                width: 160, padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 14),
                decoration: BoxDecoration(
                  color: isOn ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(TV.overlayLight),
                  borderRadius: BorderRadius.circular(TV.radiusMd),
                  border: Border.all(
                    color: focused ? TV.focusBorder : (isOn ? TV.accent.withOpacity(0.3) : Colors.transparent),
                    width: focused ? 2 : 1),
                  boxShadow: focused ? [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 16)] : []),
                child: Column(children: [
                  Icon(_iconForDevice(d['icon'] as String?), size: 40, color: isOn ? Colors.white : TV.textMuted),
                  const SizedBox(height: 10),
                  Text(d['name'] ?? '', style: TV.body.copyWith(fontWeight: FontWeight.w600), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (d['val'] != null) Text(d['val'], style: TV.sub),
                  const SizedBox(height: 6),
                  Text(isOn ? '켜짐' : '꺼짐', style: TV.sub.copyWith(fontWeight: FontWeight.w700, color: isOn ? TV.green : TV.textMuted, shadows: TV.textShadow)),
                ])),
            );
          }).toList()),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════
// 4. MediaRailCard (YouTube / 영화)
// ══════════════════════════════════════════════════
CatalogItem _mediaRailCard() => CatalogItem(
  name: 'MediaRailCard',
  dataSchema: S.object(properties: {
    'title': S.string(), 'variant': S.string(),
    'items': S.list(items: S.object(properties: {
      'title': S.string(), 'sub': S.string(), 'dur': S.string(), 'url': S.string(), 'hue': S.integer(), 'thumbnail': S.string(),
    })),
  }),
  widgetBuilder: (ctx) {
    final d = ctx.data as Map<String, dynamic>? ?? {};
    print('[MediaRailCard] ctx.data keys=${d.keys.toList()}, items type=${d['items']?.runtimeType}, items length=${(d['items'] as List?)?.length ?? "NULL"}');
    if (d['items'] is List && (d['items'] as List).isNotEmpty) {
      final first = d['items'][0];
      print('[MediaRailCard] first item type=${first.runtimeType}, keys=${first is Map ? (first as Map).keys.toList() : "N/A"}');
    }
    final title = d['title'] as String? ?? '추천';
    // variant 또는 usageHint (v0.9→SDK 변환 시 variant→usageHint로 rename됨)
    final variant = (d['variant'] as String?) ?? (d['usageHint'] as String?) ?? 'youtube';
    final items = (d['items'] as List<dynamic>?)?.map((i) => Map<String, dynamic>.from(i as Map)).toList() ?? [];
    final isMovie = variant == 'movie';
    print('[MediaRailCard] title=$title, variant=$variant, items.length=${items.length}, isMovie=$isMovie');

    // Movie → 2×2 포스터 그리드
    if (isMovie) return _MoviePosterGrid(title: title, items: items, dispatchEvent: ctx.dispatchEvent);

    // YouTube → 4×1 가로 레일
    return LayoutBuilder(builder: (context, constraints) {
      final availH = constraints.maxHeight;
      final titleH = 52.0;
      final railH = availH > 0 ? availH - titleH : 260.0;
      final thumbH = (railH - 48).clamp(60.0, 400.0); // 제목+패딩 확보
      final thumbW = thumbH * 16.0 / 9.0; // 16:9 강제

      return Container(
      decoration: glassBox(), clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.fromLTRB(TV.padding, 16, TV.padding, 4), child: Text(title, style: TV.h2)),
        Expanded(child: _ScrollableRail(
          height: railH,
          itemWidth: thumbW,
          itemCount: items.length,
          padding: const EdgeInsets.fromLTRB(TV.padding, 8, TV.padding, 12),
          itemBuilder: (_, i) {
            final v = items[i];
            // thumbnail이 없으면 YouTube URL에서 자동 추출
            var thumbnailUrl = v['thumbnail'] as String?;
            if ((thumbnailUrl == null || thumbnailUrl.isEmpty) && v['url'] is String) {
              final videoId = _extractYoutubeId(v['url'] as String);
              if (videoId != null) {
                thumbnailUrl = 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
              }
            }
            final hue = _parseHue(v['hue'], i * 60);
            return MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerUp: (_) {
                  _dispatchAction(v['action'], v['url'] as String?, ctx.dispatchEvent, 'media_$i');
                },
                child: SizedBox(width: thumbW, height: railH, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // 썸네일 (Expanded로 남은 공간 꽉 채움)
                  Expanded(
                    child: Container(
                      width: thumbW,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(TV.radiusSm),
                        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                            colors: [HSLColor.fromAHSL(1, hue.toDouble() % 360, 0.55, 0.62).toColor(), HSLColor.fromAHSL(1, (hue + 30).toDouble() % 360, 0.45, 0.52).toColor()]),
                      ),
                      child: Stack(children: [
                        // 실제 썸네일 이미지 (있으면 — LLM 제공 또는 YouTube URL 자동추출)
                        if (thumbnailUrl != null && thumbnailUrl.isNotEmpty)
                          Positioned.fill(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(TV.radiusSm),
                              child: Image.network(thumbnailUrl, fit: BoxFit.cover,
                                errorBuilder: (_, error, ___) => const SizedBox.shrink()),
                            ),
                          ),
                        Center(child: Container(width: 44, height: 44, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withOpacity(0.35)),
                            child: const Center(child: Icon(Icons.play_arrow_rounded, size: 28, color: Colors.white)))),
                        if (v['dur'] != null && (v['dur'] as String).isNotEmpty) Positioned(bottom: 8, right: 8,
                            child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(TV.radiusXs)),
                                child: Text(v['dur'], style: TV.sub.copyWith(color: Colors.white)))),
                      ]),
                    ),
                  ),
                  // 제목 (썸네일 아래)
                  Padding(padding: const EdgeInsets.only(top: 6, left: 2, right: 2),
                    child: Text(v['title'] ?? '', style: TV.body.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1, overflow: TextOverflow.ellipsis)),
                ])),
              ),
            );
          },
        )),
      ]),
    );
    });
  },
);

// ── Movie Poster Rail (4×2 풀폭, 세로 포스터 2:3 가로 레일) ──
class _MoviePosterGrid extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> items;
  final void Function(UiEvent) dispatchEvent;
  const _MoviePosterGrid({required this.title, required this.items, required this.dispatchEvent});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: glassBox(), clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(builder: (context, constraints) {
        final availH = constraints.maxHeight;
        final titleH = 56.0;
        final railH = availH > 0 ? availH - titleH : 400.0;
        final titleBelowH = 32.0; // 포스터 아래 제목 높이
        final posterH = railH - titleBelowH - 20; // 패딩 확보
        final posterW = posterH * 2.0 / 3.0; // 2:3 세로 비율

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(TV.padding, 20, TV.padding, 8),
            child: Text(title, style: TV.h2),
          ),
          Expanded(child: _ScrollableRail(
            height: railH,
            itemWidth: posterW,
            itemCount: items.length,
            padding: const EdgeInsets.fromLTRB(TV.padding, 0, TV.padding, 12),
            spacing: 20,
            itemBuilder: (_, i) {
              final v = items[i];
              final hue = (_parseHue(v['hue'], i * 50 + 200) % 360).toDouble();
              final hasThumbnail = v['thumbnail'] is String && (v['thumbnail'] as String).isNotEmpty;

              return MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerUp: (_) {
                    _dispatchAction(v['action'], v['url'] as String?, dispatchEvent, 'movie_$i');
                  },
                  child: SizedBox(width: posterW, height: railH, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // 세로 포스터 (2:3)
                    Expanded(
                      child: Container(
                        width: posterW,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(TV.radiusSm),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter, end: Alignment.bottomCenter,
                            colors: [
                              HSLColor.fromAHSL(1, hue, 0.5, 0.45).toColor(),
                              HSLColor.fromAHSL(1, (hue + 20) % 360, 0.6, 0.25).toColor(),
                            ],
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(children: [
                          // 포스터 이미지
                          if (hasThumbnail)
                            Positioned.fill(child: Image.network(v['thumbnail'] as String, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                            )),
                          // 이미지 없을 때: 텍스트 포스터
                          if (!hasThumbnail)
                            Positioned.fill(child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                                  colors: [Colors.transparent, Colors.black.withOpacity(0.5)]),
                              ),
                              child: Column(mainAxisAlignment: MainAxisAlignment.end, crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(v['title'] ?? '', style: TextStyle(fontSize: (posterW * 0.16).clamp(16, 28), fontWeight: FontWeight.w800, color: Colors.white, height: 1.15,
                                    shadows: const [Shadow(blurRadius: 10, color: Colors.black87)]),
                                    maxLines: 3, overflow: TextOverflow.ellipsis),
                              ]),
                            )),
                          // 장르/부제 상단
                          if (v['sub'] != null)
                            Positioned(top: 10, left: 10, right: 10,
                              child: Text(v['sub']!, style: TV.small.copyWith(color: Colors.white.withOpacity(0.75),
                                  shadows: const [Shadow(blurRadius: 6, color: Colors.black54)]),
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                          // 재생시간 하단 우측
                          if (v['dur'] != null && (v['dur'] as String).isNotEmpty)
                            Positioned(bottom: 10, right: 10,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(TV.radiusXs)),
                                child: Text(v['dur']!, style: TV.small.copyWith(color: Colors.white70)),
                              ),
                            ),
                        ]),
                      ),
                    ),
                    // 제목 (포스터 아래)
                    Padding(padding: const EdgeInsets.only(top: 6, left: 2, right: 2),
                      child: Text(v['title'] ?? '', style: TV.sub.copyWith(fontWeight: FontWeight.w600, color: TV.text),
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ])),
                ),
              );
            },
          )),
        ]);
      }),
    );
  }
}

// ══════════════════════════════════════════════════
// 5. PlaceRailCard (맛집/카페)
// ══════════════════════════════════════════════════
CatalogItem _placeRailCard() => CatalogItem(
  name: 'PlaceRailCard',
  dataSchema: S.object(properties: {
    'title': S.string(),
    'places': S.list(items: S.object(properties: {
      'name': S.string(), 'cat': S.string(), 'rating': S.number(),
      'badge': S.string(), 'url': S.string(), 'hue': S.integer(),
      'address': S.string(), 'reviewCount': S.integer(), 'mapImageUrl': S.string(),
    })),
  }),
  widgetBuilder: (ctx) {
    final d = ctx.data as Map<String, dynamic>? ?? {};
    final places = (d['places'] as List<dynamic>?)?.map((i) => Map<String, dynamic>.from(i as Map)).toList() ?? [];

    return LayoutBuilder(builder: (context, constraints) {
      final availH = constraints.maxHeight;
      final titleH = 52.0;
      final railH = availH > 0 ? availH - titleH : 260.0;
      // 하단 정보 영역 최소 확보 후 나머지를 썸네일에 할당
      final infoMinH = 100.0; // padding(24) + name(22) + address(20) + rating(22) + gaps
      final thumbH = (railH - infoMinH).clamp(40.0, 180.0);

      return Container(
      decoration: glassBox(), clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.fromLTRB(TV.padding, 20, TV.padding, 8),
            child: Text(d['title'] as String? ?? '맛집 추천', style: TV.h2)),
        Expanded(child: _ScrollableRail(
          height: railH,
          itemWidth: 280,
          itemCount: places.length,
          padding: const EdgeInsets.fromLTRB(TV.padding, 8, TV.padding, 12),
          itemBuilder: (_, i) {
            final p = places[i];
            final hue = _parseHue(p['hue'], i * 40 + 20);
            final rating = (p['rating'] as num?)?.toDouble() ?? 4.5;
            final address = p['address'] as String?;
            final rawMapUrl = p['mapImageUrl'] as String?;
            // 주소가 있으면 Google Maps Static API로 지도 이미지 자동 생성
            final mapImageUrl = rawMapUrl ?? (address != null && address.isNotEmpty
                ? 'https://maps.googleapis.com/maps/api/staticmap?center=${Uri.encodeComponent(address)}&zoom=16&size=400x200&markers=color:red%7C${Uri.encodeComponent(address)}&key=AIzaSyCjKeTNZxONs7CWddHMmJ7L6H1aenqdHCA'
                : null);
            return Semantics(
              label: '${p['name'] ?? ''}, ${p['cat'] ?? ''}, 평점 $rating',
              button: true,
              child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerUp: (_) { _dispatchAction(p['action'], p['url'] as String?, ctx.dispatchEvent, 'place_$i'); },
                child: Container(width: 280,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(TV.radiusMd), color: Colors.white.withOpacity(TV.overlayLight), border: Border.all(color: Colors.white.withOpacity(TV.overlayMedium))),
                  clipBehavior: Clip.antiAlias,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // 썸네일: 지도 이미지 또는 카테고리별 아이콘+그라데이션
                    Container(height: thumbH,
                      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                          colors: [HSLColor.fromAHSL(1, hue.toDouble() % 360, 0.25, 0.25).toColor(), HSLColor.fromAHSL(1, (hue + 30).toDouble() % 360, 0.2, 0.15).toColor()])),
                      child: Stack(children: [
                        if (mapImageUrl != null)
                          Positioned.fill(child: Image.network(mapImageUrl, fit: BoxFit.cover,
                            loadingBuilder: (ctx, child, progress) {
                              if (progress == null) { print('[PlaceRailCard] Map image LOADED OK'); return child; }
                              print('[PlaceRailCard] Map loading: ${progress.cumulativeBytesLoaded}/${progress.expectedTotalBytes}');
                              return Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38)));
                            },
                            errorBuilder: (_, error, ___) { print('[PlaceRailCard] Map image error: $error'); return const SizedBox.shrink(); },
                          )),
                        if (mapImageUrl == null)
                          Center(child: Icon(
                            _placeIcon(p['cat'] as String? ?? ''),
                            size: 48, color: HSLColor.fromAHSL(0.4, hue.toDouble() % 360, 0.4, 0.6).toColor(),
                          )),
                        if (p['badge'] != null && (p['badge'] as String).isNotEmpty)
                          Positioned(top: 10, left: 12, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(color: Colors.white.withOpacity(0.92), borderRadius: BorderRadius.circular(TV.radiusXs)),
                              child: Text(p['badge'], style: TV.sub.copyWith(fontWeight: FontWeight.w600, color: const Color(0xFF1A1A1A))))),
                      ]),
                    ),
                    // 하단 정보 — Expanded + SingleChildScrollView로 안전하게 맞춤
                    Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p['name'] ?? '', style: TV.caption.copyWith(fontWeight: FontWeight.w600, color: TV.text), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      if (address != null)
                        Row(children: [
                          const Icon(Icons.location_on_rounded, size: 16, color: TV.textMuted),
                          const SizedBox(width: 4),
                          Expanded(child: Text(address, style: TV.small, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        ])
                      else if (p['cat'] != null)
                        Text(p['cat'], style: TV.small),
                      const Spacer(),
                      Row(children: [
                        const Icon(Icons.star_rounded, size: 16, color: Color(0xFFFFB800)),
                        const SizedBox(width: 4),
                        Text('$rating', style: TV.caption.copyWith(fontWeight: FontWeight.w600, color: TV.text)),
                        if (p['cat'] != null) ...[
                          const Spacer(),
                          Text(p['cat'], style: TV.small),
                        ],
                      ]),
                    ]))),
                  ]),
                ),
              ),
            ));
          },
        )),
      ]),
    );
    });
  },
);

// ══════════════════════════════════════════════════
// 6. MapCard (지도 + 장소 목록)
// ══════════════════════════════════════════════════
CatalogItem _mapCard() => CatalogItem(
  name: 'MapCard',
  dataSchema: S.object(properties: {
    'title': S.string(),
    'map_url': S.string(),
    'places': S.list(items: S.object(properties: {
      'name': S.string(), 'cat': S.string(), 'address': S.string(),
      'url': S.string(), 'hue': S.integer(),
    })),
  }),
  widgetBuilder: (ctx) {
    final d = ctx.data as Map<String, dynamic>? ?? {};
    final title = d['title'] as String? ?? '장소 검색';
    final mapUrl = d['map_url'] as String? ?? '';
    final places = (d['places'] as List<dynamic>?)
        ?.map((i) => Map<String, dynamic>.from(i as Map))
        .toList() ?? [];

    return Container(
      decoration: glassBox(),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 타이틀
        Padding(
          padding: const EdgeInsets.fromLTRB(TV.padding, 16, TV.padding, 10),
          child: Text(title, style: TV.h2),
        ),
        // 지도 이미지
        Expanded(
          flex: 5,
          child: mapUrl.isNotEmpty
            ? Image.network(
                mapUrl,
                fit: BoxFit.cover,
                width: double.infinity,
                errorBuilder: (_, __, ___) => _mapPlaceholder(),
              )
            : _mapPlaceholder(),
        ),
        // 장소 목록
        Expanded(
          flex: 3,
          child: places.isEmpty
            ? const SizedBox.shrink()
            : ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: TV.padding, vertical: 10),
                itemCount: places.length,
                itemBuilder: (_, i) {
                  final p = places[i];
                  final hue = (_parseHue(p['hue'], i * 50 + 180) % 360).toDouble();
                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerUp: (_) {
                          _dispatchAction(null, p['url'] as String?, ctx.dispatchEvent, 'map_place_$i');
                        },
                        child: Container(
                          width: 180,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(TV.radiusMd),
                            color: Colors.white.withOpacity(TV.overlayLight),
                            border: Border.all(color: Colors.white.withOpacity(TV.overlayMedium)),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            // 번호 + 이름
                            Row(children: [
                              Container(
                                width: 22, height: 22,
                                decoration: BoxDecoration(
                                  color: HSLColor.fromAHSL(1, hue, 0.7, 0.45).toColor(),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text('${i + 1}',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(p['name'] as String? ?? '',
                                  style: TV.caption.copyWith(fontWeight: FontWeight.w700, color: TV.text),
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              ),
                            ]),
                            const SizedBox(height: 6),
                            Text(p['cat'] as String? ?? '',
                              style: TV.small.copyWith(color: TV.textSub),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                            if ((p['address'] as String?)?.isNotEmpty == true) ...[
                              const SizedBox(height: 4),
                              Text(p['address'] as String,
                                style: TV.small.copyWith(color: TV.textSub.withOpacity(0.7)),
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                            ],
                          ]),
                        ),
                      ),
                    ),
                  );
                },
              ),
        ),
      ]),
    );
  },
);

Widget _mapPlaceholder() => Container(
  color: const Color(0xFF1d2c4d),
  child: const Center(
    child: Icon(Icons.map_rounded, size: 48, color: Colors.white24),
  ),
);

// ══════════════════════════════════════════════════
// 7. ArticleListCard (블로그/뉴스 리스트)
// ══════════════════════════════════════════════════
CatalogItem _articleListCard() => CatalogItem(
  name: 'ArticleListCard',
  dataSchema: S.object(properties: {
    'title': S.string(),
    'articles': S.list(items: S.object(properties: {
      'tag': S.string(), 'title': S.string(), 'src': S.string(), 'time': S.string(), 'url': S.string(),
    })),
  }),
  widgetBuilder: (ctx) {
    final d = ctx.data as Map<String, dynamic>? ?? {};
    final articles = (d['articles'] as List<dynamic>?)?.map((i) => Map<String, dynamic>.from(i as Map)).toList() ?? [];

    return Container(
      decoration: glassBox(), clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.fromLTRB(TV.padding, 24, TV.padding, 12),
            child: Text(d['title'] as String? ?? '추천 글', style: TV.sub.copyWith(fontWeight: FontWeight.w600, color: TV.text))),
        ...articles.asMap().entries.map((e) {
          final i = e.key; final a = e.value;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () { _dispatchAction(a['action'], a['url'] as String?, ctx.dispatchEvent, 'article_$i'); },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: TV.padding, vertical: 18),
              decoration: BoxDecoration(border: i > 0 ? Border(top: BorderSide(color: Colors.white.withOpacity(TV.borderLight))) : null),
              child: Row(children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: i == 0 ? const Color(0x14007AFF) : Colors.white.withOpacity(TV.overlayLight), borderRadius: BorderRadius.circular(TV.radiusXs)),
                    child: Text(a['tag'] ?? '', style: TV.sub.copyWith(fontWeight: FontWeight.w600, color: i == 0 ? TV.accent : TV.textSub))),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a['title'] ?? '', style: TV.sub.copyWith(fontWeight: FontWeight.w500, color: TV.text)),
                  Text('${a['src'] ?? ''} · ${a['time'] ?? ''}', style: TV.sub),
                ])),
                Text('›', style: TV.sub.copyWith(color: TV.textMuted)),
              ]),
            ),
          );
        }),
      ]),
    );
  },
);

// ══════════════════════════════════════════════════
// 7. ArticleSummaryCard (기사 AI 요약)
// ══════════════════════════════════════════════════
CatalogItem _articleSummaryCard() => CatalogItem(
  name: 'ArticleSummaryCard',
  dataSchema: S.object(properties: {
    'title': S.string(), 'source': S.string(), 'time': S.string(), 'summary': S.string(), 'url': S.string(),
    'sections': S.list(items: S.object(properties: {'icon': S.string(), 'title': S.string(), 'text': S.string()})),
  }),
  widgetBuilder: (ctx) {
    final d = ctx.data as Map<String, dynamic>? ?? {};
    final sections = (d['sections'] as List<dynamic>?)?.map((i) => Map<String, dynamic>.from(i as Map)).toList() ?? [];

    return Container(
      decoration: glassBox(), padding: const EdgeInsets.all(TV.padding),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(d['title'] as String? ?? '', style: TV.body.copyWith(fontWeight: FontWeight.w700))),
        ]),
        Padding(padding: const EdgeInsets.only(top: 4, bottom: 20),
            child: Text('${d['source'] ?? ''} · ${d['time'] ?? ''} · LISA 요약', style: TV.sub)),
        if (sections.isNotEmpty)
          Wrap(spacing: 12, runSpacing: 12, children: sections.map((s) => Container(
            width: (MediaQuery.of(ctx.buildContext).size.width * 0.2).clamp(200.0, 320.0),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: Colors.white.withOpacity(TV.overlayLight), borderRadius: BorderRadius.circular(TV.radiusMd), border: Border.all(color: Colors.white.withOpacity(TV.borderLight))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s['title'] as String? ?? '', style: TV.body.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(s['text'] ?? '', style: TV.sub.copyWith(height: 1.6)),
            ]),
          )).toList()),
        if (d['summary'] != null) Padding(padding: const EdgeInsets.only(top: 16),
            child: Text(d['summary'], style: TV.sub.copyWith(fontWeight: FontWeight.w500, color: TV.text))),
        if (d['url'] != null || d['action'] != null) Padding(padding: const EdgeInsets.only(top: 16),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _dispatchAction(d['action'], d['url'] as String?, ctx.dispatchEvent, ctx.id),
            child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(TV.radiusSm), border: Border.all(color: const Color(0x14000000))),
                child: Center(child: Text('기사 원문 보기', style: TV.sub.copyWith(fontWeight: FontWeight.w500, color: TV.accent)))),
          ),
        ),
      ]),
    );
  },
);

// ══════════════════════════════════════════════════
// 8. ReviewSummaryCard (리뷰 AI 요약)
// ══════════════════════════════════════════════════
CatalogItem _reviewSummaryCard() => CatalogItem(
  name: 'ReviewSummaryCard',
  dataSchema: S.object(properties: {
    'name': S.string(), 'rating': S.number(), 'reviewCount': S.integer(), 'summary': S.string(), 'url': S.string(),
    'sections': S.list(items: S.object(properties: {'icon': S.string(), 'title': S.string(), 'text': S.string()})),
    'popularMenus': S.list(items: S.string()),
    'quotes': S.list(items: S.string()),
  }),
  widgetBuilder: (ctx) {
    final d = ctx.data as Map<String, dynamic>? ?? {};
    final sections = (d['sections'] as List<dynamic>?)?.map((i) => Map<String, dynamic>.from(i as Map)).toList() ?? [];
    final menus = (d['popularMenus'] as List<dynamic>?)?.map((i) => i.toString()).toList() ?? [];
    final quotes = (d['quotes'] as List<dynamic>?)?.map((i) => i.toString()).toList() ?? [];
    final rating = (d['rating'] as num?)?.toDouble() ?? 0;

    return Container(
      decoration: glassBox(), padding: const EdgeInsets.all(TV.padding),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        // 타이틀
        Text(d['name'] ?? '', style: TV.h1),
        const SizedBox(height: 10),
        // 평점 + 리뷰 수
        Row(children: [
          ...List.generate(rating.round(), (_) => const Icon(Icons.star_rounded, size: 18, color: Color(0xFFFFB800))),
          const SizedBox(width: 4),
          Text('$rating · 리뷰 ${d['reviewCount'] ?? 0}개', style: TV.sub),
        ]),
        const SizedBox(height: 16),
        // 태그 요약 (sections의 title만 칩으로)
        if (sections.isNotEmpty)
          Wrap(spacing: 10, runSpacing: 10, children: sections.map((s) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(TV.overlayMedium),
                borderRadius: BorderRadius.circular(TV.radiusMd),
              ),
              child: Text(s['title'] ?? '', style: TV.sub.copyWith(color: TV.text)),
            );
          }).toList()),
        // 인기 메뉴 태그
        if (menus.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(spacing: 8, children: menus.map((m) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: TV.accent.withOpacity(TV.overlayStrong),
              borderRadius: BorderRadius.circular(TV.radiusSm),
            ),
            child: Text(m, style: TV.sub.copyWith(color: TV.accent)),
          )).toList()),
        ],
        // 한줄 요약
        if (d['summary'] != null) ...[
          const SizedBox(height: 16),
          Text(d['summary'], style: TV.sub.copyWith(color: TV.text)),
        ],
        // 가게 보기 버튼
        if (d['url'] != null || d['action'] != null) Padding(padding: const EdgeInsets.only(top: 16),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _dispatchAction(d['action'], d['url'] as String?, ctx.dispatchEvent, ctx.id),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(TV.radiusSm), border: Border.all(color: TV.accent.withOpacity(0.3))),
              child: Text('자세히 보기', style: TV.sub.copyWith(fontWeight: FontWeight.w500, color: TV.accent)),
            ),
          ),
        ),
      ]),
    );
  },
);

// ══════════════════════════════════════════════════
// 9. GameCard
// ══════════════════════════════════════════════════
CatalogItem _gameCard() => CatalogItem(
  name: 'GameCard',
  dataSchema: S.object(properties: {'question': S.string(), 'choices': S.list(items: S.string()), 'state': S.string(), 'answer': S.integer(), 'explanation': S.string()}),
  widgetBuilder: (ctx) {
    final d = ctx.data as Map<String, dynamic>? ?? {};
    final choices = (d['choices'] as List<dynamic>?)?.map((c) => c.toString()).toList() ?? [];
    final question = d['question'] as String? ?? '';
    final answer = (d['answer'] as num?)?.toInt();
    final explanation = d['explanation'] as String?;
    return _GameCardWidget(
      question: question,
      choices: choices,
      correctAnswer: answer,
      explanation: explanation,
      dispatchEvent: ctx.dispatchEvent,
    );
  },
);

class _GameCardWidget extends StatefulWidget {
  final String question;
  final List<String> choices;
  final int? correctAnswer;
  final String? explanation;
  final DispatchEventCallback dispatchEvent;
  const _GameCardWidget({
    required this.question, required this.choices,
    this.correctAnswer, this.explanation,
    required this.dispatchEvent,
  });
  @override
  State<_GameCardWidget> createState() => _GameCardWidgetState();
}

class _GameCardWidgetState extends State<_GameCardWidget> {
  int? _selected;
  bool _revealed = false;
  int _score = 0;
  int _questionNum = 1;

  // 카드 업데이트 시 새 문제 반영
  @override
  void didUpdateWidget(covariant _GameCardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.question != widget.question) {
      _selected = null;
      _revealed = false;
      _questionNum++;
    }
  }

  void _onChoiceTap(int index) {
    print('[GAME] Choice tapped: $index');
    if (_revealed) return;
    setState(() {
      _selected = index;
      _revealed = true;
      if (widget.correctAnswer != null && index == widget.correctAnswer) {
        _score++;
      }
    });
    // AI에게 답변 전송 → 같은 surface 업데이트로 다음 문제 받기
    const labels = ['A', 'B', 'C', 'D'];
    final answer = '${labels[index % 4]} ${widget.choices[index]}';
    widget.dispatchEvent(UserActionEvent(
      name: 'answer',
      sourceComponentId: 'game_card',
      context: {'choice': answer, 'index': index},
    ));
  }

  bool get _isCorrect =>
      widget.correctAnswer != null && _selected == widget.correctAnswer;

  @override
  Widget build(BuildContext context) {
    const labels = ['A', 'B', 'C', 'D'];
    return Container(
      decoration: glassBox(), padding: const EdgeInsets.all(TV.padding),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        // 헤더: 아이콘 + 문제 번호 + 점수
        Row(children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(color: const Color(0x1AFF9500), borderRadius: BorderRadius.circular(TV.radiusXs)),
              child: const Center(child: Icon(Icons.quiz_rounded, size: 20, color: Color(0xFFFF9500)))),
          const SizedBox(width: 14),
          Text('Q$_questionNum', style: TV.sub.copyWith(fontWeight: FontWeight.w700, color: const Color(0xFFFF9500))),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: Colors.white.withOpacity(TV.borderLight), borderRadius: BorderRadius.circular(TV.radiusXs)),
            child: Text('$_score점', style: TV.sub.copyWith(color: TV.accent, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 16),
        // 문제
        Text(widget.question, style: TV.body.copyWith(fontWeight: FontWeight.w600), maxLines: 3),
        const SizedBox(height: 20),
        // 선택지
        Wrap(spacing: 10, runSpacing: 10, children: widget.choices.asMap().entries.map((e) {
          final isSelected = _selected == e.key;
          final isCorrectChoice = widget.correctAnswer == e.key;
          final isOther = _revealed && !isSelected && !isCorrectChoice;

          Color bgColor;
          Color borderColor;
          Color textColor = TV.text;

          if (_revealed && isCorrectChoice) {
            bgColor = TV.green.withOpacity(0.25);
            borderColor = TV.green.withOpacity(0.6);
          } else if (_revealed && isSelected && !_isCorrect) {
            bgColor = TV.red.withOpacity(0.25);
            borderColor = TV.red.withOpacity(0.6);
          } else if (isSelected) {
            bgColor = TV.accent.withOpacity(0.25);
            borderColor = TV.accent.withOpacity(0.6);
          } else {
            bgColor = Colors.white.withOpacity(isOther ? 0.02 : TV.overlayLight);
            borderColor = Colors.white.withOpacity(isOther ? 0.03 : TV.borderLight);
            if (isOther) textColor = TV.textMuted;
          }

          return MouseRegion(
            cursor: _revealed ? SystemMouseCursors.basic : SystemMouseCursors.click,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerUp: (_) => _onChoiceTap(e.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(TV.radiusSm),
                  border: Border.all(color: borderColor),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (_revealed && isCorrectChoice)
                    const Padding(padding: EdgeInsets.only(right: 8),
                      child: Icon(Icons.check_circle_rounded, size: 18, color: TV.green)),
                  if (_revealed && isSelected && !_isCorrect && !isCorrectChoice)
                    const Padding(padding: EdgeInsets.only(right: 8),
                      child: Icon(Icons.close_rounded, size: 18, color: TV.red)),
                  Text('${labels[e.key % 4]}  ${e.value}',
                    style: TV.sub.copyWith(fontWeight: FontWeight.w500, color: textColor)),
                ]),
              ),
            ),
          );
        }).toList()),
        // 정답/오답 피드백
        if (_revealed) ...[
          const SizedBox(height: 16),
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _isCorrect
                  ? TV.green.withOpacity(0.1)
                  : TV.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(TV.radiusXs),
              border: Border.all(color: (_isCorrect ? TV.green : TV.red).withOpacity(0.2)),
            ),
            child: Row(children: [
              Icon(_isCorrect ? Icons.celebration_rounded : Icons.info_outline_rounded,
                  size: 20, color: _isCorrect ? TV.green : TV.red),
              const SizedBox(width: 10),
              Expanded(child: Text(
                _isCorrect
                    ? '정답! ${widget.explanation ?? "잘했어요!"}'
                    : '오답! ${widget.explanation ?? "정답은 ${labels[(widget.correctAnswer ?? 0) % 4]} ${widget.choices.elementAtOrNull(widget.correctAnswer ?? 0) ?? ""}입니다."}',
                style: TV.sub.copyWith(color: _isCorrect ? TV.green : TV.red, fontWeight: FontWeight.w500),
              )),
            ]),
          ),
        ],
      ]),
    );
  }
}

// ══════════════════════════════════════════════════
// 10. ListCard
// ══════════════════════════════════════════════════
CatalogItem _listCard() => CatalogItem(
  name: 'ListCard',
  dataSchema: S.object(properties: {'title': S.string(), 'items': S.list(items: S.string())}),
  widgetBuilder: (ctx) {
    final d = ctx.data as Map<String, dynamic>? ?? {};
    return ListCardWidget(title: d['title'] as String? ?? '', items: (d['items'] as List<dynamic>?)?.map((i) => i.toString()).toList() ?? []);
  },
);

class ListCardWidget extends StatefulWidget {
  final String title; final List<String> items;
  const ListCardWidget({super.key, required this.title, required this.items});
  @override
  State<ListCardWidget> createState() => ListCardWidgetState();
}

class ListCardWidgetState extends State<ListCardWidget> {
  late List<bool> _checked;
  @override
  void initState() { super.initState(); _checked = List.filled(widget.items.length, false); }

  @override
  Widget build(BuildContext context) {
    return Container(decoration: glassBox(), padding: const EdgeInsets.all(TV.padding),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(widget.title, style: TV.sub.copyWith(fontWeight: FontWeight.w600, color: TV.text))]),
        const SizedBox(height: 20),
        ...widget.items.asMap().entries.map((e) {
          final done = _checked[e.key];
          return GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => setState(() => _checked[e.key] = !done),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(border: e.key > 0 ? Border(top: BorderSide(color: Colors.white.withOpacity(TV.borderLight))) : null),
              child: Row(children: [
                AnimatedContainer(duration: const Duration(milliseconds: 150), width: 24, height: 24,
                    decoration: BoxDecoration(color: done ? TV.accent : Colors.transparent, borderRadius: BorderRadius.circular(TV.radiusXs),
                        border: Border.all(color: done ? TV.accent : TV.textMuted, width: 2)),
                    child: done ? const Icon(Icons.check, size: 16, color: Colors.white) : null),
                const SizedBox(width: 14),
                Expanded(child: Text(e.value, style: TV.sub.copyWith(fontWeight: FontWeight.w500,
                    color: done ? TV.textSub : TV.text, decoration: done ? TextDecoration.lineThrough : null, decorationColor: TV.textMuted))),
              ])));
        }),
      ]));
  }
}

// ══════════════════════════════════════════════════
// 11. InfoCard
// ══════════════════════════════════════════════════
CatalogItem _infoCard() => CatalogItem(
  name: 'InfoCard',
  dataSchema: S.object(properties: {
    'title': S.string(), 'subtitle': S.string(), 'description': S.string(),
    'icon': S.string(), 'items': S.list(items: S.string()),
  }),
  widgetBuilder: (ctx) {
    final d = ctx.data as Map<String, dynamic>? ?? {};
    final iconName = d['icon'] as String? ?? 'info_outline';
    final items = (d['items'] as List<dynamic>?)?.cast<String>() ?? [];
    final icon = _infoIconMap[iconName] ?? Icons.info_outline_rounded;

    return tvBlurCard(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 헤더: 아이콘 + 제목
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(width: 48, height: 48,
                decoration: BoxDecoration(color: TV.accent.withOpacity(TV.overlayStrong), borderRadius: BorderRadius.circular(TV.radiusSm)),
                child: Center(child: Icon(icon, size: 24, color: TV.accent))),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d['title'] as String? ?? '', style: TV.h2),
                if (d['subtitle'] != null)
                  Padding(padding: const EdgeInsets.only(top: 4),
                    child: Text(d['subtitle'], style: TV.sub)),
              ])),
            ]),

            // 본문
            if (d['description'] != null) ...[
              const SizedBox(height: 20),
              Text(d['description'], style: TV.body.copyWith(color: TV.textSub, height: 1.7)),
            ],

            // 항목 리스트
            if (items.isNotEmpty) ...[
              const SizedBox(height: 20),
              ...items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Container(width: 6, height: 6,
                      decoration: BoxDecoration(color: TV.accent, shape: BoxShape.circle)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(item, style: TV.sub, maxLines: 2, overflow: TextOverflow.ellipsis)),
                ]),
              )),
            ],
          ]),
        ),
      ),
    );
  },
);

const Map<String, IconData> _infoIconMap = {
  'info_outline': Icons.info_outline_rounded,
  'translate': Icons.translate_rounded,
  'language': Icons.language_rounded,
  'calculate': Icons.calculate_rounded,
  'fitness': Icons.fitness_center_rounded,
  'school': Icons.school_rounded,
  'lightbulb': Icons.lightbulb_rounded,
  'schedule': Icons.schedule_rounded,
  'event': Icons.event_rounded,
  'code': Icons.code_rounded,
  'science': Icons.science_rounded,
  'psychology': Icons.psychology_rounded,
  'tips': Icons.tips_and_updates_rounded,
  'help': Icons.help_outline_rounded,
  'bookmark': Icons.bookmark_rounded,
  'star': Icons.star_rounded,
};

// ══════════════════════════════════════════════════
// 12. WebappCard
// ══════════════════════════════════════════════════
CatalogItem _webappCard() => CatalogItem(
  name: 'WebappCard',
  dataSchema: S.object(properties: {
    'title': S.string(), 'subtitle': S.string(), 'webapp_url': S.string(), 'html_code': S.string(),
  }),
  widgetBuilder: (ctx) {
    final d = ctx.data as Map<String, dynamic>? ?? {};
    final url = d['webapp_url'] as String?;
    return tvBlurCard(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 36),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
          const Icon(Icons.sports_esports_rounded, size: 72, color: TV.accent),
          const SizedBox(height: 16),
          Text(d['title'] as String? ?? '웹앱', style: TV.h1.copyWith(fontSize: 30)),
          if (d['subtitle'] != null) Padding(padding: const EdgeInsets.only(top: 8),
              child: Text(d['subtitle'] as String, style: TV.sub)),
          const SizedBox(height: 28),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              _dispatchAction(d['action'], url, ctx.dispatchEvent, ctx.id);
            },
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 18),
                decoration: BoxDecoration(color: TV.accent, borderRadius: BorderRadius.circular(TV.radiusLg)),
                child: Text('시작하기', style: TV.body.copyWith(fontWeight: FontWeight.w600))),
          ),
        ]),
        ),
      ),
    );
  },
);

// ══════════════════════════════════════════════════
// DeviceDetailCard — 기기 세부 제어
// ══════════════════════════════════════════════════
CatalogItem _deviceDetailCard() => CatalogItem(
  name: 'DeviceDetailCard',
  dataSchema: S.object(properties: {
    'name': S.string(), 'icon': S.string(), 'on': S.boolean(),
    'type': S.string(), 'val': S.string(),
    'brightness': S.integer(), 'temp': S.integer(),
    'min_temp': S.integer(), 'max_temp': S.integer(),
    'mode': S.string(), 'modes': S.list(items: S.string()),
  }),
  widgetBuilder: (ctx) {
    final d = ctx.data as Map<String, dynamic>? ?? {};
    return DeviceDetailWidget(device: d);
  },
);

IconData _iconForDevice(String? iconName) {
  const map = <String, IconData>{
    'lightbulb': Icons.lightbulb_rounded, 'ac_unit': Icons.ac_unit_rounded,
    'tv': Icons.tv_rounded, 'air': Icons.air_rounded,
    'lock': Icons.lock_rounded, 'explore': Icons.explore_rounded,
    'thermostat': Icons.thermostat_rounded, 'speaker': Icons.speaker_rounded,
  };
  return map[iconName] ?? Icons.power_settings_new_rounded;
}

class DeviceDetailWidget extends StatefulWidget {
  final Map<String, dynamic> device;
  const DeviceDetailWidget({super.key, required this.device});
  @override
  State<DeviceDetailWidget> createState() => _DeviceDetailWidgetState();
}

class _DeviceDetailWidgetState extends State<DeviceDetailWidget> {
  late bool _on;
  late double _brightness;
  late double _temp;
  late String _mode;

  static const _deviceIconMap = <String, IconData>{
    'lightbulb': Icons.lightbulb_rounded, 'ac_unit': Icons.ac_unit_rounded, 'tv': Icons.tv_rounded,
    'air': Icons.air_rounded, 'lock': Icons.lock_rounded, 'explore': Icons.smart_toy_rounded,
    'thermostat': Icons.thermostat_rounded, 'speaker': Icons.speaker_rounded,
  };

  @override
  void initState() {
    super.initState();
    _on = widget.device['on'] == true;
    _brightness = (widget.device['brightness'] as num?)?.toDouble() ?? 0;
    _temp = (widget.device['temp'] as num?)?.toDouble() ?? 22;
    _mode = widget.device['mode'] as String? ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.device['name'] as String? ?? '';
    final iconData = _deviceIconMap[widget.device['icon']] ?? Icons.bolt;
    final type = widget.device['type'] as String? ?? 'switch';
    final minTemp = (widget.device['min_temp'] as num?)?.toDouble() ?? 18;
    final maxTemp = (widget.device['max_temp'] as num?)?.toDouble() ?? 30;
    final modes = (widget.device['modes'] as List<dynamic>?)?.map((m) => m.toString()).toList() ?? [];

    return Container(
      decoration: glassBox(),
      padding: const EdgeInsets.all(32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        // 헤더
        Row(children: [
          Icon(_iconForDevice(widget.device['icon'] as String?), size: 40, color: TV.accent),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: TV.body.copyWith(fontWeight: FontWeight.w600)),
            Text(_on ? '켜짐' : '꺼짐', style: TV.sub.copyWith(color: _on ? TV.green : TV.textSub)),
          ])),
        ]),
        const SizedBox(height: 24),

        // 전원 토글
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _on = !_on),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(TV.overlayLight),
              borderRadius: BorderRadius.circular(TV.radiusSm),
              border: Border.all(color: Colors.white.withOpacity(TV.borderLight)),
            ),
            child: Row(children: [
              Text('전원', style: TV.sub.copyWith(color: TV.text)),
              const Spacer(),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 52, height: 30,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(TV.radiusSm),
                  color: _on ? TV.accent : const Color(0xFFD1D1D6),
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 200),
                  alignment: _on ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.all(3),
                    width: 24, height: 24,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white,
                        boxShadow: [BoxShadow(color: Color(0x26000000), blurRadius: 4, offset: Offset(0, 2))]),
                  ),
                ),
              ),
            ]),
          ),
        ),

        // 밝기 슬라이더 (type == light)
        if (type == 'light' && _on) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white.withOpacity(TV.overlayLight), borderRadius: BorderRadius.circular(TV.radiusSm),
                border: Border.all(color: Colors.white.withOpacity(TV.borderLight))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('밝기', style: TV.sub),
                const Spacer(),
                Text('${_brightness.round()}%', style: TV.body.copyWith(fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 8),
              SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: TV.accent, inactiveTrackColor: const Color(0x1A000000),
                  thumbColor: TV.accent, overlayColor: TV.accent.withOpacity(0.1),
                  trackHeight: 4, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10)),
                child: Slider(value: _brightness, min: 0, max: 100,
                    onChanged: (v) => setState(() => _brightness = v)),
              ),
            ]),
          ),
        ],

        // 온도 조절 (type == thermostat)
        if (type == 'thermostat' && _on) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white.withOpacity(TV.overlayLight), borderRadius: BorderRadius.circular(TV.radiusSm),
                border: Border.all(color: Colors.white.withOpacity(TV.borderLight))),
            child: Column(children: [
              Row(children: [
                Text('온도', style: TV.sub),
                const Spacer(),
                Text('${_temp.round()}°C', style: TV.body.copyWith(fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _tempButton('-', () { if (_temp > minTemp) setState(() => _temp--); }),
                Expanded(child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: TV.accent, inactiveTrackColor: const Color(0x1A000000),
                    thumbColor: TV.accent, trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10)),
                  child: Slider(value: _temp, min: minTemp, max: maxTemp,
                      divisions: (maxTemp - minTemp).toInt(),
                      onChanged: (v) => setState(() => _temp = v)),
                )),
                _tempButton('+', () { if (_temp < maxTemp) setState(() => _temp++); }),
              ]),
              Text('${minTemp.round()}°C ~ ${maxTemp.round()}°C', style: TV.sub.copyWith(color: TV.textMuted)),
            ]),
          ),
        ],

        // 모드 선택 (type == mode)
        if (type == 'mode' && _on && modes.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white.withOpacity(TV.overlayLight), borderRadius: BorderRadius.circular(TV.radiusSm),
                border: Border.all(color: Colors.white.withOpacity(TV.borderLight))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('모드', style: TV.sub),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: modes.map((m) {
                final selected = m == _mode;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _mode = m),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: selected ? TV.accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(TV.radiusXs),
                      border: Border.all(color: selected ? TV.accent : const Color(0x1A000000)),
                    ),
                    child: Text(m, style: TV.sub.copyWith(fontWeight: FontWeight.w500,
                        color: selected ? Colors.white : TV.text)),
                  ),
                );
              }).toList()),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _tempButton(String label, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0x08000000),
            border: Border.all(color: Colors.white.withOpacity(0.06))),
        child: Center(child: Text(label, style: TV.body.copyWith(fontWeight: FontWeight.w600))),
      ),
    );
  }
}

// Device detail 내부 보더
BoxDecoration _deviceSectionBox() => BoxDecoration(
  color: Colors.white.withOpacity(TV.overlayLight),
  borderRadius: BorderRadius.circular(TV.radiusSm),
  border: Border.all(color: Colors.white.withOpacity(TV.borderLight)),
);

// ══════════════════════════════════════════════════
// DocumentCard — 장문 문서 카드 (2×3)
// 말풍선 메시지 포함 가능, 내부 스크롤, 섹션 구분
// ══════════════════════════════════════════════════
CatalogItem _documentCard() => CatalogItem(
  name: 'DocumentCard',
  dataSchema: S.object(properties: {
    'title': S.string(),
    'subtitle': S.string(),
    'body': S.string(),
    'sections': S.list(items: S.object(properties: {
      'heading': S.string(), 'content': S.string(), 'icon': S.string(),
    })),
    'message': S.string(),
    'tags': S.list(items: S.string()),
  }),
  widgetBuilder: (ctx) {
    final d = ctx.data as Map<String, dynamic>? ?? {};
    return _DocumentCardWidget(data: d);
  },
);

class _DocumentCardWidget extends StatelessWidget {
  final Map<String, dynamic> data;
  const _DocumentCardWidget({required this.data});

  @override
  Widget build(BuildContext context) {
    final title = data['title'] as String? ?? '';
    final subtitle = data['subtitle'] as String?;
    final body = data['body'] as String?;
    final sections = (data['sections'] as List<dynamic>?)
        ?.map((s) => Map<String, dynamic>.from(s as Map)).toList() ?? [];
    final message = data['message'] as String?;
    final tags = (data['tags'] as List<dynamic>?)?.map((t) => t.toString()).toList() ?? [];

    return Container(
      decoration: glassBox(), clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더 (고정)
          Padding(
            padding: const EdgeInsets.fromLTRB(TV.padding, 28, TV.padding, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 44, height: 44,
                  decoration: BoxDecoration(color: TV.accent.withOpacity(TV.overlayStrong), borderRadius: BorderRadius.circular(TV.radiusXs)),
                  child: const Center(child: Icon(Icons.description_rounded, size: 22, color: TV.accent))),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: TV.h2, maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (subtitle != null)
                    Text(subtitle, style: TV.sub, maxLines: 1, overflow: TextOverflow.ellipsis),
                ])),
              ]),
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(spacing: 8, children: tags.map((t) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: TV.accent.withOpacity(TV.overlayStrong), borderRadius: BorderRadius.circular(TV.radiusXs)),
                  child: Text(t, style: TV.sub.copyWith(color: TV.accent, fontWeight: FontWeight.w500)),
                )).toList()),
              ],
              const SizedBox(height: 16),
              Container(height: 1, color: Colors.white.withOpacity(TV.overlayMedium)),
            ]),
          ),
          // 본문 (스크롤 가능)
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(TV.padding, 16, TV.padding, 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // 말풍선 메시지 (AI 응답)
                if (message != null) ...[
                  Container(
                    padding: const EdgeInsets.all(20),
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: TV.accent.withOpacity(TV.borderLight),
                      borderRadius: BorderRadius.circular(TV.radiusSm),
                      border: Border.all(color: TV.accent.withOpacity(TV.overlayStrong)),
                    ),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.smart_toy_rounded, size: 20, color: TV.accent),
                      const SizedBox(width: 12),
                      Expanded(child: Text(message, style: TV.sub.copyWith(color: TV.text, height: 1.7))),
                    ]),
                  ),
                ],
                // 본문 텍스트
                if (body != null)
                  Text(body, style: TV.sub.copyWith(height: 1.8)),
                // 섹션별 내용
                for (final section in sections) ...[
                  const SizedBox(height: 24),
                  Row(children: [
                    if (section['icon'] != null) ...[
                      Text(section['icon'] as String, style: const TextStyle(fontSize: 24)),
                      const SizedBox(width: 10),
                    ],
                    Expanded(child: Text(
                      section['heading'] as String? ?? '',
                      style: TV.h2.copyWith(fontSize: 24),
                    )),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    section['content'] as String? ?? '',
                    style: TV.sub.copyWith(height: 1.8),
                  ),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════
// 17. ComparisonCard (비교표)
// ══════════════════════════════════════════════════
CatalogItem _comparisonCard() => CatalogItem(
  name: 'ComparisonCard',
  dataSchema: S.object(properties: {
    'title': S.string(),
    'columns': S.list(items: S.string()),
    'rows': S.list(items: S.object(properties: {
      'label': S.string(),
      'values': S.list(items: S.string()),
    })),
  }),
  widgetBuilder: (ctx) {
    final d = ctx.data as Map<String, dynamic>? ?? {};
    return _ComparisonCardWidget(data: d);
  },
);

class _ComparisonCardWidget extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ComparisonCardWidget({required this.data});

  @override
  Widget build(BuildContext context) {
    final title = data['title'] as String? ?? '비교';
    // LISA가 첫 번째 column으로 "항목"/"구분" 등 label 헤더를 보내는 경우 제거
    final rawColumns = (data['columns'] as List<dynamic>?)?.cast<String>() ?? [];
    final columns = rawColumns.isNotEmpty && (rawColumns.first == '항목' || rawColumns.first == '구분')
        ? rawColumns.sublist(1)
        : rawColumns;
    final rows = (data['rows'] as List<dynamic>?)
        ?.map((r) => Map<String, dynamic>.from(r as Map)).toList() ?? [];

    return tvBlurCard(
      child: Padding(
        padding: const EdgeInsets.all(TV.padding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 제목
            Text(title, style: TV.h2),
            const SizedBox(height: 20),

            // 테이블
            Expanded(
              child: SingleChildScrollView(
                child: Column(children: [
                  // 헤더 행
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(TV.borderLight),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(TV.radiusXs)),
                    ),
                    child: Row(children: [
                      SizedBox(width: 120, child: Text('항목', style: TV.sub.copyWith(fontWeight: FontWeight.w600))),
                      ...columns.map((col) => Expanded(
                        child: Text(col, style: TV.sub.copyWith(fontWeight: FontWeight.w600),
                          textAlign: TextAlign.center),
                      )),
                    ]),
                  ),

                  // 데이터 행들
                  ...rows.asMap().entries.map((entry) {
                    final i = entry.key;
                    final row = entry.value;
                    final label = row['label'] as String? ?? '';
                    final values = (row['values'] as List<dynamic>?)?.cast<String>() ?? [];
                    final isLast = i == rows.length - 1;

                    return Container(
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                      decoration: BoxDecoration(
                        border: isLast ? null : Border(bottom: BorderSide(color: Colors.white.withOpacity(0.06))),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 120, child: Text(label, style: TV.sub.copyWith(color: TV.accent))),
                          ...List.generate(columns.length, (ci) {
                            final val = ci < values.length ? values[ci] : '';
                            return Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: Text(val, style: TV.sub, textAlign: TextAlign.center),
                              ),
                            );
                          }),
                        ],
                      ),
                    );
                  }),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════
// 16. RecipeCard
// ══════════════════════════════════════════════════
CatalogItem _recipeCard() => CatalogItem(
  name: 'RecipeCard',
  dataSchema: S.object(properties: {
    'title': S.string(),
    'imageUrl': S.string(),
    'rating': S.number(),
    'reviewCount': S.integer(),
    'prepMin': S.integer(),
    'cookMin': S.integer(),
    'servings': S.integer(),
    'calories': S.integer(),
    'difficulty': S.string(),
    'tags': S.list(items: S.string()),
    'ingredients': S.list(items: S.string()),
  }),
  widgetBuilder: (ctx) {
    final d = ctx.data as Map<String, dynamic>? ?? {};
    return _RecipeCardWidget(data: d);
  },
);

class _RecipeCardWidget extends StatelessWidget {
  final Map<String, dynamic> data;
  const _RecipeCardWidget({required this.data});

  @override
  Widget build(BuildContext context) {
    final title = data['title'] as String? ?? '레시피';
    final imageUrl = data['imageUrl'] as String?;
    final rating = (data['rating'] as num?)?.toDouble() ?? 0.0;
    final reviewCount = (data['reviewCount'] as num?)?.toInt() ?? 0;
    final prepMin = (data['prepMin'] as num?)?.toInt() ?? 0;
    final cookMin = (data['cookMin'] as num?)?.toInt() ?? 0;
    final servings = (data['servings'] as num?)?.toInt() ?? 0;
    final calories = (data['calories'] as num?)?.toInt() ?? 0;
    final difficulty = data['difficulty'] as String? ?? '';
    final tags = (data['tags'] as List<dynamic>?)?.cast<String>() ?? [];
    final ingredients = (data['ingredients'] as List<dynamic>?)?.cast<String>() ?? [];

    return tvBlurCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 이미지 영역 (항상 표시)
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(TV.radiusMd)),
            child: SizedBox(
              width: double.infinity,
              height: 200,
              child: imageUrl != null
                ? Image.network(imageUrl, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _recipeFallbackImage(),
                  )
                : _recipeFallbackImage(),
            ),
          ),

          // 콘텐츠 영역
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(TV.padding),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 제목
                    Text(title, style: TV.h2, maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 12),

                    // 별점 + 리뷰
                    Row(children: [
                      const Icon(Icons.star_rounded, size: 24, color: Color(0xFFFFB300)),
                      const SizedBox(width: 6),
                      Text(rating.toStringAsFixed(1), style: TV.body),
                      const SizedBox(width: 8),
                      Text('${_formatCount(reviewCount)} reviews', style: TV.caption),
                    ]),
                    const SizedBox(height: 16),

                    // 시간 + 인분
                    Row(children: [
                      _RecipeInfoChip(icon: Icons.timer_outlined, label: '$prepMin min prep'),
                      const SizedBox(width: 20),
                      _RecipeInfoChip(icon: Icons.local_fire_department_rounded, label: '$cookMin min cook'),
                      if (servings > 0) ...[
                        const SizedBox(width: 20),
                        _RecipeInfoChip(icon: Icons.people_outline_rounded, label: '$servings인분'),
                      ],
                    ]),

                    // 칼로리 + 난이도
                    if (calories > 0 || difficulty.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Row(children: [
                        if (calories > 0)
                          _RecipeInfoChip(icon: Icons.bolt_rounded, label: '$calories kcal'),
                        if (calories > 0 && difficulty.isNotEmpty)
                          const SizedBox(width: 20),
                        if (difficulty.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: TV.accent.withOpacity(TV.borderMedium),
                              borderRadius: BorderRadius.circular(TV.radiusMd),
                            ),
                            child: Text(difficulty, style: TV.sub.copyWith(color: TV.accent, fontWeight: FontWeight.w500)),
                          ),
                      ]),
                    ],

                    // 태그
                    if (tags.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8, runSpacing: 8,
                        children: tags.take(5).map((tag) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(TV.borderLight),
                            borderRadius: BorderRadius.circular(TV.radiusMd),
                          ),
                          child: Text('#$tag', style: TV.caption),
                        )).toList(),
                      ),
                    ],

                    // 재료
                    if (ingredients.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text('재료 ${ingredients.length}가지', style: TV.sub.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      ...ingredients.take(4).map((item) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(children: [
                          Container(width: 6, height: 6,
                            decoration: BoxDecoration(color: TV.accent, shape: BoxShape.circle)),
                          const SizedBox(width: 10),
                          Expanded(child: Text(item, style: TV.sub, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        ]),
                      )),
                      if (ingredients.length > 4)
                        Text('+${ingredients.length - 4}개 더', style: TV.caption),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _recipeFallbackImage() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF2D1B0E), Color(0xFF1A1210)],
        ),
      ),
      child: const Center(
        child: Icon(Icons.restaurant_rounded, size: 56, color: Color(0xFF5C4033)),
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }
}

class _RecipeInfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _RecipeInfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 22, color: TV.textMuted),
      const SizedBox(width: 6),
      Text(label, style: TV.caption),
    ]);
  }
}
