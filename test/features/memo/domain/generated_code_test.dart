import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tamate/features/memo/domain/generated_code.dart';

void main() {
  test('4桁のコードを作る', () {
    for (var seed = 0; seed < 100; seed++) {
      final code = GeneratedCode.create(Random(seed));

      expect(code, matches(RegExp(r'^\d{4}$')));
    }
  });

  test('0 で始まるコードも桁を落とさない', () {
    // 0429 のような値を 429 にしてしまうと、設定先に入力できない。
    final code = GeneratedCode.create(_FixedRandom(429));

    expect(code, '0429');
  });
}

/// 常に同じ値を返す [Random]。
class _FixedRandom implements Random {
  _FixedRandom(this.value);

  final int value;

  @override
  int nextInt(int max) => value;

  @override
  bool nextBool() => throw UnimplementedError();

  @override
  double nextDouble() => throw UnimplementedError();
}
