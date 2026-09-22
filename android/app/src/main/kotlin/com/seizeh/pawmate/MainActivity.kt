package com.seizeh.pawmate

import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.StandardIntegrityManager.PrepareIntegrityTokenRequest
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenProvider
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenRequest
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    /// Play Integrity 표준 요청 프로바이더 — 최초 1회 준비 후 재사용(권장 패턴).
    /// 준비·요청 실패는 그대로 오류로 돌려주고 Dart(AttestService)가 헤더 미첨부로
    /// 강등한다 — 서버가 섀도 모드라 기능에는 영향이 없다.
    private var integrityProvider: StandardIntegrityTokenProvider? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pawmate/attest")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestIntegrityToken" -> {
                        val requestHash = call.argument<String>("requestHash")
                        if (requestHash.isNullOrEmpty()) {
                            result.error("bad_args", "requestHash required", null)
                        } else {
                            requestIntegrityToken(requestHash, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun requestIntegrityToken(requestHash: String, result: MethodChannel.Result) {
        val provider = integrityProvider
        if (provider != null) {
            requestWith(provider, requestHash, result)
            return
        }
        IntegrityManagerFactory.createStandard(applicationContext)
            .prepareIntegrityToken(
                PrepareIntegrityTokenRequest.builder()
                    .setCloudProjectNumber(CLOUD_PROJECT_NUMBER)
                    .build()
            )
            .addOnSuccessListener { prepared ->
                integrityProvider = prepared
                requestWith(prepared, requestHash, result)
            }
            .addOnFailureListener { e ->
                result.error("prepare_failed", e.message, null)
            }
    }

    private fun requestWith(
        provider: StandardIntegrityTokenProvider,
        requestHash: String,
        result: MethodChannel.Result,
    ) {
        provider.request(
            StandardIntegrityTokenRequest.builder().setRequestHash(requestHash).build()
        )
            .addOnSuccessListener { response -> result.success(response.token()) }
            .addOnFailureListener { e -> result.error("request_failed", e.message, null) }
    }

    companion object {
        /// Firebase 프로젝트(pawmate-7e881)의 프로젝트 번호 — firebase_options.dart 의
        /// messagingSenderId 와 같은 값. 서버 복호(decodeIntegrityToken)의 대상 프로젝트.
        private const val CLOUD_PROJECT_NUMBER = 451_837_752_323L
    }
}
