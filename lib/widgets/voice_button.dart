import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../services/app_provider.dart';
import '../theme/tv_theme.dart';

/// ─────────────────────────────────────────────
/// 음성 입력 FAB
/// 리모컨 마이크 버튼 또는 화면의 FAB으로 활성화
/// ─────────────────────────────────────────────

class VoiceButton extends StatefulWidget {
  const VoiceButton({super.key});

  @override
  State<VoiceButton> createState() => _VoiceButtonState();
}

class _VoiceButtonState extends State<VoiceButton>
    with SingleTickerProviderStateMixin {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _available = false;
  bool _listening = false;
  String _partial = '';

  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  Future<void> _initSpeech() async {
    _available = await _speech.initialize(
      onError: (_) => _stopListening(),
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          _stopListening();
        }
      },
    );
    if (mounted) setState(() {});
  }

  void _startListening() async {
    if (!_available) return;

    final provider = context.read<AppProvider>();
    setState(() {
      _listening = true;
      _partial = '';
    });
    provider.setListening(true);
    _pulseCtrl.repeat();

    await _speech.listen(
      localeId: 'ko_KR',
      onResult: (result) {
        setState(() => _partial = result.recognizedWords);
        if (result.finalResult && result.recognizedWords.isNotEmpty) {
          provider.sendMessage(result.recognizedWords);
          _stopListening();
        }
      },
      listenFor: const Duration(seconds: 15),
      pauseFor: const Duration(seconds: 3),
    );
  }

  void _stopListening() {
    _speech.stop();
    _pulseCtrl.stop();
    _pulseCtrl.reset();
    if (mounted) {
      setState(() => _listening = false);
      context.read<AppProvider>().setListening(false);
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 인식 중 텍스트 표시
        if (_listening && _partial.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: TVTheme.spacingSm),
            padding: const EdgeInsets.symmetric(
              horizontal: TVTheme.spacingMd,
              vertical: TVTheme.spacingSm,
            ),
            decoration: BoxDecoration(
              color: TVTheme.bgCard.withOpacity(0.95),
              borderRadius: BorderRadius.circular(TVTheme.radiusMd),
              border: Border.all(
                color: TVTheme.accentPrimary.withOpacity(0.3),
              ),
            ),
            child: Text(
              _partial,
              style: TVTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
          ).animate().fadeIn(duration: 200.ms),

        // 마이크 버튼 (펄스 애니메이션)
        Focus(
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.select) {
              _listening ? _stopListening() : _startListening();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: GestureDetector(
            onTap: () => _listening ? _stopListening() : _startListening(),
            child: _PulsingMic(
              controller: _pulseCtrl,
              isListening: _listening,
            ),
          ),
        ),

        // 힌트 텍스트
        if (!_listening)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('음성으로 말하기', style: TVTheme.caption),
          ),
      ],
    );
  }
}

/// 펄스 + 리플 애니메이션이 있는 마이크 아이콘
class _PulsingMic extends AnimatedWidget {
  final bool isListening;

  const _PulsingMic({
    required AnimationController controller,
    required this.isListening,
  }) : super(listenable: controller);

  @override
  Widget build(BuildContext context) {
    final anim = listenable as Animation<double>;
    final scale = isListening ? 1.0 + (anim.value * 0.12) : 1.0;

    return SizedBox(
      width: 160,
      height: 160,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 3단계 동심원 리플
          if (isListening) ...[
            _RippleCircle(animation: anim, radius: 72, opacity: 0.10, delay: 0.0),
            _RippleCircle(animation: anim, radius: 56, opacity: 0.15, delay: 0.2),
            _RippleCircle(animation: anim, radius: 40, opacity: 0.20, delay: 0.4),
          ],
          // 메인 버튼
          Transform.scale(
            scale: scale,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: isListening
                    ? LinearGradient(
                        colors: [TVTheme.accentWarm, TVTheme.accentPrimary],
                        transform: GradientRotation(anim.value * 6.28), // 360도 회전
                      )
                    : LinearGradient(
                        colors: [
                          TVTheme.accentPrimary,
                          TVTheme.accentPrimary.withOpacity(0.7),
                        ],
                      ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (isListening ? TVTheme.accentWarm : TVTheme.accentPrimary)
                        .withOpacity(0.4),
                    blurRadius: isListening ? 30 : 16,
                    spreadRadius: isListening ? 4 : 0,
                  ),
                ],
              ),
              child: Icon(
                isListening ? Icons.mic : Icons.mic_none,
                size: 34,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 동심원 리플 링
class _RippleCircle extends StatelessWidget {
  final Animation<double> animation;
  final double radius;
  final double opacity;
  final double delay;

  const _RippleCircle({
    required this.animation,
    required this.radius,
    required this.opacity,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    // delay를 적용한 진행률 계산
    final progress = ((animation.value - delay) % 1.0).clamp(0.0, 1.0);
    final currentRadius = radius + (progress * 24); // 확산
    final currentOpacity = opacity * (1.0 - progress); // 페이드아웃

    return Container(
      width: currentRadius * 2,
      height: currentRadius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: TVTheme.accentPrimary.withOpacity(currentOpacity),
          width: 1.5,
        ),
      ),
    );
  }
}
