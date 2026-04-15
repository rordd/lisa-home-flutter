# a2ui TV -- AI-Powered TV Overlay

ZeroClaw AI 에이전트가 UI를 동적으로 생성하는 webOS Flutter 오버레이 앱.
TV 시청 중 엣지 핸들을 통해 AI 카드(날씨, 뉴스, 영화, 유튜브 등)를 표시하고,
카드 클릭 시 유튜브/브라우저 등 TV 앱을 직접 실행합니다.

## 동작 방식

```
TV Screen (Live TV / YouTube / etc.)
+----------------------------------------------+------+
|                                              | Edge |
|          Background App                      |handle|
|          (receives remote input)             |16x120|
+----------------------------------------------+------+

          Edge tap -> Widget Shelf opens

+----------------------------------------------+------+
|  +------+  +------+  +------+                |Mic  X|
|  | Card |  | Card |  | Card |                |      |
|  +------+  +------+  +------+                |      |
|  +----------+  +------+                      |      |
|  |  Wide    |  | Card |                      |      |
|  +----------+  +------+                      |      |
+----------------------------------------------+------+
       |                              |
       v                              v
+-----------+                 +----------------+
| Flutter   | <-- WebSocket --| ZeroClaw v0.6+ |
| (a2ui)    |    /app         | (Rust agent)   |
+-----------+                 +----------------+
```

| 상태 | 화면 | 입력 |
|------|------|------|
| Edge | 우측 16x120px 핸들만 표시 | 뒤 앱이 리모컨 입력 받음 (needFocus: false) |
| Widget Shelf | 저장된 AI 카드 그리드 | 이 앱이 입력 받음 (needFocus: true) |
| Spotlight | 새 AI 카드 전면 표시 | 이 앱이 입력 받음 |

## 빌드

### 사전 준비

- flutter-webos CLI (webOS Flutter SDK)
- Starfish SDK (ARM 크로스컴파일 툴체인)
- ZeroClaw 서버 (WebSocket 백엔드)

### webOS IPK 빌드

```bash
source ~/starfish-sdk-x86_64/environment-setup-ca9v1-webosmllib32-linux-gnueabi

flutter-webos build webos --ipk --release --no-tree-shake-icons
# 결과: build/webos/arm/release/ipk/dev.lge.tv.a2ui.ipk
```

`--no-tree-shake-icons` 필수 (json_schema_builder 때문에 IconTreeShaker 실패).

### WS 서버 주소 변경

`lib/screens/home_screen.dart`에서 직접 수정:
```dart
_contentGenerator = LisaWsContentGenerator('ws://SERVER_IP:42618/app');
```

## TV 설치

### 1. 개발자 모드 설정 (재부팅마다 필요)

```bash
ssh -p 2181 root@TV_IP

touch /var/luna/preferences/devmode_enabled
touch /var/luna/preferences/debug_system_apps
touch /var/luna/preferences/debug_system_services

mkdir -p /var/luna-service2-dev/{roles.d,manifests.d,client-permissions.d}
cat > /var/luna-service2-dev/devmode_certificate.json << 'EOF'
{"devmodeGroups":["public","default.permission","default.permission.platform","application.launcher","application.query","surfacemanager.query","settings.operation","settings.query","media.operation","database.operation","activity.operation","preload.operation"]}
EOF
```

### 2. 클린 설치 (순서 중요!)

```bash
scp -P 2181 dev.lge.tv.a2ui.ipk root@TV_IP:/tmp/

# cert -> scan -> 삭제 -> scan -> 설치 -> scan -> launch 순서 엄수
ls-control scan-volatile-dirs; sleep 2
killall luna-send
rm -rf /var/luna-service2-dev/roles.d/dev.lge.tv.a2ui*
rm -rf /var/luna-service2-dev/manifests.d/dev.lge.tv.a2ui*
rm -rf /var/luna-service2-dev/client-permissions.d/dev.lge.tv.a2ui*
rm -rf /media/developer/apps/usr/palm/applications/dev.lge.tv.a2ui
ls-control scan-volatile-dirs; sleep 1

luna-send -i -f luna://com.webos.appInstallService/dev/install \
  '{"id":"dev.lge.tv.a2ui","ipkUrl":"/tmp/dev.lge.tv.a2ui.ipk","subscribe":true}'
# "state": "installed" 확인

ls-control scan-volatile-dirs; sleep 2
luna-send -n 1 -f luna://com.webos.applicationManager/launch '{"id":"dev.lge.tv.a2ui"}'
```

순서가 틀리면 `LS::Error: Invalid permissions` 크래시 발생.

### 3. ZeroClaw 서버 실행

```bash
cd /path/to/lisa
source ~/.zeroclaw/.env
./target/release/zeroclaw daemon
```

daemon 모드 필수. `gateway start`만으로는 Lisa 채널이 동작하지 않음.

## webOS Window Type 참고

| 타입 | 설명 |
|------|------|
| card | 일반 전체화면 |
| overlay | 카드 앱 위에 표시, 포커스는 overlay 앱이 가져감 |
| **floating** | 카드 앱 위에 표시, 포커스를 카드 앱/floating 앱 둘 다 가져갈 수 있음 |

이 앱은 `floating` 타입 사용. `needFocus`를 동적으로 전환하여 뒤 앱과 입력을 공유.

## 리모컨 조작

| 키 | 동작 |
|----|------|
| RED (F1) | 위젯 패널 열기/닫기 |
| Back / ESC | 패널/spotlight 닫기, edge 전환 |
| 마우스 우클릭 | Back과 동일 |
| Edge 핸들 탭 | 위젯 패널 열기 |

## 파일 구조

```
lib/
  main.dart                          # 진입점 + LS2ServiceChannel 등록
  screens/
    home_screen.dart                 # 메인 (edge, widget shelf, spotlight)
  catalog/
    tv_catalog.dart                  # A2UI 카드 카탈로그 + openUrl (luna API)
  services/
    lisa_ws_content_generator.dart   # ZeroClaw WebSocket 통신
  theme/
    tv_theme.dart                    # TV 다크 테마

webos/
  meta/
    appinfo.json                     # webOS 앱 설정 (floating, transparent)
```
