package com.flutter_tencent_lbs_plugin.pigeon

import android.content.Context
import android.os.Looper
import com.flutter_tencent_lbs_plugin.utils.NotificationUtils
import com.tencent.map.geolocation.TencentLocation
import com.tencent.map.geolocation.TencentLocationListener
import com.tencent.map.geolocation.TencentLocationManager
import com.tencent.map.geolocation.TencentLocationManagerOptions
import com.tencent.map.geolocation.TencentLocationRequest

/**
 * Pigeon Host API 实现，与腾讯定位 SDK 文档对齐。
 * 坐标系：Flutter 统一 0=GCJ02, 1=WGS84 → Android COORDINATE_TYPE_GCJ02=1, COORDINATE_TYPE_WGS84=0
 */
class TencentLBSHostApiImpl(
    private val context: Context,
    private val flutterApi: TencentLBSFlutterApi,
) : TencentLBSHostApi, TencentLocationListener {

    private var locationManager: TencentLocationManager? = null
    private var tencentLocationRequest: TencentLocationRequest? = null
    private var isListeningLocationUpdates = false
    private var disposed = false
    private val singleRequests = mutableMapOf<TencentLocationListener, (Result<LocationData?>) -> Unit>()

    override fun configure(options: InitOptions): Boolean {
        if (disposed) throw FlutterError("disposed", "定位插件已释放")
        if (isListeningLocationUpdates || singleRequests.isNotEmpty()) {
            throw FlutterError("in-progress", "定位进行中，不能重新初始化")
        }
        TencentLocationManagerOptions.setKey(options.apiKey)
        locationManager = TencentLocationManager.getInstance(context)

        // 坐标系：Flutter 0=GCJ02 -> Android 1, Flutter 1=WGS84 -> Android 0
        val coordType = when (options.coordinateType?.toInt()) {
            0 -> TencentLocationManager.COORDINATE_TYPE_GCJ02
            1 -> TencentLocationManager.COORDINATE_TYPE_WGS84
            else -> TencentLocationManager.COORDINATE_TYPE_WGS84
        }
        locationManager?.coordinateType = coordType
        locationManager?.setMockEnable(options.mockEnable ?: false)

        val request = TencentLocationRequest.create()
        request.requestLevel = (options.requestLevel ?: TencentLocationRequest.REQUEST_LEVEL_ADMIN_AREA).toInt()
        request.locMode = (options.locMode ?: TencentLocationRequest.HIGH_ACCURACY_MODE).toInt()
        request.isAllowGPS = options.allowGps ?: true
        request.isIndoorLocationMode = options.indoorLocationMode ?: false
        request.isGpsFirst = options.gpsFirst ?: false
        request.gpsFirstTimeOut = (options.gpsFirstTimeOutMs ?: 5000).toInt().coerceIn(0, 60000)
        tencentLocationRequest = request
        return true
    }

    override fun setUserAgreePrivacy(agree: Boolean) {
        TencentLocationManager.setUserAgreePrivacy(agree)
    }

    override fun requestLocationOnce(callback: (Result<LocationData?>) -> Unit) {
        val manager = locationManager
        val request = tencentLocationRequest
        if (manager == null || request == null) {
            callback(Result.success(null))
            return
        }
        lateinit var listener: TencentLocationListener
        fun finish(result: Result<LocationData?>) {
            val pending = singleRequests.remove(listener) ?: return
            manager.removeUpdates(listener)
            pending(result)
        }
        // A single request must never consume a continuous callback or error.
        listener = object : TencentLocationListener {
            override fun onLocationChanged(location: TencentLocation?, error: Int, reason: String?) {
                finish(Result.success(
                    if (error == TencentLocation.ERROR_OK && location != null) toLocationData(location) else null,
                ))
            }

            override fun onStatusUpdate(name: String?, status: Int, desc: String?) {}
        }
        singleRequests[listener] = callback
        try {
            val errorCode = manager.requestSingleFreshLocation(request, listener, Looper.getMainLooper())
            if (errorCode != TencentLocation.ERROR_OK) finish(Result.success(null))
        } catch (error: Throwable) {
            finish(Result.failure(error))
        }
    }

    override fun startLocationUpdates(
        request: ContinuousLocationRequest,
        androidNotificationOptions: AndroidNotificationOptions?,
    ) {
        val manager = locationManager ?: return
        val previous = tencentLocationRequest ?: return
        if (isListeningLocationUpdates) {
            return
        }
        // 后台定位必须提供通知配置且 id > 0，否则无法启用前台服务
        if (request.backgroundLocation == true) {
            if (androidNotificationOptions == null ||
                androidNotificationOptions.id !in 1..Int.MAX_VALUE.toLong()) {
                throw FlutterError("invalid-argument", "后台定位需要 androidNotificationOptions 且 id 为正的 32 位整数")
            }
        }
        val intervalError = validateIntervalMs(request.intervalMs)
        if (intervalError != null) {
            throw FlutterError("invalid-argument", intervalError)
        }
        val req = TencentLocationRequest(previous)
        req.interval = request.intervalMs
        applyCommonRequestOptions(
            req = req,
            requestLevel = request.requestLevel,
            locMode = request.locMode,
            allowGps = request.allowGps,
            allowCache = request.allowCache,
            gpsFirst = request.gpsFirst,
            gpsFirstTimeOutMs = request.gpsFirstTimeOutMs,
        )

        if (request.backgroundLocation == true && androidNotificationOptions != null) {
            val notifId = androidNotificationOptions.id.toInt()
            if (notifId > 0) {
                manager.enableForegroundLocation(notifId, NotificationUtils.buildNotification(context, androidNotificationOptions))
            }
        }
        val errorCode = manager.requestLocationUpdates(req, this, Looper.getMainLooper())
        if (errorCode != TencentLocation.ERROR_OK) {
            if (request.backgroundLocation == true) manager.disableForegroundLocation(true)
            throw FlutterError("location-request-failed", "开启连续定位失败", errorCode)
        }
        tencentLocationRequest = req
        isListeningLocationUpdates = true
    }

    override fun updateLocationRequest(update: LocationRequestUpdate?) {
        if (update == null) return
        val manager = locationManager ?: return
        val req = tencentLocationRequest ?: return
        if (!isListeningLocationUpdates) throw FlutterError("not-started", "请先开启连续定位")

        val onlyInterval = update.intervalMs != null &&
            update.requestLevel == null &&
            update.locMode == null &&
            update.gpsFirstTimeOutMs == null &&
            update.allowGps == null &&
            update.allowCache == null &&
            update.gpsFirst == null

        if (onlyInterval) {
            val interval = update.intervalMs!!
            val intervalError = validateIntervalMs(interval)
            if (intervalError != null) {
                throw FlutterError("invalid-argument", intervalError)
            }
            manager.changeCallbackInterval(interval)
            req.interval = interval
            return
        }

        // iOS-only fields and an empty update must not re-register Android.
        if (update.intervalMs == null && update.requestLevel == null && update.locMode == null &&
            update.gpsFirstTimeOutMs == null && update.allowGps == null &&
            update.allowCache == null && update.gpsFirst == null) {
            return
        }

        val nextRequest = TencentLocationRequest(req)
        update.intervalMs?.let {
            val intervalError = validateIntervalMs(it)
            if (intervalError != null) {
                throw FlutterError("invalid-argument", intervalError)
            }
            nextRequest.interval = it
        }
        applyCommonRequestOptions(
            req = nextRequest,
            requestLevel = update.requestLevel,
            locMode = update.locMode,
            allowGps = update.allowGps,
            allowCache = update.allowCache,
            gpsFirst = update.gpsFirst,
            gpsFirstTimeOutMs = update.gpsFirstTimeOutMs,
        )

        // Re-submit with the same listener; removeUpdates would stop the engine.
        // Keep the foreground service and the old request if registration fails.
        val errorCode = manager.requestLocationUpdates(nextRequest, this, Looper.getMainLooper())
        if (errorCode != TencentLocation.ERROR_OK) {
            throw FlutterError("location-request-failed", "更新定位请求失败，保留原请求", errorCode)
        }
        tencentLocationRequest = nextRequest
    }

    override fun stopLocationUpdates() {
        isListeningLocationUpdates = false
        locationManager?.disableForegroundLocation(true)
        locationManager?.removeUpdates(this)
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        val manager = locationManager
        stopLocationUpdates()
        val pending = singleRequests.toMap()
        singleRequests.clear()
        locationManager = null
        tencentLocationRequest = null
        for ((listener, callback) in pending) {
            manager?.removeUpdates(listener)
            callback(Result.success(null))
        }
    }

    override fun onLocationChanged(location: TencentLocation?, error: Int, reason: String?) {
        if (disposed) return
        if (error == TencentLocation.ERROR_OK && location != null) {
            flutterApi.onLocation(toLocationData(location)) {}
        } else {
            flutterApi.onError(error.toLong(), reason ?: "定位失败") {}
        }
    }

    private fun toLocationData(location: TencentLocation): LocationData {
        val rawProvider = location.sourceProvider
        val unifiedSource = toUnifiedLocationSource(rawProvider)
        val acc = location.accuracy.toDouble()
        return LocationData(
            code = TencentLocation.ERROR_OK.toLong(),
            latitude = location.latitude.toDouble(),
            longitude = location.longitude.toDouble(),
            altitude = location.altitude.toDouble(),
            accuracy = acc,
            horizontalAccuracy = acc,
            verticalAccuracy = null,
            speed = location.speed.toDouble(),
            bearing = location.bearing.toDouble().takeIf { it in 0.0..360.0 },
            address = location.address,
            name = location.name,
            timeIso = null,
            timeMs = location.time,
            sourceProvider = rawProvider,
            locationSource = unifiedSource,
        )
    }

    /**
     * 将 Android TencentLocation.getSourceProvider() 的字符串映射为与 iOS 统一的定位来源码。
     * 统一约定：-1=未知，0=GPS，1=网络，2=模拟，3=外设GPS，4=外设网络。
     */
    private fun toUnifiedLocationSource(sourceProvider: String?): Long? {
        if (sourceProvider.isNullOrEmpty()) return -1L
        return when (sourceProvider) {
            TencentLocation.GPS_PROVIDER,
            TencentLocation.BEIDOU_PROVIDER -> 0L  // 卫星/GPS
            TencentLocation.NETWORK_PROVIDER,
            TencentLocation.WIFI_PROVIDER,
            TencentLocation.CELL_PROVIDER,
            TencentLocation.COARSE_PROVIDER,
            TencentLocation.FUSED_PROVIDER -> 1L  // 网络
            TencentLocation.FAKE -> 2L            // 模拟/作弊
            else -> -1L
        }
    }

    override fun onStatusUpdate(name: String?, status: Int, desc: String?) {
        if (disposed) return
        flutterApi.onStatus(LocationStatusData(name = name, status = status.toLong())) {}
    }

    private fun applyCommonRequestOptions(
        req: TencentLocationRequest,
        requestLevel: Long?,
        locMode: Long?,
        allowGps: Boolean?,
        allowCache: Boolean?,
        gpsFirst: Boolean?,
        gpsFirstTimeOutMs: Long?,
    ) {
        requestLevel?.toInt()?.let { req.requestLevel = it }
        locMode?.let {
            if (it != TencentLocationRequest.HIGH_ACCURACY_MODE.toLong() &&
                it != TencentLocationRequest.ONLY_NETWORK_MODE.toLong() &&
                it != TencentLocationRequest.ONLY_GPS_MODE.toLong()) {
                throw FlutterError("invalid-argument", "locMode 必须为 10、11 或 12")
            }
            req.locMode = it.toInt()
        }
        allowGps?.let { req.isAllowGPS = it }
        allowCache?.let { req.isAllowCache = it }
        gpsFirst?.let { req.isGpsFirst = it }
        gpsFirstTimeOutMs?.toInt()?.coerceIn(0, 60000)?.let { req.gpsFirstTimeOut = it }
    }

    /** 校验 interval（严格按指南口径）：必须 >= 1000ms。 */
    private fun validateIntervalMs(intervalMs: Long): String? {
        if (intervalMs < 1000L) {
            return "intervalMs 必须大于等于 1000，当前值: $intervalMs"
        }
        return null
    }
}
