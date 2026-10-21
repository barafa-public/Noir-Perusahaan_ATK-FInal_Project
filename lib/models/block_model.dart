class BlockModel {
  final int index;
  final String type; // 'GENESIS' | 'SALE'
  final String? refId; // id penjualan; null untuk genesis
  final String payload;
  final String prevHash;
  final String hash;
  final String createdAt; // ISO-8601 UTC, waktu diterima server

  const BlockModel({
    required this.index,
    required this.type,
    required this.refId,
    required this.payload,
    required this.prevHash,
    required this.hash,
    required this.createdAt,
  });

  bool get isGenesis => type == 'GENESIS';

  factory BlockModel.fromJson(Map<String, dynamic> j) => BlockModel(
    index: (j['block_index'] as num).toInt(),
    type: j['block_type'] as String,
    refId: j['ref_id'] as String?,
    payload: j['payload'] as String,
    prevHash: j['prev_hash'] as String,
    hash: j['hash'] as String,
    createdAt: j['created_at'] as String,
  );

  /// Payload penjualan "product=...;qty=...;total=..." -> peta kunci/nilai.
  Map<String, String> get fields {
    final m = <String, String>{};
    for (final part in payload.split(';')) {
      final i = part.indexOf('=');
      if (i > 0) m[part.substring(0, i)] = part.substring(i + 1);
    }
    return m;
  }

  /// 'a138c2f4…d7b6d6' untuk tampilan ringkas.
  static String shortHash(String h) =>
      h.length > 16 ? '${h.substring(0, 8)}…${h.substring(h.length - 6)}' : h;
}
