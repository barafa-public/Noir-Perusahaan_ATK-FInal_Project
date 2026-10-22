import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../services/ai_service.dart';
import '../../services/api_client.dart';

class _Msg {
  final String role; // 'user' | 'assistant'
  final String text;
  final bool isError;

  const _Msg(this.role, this.text, {this.isError = false});
}

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  static const _suggestions = [
    'Produk apa yang stoknya menipis?',
    'Produk apa yang paling laris minggu ini?',
    'Apa yang perlu direstok?',
    'Berapa total produk yang habis?',
  ];

  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _messages = [];
  bool _sending = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Riwayat untuk server: pesan error tidak ikut dikirim.
  List<ChatMessage> get _history => _messages
      .where((m) => !m.isError)
      .map((m) => ChatMessage(m.role, m.text))
      .toList();

  Future<void> _send([String? preset]) async {
    if (_sending) return;
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty) return;

    setState(() => _messages.add(_Msg('user', text)));
    _input.clear();
    await _ask();
  }

  Future<void> _ask() async {
    setState(() => _sending = true);
    _scrollToEnd();
    try {
      final reply = await AiService.instance.ask(_history);
      if (!mounted) return;
      setState(() => _messages.add(_Msg('assistant', reply)));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(
          () => _messages.add(_Msg('assistant', e.message, isError: true)));
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToEnd();
    }
  }

  Future<void> _retry() async {
    if (_sending) return;
    setState(() {
      if (_messages.isNotEmpty && _messages.last.isError)
        _messages.removeLast();
    });
    await _ask();
  }

  void _clear() => setState(_messages.clear);

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Asisten ATK'),
        actions: [
          IconButton(
            tooltip: 'Percakapan baru',
            onPressed: (_messages.isEmpty || _sending) ? null : _clear,
            icon: const Icon(Icons.add_comment_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _emptyState()
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    itemCount: _messages.length + (_sending ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i == _messages.length) return const _TypingRow();
                      final m = _messages[i];
                      final isLast = i == _messages.length - 1;
                      return _Bubble(
                        msg: m,
                        onRetry:
                            (m.isError && isLast && !_sending) ? _retry : null,
                      );
                    },
                  ),
          ),
          _inputBar(),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.smart_toy_rounded,
                size: 56, color: AppColors.yellow),
            const SizedBox(height: 16),
            const Text(
              'Tanya soal stok',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Asisten menjawab berdasarkan data stok dan penjualan toko Anda.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: _suggestions
                  .map(
                    (s) => ActionChip(
                      label: Text(s),
                      onPressed: () => _send(s),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 20),
            const Text(
              'Jawaban AI bisa keliru. Periksa angka penting di menu Produk.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _inputBar() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.black,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 500,
                  buildCounter: (_,
                          {required currentLength,
                          required isFocused,
                          maxLength}) =>
                      null,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Tulis pertanyaan...',
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Kirim',
                onPressed: _sending ? null : _send,
                icon: const Icon(Icons.send_rounded),
                color: AppColors.yellow,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final _Msg msg;
  final VoidCallback? onRetry;

  const _Bubble({required this.msg, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final isUser = msg.role == 'user';
    final Color bg;
    final Color fg;
    BoxBorder? border;

    if (isUser) {
      bg = AppColors.yellow;
      fg = AppColors.black;
    } else if (msg.isError) {
      bg = AppColors.error.withValues(alpha: 0.12);
      fg = AppColors.error;
      border = Border.all(color: AppColors.error.withValues(alpha: 0.5));
    } else {
      bg = AppColors.surface;
      fg = AppColors.white;
      border = Border.all(color: AppColors.border);
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          border: border,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (msg.isError)
              Text(msg.text, style: TextStyle(color: fg))
            else
              SelectableText(msg.text,
                  style: TextStyle(color: fg, height: 1.35)),
            if (onRetry != null) ...[
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Coba lagi'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.error,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 32),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TypingRow extends StatelessWidget {
  const _TypingRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.yellow,
            ),
          ),
          SizedBox(width: 10),
          Text(
            'Asisten sedang menulis...',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
