"""
a2ui TV Server v0.9
- /             → Flutter web app
- /api/generate → GPT → A2UI v0.9 JSON generation
- /api/chat     → Azure OpenAI proxy
- /api/weather  → wttr.in proxy
- /api/webapp   → AI-generated webapp storage
- /webapps/     → saved webapp static serving
"""
import json
import ssl
import uuid as _uuid
import urllib.request
from http.server import HTTPServer, SimpleHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
from pathlib import Path
import os

# ── .env 로딩 ───────────────────────────────────
BASE_DIR = Path(__file__).parent
ENV_FILE = BASE_DIR / ".env"

def load_env():
    env = {}
    if ENV_FILE.exists():
        for line in ENV_FILE.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" in line:
                k, v = line.split("=", 1)
                env[k.strip()] = v.strip()
                os.environ.setdefault(k.strip(), v.strip())
    return env

ENV = load_env()

# ── Config ──────────────────────────────────────
AZURE_KEY = ENV.get("AZURE_API_KEY", "")
AZURE_HOST = ENV.get("AZURE_HOST", "tvdevops.openai.azure.com")
AZURE_IP = ENV.get("AZURE_IP", "10.182.173.75")
AZURE_MODEL = ENV.get("AZURE_MODEL", "gpt-5.4")
AZURE_API_VERSION = ENV.get("AZURE_API_VERSION", "2025-04-01-preview")
AZURE_URL = f"https://{AZURE_IP}/openai/responses?api-version={AZURE_API_VERSION}"

WEBAPPS_DIR = str(BASE_DIR / "webapps")
STATIC_DIR = str(BASE_DIR / "build" / "web")
os.makedirs(WEBAPPS_DIR, exist_ok=True)
os.makedirs(STATIC_DIR, exist_ok=True)

# SSL (private endpoint)
ssl_ctx = ssl.create_default_context()
ssl_ctx.check_hostname = False
ssl_ctx.verify_mode = ssl.CERT_NONE

# ── A2UI v0.9 카탈로그 정의 ──────────────────────
BASIC_CATALOG_ID = "https://a2ui.org/specification/v0_9/basic_catalog.json"
TV_CATALOG_ID = "https://a2ui.tv/catalogs/tv_home_v1.json"

