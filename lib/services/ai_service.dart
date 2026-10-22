import 'api_client.dart';

class ChatMessage {
  final String role; // 'user' | 'assistant'
  final String content;

  const ChatMessage(this.role, this.content);

  Map<String, String> toJson() => {'role': role, 'content': content};
}

class AiService {
  AiService._();
  static final AiService instance = AiService._();

  static const int maxHistory = 10;
  static const Duration _timeout = Duration(seconds: 35);

  /// Mengirim riwayat percakapan (pesan terakhir harus dari 'user') dan
  /// mengembalikan jawaban asisten. Melempar [ApiException] dengan pesan
  /// yang siap ditampilkan.
  Future<String> ask(List<ChatMessage> history) async {
    final recent = history.length > maxHistory
        ? history.sublist(history.length - maxHistory)
        : history;

    final res = await ApiClient.instance.post(
      '/ai-chat',
      body: {'messages': recent.map((m) => m.toJson()).toList()},
      timeout: _timeout,
    );

    final reply = (res['reply'] as String?)?.trim();
    if (reply == null || reply.isEmpty) {
      throw const ApiException(
        'Asisten tidak memberi jawaban. Coba ulangi pertanyaan.',
      );
    }
    return reply;
  }
}
