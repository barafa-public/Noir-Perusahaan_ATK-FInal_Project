import 'package:flutter_test/flutter_test.dart';
import 'package:noir_final_project/models/block_model.dart';
import 'package:noir_final_project/services/blockchain_service.dart';

const _genesisHash =
    'a138c2f40105a90497554cc24e21a0f8aa9959d5fb1083d03a98b0d7a7d1d7b6';
const _hash1 =
    '38e3006b9e1303f44eed3b38a2dfffc997e0d1168a70ccc92b70e28b49a7328f';
const _hash2 =
    'a3aa27e1bd3d8220eee441de95b2795bec8005052942b8266fa01f2561fda3bc';

const _ref1 = '11111111-1111-4111-8111-111111111111';
const _ref2 = '33333333-3333-4333-8333-333333333333';
const _pay1 =
    'product=Pulpen Hitam;qty=2;unit_price=3500;total=7000;sold_at=2026-10-21T05:00:00Z;cashier=22222222-2222-4222-8222-222222222222';
const _pay2 =
    'product=Buku Tulis 38 Lembar;qty=1;unit_price=4500;total=4500;sold_at=2026-10-21T06:30:00Z;cashier=22222222-2222-4222-8222-222222222222';

BlockModel _block(
  int i,
  String type,
  String? ref,
  String payload,
  String prev,
  String hash,
) => BlockModel(
  index: i,
  type: type,
  refId: ref,
  payload: payload,
  prevHash: prev,
  hash: hash,
  createdAt: '2026-10-21T05:00:00Z',
);

List<BlockModel> _chain() => [
  _block(0, 'GENESIS', null, 'Noir Genesis', '0' * 64, _genesisHash),
  _block(1, 'SALE', _ref1, _pay1, _genesisHash, _hash1),
  _block(2, 'SALE', _ref2, _pay2, _hash1, _hash2),
];

void main() {
  group('computeHash', () {
    test('blok genesis', () {
      expect(
        BlockchainService.computeHash(
          index: 0,
          type: 'GENESIS',
          refId: null,
          payload: 'Noir Genesis',
          prevHash: '0' * 64,
        ),
        _genesisHash,
      );
    });

    test('blok penjualan', () {
      expect(
        BlockchainService.computeHash(
          index: 1,
          type: 'SALE',
          refId: _ref1,
          payload: _pay1,
          prevHash: _genesisHash,
        ),
        _hash1,
      );
    });
  });

  group('verify', () {
    test('rantai valid', () {
      final r = BlockchainService.verify(_chain());
      expect(r.ok, isTrue);
      expect(r.checked, 3);
    });

    test('rantai kosong gagal', () {
      final r = BlockchainService.verify(const []);
      expect(r.ok, isFalse);
      expect(r.issue, ChainIssue.empty);
    });

    test('isi blok diubah -> hash tidak cocok', () {
      final c = _chain();
      c[1] = _block(
        1,
        'SALE',
        _ref1,
        _pay1.replaceFirst('qty=2', 'qty=20'),
        _genesisHash,
        _hash1,
      );
      final r = BlockchainService.verify(c);
      expect(r.ok, isFalse);
      expect(r.issue, ChainIssue.hashMismatch);
      expect(r.badIndex, 1);
    });

    test(
      'blok diubah lalu hash dihitung ulang -> blok berikutnya terputus',
      () {
        final c = _chain();
        final tamperedPayload = _pay1.replaceFirst('qty=2', 'qty=20');
        final newHash = BlockchainService.computeHash(
          index: 1,
          type: 'SALE',
          refId: _ref1,
          payload: tamperedPayload,
          prevHash: _genesisHash,
        );
        c[1] = _block(1, 'SALE', _ref1, tamperedPayload, _genesisHash, newHash);
        final r = BlockchainService.verify(c);
        expect(r.ok, isFalse);
        expect(r.issue, ChainIssue.prevMismatch);
        expect(r.badIndex, 2);
      },
    );

    test('blok dihapus -> urutan terputus', () {
      final c = _chain()..removeAt(1);
      final r = BlockchainService.verify(c);
      expect(r.ok, isFalse);
      expect(r.issue, ChainIssue.indexGap);
      expect(r.badIndex, 2);
    });

    test('genesis diubah', () {
      final c = _chain();
      c[0] = _block(0, 'GENESIS', null, 'Palsu', '0' * 64, _genesisHash);
      final r = BlockchainService.verify(c);
      expect(r.ok, isFalse);
      expect(r.issue, ChainIssue.genesisInvalid);
      expect(r.badIndex, 0);
    });
  });

  group('verify dengan blok terakhir yang diingat', () {
    test('hash sama -> valid', () {
      final r = BlockchainService.verify(
        _chain(),
        pinnedIndex: 2,
        pinnedHash: _hash2,
      );
      expect(r.ok, isTrue);
    });

    test('hash berbeda -> riwayat diubah', () {
      final r = BlockchainService.verify(
        _chain(),
        pinnedIndex: 2,
        pinnedHash: 'f' * 64,
      );
      expect(r.ok, isFalse);
      expect(r.issue, ChainIssue.headChanged);
    });

    test('rantai lebih pendek dari yang diingat', () {
      final r = BlockchainService.verify(
        _chain(),
        pinnedIndex: 5,
        pinnedHash: _hash2,
      );
      expect(r.ok, isFalse);
      expect(r.issue, ChainIssue.headChanged);
    });
  });

  test('BlockModel.fields membaca payload penjualan', () {
    final b = _chain()[1];
    expect(b.fields['product'], 'Pulpen Hitam');
    expect(b.fields['qty'], '2');
    expect(b.fields['total'], '7000');
  });
}