# ── IoT Mock 데이터 ──────────────────────────────
IOT_DEVICES = {
    "거실": [
        {"id":"living_light","name":"거실 조명","icon":"lightbulb","on":True,"val":"80%","type":"light","brightness":80},
        {"id":"living_ac","name":"에어컨","icon":"ac_unit","on":False,"val":"24°C","type":"thermostat","temp":24,"min_temp":18,"max_temp":30},
        {"id":"living_tv","name":"TV","icon":"tv","on":True,"val":"HDMI1","type":"switch","input":"HDMI1"},
        {"id":"living_speaker","name":"스피커","icon":"speaker","on":True,"val":"30%","type":"light","brightness":30},
        {"id":"living_air","name":"공기청정기","icon":"air","on":True,"val":"자동","type":"mode","mode":"auto","modes":["자동","수동","수면"]},
        {"id":"living_robot","name":"로봇청소기","icon":"explore","on":False,"val":"충전중","type":"switch"},
    ],
    "주방": [
        {"id":"kitchen_light","name":"주방 조명","icon":"lightbulb","on":True,"val":"100%","type":"light","brightness":100},
        {"id":"kitchen_hood","name":"레인지후드","icon":"air","on":False,"val":"꺼짐","type":"mode","mode":"off","modes":["꺼짐","약","중","강"]},
        {"id":"kitchen_fridge","name":"냉장고","icon":"thermostat","on":True,"val":"3°C","type":"thermostat","temp":3,"min_temp":1,"max_temp":7},
        {"id":"kitchen_dishwasher","name":"식기세척기","icon":"explore","on":False,"val":"대기","type":"switch"},
    ],
    "침실": [
        {"id":"bed_light","name":"침실 조명","icon":"lightbulb","on":False,"val":"0%","type":"light","brightness":0},
        {"id":"bed_ac","name":"침실 에어컨","icon":"ac_unit","on":False,"val":"22°C","type":"thermostat","temp":22,"min_temp":18,"max_temp":30},
        {"id":"bed_humidifier","name":"가습기","icon":"air","on":True,"val":"50%","type":"light","brightness":50},
        {"id":"bed_curtain","name":"전동 커튼","icon":"lock","on":False,"val":"닫힘","type":"switch"},
    ],
    "현관": [
        {"id":"door_lock","name":"도어락","icon":"lock","on":True,"val":"잠김","type":"switch"},
        {"id":"door_cam","name":"현관 카메라","icon":"tv","on":True,"val":"녹화중","type":"switch"},
        {"id":"door_light","name":"현관 조명","icon":"lightbulb","on":True,"val":"자동","type":"mode","mode":"auto","modes":["자동","수동","꺼짐"]},
    ],
}


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=STATIC_DIR, **kwargs)

    # ── POST ────────────────────────────────────
    def do_POST(self):
        if self.path == "/api/generate":
            self._handle_generate()
        elif self.path == "/api/chat":
            self._handle_chat()
        elif self.path == "/api/webapp":
            self._handle_webapp()
        else:
            self.send_response(404)
            self.end_headers()

    # ── GET ─────────────────────────────────────
    def do_GET(self):
        if self.path.startswith("/webapps/"):
            self._serve_webapp()
        elif self.path.startswith("/api/weather"):
            self._handle_weather()
        elif self.path.startswith("/api/news"):
            self._handle_news()
        elif self.path.startswith("/api/youtube"):
            self._handle_youtube()
        elif self.path.startswith("/api/places"):
            self._handle_places()
        else:
            super().do_GET()

    # ── /api/generate: GPT → A2UI v0.9 JSON ────
    def _handle_generate(self):
        length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(length))
        user_msg = body.get("message", "")
        history = body.get("history", [])

        # IoT 기기 요청은 GPT 없이 즉시 반환
        iot_result = self._try_iot_direct(user_msg)
        if iot_result:
            self._json_response(200, iot_result)
            return

        gpt_prompt = self._build_gpt_prompt()
        gpt_input = []
        for h in history[-6:]:
            gpt_input.append({"role": h.get("role", "user"), "content": h.get("content", "")})

        # 컨텍스트 데이터를 미리 수집해서 GPT에 전달
        context_data = self._gather_context(user_msg)
        enriched_msg = user_msg
        if context_data:
            enriched_msg += "\n\n[실시간 데이터 — 이 데이터를 카드에 직접 포함하세요]\n" + context_data
        gpt_input.append({"role": "user", "content": enriched_msg})

        gpt_result = self._call_azure(gpt_prompt, gpt_input)
        if not gpt_result:
            self._json_response(200, {
                "spoken_text": "처리 중 문제가 발생했어요.",
                "a2ui": [],
                "show_chat": True,
            })
            return

        # GPT 응답 파싱
        try:
            gpt_data = json.loads(gpt_result)
        except json.JSONDecodeError:
            gpt_data = {"spoken_text": gpt_result, "a2ui": [], "show_chat": True}

        spoken = gpt_data.get("spoken_text", "")
        a2ui_messages = gpt_data.get("a2ui", [])
        show_chat = gpt_data.get("show_chat", False)

        # WebappCard html_code → 서버에 업로드하고 URL 추가
        self._process_webapp_cards(a2ui_messages)

        self._json_response(200, {
            "version": "v0.9",
            "spoken_text": spoken,
            "a2ui": a2ui_messages,
            "show_chat": show_chat,
        })

    # ── IoT 기기 직접 반환 (GPT 우회) ──────────────
    def _try_iot_direct(self, msg):
        """집안 기기 요청이면 GPT 없이 mock 데이터로 즉시 A2UI JSON 생성"""
        msg_lower = msg.lower()
        direct_kw = ['기기 보여', '기기 상태', '집안 기기', '홈 기기', '스마트홈',
                      '거실 기기', '주방 기기', '침실 기기', '현관 기기',
                      '기기 알려', '기기 뭐', '기기 어떻', '기기 확인', '가전',
                      '조명 보여', '조명 상태', '에어컨 상태', '전등']
        if not any(k in msg_lower for k in direct_kw):
            return None

        # 어떤 방을 보여줄지
        rooms = []
        if '거실' in msg_lower: rooms.append('거실')
        if '주방' in msg_lower: rooms.append('주방')
        if '침실' in msg_lower: rooms.append('침실')
        if '현관' in msg_lower: rooms.append('현관')
        if not rooms:
            rooms = list(IOT_DEVICES.keys())

        # 모든 방을 하나의 카드에 묶어서 전송
        room_data = []
        for room in rooms:
            devices = IOT_DEVICES.get(room, [])
            dev_list = [{"name":d["name"],"icon":d["icon"],"on":d["on"],"val":d["val"],
                         "id":d["id"],"type":d["type"]} for d in devices]
            room_data.append({"room": f"{room} 기기", "devices": dev_list})

        a2ui = [
            {"version":"v0.9","createSurface":{"surfaceId":"iot_home","catalogId":TV_CATALOG_ID}},
            {"version":"v0.9","updateComponents":{"surfaceId":"iot_home","components":[
                {"id":"home_control","component":"HomeControlCard","title":"집안 기기","rooms": room_data}
            ]}},
        ]

        return {
            "version": "v0.9",
            "spoken_text": f"{'·'.join(rooms)} 기기 상태입니다.",
            "a2ui": a2ui,
            "show_chat": False,
        }

    # ── WebappCard html_code 처리 ─────────────────
    def _process_webapp_cards(self, messages):
        """WebappCard에 html_code가 있으면 서버에 업로드하고 webapp_url 추가"""
        for msg in messages:
            if "updateComponents" in msg:
                for comp in msg["updateComponents"].get("components", []):
                    if comp.get("component") == "WebappCard":
                        html_code = comp.get("html_code")
                        if html_code:
                            url = self._save_webapp(html_code)
                            comp["webapp_url"] = url
                            print(f"  WebApp saved: {url}")

    # ── 컨텍스트 데이터 수집 (GPT 호출 전) ────────
    def _gather_context(self, user_msg):
        """사용자 메시지를 분석해서 필요한 API 데이터를 미리 수집"""
        parts = []
        msg_lower = user_msg.lower()

        # 날씨 관련 키워드
        weather_kw = ['날씨', '기온', '온도', '비', '눈', '우산', '뭐 입', '입지', '옷']
        if any(k in msg_lower for k in weather_kw):
            try:
                from datetime import datetime
                city = 'Seoul'
                cities = {'서울':'Seoul','부산':'Busan','대구':'Daegu','인천':'Incheon',
                          '광주':'Gwangju','대전':'Daejeon','제주':'Jeju','뉴욕':'New York',
                          '도쿄':'Tokyo','런던':'London','파리':'Paris'}
                for kr, en in cities.items():
                    if kr in user_msg:
                        city = en
                        break
                # Open-Meteo로 날씨 데이터 수집
                coords = self._CITY_COORDS.get(city.lower(), (37.5665, 126.9780))
                lat, lon = coords
                api_url = (
                    f"https://api.open-meteo.com/v1/forecast?"
                    f"latitude={lat}&longitude={lon}"
                    f"&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code"
                    f"&daily=temperature_2m_max,temperature_2m_min,weather_code,precipitation_probability_max"
                    f"&timezone=auto&forecast_days=7"
                )
                req = urllib.request.Request(api_url)
                with urllib.request.urlopen(req, timeout=10) as resp:
                    raw = json.loads(resp.read())
                cur = raw["current"]
                daily = raw["daily"]
                days_kr = ["월","화","수","목","금","토","일"]
                wmo_desc = self._WMO_DESC
                # WeatherCard JSON에 바로 복붙할 수 있는 형태로 제공
                fc_json = []
                for i in range(min(5, len(daily["time"]))):
                    dt = datetime.strptime(daily["time"][i], "%Y-%m-%d")
                    desc = wmo_desc.get(daily["weather_code"][i], "Clear")
                    fc_json.append(f'{{"day":"{days_kr[dt.weekday()]}","max_c":{int(daily["temperature_2m_max"][i])},"min_c":{int(daily["temperature_2m_min"][i])},"desc":"{desc}"}}')
                wmo_cur = cur["weather_code"]
                rain_pct = int(daily["precipitation_probability_max"][0] or 0)
                parts.append(
                    f'날씨({city}) — WeatherCard component에 아래 값을 그대로 사용하세요:\n'
                    f'"city":"{city}","temp_c":{int(cur["temperature_2m"])},"feels_like_c":{int(cur["apparent_temperature"])},'
                    f'"desc":"{wmo_desc.get(wmo_cur, "Clear")}","humidity":{int(cur["relative_humidity_2m"])},'
                    f'"max_c":{int(daily["temperature_2m_max"][0])},"min_c":{int(daily["temperature_2m_min"][0])},"rain_pct":{rain_pct},'
                    f'"forecast":[{",".join(fc_json)}]'
                )
            except Exception as e:
                print(f"Weather fetch error: {e}")

        # 뉴스 관련
        news_kw = ['뉴스', '기사', '블로그', '소식', '트렌드']
        if any(k in msg_lower for k in news_kw):
            try:
                req = urllib.request.Request("https://hacker-news.firebaseio.com/v0/topstories.json")
                with urllib.request.urlopen(req, timeout=10) as resp:
                    ids = json.loads(resp.read())[:5]
                articles = []
                for sid in ids:
                    req2 = urllib.request.Request(f"https://hacker-news.firebaseio.com/v0/item/{sid}.json")
                    with urllib.request.urlopen(req2, timeout=5) as resp2:
                        item = json.loads(resp2.read())
                        articles.append(f'{item.get("title","")} (by {item.get("by","")}, score:{item.get("score",0)}, url:{item.get("url","")})')
                parts.append(f'실시간 뉴스: {" | ".join(articles)}')
            except Exception as e:
                print(f"News fetch error: {e}")

        # YouTube 관련
        yt_kw = ['유튜브', 'youtube', '영상', '동영상', '리뷰 영상']
        if any(k in msg_lower for k in yt_kw):
            parts.append('YouTube 데이터: 검색 키워드를 기반으로 제목, 채널, 조회수, 재생시간, URL을 생성하세요. '
                'URL은 https://www.youtube.com/results?search_query=검색어 형식으로 만드세요.')

        # 맛집/장소 관련
        place_kw = ['맛집', '카페', '식당', '맛있는', '근처', '추천 식당']
        if any(k in msg_lower for k in place_kw):
            parts.append('맛집 데이터: 사용자 요청에 맞는 가게 이름, 카테고리, 지역, 평점, 특징을 직접 생성하세요. '
                'URL은 https://map.naver.com 형식으로 만드세요.')

        # IoT 기기 관련
        iot_kw = ['기기', '조명', '에어컨', '가전', '스마트홈', '홈', '거실', '주방', '침실', '현관',
                  '켜줘', '꺼줘', '온도', '불', '티비', 'tv', '세탁기', '청소기', '커튼', '도어락']
        if any(k in msg_lower for k in iot_kw):
            # 어떤 방을 요청하는지 파악
            rooms = []
            if '거실' in msg_lower: rooms.append('거실')
            if '주방' in msg_lower: rooms.append('주방')
            if '침실' in msg_lower: rooms.append('침실')
            if '현관' in msg_lower: rooms.append('현관')
            if not rooms:  # 특정 방 언급 없으면 전체
                rooms = list(IOT_DEVICES.keys())

            for room in rooms:
                devs = IOT_DEVICES.get(room, [])
                dev_strs = []
                for d in devs:
                    status = "켜짐" if d["on"] else "꺼짐"
                    extra = ""
                    if d["type"] == "thermostat":
                        extra = f', 현재온도:{d["temp"]}°C, 범위:{d.get("min_temp",18)}~{d.get("max_temp",30)}°C'
                    elif d["type"] == "light":
                        extra = f', 밝기:{d.get("brightness",0)}%'
                    elif d["type"] == "mode":
                        extra = f', 현재모드:{d.get("mode","")}, 모드목록:{d.get("modes",[])}'
                    dev_strs.append(f'{d["name"]}({d["icon"]}):{status},값:{d["val"]}{extra}')
                parts.append(f'{room} 기기: {" | ".join(dev_strs)}')

            parts.append('기기 세부 제어가 필요하면 DeviceDetailCard를 사용하세요. '
                '사용자가 기기를 클릭하면 세부 카드가 떠야 합니다.')

        # 시간 컨텍스트 항상 포함
        from datetime import datetime
        now = datetime.now()
        days = ["월","화","수","목","금","토","일"]
        parts.insert(0, f'현재시각: {now.strftime("%Y-%m-%d %H:%M")} {days[now.weekday()]}요일')

        return "\n".join(parts) if parts else ""

    # ── GPT system prompt (A2UI v0.9 프로토콜) ──
    def _build_gpt_prompt(self):
        return '''당신은 TV 앱의 AI UI 엔진입니다. A2UI v0.9 프로토콜을 엄격히 준수합니다.

## 응답 형식 (마크다운/설명 금지, 순수 JSON만)

```json
{
  "version": "v0.9",
  "spoken_text": "TTS용 한국어",
  "a2ui": [
    {"version":"v0.9", "createSurface": {"surfaceId":"고유ID", "catalogId":"카탈로그URL"}},
    {"version":"v0.9", "updateComponents": {"surfaceId":"고유ID", "components":[...]}}
  ]
}
```

## 핵심 규칙

1. 모든 a2ui 메시지에 `"version":"v0.9"` 필수
2. components 중 반드시 하나는 `"id":"root"` — 컴포넌트 트리의 진입점
3. `createSurface`는 새 surface 최초 1회만. 같은 맥락 업데이트는 `updateComponents`만
4. 컴포넌트 속성은 같은 레벨에 flat (중첩 금지)
5. TV Home 커스텀 컴포넌트 사용 시 catalogId는 반드시 `''' + TV_CATALOG_ID + '''`
6. 컴포넌트는 1개만! components 배열에 `{"id":"root","component":"WeatherCard",...}` 형태로 1개
7. updateDataModel은 사용하지 않음 — 데이터를 component 속성에 직접 flat으로 포함
8. 실시간 데이터([실시간 데이터] 섹션)는 반드시 그대로 사용 — 값을 임의로 만들지 말 것!
9. 요청당 카드 1개 (사용자가 복수 요청 시만 예외)

## 카탈로그

- Basic: `''' + BASIC_CATALOG_ID + '''` (Text, Column, Row, Button, Image, Card 등 범용 빌딩블록)
- TV Home: `''' + TV_CATALOG_ID + '''` (아래 커스텀 컴포넌트)

## 컴포넌트 선택 규칙

**1단계: 커스텀 카드 매칭 시도**

| 요청 | 컴포넌트 |
|------|----------|
| 날씨 | WeatherCard |
| 뭐 입지/옷 | ContextCard |
| 유튜브/영상/리뷰 영상 | MediaRailCard(variant:"youtube") |
| 영화/넷플릭스/드라마 | MediaRailCard(variant:"movie") |
| 맛집/카페/식당 | PlaceRailCard |
| 뉴스/기사/블로그 | ArticleListCard |
| 기사 요약 | ArticleSummaryCard |
| 리뷰 요약 | ReviewSummaryCard |
| 퀴즈/게임 | GameCard (surfaceId 재사용!) |
| 게임/앱 만들어줘 | WebappCard (html_code 포함) |
| 목록/할일/장보기 | ListCard |
| 레시피/요리/음식 만들기 | RecipeCard |
| 비교/VS/차이점 | ComparisonCard |
| 장문 설명/문서/가이드 | DocumentCard |

**2단계: 위 표에 없으면 → 반드시 Basic 컴포넌트 조합 사용!**

번역, 계산, 운동, 주식, 일정, 팁, 설명 등 위 표에 없는 모든 요청은 Basic 카탈로그의 컴포넌트를 조합하세요.
InfoCard를 사용하지 마세요! Basic 조합이 더 풍부하고 유연합니다.
catalogId는 `''' + BASIC_CATALOG_ID + '''`를 사용합니다.

### Basic 컴포넌트 조합 규칙

사용 가능한 Basic 컴포넌트:
- **Column**: 세로 배치 (children으로 자식 id 배열)
- **Row**: 가로 배치 (children으로 자식 id 배열)
- **Text**: 텍스트 표시 (text, usageHint: "h1"/"h2"/"h3"/"body"/"caption")
- **Image**: 이미지 (url, fit: "cover"/"contain")
- **Card**: 카드 컨테이너 (child로 자식 id 1개)
- **Button**: 버튼 (label, action)
- **Icon**: 아이콘 (name: Material Icon 이름)
- **Divider**: 구분선
- **List**: 스크롤 리스트 (children)

### 조합 예시

**주식 정보 요청:**
```json
[
  {"id":"root","component":"Card","child":"content"},
  {"id":"content","component":"Column","children":["header","price","change"]},
  {"id":"header","component":"Row","children":["icon","name"]},
  {"id":"icon","component":"Icon","name":"trending_up"},
  {"id":"name","component":"Text","text":"삼성전자","usageHint":"h2"},
  {"id":"price","component":"Text","text":"72,500원","usageHint":"h1"},
  {"id":"change","component":"Text","text":"+2.3% (1,630원)","usageHint":"body"}
]
```

**운동 루틴 요청:**
```json
[
  {"id":"root","component":"Card","child":"content"},
  {"id":"content","component":"Column","children":["title","divider","ex1","ex2","ex3"]},
  {"id":"title","component":"Text","text":"오늘의 운동 루틴","usageHint":"h2"},
  {"id":"divider","component":"Divider"},
  {"id":"ex1","component":"Row","children":["i1","t1"]},
  {"id":"i1","component":"Icon","name":"fitness_center"},
  {"id":"t1","component":"Text","text":"스쿼트 3세트 x 15회","usageHint":"body"},
  {"id":"ex2","component":"Row","children":["i2","t2"]},
  {"id":"i2","component":"Icon","name":"fitness_center"},
  {"id":"t2","component":"Text","text":"플랭크 3세트 x 1분","usageHint":"body"},
  {"id":"ex3","component":"Row","children":["i3","t3"]},
  {"id":"i3","component":"Icon","name":"directions_run"},
  {"id":"t3","component":"Text","text":"러닝 30분","usageHint":"body"}
]
```

### 주의사항
- Basic 조합 시 root 컴포넌트는 반드시 Card로 감싸세요 (TV 다크 테마에서 배경 구분)
- Text의 usageHint로 크기 위계를 지정하세요: h1(가장 큼) > h2 > h3 > body > caption(가장 작음)
- 너무 많은 컴포넌트를 중첩하지 마세요 (최대 depth 3단계, 컴포넌트 총 15개 이내)
- DocumentCard에 텍스트만 넣는 것보다 Basic 조합이 훨씬 보기 좋습니다

## TV Home 컴포넌트 스펙

### WeatherCard (2가지 모드)
- 오늘 날씨만 (1×1): forecast 생략 → `{"id":"root","component":"WeatherCard","city":"Seoul","temp_c":18,"feels_like_c":18,"desc":"Sunny","humidity":37,"max_c":18,"min_c":9,"rain_pct":0}`
- 주간 예보 포함 (2×1): forecast 포함 → `{"id":"root","component":"WeatherCard","city":"Seoul","temp_c":18,...,"forecast":[{"day":"목","max_c":18,"min_c":9,"desc":"Sunny"},...]}`
- "날씨 알려줘" → forecast 없이 (1×1 미니)
- "주간 날씨", "이번주 날씨" → forecast 포함 (2×1 풀)
- 반드시 [실시간 데이터]의 날씨 값을 그대로 사용!

### ContextCard
`{"id":"root","component":"ContextCard","title":"오늘 뭐 입지","recommendation":"가벼운 자켓","detail":"설명","tips":["팁1","팁2"]}`

### ControlCard
- devices: [{name, icon, on, val, id, type}]
- icon: lightbulb, ac_unit, tv, air, lock, explore, thermostat, speaker
- type: light, thermostat, mode, switch

### HomeControlCard — 전체 집안
- rooms: [{room:"거실", devices:[{name,icon,on,val}]}]

### MediaRailCard
- variant: "youtube"|"movie", items: [{title, sub, dur, url, hue}]

### PlaceRailCard
- places: [{name, cat, rating, badge, url, hue}]

### ArticleListCard
- articles: [{tag, title, src, time, url}]

### GameCard — 퀴즈 (answer + explanation 필수!)
`{"id":"root","component":"GameCard","question":"문제","choices":["A","B","C","D"],"state":"question","answer":1,"explanation":"해설"}`
- 첫 문제: createSurface + updateComponents
- 다음 문제: updateComponents만 (같은 surfaceId!)

### ComparisonCard — 비교표 (2×2 대형 카드)
`{"id":"root","component":"ComparisonCard","title":"아이폰 16 vs 갤럭시 S25 비교","columns":["아이폰 16","갤럭시 S25"],"rows":[{"label":"디자인","values":["세련된 일체감","슬림하고 실용적"]},{"label":"카메라","values":["색감 자연스러움","줌/AI 보정 다양"]},{"label":"추천","values":["영상/연동 중시","기능 다양성 중시"]}]}`
- 필수: title, columns (비교 대상 이름 배열), rows (행 배열)
- rows 각 항목: label (항목명), values (각 컬럼 값 배열)
- 비교/VS/차이점/어느게 나아 요청 시 사용
- columns는 2~3개 권장

### PlaceRailCard — 맛집/관광지 (확장)
- 기존 필드: name, cat, rating, badge, url, hue
- 추가 필드: address (주소), reviewCount (리뷰 수), mapImageUrl (지도 이미지 URL)
- mapImageUrl은 반드시 포함! 형식: `https://source.unsplash.com/400x300/?{장소+영어키워드}`
  예: 맛집 → `?korean+restaurant`, 카페 → `?cafe+interior`, 관광지 → `?seoul+tower`
  또는 장소 분위기 사진: `?food+restaurant+korean`, `?cafe+dessert`
- places 예시:
  `{"name":"마곡하우정","cat":"한식","rating":4.7,"badge":"맛집","address":"서울 강서구 마곡동","reviewCount":342,"mapImageUrl":"https://source.unsplash.com/400x300/?korean+bbq+restaurant","url":"https://map.naver.com/..."}`

### RecipeCard — 레시피/요리 (2×2 대형 카드)
`{"id":"root","component":"RecipeCard","title":"김치찌개","imageUrl":"https://source.unsplash.com/400x300/?kimchi+stew","rating":4.8,"reviewCount":2547,"prepMin":8,"cookMin":20,"servings":4,"calories":380,"difficulty":"쉬움","tags":["한식","찌개"],"ingredients":["김치 2컵","돼지고기 150g","두부 반 모"]}`
- 필수: title, imageUrl
- imageUrl은 반드시 포함! 형식: `https://source.unsplash.com/400x300/?{음식+영어키워드}`
  예: 김치찌개 → `?kimchi+stew`, 파스타 → `?pasta`, 샐러드 → `?salad+bowl`
- 옵션: rating, reviewCount, prepMin, cookMin, servings, calories, difficulty, tags, ingredients
- 요리/레시피/음식 만들기 요청 시 사용

### DocumentCard — 장문 문서 (2×3 대형 카드, 내부 스크롤)
`{"id":"root","component":"DocumentCard","title":"제목","subtitle":"부제","body":"본문 텍스트","sections":[{"heading":"섹션제목","content":"섹션내용","icon":"📌"}],"message":"AI 말풍선 메시지","tags":["태그1","태그2"]}`
- body: 일반 본문 텍스트 (긴 글 가능)
- sections: 구분된 섹션 배열 [{heading, content, icon}]
- message: AI 말풍선 (카드 상단에 하이라이트 표시)
- tags: 태그 배열 (헤더 아래 표시)
- 사용: 긴 설명, 가이드, 요약 문서, AI 상세 응답
- body만 사용해도 되고, sections만 사용해도 되고, 둘 다 써도 됨

### ListCard
- title, items(배열)

### WebappCard
- title: 웹앱 제목
- subtitle: 설명
- html_code: 완전한 HTML 코드 (<!DOCTYPE html>부터). 서버가 자동으로 호스팅하고 webapp_url을 추가합니다.
- "게임 만들어줘" → html_code에 완전한 게임 HTML/JS를 포함하세요

### InfoCard — 범용 정보 카드 (번역, 계산, 팁, 설명 등 모든 일반 정보)
`{"id":"root","component":"InfoCard","title":"스페인어 표현","subtitle":"날씨 어때","description":"보통 ¿Qué tiempo hace?라고 합니다.","icon":"translate","items":["tiempo = 날씨/시간","hace = ~하다 (3인칭)"]}`
- 필수: title
- 옵션: subtitle, description, icon, items
- icon 값: translate, language, calculate, fitness, school, lightbulb, schedule, event, code, science, psychology, tips, help, bookmark, star, info_outline(기본)
- items: 구조화된 정보를 글머리 기호 리스트로 표시 (선택)
- 번역/계산/설명/팁/추천 등 커스텀 카드에 매칭 안 되는 모든 요청에 사용
- icon은 내용에 맞는 것을 선택: 번역→translate, 계산→calculate, 운동→fitness, 일정→schedule 등
'''

    # ── Azure OpenAI call ───────────────────────
    def _call_azure(self, system_prompt, input_msgs):
        body = json.dumps({
            "model": AZURE_MODEL,
            "instructions": system_prompt,
            "input": input_msgs,
            "temperature": 0.7,
        }).encode()
        req = urllib.request.Request(AZURE_URL, data=body, headers={
            "Content-Type": "application/json",
            "api-key": AZURE_KEY,
            "Host": AZURE_HOST,
        }, method="POST")
        try:
            with urllib.request.urlopen(req, context=ssl_ctx, timeout=60) as resp:
                data = json.loads(resp.read())
            content = ""
            for item in data.get("output", []):
                if item.get("type") == "message":
                    for c in item.get("content", []):
                        if c.get("type") == "output_text":
                            content += c.get("text", "")
            return content
        except Exception as e:
            print(f"Azure error: {e}")
            return None

    # ── /api/chat (raw Azure proxy) ─────────────
    def _handle_chat(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)
        req = urllib.request.Request(AZURE_URL, data=body, headers={
            "Content-Type": "application/json",
            "api-key": AZURE_KEY,
            "Host": AZURE_HOST,
        }, method="POST")
        try:
            with urllib.request.urlopen(req, context=ssl_ctx, timeout=60) as resp:
                result = resp.read()
            self._raw_response(200, result, "application/json")
        except urllib.error.HTTPError as e:
            self._raw_response(e.code, e.read(), "application/json")
        except Exception as e:
            self._json_response(500, {"error": str(e)})

    # ── /api/weather ────────────────────────────
    # 도시명 → 위경도 매핑
    _CITY_COORDS = {
        "seoul": (37.5665, 126.9780), "서울": (37.5665, 126.9780),
        "busan": (35.1796, 129.0756), "부산": (35.1796, 129.0756),
        "incheon": (37.4563, 126.7052), "인천": (37.4563, 126.7052),
        "daegu": (35.8714, 128.6014), "대구": (35.8714, 128.6014),
        "daejeon": (36.3504, 127.3845), "대전": (36.3504, 127.3845),
        "gwangju": (35.1595, 126.8526), "광주": (35.1595, 126.8526),
        "jeju": (33.4996, 126.5312), "제주": (33.4996, 126.5312),
        "suwon": (37.2636, 127.0286), "수원": (37.2636, 127.0286),
        "tokyo": (35.6762, 139.6503), "도쿄": (35.6762, 139.6503),
        "new york": (40.7128, -74.0060), "뉴욕": (40.7128, -74.0060),
        "london": (51.5074, -0.1278), "런던": (51.5074, -0.1278),
        "paris": (48.8566, 2.3522), "파리": (48.8566, 2.3522),
    }

    # WMO 날씨 코드 → 영문 설명
    _WMO_DESC = {
        0: "Clear", 1: "Mostly Clear", 2: "Partly Cloudy", 3: "Overcast",
        45: "Foggy", 48: "Foggy", 51: "Light Drizzle", 53: "Drizzle", 55: "Heavy Drizzle",
        61: "Light Rain", 63: "Rain", 65: "Heavy Rain",
        71: "Light Snow", 73: "Snow", 75: "Heavy Snow",
        80: "Light Showers", 81: "Showers", 82: "Heavy Showers",
        95: "Thunderstorm", 96: "Thunderstorm", 99: "Thunderstorm",
    }

    def _handle_weather(self):
        qs = parse_qs(urlparse(self.path).query)
        city = qs.get("city", ["Seoul"])[0]
        from datetime import datetime
        try:
            # 도시 → 좌표 (없으면 geocoding API)
            coords = self._CITY_COORDS.get(city.lower())
            if not coords:
                geo_url = f"https://geocoding-api.open-meteo.com/v1/search?name={urllib.request.quote(city)}&count=1&language=ko"
                req = urllib.request.Request(geo_url)
                with urllib.request.urlopen(req, timeout=5) as resp:
                    geo = json.loads(resp.read())
                results = geo.get("results", [])
                if results:
                    coords = (results[0]["latitude"], results[0]["longitude"])
                else:
                    coords = (37.5665, 126.9780)  # 기본값: 서울

            lat, lon = coords
            # Open-Meteo API (무료, 키 불필요)
            api_url = (
                f"https://api.open-meteo.com/v1/forecast?"
                f"latitude={lat}&longitude={lon}"
                f"&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code"
                f"&daily=temperature_2m_max,temperature_2m_min,weather_code,precipitation_probability_max"
                f"&timezone=auto&forecast_days=7"
            )
            req = urllib.request.Request(api_url)
            with urllib.request.urlopen(req, timeout=10) as resp:
                raw = json.loads(resp.read())

            cur = raw["current"]
            daily = raw["daily"]
            days_kr = ["월","화","수","목","금","토","일"]

            forecast = []
            for i in range(len(daily["time"])):
                dt = datetime.strptime(daily["time"][i], "%Y-%m-%d")
                wmo = daily["weather_code"][i]
                forecast.append({
                    "day": days_kr[dt.weekday()],
                    "date": daily["time"][i],
                    "max_c": int(daily["temperature_2m_max"][i]),
                    "min_c": int(daily["temperature_2m_min"][i]),
                    "desc": self._WMO_DESC.get(wmo, "Clear"),
                    "rain_pct": int(daily["precipitation_probability_max"][i] or 0),
                })

            today_max = int(daily["temperature_2m_max"][0])
            today_min = int(daily["temperature_2m_min"][0])
            wmo_cur = cur["weather_code"]

            self._json_response(200, {
                "city": city,
                "temp_c": int(cur["temperature_2m"]),
                "feels_like_c": int(cur["apparent_temperature"]),
                "desc": self._WMO_DESC.get(wmo_cur, "Clear"),
                "humidity": int(cur["relative_humidity_2m"]),
                "max_c": today_max,
                "min_c": today_min,
                "rain_pct": int(daily["precipitation_probability_max"][0] or 0),
                "forecast": forecast,
            })
        except Exception as e:
            self._json_response(500, {"error": str(e)})

    # ── /api/news (뉴스 프록시 — Hacker News API) ──
    def _handle_news(self):
        try:
            # Hacker News top stories
            req = urllib.request.Request("https://hacker-news.firebaseio.com/v0/topstories.json")
            with urllib.request.urlopen(req, timeout=10) as resp:
                ids = json.loads(resp.read())[:5]
            articles = []
            for sid in ids:
                req2 = urllib.request.Request(f"https://hacker-news.firebaseio.com/v0/item/{sid}.json")
                with urllib.request.urlopen(req2, timeout=5) as resp2:
                    item = json.loads(resp2.read())
                    articles.append({
                        "title": item.get("title", ""),
                        "url": item.get("url", f"https://news.ycombinator.com/item?id={sid}"),
                        "score": item.get("score", 0),
                        "by": item.get("by", ""),
                    })
            self._json_response(200, {"articles": articles})
        except Exception as e:
            self._json_response(500, {"error": str(e)})

    # ── /api/youtube (YouTube 트렌딩 — 샘플 데이터) ──
    def _handle_youtube(self):
        # YouTube Data API 키가 없으면 샘플 데이터 반환
        sample = [
            {"title": "2026 여행지 TOP 10", "sub": "여행의 기술 · 142만", "dur": "18:24", "url": "https://youtube.com", "hue": 0},
            {"title": "초보 홈트 30분 루틴", "sub": "핏라이프 · 89만", "dur": "22:10", "url": "https://youtube.com", "hue": 150},
            {"title": "AI가 바꾸는 일상", "sub": "테크인사이드 · 203만", "dur": "15:33", "url": "https://youtube.com", "hue": 220},
            {"title": "봄 파스타 레시피", "sub": "맛있는주방 · 67만", "dur": "12:45", "url": "https://youtube.com", "hue": 30},
            {"title": "재즈 플레이리스트", "sub": "뮤직라운지 · 315만", "dur": "1:02:30", "url": "https://youtube.com", "hue": 280},
        ]
        self._json_response(200, {"items": sample})

    # ── /api/places (맛집 — 샘플 데이터) ──────────
    def _handle_places(self):
        sample = [
            {"name": "을지로 골목식당", "cat": "한식 · 을지로", "rating": 4.7, "badge": "예약 가능", "url": "https://map.naver.com", "hue": 25},
            {"name": "스시 오마카세 린", "cat": "일식 · 압구정", "rating": 4.9, "badge": "인기", "url": "https://map.naver.com", "hue": 200},
            {"name": "트라토리아 봉골레", "cat": "이탈리안 · 이태원", "rating": 4.5, "badge": "", "url": "https://map.naver.com", "hue": 10},
        ]
        self._json_response(200, {"places": sample})

    # ── /api/webapp ─────────────────────────────
    def _handle_webapp(self):
        length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(length))
        url = self._save_webapp(body.get("html", ""))
        self._json_response(200, {"url": url})

    def _save_webapp(self, html):
        app_id = str(_uuid.uuid4())[:8]
        filename = f"{app_id}.html"
        with open(os.path.join(WEBAPPS_DIR, filename), "w", encoding="utf-8") as f:
            f.write(html)
        host = self.headers.get("Host", "localhost:3002") if hasattr(self, 'headers') else "localhost:3002"
        return f"http://{host}/webapps/{filename}"

    def _serve_webapp(self):
        filename = self.path[9:]
        filepath = os.path.join(WEBAPPS_DIR, filename)
        if os.path.exists(filepath):
            with open(filepath, "rb") as f:
                self._raw_response(200, f.read(), "text/html; charset=utf-8")
        else:
            self.send_response(404)
            self.end_headers()

    # ── Helpers ─────────────────────────────────
    def _json_response(self, code, data):
        body = json.dumps(data, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def _raw_response(self, code, data, content_type):
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(data if isinstance(data, bytes) else data.encode())

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def log_message(self, fmt, *args):
        if "/api/" in (args[0] if args else ""):
            print(f"  {args[0]}")


if __name__ == "__main__":
    port = 3002
    print(f"a2ui v0.9 server on http://0.0.0.0:{port}")
    print(f"  Azure GPT: {'configured' if AZURE_KEY else 'NOT SET'}")
    print(f"  A2UI protocol: v0.9")
    HTTPServer(("0.0.0.0", port), Handler).serve_forever()
