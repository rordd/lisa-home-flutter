import 'package:uuid/uuid.dart';

/// ─────────────────────────────────────────────
/// 데이터 모델
/// ─────────────────────────────────────────────

const _uuid = Uuid();

// ── 채팅 메시지 ───────────────────────────────
enum MessageRole { user, assistant, system }

class ChatMessage {
  final String id;
  final MessageRole role;
  final String content;
  final DateTime timestamp;
  final bool isLoading;

  ChatMessage({
    String? id,
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.isLoading = false,
  })  : id = id ?? _uuid.v4(),
        timestamp = timestamp ?? DateTime.now();

  ChatMessage copyWith({String? content, bool? isLoading}) {
    return ChatMessage(
      id: id,
      role: role,
      content: content ?? this.content,
      timestamp: timestamp,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

// ── AI가 생성하는 UI 카드 ──────────────────────
enum CardType {
  info,       // 정보 카드
  action,     // 실행 가능한 액션
  media,      // 미디어 (이미지/영상)
  weather,    // 날씨
  news,       // 뉴스
  recommend,  // 추천 콘텐츠
  setting,    // 설정
  shortcut,   // 바로가기
  control,    // 집안 기기 제어
  list,       // 리스트 (쇼핑 등)
  search,     // 검색
  game,       // 대화형 게임/퀴즈
  webapp,     // AI 생성 웹앱
}

class UICard {
  final String id;
  final CardType type;
  final String title;
  final String? subtitle;
  final String? description;
  final String? iconName;
  final String? imageUrl;
  final String? actionLabel;
  final Map<String, dynamic>? metadata;
  final int gridWidth;   // 1~4 (4칸 그리드 기준)
  final int gridHeight;  // 1~2
  final List<String>? items;   // list/game 카드용 항목 목록
  final bool? deviceOn;        // control 카드용 기기 상태
  final String? searchQuery;   // search 카드용 검색어
  final String? webappUrl;     // webapp 카드용 URL
  final String? gameState;     // game 카드용 상태 (question/feedback)

  UICard({
    String? id,
    required this.type,
    required this.title,
    this.subtitle,
    this.description,
    this.iconName,
    this.imageUrl,
    this.actionLabel,
    this.metadata,
    this.gridWidth = 1,
    this.gridHeight = 1,
    this.items,
    this.deviceOn,
    this.searchQuery,
    this.webappUrl,
    this.gameState,
  }) : id = id ?? _uuid.v4();
}

// ── AI 응답 파싱 결과 ─────────────────────────
class AIResponse {
  final String? spokenText;       // TTS로 읽어줄 텍스트
  final List<UICard> cards;       // 화면에 표시할 카드
  final String? layoutHint;       // 레이아웃 힌트 (grid, list, hero, etc.)
  final bool showChat;            // 채팅창 열기 여부
  final Map<String, dynamic>? rawJson;

  AIResponse({
    this.spokenText,
    this.cards = const [],
    this.layoutHint,
    this.showChat = false,
    this.rawJson,
  });
}

// ── Stitch 응답 (GPT + Stitch 통합) ─────────
class StitchResponse {
  final String spokenText;
  final String html;
  final bool showChat;

  StitchResponse({
    required this.spokenText,
    required this.html,
    this.showChat = false,
  });
}

// ── HTML 카드 섹션 ──────────────────────────
class HtmlSection {
  final String id;
  final String html;
  final DateTime createdAt;

  HtmlSection({
    String? id,
    required this.html,
  })  : id = id ?? _uuid.v4(),
        createdAt = DateTime.now();
}

// ── 앱 전체 UI 상태 ──────────────────────────
class AppUIState {
  final List<UICard> cards;
  final List<HtmlSection> htmlSections;
  final String currentLayout;
  final String greeting;
  final bool isBusy;

  static const int maxSections = 3;

  AppUIState({
    this.cards = const [],
    this.htmlSections = const [],
    this.currentLayout = 'dashboard',
    this.greeting = '',
    this.isBusy = false,
  });

  AppUIState copyWith({
    List<UICard>? cards,
    List<HtmlSection>? htmlSections,
    String? currentLayout,
    String? greeting,
    bool? isBusy,
  }) {
    return AppUIState(
      cards: cards ?? this.cards,
      htmlSections: htmlSections ?? this.htmlSections,
      currentLayout: currentLayout ?? this.currentLayout,
      greeting: greeting ?? this.greeting,
      isBusy: isBusy ?? this.isBusy,
    );
  }
}
