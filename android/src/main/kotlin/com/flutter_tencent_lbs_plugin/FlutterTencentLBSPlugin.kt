package com.flutter_tencent_lbs_plugin

import io.flutter.embedding.engine.plugins.FlutterPlugin
import com.flutter_tencent_lbs_plugin.pigeon.TencentLBSFlutterApi
import com.flutter_tencent_lbs_plugin.pigeon.TencentLBSHostApi
import com.flutter_tencent_lbs_plugin.pigeon.TencentLBSHostApiImpl

class FlutterTencentLBSPlugin : FlutterPlugin {
    private var hostApi: TencentLBSHostApiImpl? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val messenger = binding.binaryMessenger
        val flutterApi = TencentLBSFlutterApi(messenger)
        val api = TencentLBSHostApiImpl(binding.applicationContext, flutterApi)
        hostApi = api
        TencentLBSHostApi.setUp(messenger, api)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        hostApi?.dispose()
        hostApi = null
        TencentLBSHostApi.setUp(binding.binaryMessenger, null)
    }
}
