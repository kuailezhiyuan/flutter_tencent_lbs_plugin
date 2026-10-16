package com.flutter_tencent_lbs_plugin

import android.content.Context
import android.os.Looper
import com.flutter_tencent_lbs_plugin.pigeon.AndroidNotificationOptions
import com.flutter_tencent_lbs_plugin.pigeon.ContinuousLocationRequest
import com.flutter_tencent_lbs_plugin.pigeon.FlutterError
import com.flutter_tencent_lbs_plugin.pigeon.InitOptions
import com.flutter_tencent_lbs_plugin.pigeon.LocationData
import com.flutter_tencent_lbs_plugin.pigeon.LocationRequestUpdate
import com.flutter_tencent_lbs_plugin.pigeon.TencentLBSFlutterApi
import com.flutter_tencent_lbs_plugin.pigeon.TencentLBSHostApiImpl
import com.tencent.map.geolocation.TencentLocation
import com.tencent.map.geolocation.TencentLocationListener
import com.tencent.map.geolocation.TencentLocationManager
import com.tencent.map.geolocation.TencentLocationRequest
import java.time.Duration
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertNotSame
import kotlin.test.assertTrue
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.Mockito
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
@LooperMode(LooperMode.Mode.PAUSED)
class RuntimeLocationRequestTest {
    private lateinit var host: TencentLBSHostApiImpl
    private lateinit var manager: TencentLocationManager
    private lateinit var flutterApi: TencentLBSFlutterApi
    private lateinit var activeRequest: TencentLocationRequest
    private val continuousListeners = mutableListOf<TencentLocationListener>()
    private val singleListeners = mutableListOf<TencentLocationListener>()
    private var nextRegistrationError = 0
    private var foregroundEnabled = false
    private var engineStops = 0

    @After
    fun tearDown() {
        host.dispose()
    }

    @Before
    fun setUp() {
        val context: Context = RuntimeEnvironment.getApplication()
        manager = Mockito.mock(TencentLocationManager::class.java)
        flutterApi = Mockito.mock(TencentLBSFlutterApi::class.java)
        host = TencentLBSHostApiImpl(context, flutterApi) { manager }
        host.configure(InitOptions(apiKey = "test"))

        // SDK 7.6.1.9 appends registrations even for the same listener.
        // Model that contract so a mock cannot conceal duplicate callbacks or
        // a location engine left running after stop/dispose.
        Mockito.`when`(manager.requestLocationUpdates(
            Mockito.any(TencentLocationRequest::class.java),
            Mockito.any(TencentLocationListener::class.java), Mockito.eq(Looper.getMainLooper()),
        )).thenAnswer { call ->
            if (nextRegistrationError != 0) nextRegistrationError else {
                activeRequest = call.getArgument(0)
                continuousListeners.add(call.getArgument(1))
                0
            }
        }
        Mockito.`when`(manager.requestSingleFreshLocation(
            Mockito.any(TencentLocationRequest::class.java),
            Mockito.any(TencentLocationListener::class.java), Mockito.eq(Looper.getMainLooper()),
        )).thenAnswer { call ->
            singleListeners.add(call.getArgument(1))
            0
        }
        Mockito.doAnswer { call ->
            continuousListeners.remove(call.getArgument<TencentLocationListener>(0))
            null
        }.`when`(manager).removeLocationListener(Mockito.any(TencentLocationListener::class.java))
        Mockito.doAnswer { call ->
            val listener = call.getArgument<TencentLocationListener>(0)
            continuousListeners.remove(listener)
            singleListeners.remove(listener)
            if (continuousListeners.isEmpty() && singleListeners.isEmpty()) engineStops += 1
            null
        }.`when`(manager).removeUpdates(Mockito.any(TencentLocationListener::class.java))
        Mockito.doAnswer {
            foregroundEnabled = true
            null
        }.`when`(manager).enableForegroundLocation(Mockito.anyInt(), Mockito.any())
        Mockito.doAnswer {
            foregroundEnabled = false
            null
        }.`when`(manager).disableForegroundLocation(true)
    }

    private fun start(background: Boolean = false) {
        host.startLocationUpdates(
            ContinuousLocationRequest(intervalMs = 1000, backgroundLocation = background, allowCache = false),
            if (background) AndroidNotificationOptions(
                id = 1, channelId = "location", channelName = "Location", notificationTitle = "Location",
            ) else null,
        )
    }

    private fun deliverContinuousLocation() {
        val location = Mockito.mock(TencentLocation::class.java)
        continuousListeners.toList().forEach { it.onLocationChanged(location, TencentLocation.ERROR_OK, "") }
    }

