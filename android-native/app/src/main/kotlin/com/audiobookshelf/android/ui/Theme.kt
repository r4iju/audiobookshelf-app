package com.audiobookshelf.android.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.shape.RoundedCornerShape
import com.audiobookshelf.android.data.Appearance

/** Shared semantic accent with the Apple preview (ShelfStyle.accent). */
val Accent = Color(0xFFCC4F2B)

private val Light = lightColorScheme(
    primary = Accent,
    onPrimary = Color.White,
    primaryContainer = Color(0xFFFFDBCF),
    onPrimaryContainer = Color(0xFF3A0B00),
    secondary = Color(0xFF6E5B53),
    secondaryContainer = Color(0xFFF5DED5),
    background = Color(0xFFFBF8F6),
    onBackground = Color(0xFF201A18),
    surface = Color(0xFFFBF8F6),
    onSurface = Color(0xFF201A18),
    surfaceVariant = Color(0xFFEFE6E2),
    onSurfaceVariant = Color(0xFF53433E),
    surfaceContainer = Color(0xFFF3EDEA),
    surfaceContainerHigh = Color(0xFFEDE6E3),
    outline = Color(0xFF85736D),
    outlineVariant = Color(0xFFD8C2BB),
    error = Color(0xFFB3261E),
)

private val Dark = darkColorScheme(
    primary = Color(0xFFFFB59D),
    onPrimary = Color(0xFF5D1900),
    primaryContainer = Color(0xFF8A3014),
    onPrimaryContainer = Color(0xFFFFDBCF),
    secondary = Color(0xFFE7BDB1),
    secondaryContainer = Color(0xFF5D4038),
    background = Color(0xFF181210),
    onBackground = Color(0xFFEDE0DC),
    surface = Color(0xFF181210),
    onSurface = Color(0xFFEDE0DC),
    surfaceVariant = Color(0xFF3A302C),
    onSurfaceVariant = Color(0xFFD8C2BB),
    surfaceContainer = Color(0xFF231B18),
    surfaceContainerHigh = Color(0xFF2E2522),
    outline = Color(0xFFA08D87),
    outlineVariant = Color(0xFF53433E),
    error = Color(0xFFFFB4AB),
)

private val Black = Dark.copy(background = Color.Black, surface = Color.Black, surfaceContainer = Color(0xFF0E0B0A), surfaceContainerHigh = Color(0xFF171210))

private val AppTypography = Typography().let {
    it.copy(
        headlineSmall = it.headlineSmall.copy(fontWeight = FontWeight.SemiBold),
        titleLarge = it.titleLarge.copy(fontWeight = FontWeight.SemiBold),
        titleMedium = it.titleMedium.copy(fontWeight = FontWeight.SemiBold),
        labelLarge = it.labelLarge.copy(fontWeight = FontWeight.SemiBold),
    )
}

val CoverShape = RoundedCornerShape(10.dp)
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
        shapes = Shapes(small = RoundedCornerShape(8.dp), medium = RoundedCornerShape(14.dp), large = RoundedCornerShape(22.dp)),
        content = content,
    )
}
