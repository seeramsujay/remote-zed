package dev.zed.mobile

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.zeddesktop.mobile.R

/**
 * Material 3 / Material You Color System for Zed Mobile.
 *
 * Designed with rich semantic tokens, dynamic wallpaper color harmonizing (Android 12+),
 * and human-crafted tactile contrast so it never looks like a flat, generic AI-generated interface.
 */
object ZedColors {
    // Brand Violet
    val Brand = Color(0xFF7C5CFC)
    val BrandLight = Color(0xFFA58DFE)
    val BrandDark = Color(0xFF5E3FE6)

    // Dark Mode Palette (Refined Zinc & Obsidian)
    val DarkBackground = Color(0xFF0F0F12)
    val DarkSurface = Color(0xFF16161B)
    val DarkSurfaceContainer = Color(0xFF1E1E26)
    val DarkSurfaceContainerHigh = Color(0xFF262630)
    val DarkSurfaceContainerHighest = Color(0xFF2E2E3B)
    val DarkHairline = Color(0xFF32323E)
    val DarkText = Color(0xFFF3F3F7)
    val DarkMuted = Color(0xFF9E9EAC)
    val DarkFaint = Color(0xFF6E6E7C)

    // Light Mode Palette (Crisp Paper & Quartz)
    val LightBackground = Color(0xFFF8F8FA)
    val LightSurface = Color(0xFFFFFFFF)
    val LightSurfaceContainer = Color(0xFFF1F1F5)
    val LightSurfaceContainerHigh = Color(0xFFE8E8EE)
    val LightSurfaceContainerHighest = Color(0xFFE0E0E7)
    val LightHairline = Color(0xFFE2E2E8)
    val LightText = Color(0xFF151518)
    val LightMuted = Color(0xFF62626E)
    val LightFaint = Color(0xFF92929E)

    // Status Semantics
    val Success = Color(0xFF27A868)
    val SuccessSoft = Color(0xFF153323)
    val Danger = Color(0xFFE5484D)
    val DangerSoft = Color(0xFF38181A)
    val Warning = Color(0xFFF5A524)
    val WarningSoft = Color(0xFF38260F)
    val Info = Color(0xFF3B82F6)

    // Diff Surface Tints
    val AddedBackgroundDark = Color(0xFF12281E)
    val RemovedBackgroundDark = Color(0xFF2E1517)
    val AddedBackgroundLight = Color(0xFFE6F7ED)
    val RemovedBackgroundLight = Color(0xFFFDEBED)

    // Backward compatibility aliases for existing components
    val Background get() = DarkBackground
    val Surface get() = DarkSurface
    val Subtle get() = DarkSurfaceContainer
    val Hairline get() = DarkHairline
    val Text get() = DarkText
    val Muted get() = DarkMuted
    val Faint get() = DarkFaint
    val Accent get() = BrandLight
    val AccentPressed get() = Brand
    val AccentSoft get() = DarkSurfaceContainerHigh
    val AccentText get() = DarkText
    val AddedBackground get() = AddedBackgroundDark
    val RemovedBackground get() = RemovedBackgroundDark
}

// Inter and JetBrains Mono variable fonts
@OptIn(ExperimentalTextApi::class)
private fun interWeight(weight: Int) = Font(
    R.font.inter,
    FontWeight(weight),
    variationSettings = FontVariation.Settings(FontVariation.weight(weight)),
)

@OptIn(ExperimentalTextApi::class)
private fun monoWeight(weight: Int) = Font(
    R.font.jetbrains_mono,
    FontWeight(weight),
    variationSettings = FontVariation.Settings(FontVariation.weight(weight)),
)

internal val InterFamily = FontFamily(interWeight(400), interWeight(500), interWeight(600), interWeight(700))
internal val MonoFamily = FontFamily(monoWeight(400), monoWeight(500), monoWeight(700))