    @Test
    fun modeSwitchesDeliverOnceAndStopReleasesTheEngine() {
        start(background = true)
        val original = activeRequest
        host.updateLocationRequest(LocationRequestUpdate(intervalMs = 30000, locMode = 11, allowGps = false))
        assertEquals(11, activeRequest.locMode)
        assertFalse(activeRequest.isAllowGPS)
        host.updateLocationRequest(LocationRequestUpdate(intervalMs = 1000, locMode = 10, allowGps = true))
        assertEquals(10, activeRequest.locMode)
        assertTrue(activeRequest.isAllowGPS)
        assertFalse(activeRequest.isAllowCache)
        assertEquals(10, original.locMode)
        assertTrue(foregroundEnabled)
        assertEquals(0, engineStops)
        deliverContinuousLocation()
        Mockito.verify(flutterApi).onLocation(Mockito.any(LocationData::class.java) ?: LocationData(), anyCallback())

        host.stopLocationUpdates()
        assertTrue(continuousListeners.isEmpty())
        assertEquals(1, engineStops)
        assertFalse(foregroundEnabled)
        Mockito.clearInvocations(flutterApi)
        deliverContinuousLocation()
        Mockito.verifyNoInteractions(flutterApi)
    }

    @Test
    fun intervalOnlyUpdatesKeepOneRegistrationAndTheForegroundService() {
        start(background = true)
        host.updateLocationRequest(LocationRequestUpdate(intervalMs = 15000))
        Mockito.verify(manager).changeCallbackInterval(15000)
        assertEquals(15000L, activeRequest.interval)
        assertEquals(1, continuousListeners.size)
        assertTrue(foregroundEnabled)
        host.stopLocationUpdates()
        assertTrue(continuousListeners.isEmpty())
        assertEquals(1, engineStops)
    }

    @Test
    fun failedUpdatePreservesTheActiveRequestAndCanBeRetried() {
        start(background = true)
        nextRegistrationError = 1
        val failure = assertFailsWith<FlutterError> {
            host.updateLocationRequest(LocationRequestUpdate(intervalMs = 30000, locMode = 11, allowGps = false))
        }
        assertEquals("location-request-failed", failure.code)
        assertEquals(listOf<TencentLocationListener>(host), continuousListeners)
        assertTrue(foregroundEnabled)
        deliverContinuousLocation()
        Mockito.verify(flutterApi).onLocation(Mockito.any(LocationData::class.java) ?: LocationData(), anyCallback())

        nextRegistrationError = 0
        host.updateLocationRequest(LocationRequestUpdate(requestLevel = 0))
        assertEquals(1000L, activeRequest.interval)
        assertEquals(10, activeRequest.locMode)
        assertTrue(activeRequest.isAllowGPS)
        assertEquals(listOf<TencentLocationListener>(host), continuousListeners)
        host.stopLocationUpdates()
        assertEquals(1, engineStops)
    }

    @Test
    fun invalidUpdatesLeaveTheActiveRequestUntouched() {
        start()
        assertFailsWith<FlutterError> {
            host.updateLocationRequest(LocationRequestUpdate(intervalMs = 500, locMode = 11))
        }
        assertFailsWith<FlutterError> {
            host.updateLocationRequest(LocationRequestUpdate(locMode = 4294967306))
        }
        assertEquals(1000L, activeRequest.interval)
        assertEquals(10, activeRequest.locMode)
        assertEquals(listOf<TencentLocationListener>(host), continuousListeners)
        assertEquals(0, engineStops)
    }

    @Test
    fun singleRepliesAndContinuousEventsStayIndependent() {
        start()
        val replies = mutableListOf<LocationData?>()
        host.requestLocationOnce { replies.add(it.getOrThrow()) }
        val listener = singleListeners.single()
        assertNotSame(host, listener)
        deliverContinuousLocation()
        host.onLocationChanged(null, 7, "continuous failure")
        assertTrue(replies.isEmpty())
        Mockito.verify(flutterApi).onLocation(Mockito.any(LocationData::class.java) ?: LocationData(), anyCallback())
        Mockito.verify(flutterApi).onError(Mockito.eq(7L), Mockito.eq("continuous failure") ?: "", anyCallback())
        Mockito.clearInvocations(flutterApi)

        listener.onLocationChanged(Mockito.mock(TencentLocation::class.java), TencentLocation.ERROR_OK, "")
        listener.onLocationChanged(null, 8, "late duplicate")
        assertEquals(0L, replies.single()?.code)
        host.requestLocationOnce { replies.add(it.getOrThrow()) }
        singleListeners.single().onLocationChanged(null, 7, "single failure")
        assertNull(replies.last())
        Mockito.verifyNoInteractions(flutterApi)
    }

