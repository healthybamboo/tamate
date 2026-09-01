import 'dart:math';

/// アプリの外のシステム（スクリーンタイムなど）に設定するコードを作る。
///
/// 覚えていては意味がない類のコードなので、アプリは生成された値を本文として
/// 抱えるだけで、あとは他のメモと同じように待たないと読めなくする。
abstract final class GeneratedCode {
  /// 生成するコードの桁数。
  static const int digits = 4;

  /// 4桁のコードを作る。
  static String create([Random? random]) {
    final source = random ?? Random.secure();
    return source.nextInt(10000).toString().padLeft(digits, '0');
  }
}