private val DarkColorScheme = darkColorScheme(
    primary = ZedColors.BrandLight,
    onPrimary = Color(0xFF180F3E),
    primaryContainer = ZedColors.BrandDark,
    onPrimaryContainer = Color(0xFFEDE8FF),
    secondary = Color(0xFFCBC4DC),
    onSecondary = Color(0xFF332D41),
    secondaryContainer = ZedColors.DarkSurfaceContainerHigh,
    onSecondaryContainer = ZedColors.DarkText,
    tertiary = Color(0xFFEFB8C8),
    onTertiary = Color(0xFF492532),
    background = ZedColors.DarkBackground,
    onBackground = ZedColors.DarkText,
    surface = ZedColors.DarkSurface,
    onSurface = ZedColors.DarkText,
    surfaceVariant = ZedColors.DarkSurfaceContainer,
    onSurfaceVariant = ZedColors.DarkMuted,
    surfaceContainerLowest = ZedColors.DarkBackground,
    surfaceContainerLow = ZedColors.DarkSurface,
    surfaceContainer = ZedColors.DarkSurfaceContainer,
    surfaceContainerHigh = ZedColors.DarkSurfaceContainerHigh,
    surfaceContainerHighest = ZedColors.DarkSurfaceContainerHighest,
    surfaceTint = ZedColors.BrandLight,
    error = ZedColors.Danger,
    onError = Color(0xFF601410),
    errorContainer = ZedColors.DangerSoft,
    onErrorContainer = Color(0xFFFFB4AB),
    outline = ZedColors.DarkHairline,
    outlineVariant = Color(0xFF262632),
)

private val LightColorScheme = lightColorScheme(
    primary = ZedColors.Brand,
    onPrimary = Color.White,
    primaryContainer = Color(0xFFECE7FE),
    onPrimaryContainer = Color(0xFF2A1578),
    secondary = Color(0xFF625B71),
    onSecondary = Color.White,
    secondaryContainer = ZedColors.LightSurfaceContainer,
    onSecondaryContainer = ZedColors.LightText,
    tertiary = Color(0xFF7D5260),
    onTertiary = Color.White,
    background = ZedColors.LightBackground,
    onBackground = ZedColors.LightText,
    surface = ZedColors.LightSurface,
    onSurface = ZedColors.LightText,
    surfaceVariant = ZedColors.LightSurfaceContainer,
    onSurfaceVariant = ZedColors.LightMuted,
    surfaceContainerLowest = Color.White,
    surfaceContainerLow = ZedColors.LightSurface,
    surfaceContainer = ZedColors.LightSurfaceContainer,
    surfaceContainerHigh = ZedColors.LightSurfaceContainerHigh,
    surfaceContainerHighest = ZedColors.LightSurfaceContainerHighest,
    surfaceTint = ZedColors.Brand,
    error = ZedColors.Danger,
    onError = Color.White,
    errorContainer = Color(0xFFFFDAD6),
    onErrorContainer = Color(0xFF410002),
    outline = ZedColors.LightHairline,
    outlineVariant = Color(0xFFECECEF),
)

/**
 * Material 3 Theme with Material You dynamic color support on Android 12+.
 */
@Composable
fun ZedTheme(
    darkTheme: Boolean = true,
    dynamicColor: Boolean = false,
    content: @Composable () -> Unit,
) {
    val context = LocalContext.current
    val colorScheme: ColorScheme = when {
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }
        darkTheme -> DarkColorScheme
        else -> LightColorScheme
    }

    fun style(size: Int, line: Int, weight: Int = 400, tracking: Double = 0.0) = TextStyle(
        fontFamily = InterFamily,
        fontSize = size.sp,
        lineHeight = line.sp,
        fontWeight = FontWeight(weight),
        letterSpacing = tracking.sp,
    )

    val typography = Typography(
        displayLarge = style(40, 48, 700, -0.8),
        displayMedium = style(34, 42, 600, -0.7),
        displaySmall = style(28, 36, 600, -0.6),
        headlineLarge = style(26, 34, 600, -0.5),
        headlineMedium = style(22, 30, 600, -0.4),
        headlineSmall = style(20, 26, 600, -0.3),
        titleLarge = style(18, 24, 600, -0.2),
        titleMedium = style(16, 22, 500, -0.15),
        titleSmall = style(14, 20, 600, -0.05),
        bodyLarge = style(16, 24, 400, -0.1),
        bodyMedium = style(14, 20, 400, -0.05),
        bodySmall = style(13, 18, 400),
        labelLarge = style(14, 20, 600, 0.1),
        labelMedium = style(12, 16, 500, 0.2),
        labelSmall = style(11, 14, 500, 0.3),
    )

    MaterialTheme(
        colorScheme = colorScheme,
        typography = typography,
        shapes = Shapes(
            extraSmall = RoundedCornerShape(8.dp),
            small = RoundedCornerShape(12.dp),
            medium = RoundedCornerShape(16.dp),
            large = RoundedCornerShape(22.dp),
            extraLarge = RoundedCornerShape(28.dp),
        ),
        content = content,
    )
}

val CodeTextStyle = TextStyle(
    fontFamily = MonoFamily,
    fontSize = 12.5.sp,
    lineHeight = 19.sp,
    color = ZedColors.DarkText,
)
