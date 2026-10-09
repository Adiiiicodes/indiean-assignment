package com.focusdesk.focusdesk

import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.WindowInsetsController
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // The embedding resets legacy appearance during its startup handoff.
        // Apply once after that handoff; Flutter owns all subsequent styling.
        window.decorView.post { applyLaunchSystemBarsAppearance() }
    }

    @Suppress("DEPRECATION")
    private fun applyLaunchSystemBarsAppearance() {
        if (isFinishing || isDestroyed) return
        val dark = (resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
            Configuration.UI_MODE_NIGHT_YES
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val mask = WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS or
                WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS
            window.insetsController?.setSystemBarsAppearance(if (dark) 0 else mask, mask)
        } else {
            val navigationMask = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
            } else {
                0
            }
            val mask = View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR or navigationMask
            val existing = window.decorView.systemUiVisibility
            window.decorView.systemUiVisibility = if (dark) {
                existing and mask.inv()
            } else {
                existing or mask
            }
        }
    }
}
