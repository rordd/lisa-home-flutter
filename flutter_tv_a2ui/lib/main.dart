import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/home_screen.dart';
import 'theme/tv_theme.dart';

/// a2ui v0.9 TV App
/// Google A2UI 프로토콜 + Stitch 디자인 시스템 기반
/// AI가 A2UI JSON으로 UI를 동적 생성, Flutter 네이티브 렌더링

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // TV 전체화면 + 가로 고정 (native only, not web)
  if (!kIsWeb) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  runApp(const A2UIApp());
}

class A2UIApp extends StatelessWidget {
  const A2UIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'a2ui v0.9',
      debugShowCheckedModeBanner: false,
      theme: TVTheme.build(),
      shortcuts: {
        ...WidgetsApp.defaultShortcuts,
        const SingleActivator(LogicalKeyboardKey.arrowUp):
            const DirectionalFocusIntent(TraversalDirection.up),
        const SingleActivator(LogicalKeyboardKey.arrowDown):
            const DirectionalFocusIntent(TraversalDirection.down),
        const SingleActivator(LogicalKeyboardKey.arrowLeft):
            const DirectionalFocusIntent(TraversalDirection.left),
        const SingleActivator(LogicalKeyboardKey.arrowRight):
            const DirectionalFocusIntent(TraversalDirection.right),
      },
      home: const HomeScreen(),
    );
  }
}
