package com.flutter_tencent_lbs_plugin

import android.content.Context
import android.os.Looper
import com.flutter_tencent_lbs_plugin.pigeon.AndroidNotificationOptions
import com.flutter_tencent_lbs_plugin.pigeon.ContinuousLocationRequest
import com.flutter_tencent_lbs_plugin.pigeon.FlutterError
import com.flutter_tencent_lbs_plugin.pigeon.InitOptions
import com.flutter_tencent_lbs_plugin.pigeon.LocationRequestUpdate
import com.flutter_tencent_lbs_plugin.pigeon.LocationData
import com.flutter_tencent_lbs_plugin.pigeon.TencentLBSFlutterApi
import com.flutter_tencent_lbs_plugin.pigeon.TencentLBSHostApiImpl
import com.tencent.map.geolocation.TencentLocationListener
import com.tencent.map.geolocation.TencentLocationManager
import com.tencent.map.geolocation.TencentLocation
import com.tencent.map.geolocation.TencentLocationRequest
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertNotSame
import kotlin.test.assertTrue
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.ArgumentCaptor
import org.mockito.Mockito
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
class RuntimeLocationRequestTest {
    private lateinit var host: TencentLBSHostApiImpl
    private lateinit var manager: TencentLocationManager
    private lateinit var initialRequest: TencentLocationRequest
    private lateinit var flutterApi: TencentLBSFlutterApi

    @Before
    fun setUp() {
        val context: Context = RuntimeEnvironment.getApplication()
        manager = Mockito.mock(TencentLocationManager::class.java)
        flutterApi = Mockito.mock(TencentLBSFlutterApi::class.java)
        host = TencentLBSHostApiImpl(context, flutterApi)
        initialRequest = TencentLocationRequest.create().apply {
            interval = 1000
            locMode = TencentLocationRequest.HIGH_ACCURACY_MODE
            isAllowGPS = true
            isAllowCache = false
            isGpsFirst = false
        }
        setState("locationManager", manager)
        setState("tencentLocationRequest", initialRequest)
        setState("isListeningLocationUpdates", true)
    }

    @Test
    fun switchingModesKeepsListenerAndForegroundService() {
        host.updateLocationRequest(LocationRequestUpdate(
            intervalMs = 30000,
            locMode = TencentLocationRequest.ONLY_NETWORK_MODE.toLong(),
            allowGps = false,
        ))
        host.updateLocationRequest(LocationRequestUpdate(
            intervalMs = 1000,
            locMode = TencentLocationRequest.HIGH_ACCURACY_MODE.toLong(),
            allowGps = true,
        ))

        val captor = ArgumentCaptor.forClass(TencentLocationRequest::class.java)
        Mockito.verify(manager, Mockito.times(2)).requestLocationUpdates(
            captor.capture(), Mockito.same(host), Mockito.eq(Looper.getMainLooper()),
        )
        val low = captor.allValues[0]
        val high = captor.allValues[1]
        assertEquals(30000L, low.interval)
        assertEquals(TencentLocationRequest.ONLY_NETWORK_MODE, low.locMode)
        assertFalse(low.isAllowGPS)
        assertEquals(1000L, high.interval)
        assertEquals(TencentLocationRequest.HIGH_ACCURACY_MODE, high.locMode)
        assertTrue(high.isAllowGPS)
        assertFalse(high.isAllowCache)
        assertFalse(high.isGpsFirst)
        assertEquals(TencentLocationRequest.HIGH_ACCURACY_MODE, initialRequest.locMode)
        Mockito.verifyNoMoreInteractions(manager)
    }

    @Test
    fun changingOnlyIntervalUsesNativeIntervalUpdate() {
        host.updateLocationRequest(LocationRequestUpdate(intervalMs = 15000))
        Mockito.verify(manager).changeCallbackInterval(15000)
        assertEquals(15000L, initialRequest.interval)
        Mockito.verifyNoMoreInteractions(manager)
    }

    @Test
    fun failedUpdatePreservesPreviousRequestAndSession() {
        Mockito.`when`(manager.requestLocationUpdates(
            Mockito.any(TencentLocationRequest::class.java), Mockito.same(host),
            Mockito.eq(Looper.getMainLooper()),
        )).thenReturn(1, 0)

        val failure = assertFailsWith<FlutterError> {
            host.updateLocationRequest(LocationRequestUpdate(
                intervalMs = 30000,
                locMode = TencentLocationRequest.ONLY_NETWORK_MODE.toLong(),
                allowGps = false,
            ))
        }
        assertEquals("location-request-failed", failure.code)
        host.updateLocationRequest(LocationRequestUpdate(requestLevel = 0))
        val captor = ArgumentCaptor.forClass(TencentLocationRequest::class.java)
        Mockito.verify(manager, Mockito.times(2)).requestLocationUpdates(
            captor.capture(), Mockito.same(host), Mockito.eq(Looper.getMainLooper()),
        )
        val recovered = captor.allValues[1]
        assertEquals(1000L, recovered.interval)
        assertEquals(TencentLocationRequest.HIGH_ACCURACY_MODE, recovered.locMode)
        assertTrue(recovered.isAllowGPS)
        Mockito.verifyNoMoreInteractions(manager)
    }

