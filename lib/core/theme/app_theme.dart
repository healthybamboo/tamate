import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// アプリ全体のテーマ定義。
///
/// 「待つ」時間を過ごす画面なので、暗い方を主役にした低彩度の配色にしてある。
/// 面と余白で区切り、枠線と影はできるだけ使わない。
abstract final class AppTheme {
  /// ライト。紙より少し青い白を敷く。
  static ThemeData light() => _build(_lightScheme);

  /// ダーク。こちらが主。
  static ThemeData dark() => _build(_darkScheme);

  static const ColorScheme _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF3E5F92),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFDCE6F6),
    onPrimaryContainer: Color(0xFF17263D),
    secondary: Color(0xFF55637B),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFDCE6F6),
    onSecondaryContainer: Color(0xFF17263D),
    error: Color(0xFF8F3B36),
    onError: Color(0xFFFFFFFF),
    surface: Color(0xFFF4F6FA),
    onSurface: Color(0xFF1B2029),
    onSurfaceVariant: Color(0xFF5A6373),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF0F3F8),
    surfaceContainer: Color(0xFFEAEEF5),
    surfaceContainerHigh: Color(0xFFE4E9F2),
    surfaceContainerHighest: Color(0xFFDDE3EE),
    outline: Color(0xFFB8C1D0),
    outlineVariant: Color(0xFFD8DEE9),
  );

  static const ColorScheme _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF8AA9D6),
    onPrimary: Color(0xFF10192A),
    primaryContainer: Color(0xFF25344B),
    onPrimaryContainer: Color(0xFFCFE0F5),
    secondary: Color(0xFF9BA7BC),
    onSecondary: Color(0xFF12151B),
    secondaryContainer: Color(0xFF22303F),
    onSecondaryContainer: Color(0xFFCFE0F5),
    error: Color(0xFFE9A8A3),
    onError: Color(0xFF2A1210),
    surface: Color(0xFF12151B),
    onSurface: Color(0xFFE6E9EF),
    onSurfaceVariant: Color(0xFFA8B0BF),
    surfaceContainerLowest: Color(0xFF0D1015),
    surfaceContainerLow: Color(0xFF171B22),
    surfaceContainer: Color(0xFF1B2029),
    surfaceContainerHigh: Color(0xFF212733),
    surfaceContainerHighest: Color(0xFF272E3B),
    outline: Color(0xFF49525F),
    outlineVariant: Color(0xFF2C333F),
  );

  /// 角の丸み。面で見せるので、どの部品も同じ丸みで揃える。
  static const double _radius = 12;

  static ThemeData _build(ColorScheme colorScheme) {
    final isDark = colorScheme.brightness == Brightness.dark;
    final base = ThemeData(colorScheme: colorScheme, useMaterial3: true);
    final textTheme =
        GoogleFonts.zenKakuGothicNewTextTheme(base.textTheme).apply(
      bodyColor: colorScheme.onSurface,
      displayColor: colorScheme.onSurface,
    );

    return base.copyWith(
      scaffoldBackgroundColor: colorScheme.surface,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        // 画面の名前は控えめにしすぎない。ここが小さいと全体が締まらない。
        titleTextStyle: textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ),
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      // 面で塗り、枠線は引かない。
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainer,
        border: _inputBorder(),
        enabledBorder: _inputBorder(),
        focusedBorder: _inputBorder(color: colorScheme.primary, width: 1.5),
        errorBorder: _inputBorder(color: colorScheme.error),
        focusedErrorBorder: _inputBorder(color: colorScheme.error, width: 1.5),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(_radius)),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          side: BorderSide(color: colorScheme.outline),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(_radius)),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(textStyle: textTheme.labelLarge),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: colorScheme.surfaceContainerLow,
          selectedBackgroundColor: colorScheme.primaryContainer,
          selectedForegroundColor: colorScheme.onPrimaryContainer,
          side: BorderSide(color: colorScheme.outlineVariant),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(_radius)),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainer,
        selectedColor: colorScheme.primaryContainer,
        checkmarkColor: colorScheme.onPrimaryContainer,
        side: BorderSide.none,
        showCheckmark: true,
        labelStyle: textTheme.labelLarge,
        secondaryLabelStyle: textTheme.labelLarge?.copyWith(
          color: colorScheme.onPrimaryContainer,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(_radius)),
        ),
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainer,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        iconColor: colorScheme.onSurfaceVariant,
        titleTextStyle: textTheme.titleMedium,
        subtitleTextStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        // 画面の名前は控えめにしすぎない。ここが小さいと全体が締まらない。
        titleTextStyle: textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ),
        contentTextStyle: textTheme.bodyMedium,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colorScheme.surfaceContainerHighest,
        contentTextStyle: textTheme.bodyMedium,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(_radius)),
        ),
      ),
      expansionTileTheme: ExpansionTileThemeData(
        iconColor: colorScheme.onSurfaceVariant,
        collapsedIconColor: colorScheme.onSurfaceVariant,
        textColor: colorScheme.onSurface,
        collapsedTextColor: colorScheme.onSurface,
        shape: const Border(),
        collapsedShape: const Border(),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colorScheme.onPrimary
              : colorScheme.outline,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colorScheme.primary
              : colorScheme.surfaceContainerHighest,
        ),
      ),
    );
  }

  static OutlineInputBorder _inputBorder({Color? color, double width = 1}) =>
      OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(_radius)),
        borderSide: color == null
            ? BorderSide.none
            : BorderSide(color: color, width: width),
      );
}
