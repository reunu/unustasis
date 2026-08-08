package de.freal.unustasis.wear.ui

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.colorResource
import androidx.wear.compose.material.Colors
import androidx.wear.compose.material.MaterialTheme
import de.freal.unustasis.wear.R

/** The phone app's dark palette, which is the only one a Wear OS screen needs. */
@Composable
fun UnustasisWearTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colors = Colors(
            primary = colorResource(R.color.unu_primary),
            onPrimary = colorResource(R.color.unu_on_primary),
            secondary = colorResource(R.color.unu_on_surface_variant),
            onSecondary = colorResource(R.color.unu_surface),
            surface = colorResource(R.color.unu_surface),
            onSurface = colorResource(R.color.unu_on_surface),
            onSurfaceVariant = colorResource(R.color.unu_on_surface_variant),
            background = colorResource(R.color.unu_background),
            onBackground = colorResource(R.color.unu_on_surface),
            error = colorResource(R.color.unu_seat_open),
            onError = colorResource(R.color.unu_on_surface),
        ),
        content = content,
    )
}
