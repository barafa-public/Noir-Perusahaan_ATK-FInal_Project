import 'api_client.dart';

class FeedbackService {
  FeedbackService._();
  static final FeedbackService instance = FeedbackService._();

  /// Mengirim saran dan kesan ke Supabase lewat Edge Function `feedback`.
  /// Melempar [ApiException] jika gagal.
  Future<void> submit({
    required int rating,
    required String impression,
    required String suggestion,
  }) async {
    await ApiClient.instance.post(
      '/feedback',
      body: {
        'rating': rating,
        'impression': impression.trim(),
        'suggestion': suggestion.trim(),
      },
    );
  }
}
