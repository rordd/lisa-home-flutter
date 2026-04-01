# A2UI v0.9 Protocol Specification

## 1. 메시지 구조

모든 A2UI 응답은 아래 형식을 따릅니다:

```json
{
  "version": "v0.9",
  "spoken_text": "TTS용 한국어 응답",

  "a2ui": [ ...메시지 배열... ]
}
```

## 2. a2ui 메시지 타입

### 2.1 createSurface — 새 UI 표면 생성
```json
{
  "version": "v0.9",
  "createSurface": {
    "surfaceId": "고유ID",
    "catalogId": "카탈로그URL"
  }
}
```
- `surfaceId`: 고유 식별자. 같은 맥락의 UI는 같은 surfaceId를 재사용
- `catalogId`: 사용할 카탈로그 URL

### 2.2 updateComponents — UI 구조 정의
```json
{
  "version": "v0.9",
  "updateComponents": {
    "surfaceId": "대상surfaceId",
    "components": [ ...컴포넌트 배열... ]
  }
}
```

### 2.3 updateDataModel — 데이터 바인딩
```json
{
  "version": "v0.9",
  "updateDataModel": {
    "surfaceId": "대상surfaceId",
    "path": "/데이터/경로",
    "value": { ...데이터 객체... }
  }
}
```

## 3. 카탈로그

### 3.1 Basic Catalog
`https://a2ui.core/catalogs/basic_v1.json`

기본 UI 빌딩 블록: Text, Card, Column, Row, Button, Image, Icon, List, CheckBox, Slider, Divider, Tabs, Modal

### 3.2 TV Home Catalog
`https://a2ui.tv/catalogs/tv_home_v1.json`

TV 전용 커스텀 컴포넌트. 각 컴포넌트는 데이터를 flat 속성으로 받습니다.

## 4. 컴포넌트 형식

### 4.1 Basic 컴포넌트 (데이터 바인딩)
```json
{
  "id": "컴포넌트ID",
  "component": "Text",
  "text": { "path": "/data/field" },
  "variant": "h1"
}
```
- `children`: 자식 컴포넌트 ID 배열 `["child1", "child2"]`
- 데이터 참조: `{ "path": "/경로" }` 또는 `{ "function": "formatString", "args": { "template": "{/경로}°" } }`
- 리스트 렌더링: `{ "template": { "componentId": "item_template" }, "data": { "path": "/list" } }`

### 4.2 TV 커스텀 컴포넌트 (flat 속성)
```json
{
  "id": "컴포넌트ID",
  "component": "WeatherCard",
  "city": "Seoul",
  "temp_c": 18,
  "desc": "Sunny"
}
```

## 5. TV 커스텀 컴포넌트 스펙

### WeatherCard
| 속성 | 타입 | 설명 |
|------|------|------|
| city | string | 도시명 |
| temp_c | int | 현재 기온 |
| feels_like_c | int | 체감 온도 |
| desc | string | 날씨 (영문: Sunny, Cloudy, Overcast 등) |
| humidity | int | 습도 (%) |
| max_c | int | 최고기온 |
| min_c | int | 최저기온 |
| rain_pct | int | 강수확률 (%) |
| forecast | array | 주간 예보 [{day, max_c, min_c, desc}] |

### ContextCard — 상황 추천
| 속성 | 타입 | 설명 |
|------|------|------|
| title | string | 제목 ("오늘 뭐 입지") |
| recommendation | string | 추천 내용 |
| detail | string | 상세 설명 |
| icon | string | 이모지 아이콘 |
| tips | array | 팁 문자열 배열 |

### ControlCard — IoT 기기 제어
| 속성 | 타입 | 설명 |
|------|------|------|
| title | string | 방 이름 ("거실 기기") |
| devices | array | [{name, icon, on, val, id, type}] |

### HomeControlCard — 전체 집안 기기
| 속성 | 타입 | 설명 |
|------|------|------|
| title | string | "집안 기기" |
| rooms | array | [{room, devices: [{name, icon, on, val}]}] |