    @Test
    fun invalidUpdatesLeaveActiveRequestUntouched() {
        assertFailsWith<FlutterError> {
            host.updateLocationRequest(LocationRequestUpdate(intervalMs = 500, locMode = 11))
        }
        assertFailsWith<FlutterError> {
            host.updateLocationRequest(LocationRequestUpdate(locMode = 4294967306))
        }
        assertEquals(1000L, initialRequest.interval)
        assertEquals(TencentLocationRequest.HIGH_ACCURACY_MODE, initialRequest.locMode)
        Mockito.verifyNoInteractions(manager)
    }

    @Test
    fun iosOnlyFieldsDoNotRestartAndroid() {
        host.updateLocationRequest(LocationRequestUpdate(iosDesiredAccuracy = 100.0, iosDistanceFilter = 50.0))
        host.updateLocationRequest(LocationRequestUpdate())
        Mockito.verifyNoInteractions(manager)
    }

    @Test
    fun updatingStoppedSessionReportsError() {
        setState("isListeningLocationUpdates", false)
        val failure = assertFailsWith<FlutterError> {
            host.updateLocationRequest(LocationRequestUpdate(locMode = 11))
        }
        assertEquals("not-started", failure.code)
        Mockito.verifyNoInteractions(manager)
    }

    @Test
    fun locationCallbacksAreDelivered() {
        Mockito.clearInvocations(flutterApi)
        val location = Mockito.mock(TencentLocation::class.java)
        repeat(3) { host.onLocationChanged(location, TencentLocation.ERROR_OK, "") }
        Mockito.verify(flutterApi, Mockito.times(3)).onLocation(Mockito.any(LocationData::class.java) ?: LocationData(), anyCallback())
    }

    @Test
    fun singleRequestUsesSeparateListenerAndKeepsContinuousEvents() {
        val replies = mutableListOf<LocationData?>()
        host.requestLocationOnce { replies.add(it.getOrThrow()) }
        val listener = ArgumentCaptor.forClass(TencentLocationListener::class.java)
        Mockito.verify(manager).requestSingleFreshLocation(
            Mockito.same(initialRequest), listener.capture(), Mockito.eq(Looper.getMainLooper()),
        )
        assertNotSame(host, listener.value)
        val location = Mockito.mock(TencentLocation::class.java)
        host.onLocationChanged(location, TencentLocation.ERROR_OK, "")
        host.onLocationChanged(null, 7, "continuous failure")
        assertTrue(replies.isEmpty())
        Mockito.verify(flutterApi).onLocation(Mockito.any(LocationData::class.java) ?: LocationData(), anyCallback())
        Mockito.verify(flutterApi).onError(Mockito.eq(7L), Mockito.eq("continuous failure") ?: "", anyCallback())

        listener.value.onLocationChanged(location, TencentLocation.ERROR_OK, "")
        assertEquals(1, replies.size)
        assertEquals(0L, replies.single()?.code)
        listener.value.onLocationChanged(null, 8, "late duplicate")
        assertEquals(1, replies.size)
        Mockito.verifyNoMoreInteractions(flutterApi)
    }

    @Test
    fun singleRequestErrorsOnlyCompleteTheirOwnReply() {
        val replies = mutableListOf<LocationData?>()
        host.requestLocationOnce { replies.add(it.getOrThrow()) }
        val listener = ArgumentCaptor.forClass(TencentLocationListener::class.java)
        Mockito.verify(manager).requestSingleFreshLocation(
            Mockito.same(initialRequest), listener.capture(), Mockito.eq(Looper.getMainLooper()),
        )
        listener.value.onLocationChanged(null, 7, "single failure")
        assertEquals(1, replies.size)
        assertNull(replies.single())
        Mockito.verifyNoInteractions(flutterApi)
    }

    @Test
    fun singleRequestRegistrationFailureAndExceptionReachTheirReply() {
        Mockito.`when`(manager.requestSingleFreshLocation(
            Mockito.any(TencentLocationRequest::class.java),
            Mockito.any(TencentLocationListener::class.java), Mockito.eq(Looper.getMainLooper()),
        )).thenReturn(1).thenThrow(SecurityException("permission revoked")).thenReturn(0)
        val replies = mutableListOf<Result<LocationData?>>()
        host.requestLocationOnce { replies.add(it) }
        assertTrue(replies.single().isSuccess)
        assertNull(replies.single().getOrNull())
        host.requestLocationOnce { replies.add(it) }
        assertTrue(replies.last().exceptionOrNull() is SecurityException)
        host.requestLocationOnce { replies.add(it) }
        // The third request is pending its own SDK callback, rather than blocked.
        assertEquals(2, replies.size)
        Mockito.verify(manager, Mockito.times(3)).requestSingleFreshLocation(
            Mockito.any(TencentLocationRequest::class.java),
            Mockito.any(TencentLocationListener::class.java), Mockito.eq(Looper.getMainLooper()),
        )
        Mockito.verifyNoInteractions(flutterApi)
    }

