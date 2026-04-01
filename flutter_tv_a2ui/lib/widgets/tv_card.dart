import 'dart:convert';
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
import '../theme/tv_theme.dart';

/// ─────────────────────────────────────────────
/// TV 카드 — Glassmorphism, typography-led hierarchy
/// ─────────────────────────────────────────────

class TVCard extends StatefulWidget {
  final UICard card;
  final VoidCallback? onSelect;
  final bool autofocus;
  final int index;

  const TVCard({
    super.key,
    required this.card,
    this.onSelect,
    this.autofocus = false,
    this.index = 0,
  });

  @override
  State<TVCard> createState() => _TVCardState();
}

class _TVCardState extends State<TVCard> with SingleTickerProviderStateMixin {
  bool _focused = false;
  late final AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  /// 카드 타입별 subtle tint (아이콘 배경에만 사용)
  Color get _tint {
    switch (widget.card.type) {
      case CardType.weather:   return TVTheme.tintTeal;
      case CardType.news:      return TVTheme.tintWarm;
      case CardType.media:
      case CardType.recommend: return TVTheme.tintPurple;
      case CardType.action:    return TVTheme.tintGreen;
      case CardType.control:   return TVTheme.tintOrange;
      case CardType.game:      return TVTheme.tintYellow;
      case CardType.webapp:    return TVTheme.tintPurple;
      case CardType.list:      return TVTheme.accent;
      case CardType.search:    return TVTheme.accent;
      default:                 return TVTheme.accent;
    }
  }

  IconData get _icon {
    final name = widget.card.iconName ?? 'circle';
    return _iconMap[name] ?? Icons.circle;
  }

