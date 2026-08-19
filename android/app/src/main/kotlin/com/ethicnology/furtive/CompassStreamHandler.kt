package com.ethicnology.furtive

import android.app.Activity
import android.content.Context
import android.hardware.GeomagneticField
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.util.Log
import android.view.Surface
import io.flutter.plugin.common.EventChannel
import kotlin.math.PI
import kotlin.math.abs

/**
 * Streams the device's heading — the direction the phone is *pointing* — to
 * Dart.
 *
 * Written here rather than pulled from a package on purpose. The maintained
 * option (`sensors_plus`) exposes only raw accelerometer/gyroscope/magnetometer
 * and would force us to re-implement sensor fusion in Dart, worse than what the
 * platform already does; the option that does return an azimuth
 * (`flutter_compass`) has been unmaintained for well over a year and asks for
 * INTERNET and location permissions to read a compass. This needs no
 * permission, no Google Play Services and no new dependency — it is ~100 lines
 * against the same SensorManager either package wraps.
 *
 * Three things this gets right that a naive magnetometer reading does not:
 *
 *  * **It uses the fused rotation vector.** TYPE_ROTATION_VECTOR combines the
 *    gyroscope, accelerometer and magnetometer. The gyroscope alone measures
 *    angular velocity and drifts with no absolute reference; the magnetometer
 *    alone is noisy and tilt-sensitive. Fusion is what makes the arrow steady.
 *  * **It remaps for screen rotation.** Without [remapCoordinateSystem] the
 *    heading is 90° out as soon as the device is held in landscape.
 *  * **It corrects to true north.** The sensor reports magnetic north; a map is
 *    drawn in true north. The difference is around 13° in Montréal and over
 *    20° in parts of Canada — far more than the error anyone would accept from
 *    a compass. [GeomagneticField] converts, given a position, which Dart
 *    supplies through [updatePosition].
 */
class CompassStreamHandler(private val activity: Activity) :
    EventChannel.StreamHandler, SensorEventListener {

    // The Activity, not applicationContext, and the distinction is not
    // cosmetic: querying the display needs a *visual* context, and
    // Context.getDisplay() throws UnsupportedOperationException on an
    // application context from Android 11 onwards. Because that call happens
    // inside a sensor callback, getting it wrong does not degrade the compass
    // — it takes the whole app down on the first sensor sample.
    private val sensorManager =
        activity.applicationContext.getSystemService(Context.SENSOR_SERVICE)
                as SensorManager?
    private val rotationSensor: Sensor? =
        sensorManager?.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)

    private var sink: EventChannel.EventSink? = null

    private val rotationMatrix = FloatArray(9)
    private val remapped = FloatArray(9)
    private val orientation = FloatArray(3)

    /** Magnetic-to-true-north correction, degrees. 0 until Dart sends a fix. */
    @Volatile
    private var declinationDegrees: Float = 0f

    /**
     * Last value handed to Dart. Used to drop sub-degree jitter: the sensor
     * emits far faster than a map needs redrawing, and forwarding every sample
     * would rebuild the marker layer for changes nobody can see.
     */
    private var lastEmitted: Double? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        if (sensorManager == null || rotationSensor == null) {
            // No rotation vector on this device (rare, but real on low-end
            // hardware without a magnetometer). Report absence rather than
            // failing: Dart falls back to course over ground.
            events?.success(null)
            return
        }
        sensorManager.registerListener(
            this,
            rotationSensor,
            // ~60 ms. A map redraws far slower than SENSOR_DELAY_GAME/FASTEST,
            // which would only burn battery for samples that get discarded.
            SensorManager.SENSOR_DELAY_UI,
        )
    }

    override fun onCancel(arguments: Any?) {
        // Unregistering matters: a rotation-vector listener left running keeps
        // the sensor hub awake for a recording that can last hours.
        sensorManager?.unregisterListener(this)
        sink = null
        lastEmitted = null
    }

    /** Position used to derive the magnetic declination. */
    fun updatePosition(latitude: Double, longitude: Double, altitudeMeters: Double) {
        declinationDegrees = GeomagneticField(
            latitude.toFloat(),
            longitude.toFloat(),
            altitudeMeters.toFloat(),
            System.currentTimeMillis(),
        ).declination
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    override fun onSensorChanged(event: SensorEvent?) {
        val values = event?.values ?: return
        val target = sink ?: return

        SensorManager.getRotationMatrixFromVector(rotationMatrix, values)

        // The sensor frame is defined against the device's natural
        // orientation. Holding the phone in landscape rotates the screen but
        // not the sensor, so the axes have to be remapped by the current
        // display rotation or the heading is a right angle out.
        val (axisX, axisY) = when (displayRotation()) {
            Surface.ROTATION_90 -> SensorManager.AXIS_Y to SensorManager.AXIS_MINUS_X
            Surface.ROTATION_180 -> SensorManager.AXIS_MINUS_X to SensorManager.AXIS_MINUS_Y
            Surface.ROTATION_270 -> SensorManager.AXIS_MINUS_Y to SensorManager.AXIS_X
            else -> SensorManager.AXIS_X to SensorManager.AXIS_Y
        }
        SensorManager.remapCoordinateSystem(rotationMatrix, axisX, axisY, remapped)
        SensorManager.getOrientation(remapped, orientation)

        val magnetic = orientation[0] * 180.0 / PI
        val trueHeading = normalise(magnetic + declinationDegrees)

        val previous = lastEmitted
        if (previous != null && angularDistance(previous, trueHeading) < MIN_CHANGE_DEGREES) {
            return
        }
        lastEmitted = trueHeading
        target.success(trueHeading)
    }

    /// Wrapped defensively on top of using the right context. This runs in a
    /// sensor callback on the main looper, where an escaping exception is a
    /// fatal crash rather than a bad reading — a wrong rotation is worth a
    /// heading that is 90° out, never a dead app.
    @Suppress("DEPRECATION")
    private fun displayRotation(): Int = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activity.display?.rotation ?: Surface.ROTATION_0
        } else {
            // Activity.getWindowManager().defaultDisplay is deprecated from
            // API 30, which is exactly why the branch above exists; below it
            // there is no alternative.
            activity.windowManager?.defaultDisplay?.rotation ?: Surface.ROTATION_0
        }
    } catch (e: RuntimeException) {
        Log.w(TAG, "display rotation unavailable; assuming portrait", e)
        Surface.ROTATION_0
    }

    private fun normalise(degrees: Double): Double {
        val wrapped = degrees % 360.0
        return if (wrapped < 0) wrapped + 360.0 else wrapped
    }

    /** Shortest angle between two bearings, so 359° and 1° are 2° apart. */
    private fun angularDistance(a: Double, b: Double): Double {
        val diff = abs(a - b) % 360.0
        return if (diff > 180.0) 360.0 - diff else diff
    }

    private companion object {
        const val TAG = "FurtiveCompass"

        /**
         * Smallest change worth waking the UI for. One degree is roughly the
         * sensor's own noise floor and well under what is visible on a marker
         * a few dozen pixels across.
         */
        const val MIN_CHANGE_DEGREES = 1.0
    }
}
