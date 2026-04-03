import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../models/models.dart';
import '../services/app_provider.dart';
import '../theme/tv_theme.dart';

String _stripHtml(String s) => s.replaceAll(RegExp(r'<[^>]*>'), '').trim();

/// ─────────────────────────────────────────────
/// 채팅 오버레이 — Glass panel, typography-led
/// ─────────────────────────────────────────────

class ChatOverlay extends StatefulWidget {
  const ChatOverlay({super.key});
  @override
  State<ChatOverlay> createState() => _ChatOverlayState();
}

class _ChatOverlayState extends State<ChatOverlay> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _send(AppProvider provider) {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    provider.sendMessage(text);
    _controller.clear();
    Future.delayed(100.ms, () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: 300.ms, curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final messages = provider.chatHistory;

    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(TVTheme.radiusLg),
        bottomLeft: Radius.circular(TVTheme.radiusLg),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Container(
          width: 460,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.55),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(TVTheme.radiusLg),
              bottomLeft: Radius.circular(TVTheme.radiusLg),
            ),
            border: Border(
              left: BorderSide(color: Colors.white.withOpacity(0.08), width: 0.5),
            ),
          ),
          child: Column(
            children: [
              _buildHeader(provider),
              Expanded(
                child: messages.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        itemCount: messages.length,
                        itemBuilder: (ctx, i) => _buildMessage(messages[i]),
                      ),
              ),
              _buildInputBar(provider),
            ],
          ),
        ),
      ),
    )
        .animate()
        .slideX(
          begin: 1.0, end: 0.0,
          duration: 400.ms,
          curve: Curves.easeOutCubic,
        )
        .fadeIn(duration: 300.ms);
  }

  Widget _buildHeader(AppProvider provider) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 12, 12),
      child: Row(
        children: [
          Text('LISA', style: TVTheme.titleLarge.copyWith(
              color: TVTheme.accent, fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          Container(width: 6, height: 6,
              decoration: BoxDecoration(
                  color: TVTheme.tintGreen, shape: BoxShape.circle)),
          const Spacer(),
          GestureDetector(
            onTap: () => provider.hideChat(),
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded,
                  size: 18, color: TVTheme.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('무엇이든 물어보세요',
              style: TVTheme.headlineMedium.copyWith(color: TVTheme.textMuted)),
          const SizedBox(height: 8),
          Text('"날씨 알려줘" · "퀴즈 하자"',
              style: TVTheme.bodyMedium.copyWith(
                  color: TVTheme.textMuted.withOpacity(0.6))),
        ],
      ),
    );
  }

  Widget _buildMessage(ChatMessage message) {
    final isUser = message.role == MessageRole.user;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: TVTheme.accent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.smart_toy_rounded,
                  size: 16, color: TVTheme.accent),
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isUser
                    ? TVTheme.accent
                    : Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(14),
                  topRight: const Radius.circular(14),
                  bottomLeft: Radius.circular(isUser ? 14 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 14),
                ),
              ),
              child: message.isLoading
                  ? _buildLoadingIndicator()
                  : Text(_stripHtml(message.content),
                      style: TVTheme.bodyLarge.copyWith(
                        color: isUser ? Colors.white : TVTheme.textPrimary,
                        fontSize: 22,
                      )),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return Shimmer.fromColors(
      baseColor: TVTheme.textMuted,
      highlightColor: TVTheme.textSecondary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 180, height: 14,
              decoration: BoxDecoration(
                  color: TVTheme.textMuted, borderRadius: BorderRadius.circular(6))),
          const SizedBox(height: 8),
          Container(width: 120, height: 14,
              decoration: BoxDecoration(
                  color: TVTheme.textMuted, borderRadius: BorderRadius.circular(6))),
        ],
      ),
    );
  }

  Widget _buildInputBar(AppProvider provider) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _controller,
                focusNode: _inputFocus,
                style: TVTheme.bodyLarge.copyWith(
                    color: TVTheme.textPrimary, fontSize: 22),
                decoration: InputDecoration(
                  hintText: '메시지 입력...',
                  hintStyle: TVTheme.bodyMedium.copyWith(color: TVTheme.textMuted),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                ),
                onSubmitted: (_) => _send(provider),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => _send(provider),
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: TVTheme.accent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.arrow_upward_rounded,
                  size: 20, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
