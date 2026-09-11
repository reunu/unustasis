package de.freal.unustasis.tasker

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.Gravity
import android.widget.ArrayAdapter
import android.widget.LinearLayout
import android.widget.ListView
import android.widget.TextView
import de.freal.unustasis.BatteryOptimization
import de.freal.unustasis.R

/**
 * The screen Tasker opens when the action is added or edited: pick one of the
 * scooter actions, and that choice goes back to Tasker in the config bundle.
 *
 * Picking commits immediately — there's exactly one setting, so a save button
 * would only be in the way. Backing out leaves the action as it was.
 */
class TaskerActionEditActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setTitle(R.string.tasker_config_title)

        val actions = TaskerAction.entries
        val list = ListView(this).apply {
            adapter = ArrayAdapter(
                this@TaskerActionEditActivity,
                android.R.layout.simple_list_item_single_choice,
                actions.map { getString(it.labelRes) },
            )
            choiceMode = ListView.CHOICE_MODE_SINGLE
            setOnItemClickListener { _, _, position, _ -> save(actions[position]) }
            // Balances the space the title leaves above the first row.
            setPadding(0, 0, 0, dp(8))
            clipToPadding = false
        }

        // Preselect whatever the action is currently set to, if we're editing.
        previousAction()?.let { list.setItemChecked(actions.indexOf(it), true) }

        setContentView(
            LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                warningView()?.let { addView(it) }
                addView(
                    list,
                    LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.MATCH_PARENT,
                        0,
                        1f,
                    ),
                )
            }
        )
    }

    /**
     * Warns when nothing will be able to start the background service: with
     * background scanning off it stops itself, and Android won't let another
     * app's broadcast start it again without the Doze exemption.
     */
    private fun warningView(): TextView? {
        if (backgroundScanEnabled() || BatteryOptimization.isIgnored(this)) return null
        return TextView(this).apply {
            text = getString(R.string.tasker_warning_unreachable)
            gravity = Gravity.START
            setPadding(dp(16), dp(16), dp(16), dp(8))
        }
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    /** Reads the app's own setting out of the file shared_preferences writes. */
    private fun backgroundScanEnabled(): Boolean =
        getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getBoolean("flutter.backgroundScan", false)

    private fun previousAction(): TaskerAction? = TaskerAction.fromKey(
        intent.getBundleExtra(TaskerPluginProtocol.EXTRA_BUNDLE)
            ?.getString(TaskerPluginProtocol.BUNDLE_KEY_ACTION)
    )

    /**
     * The timeout and variable declarations go in both the result intent and
     * the stored config bundle, since hosts differ on which they read.
     */
    private fun save(action: TaskerAction) {
        val settings = Bundle().apply {
            putString(TaskerPluginProtocol.BUNDLE_KEY_ACTION, action.key)
            putInt(
                TaskerPluginProtocol.EXTRA_REQUESTED_TIMEOUT,
                TaskerActionRunner.DEFAULT_TIMEOUT_MS.toInt(),
            )
            putStringArray(TaskerPluginProtocol.EXTRA_RELEVANT_VARIABLES, relevantVariables())
        }

        val result = Intent().apply {
            putExtra(TaskerPluginProtocol.EXTRA_BUNDLE, settings)
            // What Tasker shows on the action in the task list.
            putExtra(TaskerPluginProtocol.EXTRA_STRING_BLURB, getString(action.labelRes))
            putExtra(
                TaskerPluginProtocol.EXTRA_REQUESTED_TIMEOUT,
                TaskerActionRunner.DEFAULT_TIMEOUT_MS.toInt(),
            )
            putExtra(TaskerPluginProtocol.EXTRA_RELEVANT_VARIABLES, relevantVariables())
        }

        setResult(RESULT_OK, result)
        finish()
    }

    /** Name, label and description, newline-separated, as the protocol wants. */
    private fun relevantVariables(): Array<String> = arrayOf(
        "${TaskerPluginProtocol.VARIABLE_RESULT}\n" +
            getString(R.string.tasker_variable_result_label) + "\n" +
            getString(R.string.tasker_variable_result_description)
    )
}