### MediaRailCard — 영상 레일
| 속성 | 타입 | 설명 |
|------|------|------|
| title | string | 레일 제목 |
| variant | string | "youtube" 또는 "movie" |
| items | array | [{title, sub, dur, url, hue}] |

### PlaceRailCard — 장소 레일
| 속성 | 타입 | 설명 |
|------|------|------|
| title | string | 레일 제목 |
| places | array | [{name, cat, rating, badge, url, hue}] |

### ArticleListCard — 기사/블로그 리스트
| 속성 | 타입 | 설명 |
|------|------|------|
| title | string | 리스트 제목 |
| articles | array | [{tag, title, src, time, url}] |

### ArticleSummaryCard — 기사 요약
| 속성 | 타입 | 설명 |
|------|------|------|
| title | string | 기사 제목 |
| summary | string | 요약 본문 |
| source | string | 출처 |
| time | string | 시간 |
| sections | array | [{icon, title, text}] |

### ReviewSummaryCard — 리뷰 요약
| 속성 | 타입 | 설명 |
|------|------|------|
| name | string | 장소명 |
| rating | number | 평점 |
| reviewCount | int | 리뷰 수 |
| summary | string | 요약 |
| url | string | 링크 |
| sections | array | [{icon, title, text}] |
| popularMenus | array | 인기 메뉴 문자열 |
| quotes | array | 리뷰 인용 문자열 |

### GameCard — 퀴즈/게임
| 속성 | 타입 | 설명 |
|------|------|------|
| question | string | 문제 |
| choices | array | 선택지 문자열 배열 |
| state | string | "question" 또는 "feedback" |
| answer | int | 정답 인덱스 (0부터) |
| explanation | string | 정답 해설 |

**퀴즈 규칙:**
- 첫 문제: createSurface + updateComponents + updateDataModel
- 다음 문제: updateDataModel만 (같은 surfaceId, 컴포넌트 구조 유지, 데이터만 교체!)

### ListCard — 체크리스트
| 속성 | 타입 | 설명 |
|------|------|------|
| title | string | 리스트 제목 |
| items | array | 항목 문자열 배열 |

### WebappCard — AI 웹앱
| 속성 | 타입 | 설명 |
|------|------|------|
| title | string | 웹앱 제목 |
| subtitle | string | 설명 |
| html_code | string | 완전한 HTML 코드 |

### InfoCard — 일반 정보
| 속성 | 타입 | 설명 |
|------|------|------|
| title | string | 제목 |
| subtitle | string | 부제목 |
| description | string | 설명 |

## 6. 전체 예시: 날씨 카드

