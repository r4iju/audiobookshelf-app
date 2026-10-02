package com.audiobookshelf.android.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.audiobookshelf.android.data.Appearance

/** Orange links and neutral surfaces share the Apple ShelfStyle and web semantic vocabulary. */
val Accent = Color(0xFFB8431F)

private val Light = lightColorScheme(
    primary = Accent,
    onPrimary = Color.White,
    primaryContainer = Color(0xFFFFE5DA),
    onPrimaryContainer = Color(0xFF7A2C12),
    inversePrimary = Color(0xFFF07A54),
    secondary = Color(0xFF55555C),
    onSecondary = Color.White,
    secondaryContainer = Color(0xFFE9E9EE),
    onSecondaryContainer = Color(0xFF1C1C1E),
    tertiary = Accent,
    onTertiary = Color.White,
    tertiaryContainer = Color(0xFFFFE5DA),
    onTertiaryContainer = Color(0xFF7A2C12),
    background = Color(0xFFF2F2F7),
    onBackground = Color(0xFF1C1C1E),
    surface = Color.White,
    onSurface = Color(0xFF1C1C1E),
    surfaceVariant = Color(0xFFE9E9EE),
    onSurfaceVariant = Color(0xFF55555C),
    surfaceDim = Color(0xFFD9D9DF),
    surfaceBright = Color.White,
    surfaceContainerLowest = Color.White,
    surfaceContainerLow = Color(0xFFF7F7FA),
    surfaceContainer = Color(0xFFF2F2F7),
    surfaceContainerHigh = Color(0xFFE9E9EE),
    surfaceContainerHighest = Color(0xFFD9D9DF),
    surfaceTint = Color.Transparent,
    outline = Color(0xFF777780),
    outlineVariant = Color(0xFFD1D1D6),
    error = Color(0xFFC4271B),
)

private val Dark = darkColorScheme(
    primary = Color(0xFFF07A54),
    // A dark foreground keeps orange filled controls readable without diluting the accent.
    onPrimary = Color(0xFF21100A),
    primaryContainer = Color(0xFF48261C),
    onPrimaryContainer = Color(0xFFFFBEA6),
    inversePrimary = Accent,
    secondary = Color(0xFFB4B4BB),
    onSecondary = Color(0xFF1C1C1E),
    secondaryContainer = Color(0xFF2C2C2E),
    onSecondaryContainer = Color(0xFFF5F5F7),
    tertiary = Color(0xFFF07A54),
    onTertiary = Color(0xFF21100A),
    tertiaryContainer = Color(0xFF48261C),
    onTertiaryContainer = Color(0xFFFFBEA6),
    background = Color(0xFF121212),
    onBackground = Color(0xFFF5F5F7),
    surface = Color(0xFF121212),
    onSurface = Color(0xFFF5F5F7),
    surfaceVariant = Color(0xFF2C2C2E),
    onSurfaceVariant = Color(0xFFB4B4BB),
    surfaceDim = Color(0xFF121212),
    surfaceBright = Color(0xFF3A3A3C),
    surfaceContainerLowest = Color(0xFF0C0C0C),
    surfaceContainerLow = Color(0xFF171719),
    surfaceContainer = Color(0xFF1C1C1E),
    surfaceContainerHigh = Color(0xFF2C2C2E),
    surfaceContainerHighest = Color(0xFF3A3A3C),
    surfaceTint = Color.Transparent,
    outline = Color(0xFF85858E),
    outlineVariant = Color(0xFF38383C),
    error = Color(0xFFFF6B5E),
)

private val Black = Dark.copy(
    background = Color.Black, surface = Color.Black, surfaceDim = Color.Black,
    surfaceContainerLowest = Color.Black, surfaceContainerLow = Color(0xFF101010),
    surfaceContainer = Color(0xFF171717), surfaceContainerHigh = Color(0xFF232323),
    surfaceContainerHighest = Color(0xFF2F2F2F), outlineVariant = Color(0xFF303030),
)

private val AppTypography = Typography().let {
    it.copy(
        headlineMedium = it.headlineMedium.copy(fontWeight = FontWeight.Bold),
        headlineSmall = it.headlineSmall.copy(fontWeight = FontWeight.SemiBold),
        titleLarge = it.titleLarge.copy(fontWeight = FontWeight.SemiBold),
        titleMedium = it.titleMedium.copy(fontWeight = FontWeight.SemiBold),
        titleSmall = it.titleSmall.copy(fontWeight = FontWeight.SemiBold),
        labelLarge = it.labelLarge.copy(fontWeight = FontWeight.SemiBold),
    )
}

object ShelfSpacing {
    val page = 16.dp
    val gap = 16.dp
    val section = 24.dp
}

/** Keep readable text beside artwork as system font size grows, without scaling artwork endlessly. */
@Composable
fun catalogCoverWidth(prominent: Boolean = false) =
    (if (prominent) 168.dp else 148.dp) * LocalDensity.current.fontScale.coerceIn(1f, 1.2f)

val CoverShape = RoundedCornerShape(12.dp)
val Caption = TextStyle(fontSize = 12.sp)

@Composable
fun AbsTheme(appearance: Appearance, content: @Composable () -> Unit) {
    val dark = when (appearance) {
        Appearance.SYSTEM -> isSystemInDarkTheme()
        Appearance.LIGHT -> false
        Appearance.DARK, Appearance.BLACK -> true
    }
    val scheme = when {
        appearance == Appearance.BLACK -> Black
        dark -> Dark
        else -> Light
    }
    MaterialTheme(
        colorScheme = scheme,
        typography = AppTypography,
        shapes = Shapes(extraSmall = RoundedCornerShape(6.dp), small = RoundedCornerShape(10.dp), medium = RoundedCornerShape(16.dp), large = RoundedCornerShape(24.dp)),
        content = content,
    )
}
