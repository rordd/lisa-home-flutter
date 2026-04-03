# a2ui TV — AI-Powered TV Interface

GPT 5.4가 UI를 동적으로 생성하는 Flutter TV 앱입니다.

## 아키텍처

```
┌─────────────────────────────────────────────────────────┐
│                     TV Screen                           │
│  ┌──────────────────────────┐  ┌─────────────────────┐  │
│  │                          │  │  Chat Overlay        │  │
│  │   AI-Generated Cards     │  │  (슬라이드 인/아웃)    │  │
│  │   ┌────┐ ┌────┐ ┌────┐  │  │                     │  │
│  │   │카드│ │카드│ │카드│  │  │  필요할 때만 등장     │  │
│  │   └────┘ └────┘ └────┘  │  │  → 리모컨 메뉴 버튼  │  │
│  │   ┌─────────┐ ┌────┐   │  │  → 'm' 키           │  │
│  │   │ 와이드  │ │카드│   │  │  → AI가 필요시 자동   │  │
│  │   └─────────┘ └────┘   │  │                     │  │
│  │                          │  └─────────────────────┘  │
│  └──────────────────────────┘           🎤              │
│                                    Voice Button          │
└─────────────────────────────────────────────────────────┘
         │                              │
         ▼                              ▼
    ┌─────────┐                  ┌──────────────┐
    │ Provider │ ◄──────────────►│  GPT 5.4 API │
    │  State   │   JSON으로      │  (a2ui 엔진)  │
    └─────────┘   UI 구조 반환   └──────────────┘
```

## 핵심 컨셉: a2ui (AI to UI)

1. **사용자 입력** → 음성 또는 채팅
2. **GPT 5.4** → JSON 형태로 UI 카드 구조 반환
3. **Flutter** → JSON을 파싱하여 동적으로 UI 렌더링

## TV 최적화 포인트

| 항목 | 적용 내용 |
|------|-----------|
| **글자 크기** | 최소 18sp, 본문 22sp, 제목 24-52sp |
| **포커스** | D-pad 기반 포커스 네비게이션 + 글로우 효과 |
| **카드 확대** | 포커스 시 1.04배 스케일 업 |
| **음성** | STT(음성→텍스트) + TTS(텍스트→음성) |
| **채팅** | 평소 숨김, 필요할 때만 우측 슬라이드 |
| **화면** | 전체화면 + 가로 모드 고정 |
| **리모컨** | 방향키/선택/메뉴 버튼 매핑 |

## 셋업

### 1. 사전 준비
```bash
# Flutter 3.16+ 필요
flutter --version

# Android TV 또는 Google TV 에뮬레이터 설정
# Android Studio → AVD Manager → TV 프로필 선택
```

### 2. API 키 설정
`lib/services/gpt_service.dart` 에서:
```dart
static const String _apiKey = 'YOUR_OPENAI_API_KEY';  // ← 여기에 입력
```

> ⚠️ **보안**: 프로덕션에서는 반드시 백엔드 프록시 서버를 통해 API 키를 관리하세요.

### 3. 실행
```bash
cd tv_a2ui
flutter pub get
flutter run -d <TV_EMULATOR_ID>

# 또는 모든 디바이스 확인
flutter devices
```

### 4. 빌드
```bash
# Android TV APK
flutter build apk --release

# Android TV App Bundle
flutter build appbundle --release
```

## 리모컨 조작법

| 키 | 동작 |
|----|------|
| **방향키** | 카드 간 포커스 이동 |
| **선택(OK)** | 카드 선택 / 버튼 클릭 |
| **메뉴** or **M** | 채팅창 열기/닫기 |
| **마이크 버튼** | 음성 입력 시작 |

## 파일 구조

```
lib/
├── main.dart                  # 앱 진입점
├── theme/
│   └── tv_theme.dart          # TV 전용 테마 (큰 글자, 포커스 등)
├── models/
│   └── models.dart            # 데이터 모델 (카드, 메시지, 상태)
├── services/
│   ├── gpt_service.dart       # GPT 5.4 API 통신 + JSON 파싱
│   └── app_provider.dart      # 상태 관리 (Provider)
├── screens/
│   └── home_screen.dart       # 메인 홈 화면
└── widgets/
    ├── tv_card.dart           # 포커스 가능한 TV 카드
    ├── chat_overlay.dart      # 슬라이드 인 채팅 패널
    └── voice_button.dart      # 음성 입력 버튼
```

## 커스터마이징

### 시스템 프롬프트 수정
`gpt_service.dart`의 `_systemPrompt`를 수정하여 AI가 생성하는 UI 카드의 종류와 레이아웃을 변경할 수 있습니다.

### 카드 타입 추가
1. `models.dart`의 `CardType` enum에 새 타입 추가
2. `tv_card.dart`의 `_accentColor`와 `_iconMap`에 매핑 추가
3. 시스템 프롬프트에 새 타입 설명 추가

### 테마 변경
`tv_theme.dart`의 색상 상수와 텍스트 스타일을 수정하세요.
