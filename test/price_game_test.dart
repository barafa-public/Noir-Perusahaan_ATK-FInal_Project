import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:noir_final_project/screens/tools/game_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('pembulatan', () {
    test('step menurut besar harga', () {
      expect(PriceGame.step(3500), 500);
      expect(PriceGame.step(9999), 500);
      expect(PriceGame.step(10000), 1000);
      expect(PriceGame.step(52000), 1000);
      expect(PriceGame.step(100000), 5000);
    });

    test('roundTo tidak pernah di bawah satu step', () {
      expect(PriceGame.roundTo(10, 500), 500);
      expect(PriceGame.roundTo(4375, 500), 4500);
    });
  });

  group('buildOptions', () {
    test('selalu 4 pilihan unik, positif, memuat harga benar', () {
      final rnd = Random(7);
      final prices = [
        1,
        100,
        500,
        1000,
        2000,
        3500,
        9999,
        12000,
        52000,
        100000,
        1500000
      ];
      for (final p in prices) {
        for (var i = 0; i < 200; i++) {
          final o = PriceGame.buildOptions(p, rnd);
          expect(o.length, 4, reason: 'harga $p');
          expect(o.toSet().length, 4, reason: 'harga $p: $o');
          expect(o.contains(p), isTrue, reason: 'harga $p: $o');
          expect(o.every((v) => v > 0), isTrue, reason: 'harga $p: $o');
        }
      }
    });
  });

  group('buildQuestions', () {
    test('nama unik, harga > 0, maksimal 10 soal', () {
      final pool = [
        for (var i = 0; i < 20; i++) GameItem('Barang $i', 'X', 1000 + i * 500),
        const GameItem('barang 1', 'X', 2000), // nama ganda (beda kapital)
        const GameItem('Gratis', 'X', 0), // harga tidak valid
      ];
      final qs = PriceGame.buildQuestions(pool, Random(1));
      expect(qs.length, 10);
      final names = qs.map((q) => q.item.name.toLowerCase()).toSet();
      expect(names.length, 10);
      expect(names.contains('gratis'), isFalse);
      for (final q in qs) {
        expect(q.options[q.correctIndex], q.item.price);
      }
    });

    test('katalog kecil: soal sebanyak produk yang ada', () {
      final qs = PriceGame.buildQuestions(
        const [GameItem('A', 'X', 1000), GameItem('B', 'X', 2000)],
        Random(1),
      );
      expect(qs.length, 2);
    });
  });

  group('scoreFor', () {
    test('jawaban tercepat, tanpa beruntun', () {
      expect(PriceGame.scoreFor(remainingMs: 15000, streak: 1), 160);
    });

    test('sisa waktu nol', () {
      expect(PriceGame.scoreFor(remainingMs: 0, streak: 1), 100);
    });

    test('sisa waktu di luar batas dipotong', () {
      expect(PriceGame.scoreFor(remainingMs: 99999, streak: 1), 160);
      expect(PriceGame.scoreFor(remainingMs: -50, streak: 1), 100);
    });

    test('bonus beruntun naik 10 per jawaban dan berhenti di 50', () {
      expect(PriceGame.scoreFor(remainingMs: 0, streak: 2), 110);
      expect(PriceGame.scoreFor(remainingMs: 0, streak: 3), 120);
      expect(PriceGame.scoreFor(remainingMs: 0, streak: 6), 150);
      expect(PriceGame.scoreFor(remainingMs: 0, streak: 20), 150);
    });

    test('bonus waktu sebanding dengan sisa detik', () {
      expect(PriceGame.scoreFor(remainingMs: 7500, streak: 1), 130);
    });
  });

  group('GameScoreStore', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('awalnya 0', () async {
      expect(await const GameScoreStore().load(), 0);
    });

    test('hanya menyimpan skor yang lebih tinggi', () async {
      const store = GameScoreStore();
      expect(await store.saveIfHigher(100), isTrue);
      expect(await store.saveIfHigher(50), isFalse);
      expect(await store.saveIfHigher(100), isFalse); // sama bukan rekor
      expect(await store.load(), 100);
      expect(await store.saveIfHigher(250), isTrue);
      expect(await store.load(), 250);
    });

    test('skor tiap akun terpisah', () async {
      await const GameScoreStore('a').saveIfHigher(300);
      expect(await const GameScoreStore('b').load(), 0);
      expect(await const GameScoreStore('a').load(), 300);
    });
  });
}
