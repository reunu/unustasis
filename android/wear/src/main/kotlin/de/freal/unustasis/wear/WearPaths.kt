package de.freal.unustasis.wear

/**
 * Data Layer contract with the phone app.
 *
 * Kept byte-for-byte in sync with `de.freal.unustasis.wear.WearBridge` in the `:app` module.
 * Both apps ship under the same application ID, so the Data Layer routes between them only if
 * they are also signed with the same certificate.
 */
object WearPaths {
    const val STATE = "/unustasis/state"
    const val ACTION = "/unustasis/action"
    const val REQUEST_STATE = "/unustasis/request-state"

    const val CAPABILITY_PHONE = "unustasis_phone"

    const val ACTION_LOCK = "lock"
    const val ACTION_UNLOCK = "unlock"
    const val ACTION_OPEN_SEAT = "openseat"
}
