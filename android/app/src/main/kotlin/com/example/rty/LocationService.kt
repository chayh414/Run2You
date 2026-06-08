package com.example.running_app   

import android.Manifest
import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import com.google.android.gms.location.*

class LocationService : Service() {

    companion object {
        const val CHANNEL_ID = "r2u_location_channel"
        const val NOTI_ID = 1
        private const val TAG = "LocationService"
    }

    // 📍 구글 위치 클라이언트
    private lateinit var fusedLocationClient: FusedLocationProviderClient
    private var locationCallback: LocationCallback? = null

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "onCreate")

        // 알림 채널 생성
        createNotificationChannel()

        // 위치 클라이언트 초기화
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand")

        val notification = createNotification(
            "R2U 달리기 기록 중",
            "백그라운드에서 위치 추적 중입니다."
        )

        // 🔔 포그라운드 서비스 시작 (알림 고정)
        startForeground(NOTI_ID, notification)

        // 📍 위치 업데이트 시작
        startLocationUpdates()

        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "onDestroy")
        stopLocationUpdates()
    }

    // ======================================================
    // 🔔 Notification
    // ======================================================
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "R2U 러닝 알림",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "달리기 중 백그라운드 위치 추적 알림"
            }

            val manager =
                getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun createNotification(title: String, content: String): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(content)
            // TODO: 나중에 r2u 전용 아이콘으로 교체
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setOngoing(true)
            .build()
    }

    // ======================================================
    // 📍 위치 업데이트
    // ======================================================

    @SuppressLint("MissingPermission") // 아래에서 직접 권한 체크하니까
    private fun startLocationUpdates() {
        Log.d(TAG, "startLocationUpdates")

        // 1) 권한 체크 (FINE/COARSE/배경)
        val fineOk = ActivityCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED

        val coarseOk = ActivityCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_COARSE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED

        if (!fineOk && !coarseOk) {
            Log.w(TAG, "위치 권한 없음, 서비스 종료")
            stopSelf()
            return
        }

        // Android 10 이상이면 백그라운드 권한도 체크 (있으면 좋음)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val bgOk = ActivityCompat.checkSelfPermission(
                this,
                Manifest.permission.ACCESS_BACKGROUND_LOCATION
            ) == PackageManager.PERMISSION_GRANTED

            if (!bgOk) {
                Log.w(TAG, "백그라운드 위치 권한 없음 (항상 허용 아님)")
                // 여기서 바로 종료할지, 일단 while-in-use 만으로 진행할지는 정책에 따라 결정
                // 일단은 진행만 하고, Flutter 쪽에서 미리 안내해주는 게 좋음.
            }
        }

        // 2) LocationRequest (3초마다, 고정밀)
        val locationRequest = LocationRequest.Builder(
            Priority.PRIORITY_HIGH_ACCURACY,
            3000L // 3초
        ).setMinUpdateDistanceMeters(3f) // 3m 이상 이동 시에만 콜백 (배터리 절약용)
            .build()

        // 3) 콜백 정의
        locationCallback = object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                for (loc in result.locations) {
                    val lat = loc.latitude
                    val lng = loc.longitude
                    Log.d(TAG, "위치 업데이트: $lat, $lng")

                    // 🔥 여기서 할 일
                    // - 서버에 POST /api/run/location 이런 식으로 보내거나
                    // - 로컬 DB/SharedPreferences 에 기록하거나
                    // - 브로드캐스트/메시지로 Flutter 쪽에 보내기 등등
                }
            }
        }

        // 4) 위치 업데이트 요청
        fusedLocationClient.requestLocationUpdates(
            locationRequest,
            locationCallback as LocationCallback,
            Looper.getMainLooper()
        )
    }

    private fun stopLocationUpdates() {
        Log.d(TAG, "stopLocationUpdates")
        locationCallback?.let { fusedLocationClient.removeLocationUpdates(it) }
        locationCallback = null
    }
}