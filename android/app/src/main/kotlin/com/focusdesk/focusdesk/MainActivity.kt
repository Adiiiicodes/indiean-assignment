package com.focusdesk.focusdesk

import android.content.res.Configuration
import android.os.Bundle
import androidx.core.view.WindowInsetsControllerCompat
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    private var flutterOwnsSystemBars = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // The embedding resets legacy appearance during its startup handoff.
        // Apply once after that handoff; Flutter owns all subsequent styling.
        window.decorView.post { applyLaunchSystemBarsAppearance() }
    }

    override fun onFlutterUiDisplayed() {
        flutterOwnsSystemBars = true
        super.onFlutterUiDisplayed()
    }

    private fun applyLaunchSystemBarsAppearance() {
        if (isFinishing || isDestroyed || flutterOwnsSystemBars) return
        val dark = (resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
            Configuration.UI_MODE_NIGHT_YES
        val controller = WindowInsetsControllerCompat(window, window.decorView)
        controller.isAppearanceLightStatusBars = !dark
        controller.isAppearanceLightNavigationBars = !dark
    }
}
