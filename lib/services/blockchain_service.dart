import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/env.dart';
import '../models/block_model.dart';
import 'api_client.dart';

enum ChainIssue {
  empty,
  genesisInvalid,
  indexGap,
  prevMismatch,
  hashMismatch,
  headChanged,
}

class VerifyResult {
  final bool ok;
  final int checked;
  final int? badIndex;
  final ChainIssue? issue;
  final String message;

  const VerifyResult({
    required this.ok,
    required this.checked,
    required this.message,
    this.badIndex,
    this.issue,
  });
}

class BlockchainService {
  BlockchainService._();
  static final BlockchainService instance = BlockchainService._();

  static const String genesisPayload = 'Noir Genesis';
  static final String genesisPrevHash = '0' * 64;
  static const int _pageSize = 500;

  /// SHA-256 dari "index|type|ref_id|payload|prev_hash" (ref_id kosong untuk
  /// genesis). Rumus yang sama dengan fungsi SQL append_sale_block.
  static String computeHash({
    required int index,
    required String type,
    required String? refId,
    required String payload,
    required String prevHash,
  }) =>
      sha256
          .convert(
              utf8.encode('$index|$type|${refId ?? ''}|$payload|$prevHash'))
          .toString();

  /// Memeriksa seluruh rantai (dimulai dari genesis, urut naik).
  /// [pinnedIndex] dan [pinnedHash]: blok terakhir yang pernah lolos
  /// verifikasi; jika kini berbeda, riwayat telah diubah.
  static VerifyResult verify(
    List<BlockModel> blocks, {
    int? pinnedIndex,
    String? pinnedHash,
  }) {
    if (blocks.isEmpty) {
      return const VerifyResult(
        ok: false,
        checked: 0,
        issue: ChainIssue.empty,
        message: 'Rantai kosong: blok genesis tidak ditemukan.',
      );
    }

    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];

      if (b.index != i) {
        return VerifyResult(
          ok: false,
          checked: i,
          badIndex: b.index,
          issue: ChainIssue.indexGap,
          message:
              'Urutan blok terputus: diharapkan #$i, ditemukan #${b.index}.',
        );
      }

      if (i == 0) {
        final valid = b.type == 'GENESIS' &&
            b.refId == null &&
            b.payload == genesisPayload &&
            b.prevHash == genesisPrevHash;
        if (!valid) {
          return const VerifyResult(
            ok: false,
            checked: 0,
            badIndex: 0,
            issue: ChainIssue.genesisInvalid,
            message: 'Blok genesis tidak valid.',
          );
        }
      } else if (b.prevHash != blocks[i - 1].hash) {
        return VerifyResult(
          ok: false,
          checked: i,
          badIndex: b.index,
          issue: ChainIssue.prevMismatch,
          message:
              'Blok #${b.index} tidak tersambung ke blok sebelumnya (prev_hash berbeda).',
        );
      }

      final expected = computeHash(
        index: b.index,
        type: b.type,
        refId: b.refId,
        payload: b.payload,
        prevHash: b.prevHash,
      );
      if (expected != b.hash) {
        return VerifyResult(
          ok: false,
          checked: i,
          badIndex: b.index,
          issue: ChainIssue.hashMismatch,
          message: 'Isi blok #${b.index} telah berubah (hash tidak cocok).',
        );
      }
    }

    if (pinnedIndex != null && pinnedHash != null) {
      if (blocks.length <= pinnedIndex) {
        return VerifyResult(
          ok: false,
          checked: blocks.length,
          badIndex: pinnedIndex,
          issue: ChainIssue.headChanged,
          message:
              'Rantai lebih pendek dari verifikasi sebelumnya: blok #$pinnedIndex hilang.',
        );
      }
      if (blocks[pinnedIndex].hash != pinnedHash) {
        return VerifyResult(
          ok: false,
          checked: blocks.length,
          badIndex: pinnedIndex,
          issue: ChainIssue.headChanged,
          message:
              'Blok #$pinnedIndex berbeda dari saat terakhir diverifikasi: riwayat diubah.',
        );
      }
    }

    return VerifyResult(
      ok: true,
      checked: blocks.length,
      message: 'Rantai valid: ${blocks.length} blok terverifikasi.',
    );
  }

  // ------------------------------------------------------------------
  // Server
  // ------------------------------------------------------------------

  /// Mengunduh seluruh rantai dari server. Melempar [ApiException] bila gagal.
  Future<List<BlockModel>> fetchAll() async {
    final all = <BlockModel>[];
    var after = -1;
    while (true) {
      final res = await ApiClient.instance.get(
        '/blocks?after=$after&limit=$_pageSize',
      );
      final page = ((res['blocks'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(BlockModel.fromJson)
          .toList();
      all.addAll(page);
      if (page.length < _pageSize) break;
      after = page.last.index;
    }
    return all;
  }

  /// Mengunduh rantai terbaru lalu memverifikasinya. Jika lolos, blok
  /// terakhir diingat untuk verifikasi berikutnya.
  Future<({List<BlockModel> blocks, VerifyResult result})>
      verifyOnline() async {
    final blocks = await fetchAll();
    final pin = await _loadPin();
    final result = verify(
      blocks,
      pinnedIndex: pin?.index,
      pinnedHash: pin?.hash,
    );
    if (result.ok) await _savePin(blocks.last);
    return (blocks: blocks, result: result);
  }

  // ------------------------------------------------------------------
  // Blok terakhir yang pernah lolos verifikasi (per alamat backend)
  // ------------------------------------------------------------------

  String get _pinKey {
    final id = sha256.convert(utf8.encode(Env.backendUrl)).toString();
    return 'chain_pin_${id.substring(0, 12)}';
  }

  Future<({int index, String hash})?> _loadPin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pinKey);
      if (raw == null) return null;
      final i = raw.indexOf(':');
      final index = int.tryParse(raw.substring(0, i));
      if (index == null) return null;
      return (index: index, hash: raw.substring(i + 1));
    } catch (_) {
      return null;
    }
  }

  Future<void> _savePin(BlockModel head) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pinKey, '${head.index}:${head.hash}');
    } catch (_) {}
  }
}
