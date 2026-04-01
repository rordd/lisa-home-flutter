# TV A2UI Design System

55" TV / 3m+ viewing distance / Remote control navigation

## Typography

| Role | Size | Weight | Color | Usage |
|------|------|--------|-------|-------|
| Hero | 80-96px | w200 | white | 온도 등 한눈에 보이는 숫자 |
| Display | 36px | w700 | white | 도시명, card titles |
| Headline | 28px | w600 | white | 상세 정보 (최고/최저/체감) |
| Title | 24px | w600 | white | 주간 예보 요일 라벨 |
| Body | 22px | w400 | white/secondary | 주간 예보 온도 |
| Sub | 20px | w400 | #E0E0E0 | secondary info |
| Caption | 16px | w400 | #AAAAAA | metadata, timestamps |

### Weather Card Specific
| Element | Size | Note |
|---------|------|------|
| Hero temperature | 96px | w200, letterSpacing -4 |
| City name | 36px | |
| Weather description | 36px | |
| Detail info (최고/최저/체감/습도) | 28px | |
| Forecast day label | 24px | |
| Forecast temperature | 28px (max) / 22px (min) | |
| Weather icon | 72px (main) / 48px (forecast) | |

**Minimum font size: 20px** (anything smaller is unreadable at 3m on 55" TV)

Font: Noto Sans KR (Google Fonts), text shadow on TV catalog cards.

## Color

| Token | Value | Usage |
|-------|-------|-------|
| bg | #000000 | app background |
| bgCard | #1C1C1E | card surface |
| accent | #0A84FF | primary actions (TVTheme) |
| accent-tv | #00E5BA | mint accent (TV catalog) |
| text | #FFFFFF | primary text |
| textSub | #E0E0E0 | secondary text |
| textMuted | #AAAAAA | disabled, metadata |
| tintGreen | #32D74B | on/success state |
| tintWarm | #FF6961 | error/news |
| tintOrange | #FF9F0A | controls |

## Card Glass Style

- Background: `black 55%` opacity (unfocused), `black 75%` (focused)
- Border: `white 10%` (unfocused), `white 50% / 2px` (focused)
- Focus glow: white shadow, blur 20, spread 4
- Top edge highlight on focus: white gradient line 1.5px
- No BackdropFilter (performance on TV hardware)
- RepaintBoundary on each card

## Focus & Navigation

- Scale: 1.0 -> **1.10** on focus
- Curve: `Curves.easeOutBack` (300ms)
- Border: white 2px + glow shadow
- Shimmer: single sweep on focus gain (300ms, left to right)
- All cards must be focusable via remote (arrow keys + select)

## Animation

### Card Entrance
- Scale: 0.85 -> 1.0
- Fade: 0 -> 1
- SlideY: 0.08 -> 0
- Duration: 600ms per card
- Stagger: 120ms between cards
- Curve: easeOutBack
- Respect `MediaQuery.disableAnimations`

### Mode Transitions
- Toast/Input bar: easeOutBack slide-up (400ms)
- Chat overlay: slideX right-to-left (400ms, easeOutCubic)
- Popup: scale 0.95->1.0 + fadeIn (300ms)

### Voice Button
- 3 concentric ripple rings (radius 40/56/72px)
- Gradient rotation during listening (360deg/3s)
- Pulse scale 1.0 -> 1.12

## Layout

- Overscan margins: 48px left/right, 24px top/bottom
- Card spacing: 20px gap
- Card alignment: top-left (WrapAlignment.start)
- Max cards visible: 8 (scroll for more)
- Card internal padding: 32-40px

## AI Speech Bubble

- Position: right side of card area, bottom-aligned
- Background: black 70%, rounded (24px, bottom-right 6px for tail)
- Border: white 12%
- Animation: slideX + fadeIn (400ms)
- Shows AI spoken response instead of bottom toast

## Responsive Card Sizes

| Size class | Max width |
|------------|-----------|
| full | 55% of screen |
| wide | 50% |
| half | 45% |
| medium | 42% |
| small | 38% |
| weather | min 680px (IntrinsicWidth) |

## Performance Guidelines

- FPS target: 60fps
- Below 50fps: disable blur effects
- Below 45fps: downgrade to simple curves
- Below 30fps: disable all custom animations
- Use RepaintBoundary per card
- No continuous animations (shimmer is one-shot)
- Entrance animations use `flutter_animate`, focus uses `AnimatedContainer`

## IoT Card Structure

- Single HomeControlCard for all rooms (not separate cards per room)
- Room sections inside one large card
- Device tiles: 120px wide, toggleable
- Show total on/off count in header

## Don'ts

- No emoji in card titles
- No font below 16px
- No BackdropFilter on settled cards
- No center-aligned card layout (use top-left)
- No continuous looping animations (battery/GPU)
