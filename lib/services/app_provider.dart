import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../models/models.dart';
import '../services/gpt_service.dart';

/// a2ui v0.9 — 앱 상태 관리 (Stitch HTML 기반)

class AppProvider extends ChangeNotifier {
  AppUIState _uiState = AppUIState();
  final List<ChatMessage> _chatHistory = [];
  bool _chatVisible = false;
  bool _isListening = false;

  AppUIState get uiState => _uiState;
  List<ChatMessage> get chatHistory => List.unmodifiable(_chatHistory);
  bool get chatVisible => _chatVisible;
  bool get isListening => _isListening;

  final FlutterTts _tts = FlutterTts();

  AppProvider() {
    _initTTS();
  }

  Future<void> _initTTS() async {
    await _tts.setLanguage('ko-KR');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
  }

  /// 사용자 메시지 전송 → GPT + Stitch 호출
  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    _chatHistory.add(ChatMessage(
      role: MessageRole.user,
      content: text.trim(),
    ));

    _uiState = _uiState.copyWith(isBusy: true);
    final loadingMsg = ChatMessage(
      role: MessageRole.assistant,
      content: '',
      isLoading: true,
    );
    _chatHistory.add(loadingMsg);
    notifyListeners();

    try {
      final response = await GPTService.generate(
        text.trim(),
        history: _chatHistory.where((m) => !m.isLoading).toList(),
      );

      // 로딩 메시지 교체
      _chatHistory.removeWhere((m) => m.id == loadingMsg.id);
      if (response.spokenText.isNotEmpty) {
        _chatHistory.add(ChatMessage(
          role: MessageRole.assistant,
          content: response.spokenText,
        ));
      }

      // HTML 섹션 추가 (최대 3개 유지)
      if (response.html.isNotEmpty) {
        final sections = [
          HtmlSection(html: response.html),
          ..._uiState.htmlSections,
        ];
        // 오래된 것 제거
        final trimmed = sections.length > AppUIState.maxSections
            ? sections.sublist(0, AppUIState.maxSections)
            : sections;
        _uiState = _uiState.copyWith(
          isBusy: false,
          htmlSections: trimmed,
          greeting: response.spokenText,
        );
      } else {
        _uiState = _uiState.copyWith(isBusy: false);
      }

      // 채팅창
      if (response.showChat) {
        _chatVisible = true;
      } else if (response.html.isNotEmpty) {
        _chatVisible = false;
      }

      // TTS
      if (response.spokenText.isNotEmpty) {
        _tts.speak(response.spokenText);
      }
    } catch (_) {
      _chatHistory.removeWhere((m) => m.id == loadingMsg.id);
      _chatHistory.add(ChatMessage(
        role: MessageRole.assistant,
        content: '처리 중 문제가 발생했어요.',
      ));
      _uiState = _uiState.copyWith(isBusy: false);
    }
    notifyListeners();
  }

  void toggleChat() {
    _chatVisible = !_chatVisible;
    notifyListeners();
  }

  void showChat() {
    _chatVisible = true;
    notifyListeners();
  }

  void hideChat() {
    _chatVisible = false;
    notifyListeners();
  }

  void setListening(bool val) {
    _isListening = val;
    notifyListeners();
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }
}