    @Test
    fun singleTimeoutCleansUpBeforeReplyAndLateResultsCannotFinishTheRetry() {
        val replies = mutableListOf<LocationData?>()
        host.requestLocationOnce {
            assertTrue(singleListeners.isEmpty())
            replies.add(it.getOrThrow())
        }
        val expiredListener = singleListeners.single()
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(30))
        assertEquals(listOf<LocationData?>(null), replies)
        assertEquals(1, engineStops)
        // A timed-out request must no longer prevent reinitialization.
        host.configure(InitOptions(apiKey = "retry"))
        host.requestLocationOnce { replies.add(it.getOrThrow()) }
        expiredListener.onLocationChanged(Mockito.mock(TencentLocation::class.java), TencentLocation.ERROR_OK, "late")
        assertEquals(1, replies.size)
        singleListeners.single().onLocationChanged(Mockito.mock(TencentLocation::class.java), TencentLocation.ERROR_OK, "")
        assertEquals(0L, replies.last()?.code)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(30))
        assertEquals(2, replies.size)
    }

    @Test
    fun singleTimeoutLeavesContinuousLocationAndItsForegroundServiceRunning() {
        start(background = true)
        host.requestLocationOnce { assertNull(it.getOrThrow()) }
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(30))
        assertTrue(singleListeners.isEmpty())
        assertEquals(listOf<TencentLocationListener>(host), continuousListeners)
        assertTrue(foregroundEnabled)
        assertEquals(0, engineStops)
        deliverContinuousLocation()
        Mockito.verify(flutterApi).onLocation(Mockito.any(LocationData::class.java) ?: LocationData(), anyCallback())
    }

    @Test
    fun singleRegistrationFailureAndExceptionAllowRetryWithoutLeakingTimeouts() {
        Mockito.`when`(manager.requestSingleFreshLocation(
            Mockito.any(TencentLocationRequest::class.java),
            Mockito.any(TencentLocationListener::class.java), Mockito.eq(Looper.getMainLooper()),
        )).thenReturn(1).thenThrow(SecurityException("permission revoked")).thenReturn(0)
        val replies = mutableListOf<Result<LocationData?>>()
        host.requestLocationOnce { replies.add(it) }
        host.requestLocationOnce { replies.add(it) }
        assertNull(replies.first().getOrThrow())
        assertTrue(replies.last().exceptionOrNull() is SecurityException)
        host.requestLocationOnce { replies.add(it) }
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(30))
        assertEquals(3, replies.size)
        assertNull(replies.last().getOrThrow())
        host.configure(InitOptions(apiKey = "retry"))
        Mockito.verifyNoInteractions(flutterApi)
    }

    @Test
    fun invalidBackgroundNotificationDoesNotLeaveTheEngineOrServiceRunning() {
        val notifications = listOf<AndroidNotificationOptions?>(null) + listOf(0L, -1L, Int.MAX_VALUE.toLong() + 1, 4294967297L).map {
            AndroidNotificationOptions(id = it, channelId = "location", channelName = "Location", notificationTitle = "Location")
        }
        for (notification in notifications) {
            val failure = assertFailsWith<FlutterError> {
                host.startLocationUpdates(ContinuousLocationRequest(intervalMs = 1000, backgroundLocation = true), notification)
            }
            assertEquals("invalid-argument", failure.code)
        }
        assertTrue(continuousListeners.isEmpty())
        assertFalse(foregroundEnabled)
        start()
        host.stopLocationUpdates()
        assertEquals(1, engineStops)
    }

    @Test
    fun stoppingContinuousLocationLeavesItsSingleRequestActiveButDropsQueuedEvents() {
        start()
        val replies = mutableListOf<LocationData?>()
        host.requestLocationOnce { replies.add(it.getOrThrow()) }
        val listener = singleListeners.single()
        host.stopLocationUpdates()
        assertEquals(0, engineStops)
        assertTrue(replies.isEmpty())
        host.onLocationChanged(null, 7, "queued continuous error")
        host.onStatusUpdate("gps", 1, "queued status")
        Mockito.verifyNoInteractions(flutterApi)
        listener.onLocationChanged(Mockito.mock(TencentLocation::class.java), TencentLocation.ERROR_OK, "")
        assertEquals(0L, replies.single()?.code)
        assertEquals(1, engineStops)
    }

    @Test
    fun disposeReleasesRequestsAndTimeoutsOnceAndIgnoresLateCallbacks() {
        start(background = true)
        host.updateLocationRequest(LocationRequestUpdate(allowCache = true))
        val replies = mutableListOf<LocationData?>()
        host.requestLocationOnce { replies.add(it.getOrThrow()) }
        val listener = singleListeners.single()
        host.dispose()
        host.dispose()
        assertTrue(continuousListeners.isEmpty())
        assertTrue(singleListeners.isEmpty())
        assertFalse(foregroundEnabled)
        assertEquals(1, engineStops)
        assertEquals(listOf<LocationData?>(null), replies)
        listener.onLocationChanged(null, 7, "late single error")
        host.onLocationChanged(null, 7, "late continuous error")
        host.onStatusUpdate("gps", 1, "late status")
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(30))
        assertEquals(listOf<LocationData?>(null), replies)
        Mockito.verifyNoInteractions(flutterApi)
        assertEquals("disposed", assertFailsWith<FlutterError> { host.configure(InitOptions(apiKey = "test")) }.code)
    }

    // Java Mockito matchers return null; Pigeon's Kotlin methods require non-null arguments.
    private fun anyCallback(): (Result<Unit>) -> Unit = Mockito.any<(Result<Unit>) -> Unit>() ?: {}
}