    @Test
    fun invalidBackgroundNotificationFailsBeforeStartingSdk() {
        setState("isListeningLocationUpdates", false)
        val notifications = listOf(null) + listOf(0L, -1L, Int.MAX_VALUE.toLong() + 1, 4294967297L).map {
            AndroidNotificationOptions(id = it, channelId = "location", channelName = "Location", notificationTitle = "Location")
        }
        for (notification in notifications) {
            val failure = assertFailsWith<FlutterError> {
                host.startLocationUpdates(
                    ContinuousLocationRequest(intervalMs = 1000, backgroundLocation = true), notification,
                )
            }
            assertEquals("invalid-argument", failure.code)
        }
        Mockito.verifyNoInteractions(manager)
        Mockito.verifyNoInteractions(flutterApi)
    }

    @Test
    fun configureRejectsActiveContinuousOrSingleRequests() {
        val continuousFailure = assertFailsWith<FlutterError> {
            host.configure(InitOptions(apiKey = "test"))
        }
        assertEquals("in-progress", continuousFailure.code)
        Mockito.verifyNoInteractions(manager)

        setState("isListeningLocationUpdates", false)
        host.requestLocationOnce {}
        Mockito.clearInvocations(manager)
        val singleFailure = assertFailsWith<FlutterError> {
            host.configure(InitOptions(apiKey = "test"))
        }
        assertEquals("in-progress", singleFailure.code)
        Mockito.verifyNoInteractions(manager)
    }

    @Test
    fun stoppingContinuousLocationLeavesSingleRequestActive() {
        val replies = mutableListOf<LocationData?>()
        host.requestLocationOnce { replies.add(it.getOrThrow()) }
        val listener = ArgumentCaptor.forClass(TencentLocationListener::class.java)
        Mockito.verify(manager).requestSingleFreshLocation(
            Mockito.same(initialRequest), listener.capture(), Mockito.eq(Looper.getMainLooper()),
        )
        host.stopLocationUpdates()
        Mockito.verify(manager).removeUpdates(host)
        Mockito.verify(manager, Mockito.never()).removeUpdates(listener.value)
        assertTrue(replies.isEmpty())
        val location = Mockito.mock(TencentLocation::class.java)
        listener.value.onLocationChanged(location, TencentLocation.ERROR_OK, "")
        assertEquals(0L, replies.single()?.code)
    }

    @Test
    fun disposeReleasesAllRequestsOnceAndIgnoresLateCallbacks() {
        val replies = mutableListOf<LocationData?>()
        host.requestLocationOnce { replies.add(it.getOrThrow()) }
        val listener = ArgumentCaptor.forClass(TencentLocationListener::class.java)
        Mockito.verify(manager).requestSingleFreshLocation(
            Mockito.same(initialRequest), listener.capture(), Mockito.eq(Looper.getMainLooper()),
        )
        host.dispose()
        host.dispose()
        Mockito.verify(manager).disableForegroundLocation(true)
        Mockito.verify(manager).removeUpdates(host)
        Mockito.verify(manager).removeUpdates(listener.value)
        assertEquals(1, replies.size)
        assertNull(replies.single())
        listener.value.onLocationChanged(null, 7, "late single error")
        host.onLocationChanged(null, 7, "late continuous error")
        host.onStatusUpdate("gps", 1, "late status")
        assertEquals(1, replies.size)
        Mockito.verifyNoInteractions(flutterApi)
        val failure = assertFailsWith<FlutterError> {
            host.configure(InitOptions(apiKey = "test"))
        }
        assertEquals("disposed", failure.code)
    }

    @Test
    fun engineDetachDisposesItsHostBeforeRemovingChannels() {
        val plugin = FlutterTencentLBSPlugin()
        FlutterTencentLBSPlugin::class.java.getDeclaredField("hostApi").apply {
            isAccessible = true
            set(plugin, host)
        }
        val messenger = Mockito.mock(BinaryMessenger::class.java)
        val binding = Mockito.mock(FlutterPlugin.FlutterPluginBinding::class.java)
        Mockito.`when`(binding.binaryMessenger).thenReturn(messenger)
        plugin.onDetachedFromEngine(binding)
        val order = Mockito.inOrder(manager, messenger)
        order.verify(manager).disableForegroundLocation(true)
        order.verify(manager).removeUpdates(host)
        order.verify(messenger).setMessageHandler(
            "dev.flutter.pigeon.flutter_tencent_lbs_plugin.TencentLBSHostApi.configure", null,
        )
        plugin.onDetachedFromEngine(binding)
        Mockito.verify(manager).removeUpdates(host)
    }

    // Java Mockito matchers return null; Pigeon's Kotlin methods require non-null arguments.
    private fun anyCallback(): (Result<Unit>) -> Unit = Mockito.any<(Result<Unit>) -> Unit>() ?: {}

    private fun setState(name: String, value: Any) {
        TencentLBSHostApiImpl::class.java.getDeclaredField(name).apply {
            isAccessible = true
            set(host, value)
        }
    }
}
