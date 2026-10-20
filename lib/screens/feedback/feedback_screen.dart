import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../services/api_client.dart';
import '../../services/feedback_service.dart';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _formKey = GlobalKey<FormState>();
  final _impression = TextEditingController();
  final _suggestion = TextEditingController();

  int _rating = 0;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _impression.dispose();
    _suggestion.dispose();
    super.dispose();
  }

  String? _validateText(String? v, String label) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return '$label wajib diisi';
    if (s.length < 5) return '$label minimal 5 karakter';
    if (s.length > 500) return '$label maksimal 500 karakter';
    return null;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final valid = _formKey.currentState!.validate();
    if (_rating == 0) {
      setState(() => _error = 'Pilih penilaian bintang 1 sampai 5.');
      return;
    }
    if (!valid) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await FeedbackService.instance.submit(
        rating: _rating,
        impression: _impression.text,
        suggestion: _suggestion.text,
      );
      if (!mounted) return;
      _impression.clear();
      _suggestion.clear();
      setState(() => _rating = 0);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Terima kasih! Saran dan kesan Anda tersimpan.')),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saran & Kesan')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Mata Kuliah Pemrograman Aplikasi Mobile',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Tuliskan kesan dan saran Anda untuk mata kuliah ini.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 24),
                const Text('Penilaian',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Row(
                  children: List.generate(5, (i) {
                    final value = i + 1;
                    return IconButton(
                      onPressed: _loading
                          ? null
                          : () => setState(() {
                                _rating = value;
                                _error = null;
                              }),
                      iconSize: 36,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 48, minHeight: 48),
                      icon: Icon(
                        value <= _rating
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        color: value <= _rating
                            ? AppColors.yellow
                            : AppColors.textSecondary,
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _impression,
                  enabled: !_loading,
                  maxLines: 4,
                  maxLength: 500,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Kesan',
                    alignLabelWithHint: true,
                    hintText: 'Bagaimana kesan Anda?',
                  ),
                  validator: (v) => _validateText(v, 'Kesan'),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _suggestion,
                  enabled: !_loading,
                  maxLines: 4,
                  maxLength: 500,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Saran',
                    alignLabelWithHint: true,
                    hintText: 'Apa saran Anda?',
                  ),
                  validator: (v) => _validateText(v, 'Saran'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.error.withValues(alpha: 0.5)),
                    ),
                    child: Text(_error!,
                        style: const TextStyle(color: AppColors.error)),
                  ),
                ],
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.black),
                        )
                      : const Text('Kirim'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