### Basic 컴포넌트 방식 (정식 v0.9)
```json
{
  "version": "v0.9",
  "spoken_text": "서울 현재 18도이고 맑은 날씨입니다.",
  "a2ui": [
    {
      "version": "v0.9",
      "createSurface": {
        "surfaceId": "weather_surface",
        "catalogId": "https://a2ui.core/catalogs/basic_v1.json"
      }
    },
    {
      "version": "v0.9",
      "updateComponents": {
        "surfaceId": "weather_surface",
        "components": [
          {"id": "root", "component": "Column", "children": ["header_row", "detail_row", "forecast_list"], "align": "stretch"},
          {"id": "header_row", "component": "Row", "children": ["city_name", "current_temp"], "align": "center", "justify": "spaceBetween"},
          {"id": "city_name", "component": "Text", "text": {"path": "/weather/city"}, "variant": "h2"},
          {"id": "current_temp", "component": "Text", "text": {"function": "formatString", "args": {"template": "{/weather/temp_c}°"}}, "variant": "h1"},
          {"id": "detail_row", "component": "Row", "children": ["desc_text", "humidity_text", "feels_like_text"], "justify": "spaceBetween"},
          {"id": "desc_text", "component": "Text", "text": {"path": "/weather/desc"}, "variant": "body"},
          {"id": "humidity_text", "component": "Text", "text": {"function": "formatString", "args": {"template": "습도 {/weather/humidity}%"}}, "variant": "caption"},
          {"id": "feels_like_text", "component": "Text", "text": {"function": "formatString", "args": {"template": "체감 {/weather/feels_like_c}°"}}, "variant": "caption"},
          {"id": "forecast_list", "component": "Row", "children": {"template": {"componentId": "forecast_item"}, "data": {"path": "/weather/forecast"}}},
          {"id": "forecast_item", "component": "Column", "children": ["forecast_day", "forecast_high_low"], "align": "center"},
          {"id": "forecast_day", "component": "Text", "text": {"path": "day"}, "variant": "caption"},
          {"id": "forecast_high_low", "component": "Text", "text": {"function": "formatString", "args": {"template": "{max_c}° / {min_c}°"}}, "variant": "body"}
        ]
      }
    },
    {
      "version": "v0.9",
      "updateDataModel": {
        "surfaceId": "weather_surface",
        "path": "/weather",
        "value": {
          "city": "Seoul", "temp_c": 18, "feels_like_c": 18,
          "desc": "Sunny", "humidity": 37, "max_c": 18, "min_c": 9, "rain_pct": 0,
          "forecast": [
            {"day": "목", "max_c": 18, "min_c": 9, "desc": "Sunny"},
            {"day": "금", "max_c": 18, "min_c": 10, "desc": "Sunny"},
            {"day": "토", "max_c": 20, "min_c": 9, "desc": "Sunny"}
          ]
        }
      }
    }
  ]
}
```

### TV 커스텀 축약 방식 (레거시 — 점진적 제거 예정)
> 주의: 이 방식은 children/updateDataModel 없이 flat 속성으로 데이터를 직접 포함합니다.
> 신규 개발에서는 정식 v0.9 방식을 사용하세요.

```json
{
  "version": "v0.9",
  "spoken_text": "서울 현재 18도이고 맑은 날씨입니다.",
  "a2ui": [
    {
      "version": "v0.9",
      "createSurface": {
        "surfaceId": "weather_surface",
        "catalogId": "https://a2ui.tv/catalogs/tv_home_v1.json"
      }
    },
    {
      "version": "v0.9",
      "updateComponents": {
        "surfaceId": "weather_surface",
        "components": [
          {
            "id": "root",
            "component": "WeatherCard",
            "city": "Seoul", "temp_c": 18, "feels_like_c": 18,
            "desc": "Sunny", "humidity": 37, "max_c": 18, "min_c": 9, "rain_pct": 0,
            "forecast": [
              {"day": "목", "max_c": 18, "min_c": 9, "desc": "Sunny"},
              {"day": "금", "max_c": 18, "min_c": 10, "desc": "Sunny"},
              {"day": "토", "max_c": 20, "min_c": 9, "desc": "Sunny"}
            ]
          }
        ]
      }
    }
  ]
}
```

## 7. 규칙

1. **모든 메시지에 version 필수**: `"version": "v0.9"`
2. **`"id": "root"` 필수**: components 중 반드시 하나는 `"id": "root"` — 컴포넌트 트리의 진입점
3. **children으로 트리 구성**: Basic 컴포넌트(Column, Row 등)는 `"children": ["자식id1", "자식id2"]`로 트리 구조
4. **surfaceId 재사용**: 같은 맥락(퀴즈 진행, 데이터 업데이트)은 같은 surfaceId
5. **createSurface는 최초 1회**: 이후 같은 surface 업데이트는 updateComponents만
6. **요청당 카드 1개**: 사용자가 여러 개 명시 요청 시만 복수
7. **실시간 데이터 필수**: 날씨, 뉴스 등은 컨텍스트로 제공된 실제 데이터를 그대로 사용
8. **TV 커스텀 컴포넌트**: 속성은 같은 레벨에 flat (중첩 없음)
9. **GameCard 퀴즈**: answer(정답 인덱스)와 explanation(해설) 필수 포함
