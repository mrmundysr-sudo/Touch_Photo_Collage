package com.mundymorning.touchphotocollage.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.shape.RoundedCornerShape

enum class ThemeMode { SYSTEM, LIGHT, DARK }

val Coral = Color(0xFFE8613C)
val Sunny = Color(0xFFFFC857)
val Teal = Color(0xFF3FA796)
val Violet = Color(0xFF7B6CF0)

private val Light = lightColorScheme(
    primary = Color(0xFFD94F28), onPrimary = Color.White,
    primaryContainer = Color(0xFFFFDDD2), onPrimaryContainer = Color(0xFF3B0D00),
    secondary = Color(0xFF3B6F69), onSecondary = Color.White,
    secondaryContainer = Color(0xFFC0EDE6), onSecondaryContainer = Color(0xFF00201D),
    tertiary = Color(0xFF5D52C9), tertiaryContainer = Color(0xFFE5E0FF),
    background = Color(0xFFFFFBF7), onBackground = Color(0xFF211A17),
    surface = Color(0xFFFFFBF7), onSurface = Color(0xFF211A17),
    surfaceVariant = Color(0xFFF4E6DF), onSurfaceVariant = Color(0xFF52443E),
    surfaceContainer = Color(0xFFF8EEE8), surfaceContainerHigh = Color(0xFFF2E7E0),
    outline = Color(0xFF85746D), outlineVariant = Color(0xFFD8C2B9),
    error = Color(0xFFBA1A1A),
)

private val Dark = darkColorScheme(
    primary = Color(0xFFFF8A63), onPrimary = Color(0xFF560F00),
    primaryContainer = Color(0xFF7A2A10), onPrimaryContainer = Color(0xFFFFDDD2),
    secondary = Color(0xFF9FD0C8), onSecondary = Color(0xFF023733),
    secondaryContainer = Color(0xFF214E49), onSecondaryContainer = Color(0xFFC0EDE6),
    tertiary = Color(0xFFC6BFFF), tertiaryContainer = Color(0xFF443AB0),
    background = Color(0xFF15121A), onBackground = Color(0xFFEDE0DB),
    surface = Color(0xFF15121A), onSurface = Color(0xFFEDE0DB),
    surfaceVariant = Color(0xFF3B3340), onSurfaceVariant = Color(0xFFD6C8CE),
    surfaceContainer = Color(0xFF211C27), surfaceContainerHigh = Color(0xFF2B2531),
    outline = Color(0xFF9E8F96), outlineVariant = Color(0xFF4B4151),
    error = Color(0xFFFFB4AB),
)

private val AppTypography = Typography(
    headlineLarge = TextStyle(fontFamily = FontFamily.Serif, fontWeight = FontWeight.Bold, fontSize = 32.sp, lineHeight = 38.sp),
    headlineMedium = TextStyle(fontFamily = FontFamily.Serif, fontWeight = FontWeight.Bold, fontSize = 26.sp, lineHeight = 32.sp),
    titleLarge = TextStyle(fontWeight = FontWeight.SemiBold, fontSize = 20.sp),
    titleMedium = TextStyle(fontWeight = FontWeight.SemiBold, fontSize = 16.sp),
    bodyLarge = TextStyle(fontSize = 16.sp, lineHeight = 22.sp),
    bodyMedium = TextStyle(fontSize = 14.sp, lineHeight = 20.sp),
    labelLarge = TextStyle(fontWeight = FontWeight.SemiBold, fontSize = 14.sp),
    labelMedium = TextStyle(fontWeight = FontWeight.Medium, fontSize = 12.sp),
    labelSmall = TextStyle(fontWeight = FontWeight.Medium, fontSize = 11.sp),
)

private val AppShapes = Shapes(
    extraSmall = RoundedCornerShape(6.dp), small = RoundedCornerShape(10.dp), medium = RoundedCornerShape(16.dp),
    large = RoundedCornerShape(24.dp), extraLarge = RoundedCornerShape(32.dp),
)

@Composable
fun AppTheme(mode: ThemeMode = ThemeMode.SYSTEM, content: @Composable () -> Unit) {
    val dark = when (mode) {
        ThemeMode.SYSTEM -> isSystemInDarkTheme()
        ThemeMode.LIGHT -> false
        ThemeMode.DARK -> true
    }
    MaterialTheme(colorScheme = if (dark) Dark else Light, typography = AppTypography, shapes = AppShapes, content = content)
}