  static const Map<String, IconData> _iconMap = {
    'mic': Icons.mic_rounded, 'mic_none': Icons.mic_none_rounded,
    'play_circle_filled': Icons.play_circle_filled_rounded,
    'cloud': Icons.cloud_rounded, 'newspaper': Icons.newspaper_rounded,
    'settings': Icons.settings_rounded, 'apps': Icons.apps_rounded,
    'info_outline': Icons.info_outline_rounded,
    'movie': Icons.movie_rounded, 'music_note': Icons.music_note_rounded,
    'sports_esports': Icons.sports_esports_rounded,
    'restaurant': Icons.restaurant_rounded,
    'shopping_bag': Icons.shopping_bag_rounded,
    'fitness_center': Icons.fitness_center_rounded,
    'wb_sunny': Icons.wb_sunny_rounded, 'nightlight': Icons.nightlight_round,
    'search': Icons.search_rounded, 'home': Icons.home_rounded,
    'star': Icons.star_rounded, 'favorite': Icons.favorite_rounded,
    'bookmark': Icons.bookmark_rounded, 'alarm': Icons.alarm_rounded,
    'calendar_today': Icons.calendar_today_rounded,
    'photo': Icons.photo_rounded, 'videocam': Icons.videocam_rounded,
    'tv': Icons.tv_rounded, 'cast': Icons.cast_rounded,
    'wifi': Icons.wifi_rounded, 'bluetooth': Icons.bluetooth_rounded,
    'volume_up': Icons.volume_up_rounded,
    'brightness_6': Icons.brightness_6_rounded,
    'palette': Icons.palette_rounded, 'trending_up': Icons.trending_up_rounded,
    'flash_on': Icons.flash_on_rounded, 'explore': Icons.explore_rounded,
    'public': Icons.public_rounded, 'circle': Icons.circle,
    'power_settings_new': Icons.power_settings_new_rounded,
    'lightbulb': Icons.lightbulb_rounded, 'air': Icons.air_rounded,
    'thermostat': Icons.thermostat_rounded, 'lock': Icons.lock_rounded,
    'lock_open': Icons.lock_open_rounded,
    'checklist': Icons.checklist_rounded,
    'shopping_cart': Icons.shopping_cart_rounded,
    'list_alt': Icons.list_alt_rounded, 'task_alt': Icons.task_alt_rounded,
    'add_task': Icons.add_task_rounded,
    'manage_search': Icons.manage_search_rounded,
    'youtube_searched_for': Icons.youtube_searched_for_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    final staggerDelay = disableAnimations ? 0 : 120 * widget.index;
    final animDuration = disableAnimations ? 0 : 600;

    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (focused) {
        setState(() => _focused = focused);
        if (focused && !disableAnimations) {
          _shimmerController.forward(from: 0);
        }
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.select) {
          widget.onSelect?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onSelect,
        child: RepaintBoundary(
          child: AnimatedScale(
            scale: _focused ? 1.10 : 1.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutBack,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(TVTheme.radiusMd),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                decoration: glassDecoration(focused: _focused),
                child: Stack(
                  children: [
                    _buildContent(),
                    // 상단 edge highlight
                    if (_focused)
                      Positioned(
                        top: 0, left: 24, right: 24,
                        child: Container(
                          height: 1.5,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                Colors.white.withOpacity(0.5),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    // Shimmer sweep on focus
                    if (_focused)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: AnimatedBuilder(
                            animation: _shimmerController,
                            builder: (context, child) {
                              final progress = _shimmerController.value;
                              return FractionallySizedBox(
                                alignment: Alignment(-1.0 + 2.0 * progress, 0),
                                widthFactor: 0.15,
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.white.withOpacity(0),
                                        Colors.white.withOpacity(0.10),
                                        Colors.white.withOpacity(0),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(
          duration: Duration(milliseconds: animDuration),
          delay: Duration(milliseconds: staggerDelay),
        )
        .slideY(
          begin: 0.08, end: 0,
          duration: Duration(milliseconds: animDuration),
          delay: Duration(milliseconds: staggerDelay),
          curve: Curves.easeOutBack,
        )
        .scale(
          begin: const Offset(0.85, 0.85),
          end: const Offset(1.0, 1.0),
          duration: Duration(milliseconds: animDuration),
          delay: Duration(milliseconds: staggerDelay),
          curve: Curves.easeOutBack,
        );
  }

  Widget _buildContent() {
    switch (widget.card.type) {
      case CardType.weather: return _WeatherCardContent(city: widget.card.subtitle ?? 'Seoul');
      case CardType.game:    return _buildGameCard();
      case CardType.webapp:  return _buildWebappCard();
      case CardType.control: return _buildControlCard();
      case CardType.list:    return _buildListCard();
      case CardType.search:  return _buildSearchCard();
      default:
        if (widget.card.gridWidth >= 2) return _buildWideCard();
        return _buildCompactCard();
    }
  }

  // ── 아이콘 (원형, tint 배경) ─────────────────
  Widget _tintCircle({double size = 40, double iconSize = 20}) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: _tint.withOpacity(0.14),
        shape: BoxShape.circle,
      ),
      child: Icon(_icon, size: iconSize, color: _tint),
    );
  }

  // ── 넓은 카드 ───────────────────────────────
  Widget _buildWideCard() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          _tintCircle(size: 48, iconSize: 22),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(widget.card.title, style: TVTheme.titleLarge,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                if (widget.card.subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(widget.card.subtitle!, style: TVTheme.bodyMedium,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
                if (widget.card.description != null) ...[
                  const SizedBox(height: 4),
                  Text(widget.card.description!, style: TVTheme.caption,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
          if (widget.card.actionLabel != null)
            Container(
              margin: const EdgeInsets.only(left: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: TVTheme.accent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(widget.card.actionLabel!,
                  style: TVTheme.labelLarge.copyWith(color: TVTheme.accent)),
            ),
        ],
      ),
    );
  }

  // ── 컴팩트 카드 ─────────────────────────────
  Widget _buildCompactCard() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tintCircle(),
          const Spacer(),
          Text(widget.card.title, style: TVTheme.titleLarge,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          if (widget.card.subtitle != null) ...[
            const SizedBox(height: 3),
            Text(widget.card.subtitle!, style: TVTheme.bodyMedium,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }

  // ── 기기 제어 (멀티 디바이스 그리드) ─────────
  Widget _buildControlCard() {
    final items = widget.card.items ?? [];
    final devices = items.map((item) {
      final parts = item.split(':');
      return _DeviceInfo(
        name: parts[0].trim(),
        iconName: parts.length > 1 ? parts[1].trim() : 'power_settings_new',
        isOn: parts.length > 2 ? parts[2].trim() == 'on' : false,
      );
    }).toList();

    if (devices.isEmpty) {
      devices.add(_DeviceInfo(
        name: widget.card.title,
        iconName: widget.card.iconName ?? 'power_settings_new',
        isOn: widget.card.deviceOn ?? false,
      ));
    }

    final onCount = devices.where((d) => d.isOn).length;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더 — 타이포로 위계
          Row(
            children: [
              Text(widget.card.title, style: TVTheme.titleLarge,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const Spacer(),
              Text('$onCount/${devices.length}',
                  style: TVTheme.caption.copyWith(color: TVTheme.textSecondary)),
            ],
          ),
          const SizedBox(height: 12),
          // 디바이스 그리드
          Expanded(
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: devices.length <= 4 ? 2 : 3,
                mainAxisSpacing: 8, crossAxisSpacing: 8,
                childAspectRatio: 1.2,
              ),
              itemCount: devices.length.clamp(0, 6),
              itemBuilder: (context, i) {
                final d = devices[i];
                final icon = _iconMap[d.iconName] ?? Icons.power_settings_new_rounded;
                return Container(
                  decoration: BoxDecoration(
                    color: d.isOn
                        ? Colors.white.withOpacity(0.08)
                        : Colors.white.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 22,
                          color: d.isOn ? TVTheme.textPrimary : TVTheme.textMuted),
                      const SizedBox(height: 5),
                      Text(d.name, style: TVTheme.caption.copyWith(
                        fontSize: 20,
                        color: d.isOn ? TVTheme.textPrimary : TVTheme.textMuted,
                      ), maxLines: 1, overflow: TextOverflow.ellipsis,
                         textAlign: TextAlign.center),
                      const SizedBox(height: 3),
                      Container(
                        width: 5, height: 5,
                        decoration: BoxDecoration(
                          color: d.isOn ? TVTheme.tintGreen : TVTheme.textMuted,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── 리스트 카드 ─────────────────────────────
  Widget _buildListCard() {
    final items = widget.card.items ?? [];
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(widget.card.title, style: TVTheme.titleLarge,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const Spacer(),
              Text('${items.length}', style: TVTheme.caption.copyWith(
                  color: TVTheme.textSecondary)),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _CheckableList(items: items),
          ),
        ],
      ),
    );
  }

  // ── 검색 카드 ───────────────────────────────
  Widget _buildSearchCard() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              _tintCircle(),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.card.title, style: TVTheme.titleLarge,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (widget.card.searchQuery != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('"${widget.card.searchQuery}"',
                            style: TVTheme.bodyMedium.copyWith(
                                color: TVTheme.accent),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (widget.card.description != null) ...[
            const SizedBox(height: 10),
            Text(widget.card.description!, style: TVTheme.caption,
                maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }

  // ── 게임/퀴즈 ──────────────────────────────
  Widget _buildGameCard() {
    final choices = widget.card.items ?? [];
    final isFeedback = (widget.card.gameState ?? 'question') == 'feedback';
    final tint = isFeedback ? TVTheme.tintGreen : TVTheme.tintYellow;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 제목 — 타이포 위계 (white title, tint icon만)
          Row(
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: tint.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isFeedback ? Icons.check_circle_rounded : Icons.quiz_rounded,
                  size: 18, color: tint,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(widget.card.title, style: TVTheme.titleLarge,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          if (widget.card.description != null)
            Text(widget.card.description!, style: TVTheme.bodyMedium,
                maxLines: 2, overflow: TextOverflow.ellipsis),
          if (choices.isNotEmpty)
            Wrap(
              spacing: 6, runSpacing: 6,
              children: choices.asMap().entries.map((e) {
                const labels = ['A', 'B', 'C', 'D'];
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('${labels[e.key % 4]}  ${e.value}',
                      style: TVTheme.caption.copyWith(color: TVTheme.textSecondary)),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  // ── 웹앱 ────────────────────────────────────
  Widget _buildWebappCard() {
    final url = widget.card.webappUrl;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: TVTheme.accent.withOpacity(0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.web_rounded, size: 20, color: TVTheme.accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.card.title, style: TVTheme.titleLarge,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (widget.card.subtitle != null)
                      Text(widget.card.subtitle!, style: TVTheme.caption,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
          if (url != null)
            GestureDetector(
              onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: TVTheme.accent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.open_in_new_rounded, size: 16, color: Colors.white),
                    SizedBox(width: 6),
                    Text('열기', style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600, fontSize: 22)),
                  ],
                ),
              ),
            )
          else
            Text('생성 중...', style: TVTheme.caption.copyWith(color: TVTheme.textSecondary)),
        ],
      ),
    );
  }
}

// ── Models ─────────────────────────────────────
class _DeviceInfo {
  final String name, iconName;
  final bool isOn;
  _DeviceInfo({required this.name, required this.iconName, required this.isOn});
}

// ── Weather card ──────────────────────────────

class _WeatherCardContent extends StatefulWidget {
  final String city;
  const _WeatherCardContent({required this.city});
  @override
  State<_WeatherCardContent> createState() => _WeatherCardContentState();
}

class _WeatherCardContentState extends State<_WeatherCardContent> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() { super.initState(); _fetch(); }

  Future<void> _fetch() async {
    try {
      final base = kIsWeb
          ? '${Uri.base.scheme}://${Uri.base.host}:${Uri.base.port}'
          : 'http://localhost:3002';
      final resp = await http.get(
          Uri.parse('$base/api/weather?city=${Uri.encodeComponent(widget.city)}'));
      if (resp.statusCode == 200) {
        setState(() { _data = jsonDecode(resp.body); _loading = false; });
      } else {
        setState(() => _loading = false);
      }
    } catch (_) { setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: SizedBox(width: 20, height: 20,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: TVTheme.accent)));
    }
    if (_data == null) {
      return Center(child: Text('날씨 정보 없음', style: TVTheme.caption));
    }
    final d = _data!;
    final temp = d['temp_c'] as int;
    final feelsLike = d['feels_like_c'] as int;
    final desc = _tr(d['desc'] as String);
    final max = d['max_c'] as int;
    final min = d['min_c'] as int;
    final rain = d['rain_pct'] as int;
    final humidity = d['humidity'] as int;
    final city = d['city'] as String;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 지역 + 상태
          Row(
            children: [
              Text(city, style: TVTheme.titleLarge.copyWith(fontSize: 24)),
              const Spacer(),
              Text(desc, style: TVTheme.bodyMedium.copyWith(color: TVTheme.textSecondary)),
            ],
          ),
          // 기온
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$temp°', style: const TextStyle(
                fontSize: 52, fontWeight: FontWeight.w200,
                color: TVTheme.textPrimary, height: 1.0, letterSpacing: -2,
              )),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('체감 $feelsLike°', style: TVTheme.caption.copyWith(color: TVTheme.textSecondary)),
                    Text('$max° / $min°', style: TVTheme.caption.copyWith(color: TVTheme.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          // 하단 정보 — 장식 최소화
          Row(
            children: [
              _InfoChip(label: '강수 $rain%'),
              const SizedBox(width: 12),
              _InfoChip(label: '습도 $humidity%'),
              const SizedBox(width: 12),
              _InfoChip(label: '미세먼지 좋음'),
            ],
          ),
        ],
      ),
    );
  }

  String _tr(String d) {
    const m = {
      'Sunny': '맑음', 'Clear': '맑음', 'Partly cloudy': '구름 조금',
      'Cloudy': '흐림', 'Overcast': '흐림', 'Mist': '안개',
      'Patchy rain possible': '비 가능', 'Light rain': '가벼운 비',
      'Moderate rain': '비', 'Heavy rain': '폭우',
      'Light snow': '가벼운 눈', 'Moderate snow': '눈', 'Heavy snow': '폭설',
      'Thundery outbreaks possible': '천둥',
      'Blowing snow': '눈보라', 'Freezing drizzle': '진눈깨비',
    };
    return m[d] ?? d;
  }
}

/// 미니멀 info chip — border 없음, 타이포만
class _InfoChip extends StatelessWidget {
  final String label;
  const _InfoChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(label, style: TVTheme.caption.copyWith(
      color: TVTheme.textSecondary, fontSize: 20,
    ));
  }
}

// ── Checkable list ────────────────────────────

class _CheckableList extends StatefulWidget {
  final List<String> items;
  const _CheckableList({required this.items});
  @override
  State<_CheckableList> createState() => _CheckableListState();
}

class _CheckableListState extends State<_CheckableList> {
  late List<bool> _checked;

  @override
  void initState() {
    super.initState();
    _checked = List<bool>.filled(widget.items.length, false);
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: widget.items.length.clamp(0, 5),
      itemBuilder: (context, i) {
        final done = _checked[i];
        return GestureDetector(
          onTap: () => setState(() => _checked[i] = !_checked[i]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 18, height: 18,
                  decoration: BoxDecoration(
                    color: done ? TVTheme.accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: done ? TVTheme.accent : TVTheme.textMuted,
                      width: 1.5,
                    ),
                  ),
                  child: done
                      ? const Icon(Icons.check_rounded, size: 12, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(widget.items[i],
                    style: TVTheme.bodyMedium.copyWith(
                      decoration: done ? TextDecoration.lineThrough : null,
                      decorationColor: TVTheme.textMuted,
                      color: done ? TVTheme.textMuted : TVTheme.textPrimary,
                    ),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
