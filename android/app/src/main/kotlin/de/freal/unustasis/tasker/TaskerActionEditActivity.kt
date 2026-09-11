package de.freal.unustasis.tasker

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.widget.ArrayAdapter
import android.widget.ListView
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
        }

        // Preselect whatever the action is currently set to, if we're editing.
        previousAction()?.let { list.setItemChecked(actions.indexOf(it), true) }

        setContentView(list)
    }

    private fun previousAction(): TaskerAction? = TaskerAction.fromKey(
        intent.getBundleExtra(TaskerPluginProtocol.EXTRA_BUNDLE)
            ?.getString(TaskerPluginProtocol.BUNDLE_KEY_ACTION)
    )

    private fun save(action: TaskerAction) {
        val settings = Bundle().apply {
            putString(TaskerPluginProtocol.BUNDLE_KEY_ACTION, action.key)
            // Hosts differ on where they read the timeout request from: some
            // take it off the result intent, others off the stored config
            // bundle. It costs nothing to answer both, and a host that only
            // reads the bundle may well gate the completion intent on it.
            putInt(
                TaskerPluginProtocol.EXTRA_REQUESTED_TIMEOUT,
                TaskerActionRunner.DEFAULT_TIMEOUT_MS.toInt(),
            )
            // Declared in both places for the same reason as the timeout: the
            // host may only honour variables it knew about from the stored
            // config, and an undeclared one is dropped without a word.
            putStringArray(TaskerPluginProtocol.EXTRA_RELEVANT_VARIABLES, relevantVariables())
        }

        val result = Intent().apply {
            putExtra(TaskerPluginProtocol.EXTRA_BUNDLE, settings)
            // What Tasker shows on the action in the task list.
            putExtra(TaskerPluginProtocol.EXTRA_STRING_BLURB, getString(action.labelRes))
            // Ask for long enough to cover a cold start plus a BLE connect,
            // since the action doesn't return until the scooter has obeyed.
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
