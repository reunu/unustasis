package de.freal.unustasis.wear

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters

/** Pushes the current widget state to the paired watch, off the broadcast receiver's thread. */
class WearStateSyncWorker(
    context: Context,
    params: WorkerParameters,
) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        WearBridge.pushState(applicationContext)
        return Result.success()
    }
}
