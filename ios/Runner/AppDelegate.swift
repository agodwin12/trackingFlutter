import UIKit
import Flutter
import GoogleMaps
import FirebaseCore
import FirebaseMessaging
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, MessagingDelegate {

    private var methodChannel: FlutterMethodChannel?
    private var apnsTokenReceived = false
    private var fcmTokenReceived = false
    private var tokenSentToFlutter = false

    override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        print("\n")
        print("🚀 ==========================================")
        print("🚀 STEP 1: APP LAUNCH STARTED")
        print("🚀 ==========================================")
        print("🚀 Time: \(Date())")

        // Google Maps
        print("\n📍 STEP 2: Configuring Google Maps...")
        GMSServices.provideAPIKey("AIzaSyBn88TP5X-xaRCYo5gYxvGnVy_0WYotZWo")
        print("✅ Google Maps API configured successfully")

        // Firebase Configuration
        print("\n🔥 STEP 3: Configuring Firebase...")
        FirebaseApp.configure()
        print("✅ Firebase Core configured successfully")

        // Disable auto-init
        print("\n⏸️ STEP 4: Disabling Firebase auto-init...")
        print("⏸️ Current auto-init status: \(Messaging.messaging().isAutoInitEnabled)")
        Messaging.messaging().isAutoInitEnabled = false
        print("✅ Firebase Messaging auto-init disabled")
        print("✅ Auto-init will be enabled AFTER APNs token arrives")

        // Set delegates
        print("\n📋 STEP 5: Setting up delegates...")
        UNUserNotificationCenter.current().delegate = self
        print("✅ UNUserNotificationCenter delegate = self")
        Messaging.messaging().delegate = self
        print("✅ Messaging delegate = self")

        // Setup Flutter Method Channel
        print("\n📱 STEP 6: Setting up Flutter Method Channel...")
        let controller = window?.rootViewController as! FlutterViewController
        print("📱 Got FlutterViewController: \(controller)")
        methodChannel = FlutterMethodChannel(
            name: "com.proxym.tracking/fcm",
            binaryMessenger: controller.binaryMessenger
        )
        print("✅ Method Channel created: 'com.proxym.tracking/fcm'")
        print("✅ Method Channel ready to send tokens to Flutter")

        // Request notification permissions
        print("\n🔔 STEP 7: Requesting notification permissions...")
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { granted, error in
            print("\n🔔 STEP 8: Permission response received")

            if let error = error {
                print("❌ Permission request error: \(error.localizedDescription)")
                print("❌ Error details: \(error)")
                return
            }

            print("🔔 Permission result: \(granted ? "GRANTED ✅" : "DENIED ❌")")

            if granted {
                print("✅ User accepted notifications")
                print("\n📱 STEP 9: Registering for remote notifications...")
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                    print("✅ Remote notification registration requested")
                    print("⏳ Waiting for APNs token from Apple...")
                }
            } else {
                print("⚠️ User denied notifications - FCM will not work")
            }
        }

        // Flutter plugins
        print("\n🔌 STEP 10: Registering Flutter plugins...")
        GeneratedPluginRegistrant.register(with: self)
        print("✅ Flutter plugins registered")

        print("\n🚀 ==========================================")
        print("🚀 APP LAUNCH COMPLETED SUCCESSFULLY")
        print("🚀 Next: Waiting for APNs token...")
        print("🚀 ==========================================\n")

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // MARK: - APNs token -> Firebase
    override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        print("\n")
        print("📱 ==========================================")
        print("📱 STEP 11: APNs TOKEN RECEIVED FROM APPLE")
        print("📱 ==========================================")
        print("📱 Time: \(Date())")

        apnsTokenReceived = true

        // Convert to hex
        let hexToken = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("📱 APNs Token (hex): \(hexToken)")
        print("📱 Token length: \(hexToken.count) characters")
        print("📱 Token bytes: \(deviceToken.count) bytes")

        // Determine environment
        #if DEBUG
        let environment = "DEBUG (Sandbox)"
        let tokenType = MessagingAPNSTokenType.sandbox
        print("🔧 Build Configuration: DEBUG")
        print("🔧 Using: Sandbox APNs")
        #else
        let environment = "RELEASE (Production)"
        let tokenType = MessagingAPNSTokenType.prod
        print("🔧 Build Configuration: RELEASE")
        print("🔧 Using: Production APNs")
        #endif

        print("🔧 Environment: \(environment)")

        // Set APNs token in Firebase
        print("\n🔥 STEP 12: Setting APNs token in Firebase Messaging...")
        Messaging.messaging().setAPNSToken(deviceToken, type: tokenType)
        print("✅ APNs token successfully set in Firebase")
        print("✅ Firebase now knows the APNs token")

        // Enable auto-init NOW
        print("\n▶️ STEP 13: Enabling Firebase Messaging auto-init...")
        print("▶️ Previous auto-init status: \(Messaging.messaging().isAutoInitEnabled)")
        Messaging.messaging().isAutoInitEnabled = true
        print("✅ Auto-init enabled: \(Messaging.messaging().isAutoInitEnabled)")
        print("✅ Firebase can now generate FCM token")

        // Manually request FCM token
        print("\n🔑 STEP 14: Requesting FCM token from Firebase...")
        print("⏳ Calling Messaging.messaging().token()...")

        Messaging.messaging().token { token, error in
            print("\n🔑 STEP 15: FCM Token callback received")

            if let error = error {
                print("❌ ==========================================")
                print("❌ FCM TOKEN FETCH FAILED")
                print("❌ ==========================================")
                print("❌ Error: \(error.localizedDescription)")
                print("❌ Error code: \(error)")
                print("❌ This means APNs token was NOT properly set")
                print("❌ ==========================================\n")
                self.fcmTokenReceived = false
                self.printStatusSummary()
                return
            }

            if let token = token {
                print("✅ ==========================================")
                print("✅ FCM TOKEN RECEIVED SUCCESSFULLY!")
                print("✅ ==========================================")
                print("✅ FCM Token: \(token)")
                print("✅ Token length: \(token.count) characters")
                print("✅ Token starts with: \(token.prefix(20))...")
                self.fcmTokenReceived = true

                // Send to Flutter
                print("\n📤 STEP 16: Sending FCM token to Flutter...")
                print("📤 Channel name: com.proxym.tracking/fcm")
                print("📤 Method name: onTokenRefresh")
                print("📤 Calling methodChannel.invokeMethod()...")

                self.methodChannel?.invokeMethod("onTokenRefresh", arguments: token)

                print("✅ Method invoked successfully")
                print("✅ Flutter should receive token now")
                self.tokenSentToFlutter = true
                print("✅ ==========================================\n")
            } else {
                print("⚠️ ==========================================")
                print("⚠️ FCM TOKEN IS NIL")
                print("⚠️ ==========================================")
                print("⚠️ No error but token is nil")
                print("⚠️ This is unusual - check Firebase config")
                print("⚠️ ==========================================\n")
                self.fcmTokenReceived = false
            }

            self.printStatusSummary()
        }
    }

    override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("\n")
        print("❌ ==========================================")
        print("❌ FAILED TO REGISTER FOR REMOTE NOTIFICATIONS")
        print("❌ ==========================================")
        print("❌ Time: \(Date())")
        print("❌ Error: \(error.localizedDescription)")
        print("❌ Full error: \(error)")
        print("❌ Error code: \((error as NSError).code)")
        print("❌ Error domain: \((error as NSError).domain)")
        print("❌ This means APNs token was NOT received")
        print("❌ Possible causes:")
        print("❌   - Running on simulator (APNs doesn't work on simulator)")
        print("❌   - Missing Push Notification capability")
        print("❌   - Invalid provisioning profile")
        print("❌   - Network issues")
        print("❌ ==========================================\n")

        apnsTokenReceived = false
        printStatusSummary()
    }

    // MARK: - Foreground notification display
    override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo

        print("\n")
        print("📩 ==========================================")
        print("📩 FOREGROUND NOTIFICATION RECEIVED")
        print("📩 ==========================================")
        print("📩 Time: \(Date())")
        print("📩 Title: \(notification.request.content.title)")
        print("📩 Body: \(notification.request.content.body)")
        print("📩 User Info: \(userInfo)")
        print("📩 ==========================================\n")

        if #available(iOS 14.0, *) {
            completionHandler([.banner, .sound, .badge])
            print("✅ Showing notification with banner, sound, badge")
        } else {
            completionHandler([.alert, .sound, .badge])
            print("✅ Showing notification with alert, sound, badge")
        }
    }

    // MARK: - User tapped notification
    override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        print("\n")
        print("👆 ==========================================")
        print("👆 NOTIFICATION TAPPED BY USER")
        print("👆 ==========================================")
        print("👆 Time: \(Date())")
        print("👆 Action: \(response.actionIdentifier)")
        print("👆 User Info: \(userInfo)")
        print("👆 ==========================================\n")

        completionHandler()
    }

    // MARK: - Background / data messages
    override func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable : Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        print("\n")
        print("🌙 ==========================================")
        print("🌙 BACKGROUND NOTIFICATION RECEIVED")
        print("🌙 ==========================================")
        print("🌙 Time: \(Date())")
        print("🌙 User Info: \(userInfo)")
        print("🌙 ==========================================\n")

        Messaging.messaging().appDidReceiveMessage(userInfo)
        completionHandler(.newData)
    }

    // MARK: - FCM token via delegate
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        print("\n")
        print("🔄 ==========================================")
        print("🔄 FCM TOKEN RECEIVED VIA DELEGATE")
        print("🔄 ==========================================")
        print("🔄 Time: \(Date())")
        print("🔄 This is called when token refreshes")

        guard let token = fcmToken else {
            print("⚠️ Token is nil in delegate callback")
            print("🔄 ==========================================\n")
            return
        }

        print("🔑 FCM Token: \(token)")
        print("🔑 Token length: \(token.count) characters")

        // Send to Flutter
        print("\n📤 Sending token to Flutter via delegate...")
        methodChannel?.invokeMethod("onTokenRefresh", arguments: token)
        print("✅ Token sent to Flutter")
        tokenSentToFlutter = true

        print("🔄 ==========================================\n")
    }

    // MARK: - Status Summary
    private func printStatusSummary() {
        print("\n")
        print("📊 ==========================================")
        print("📊 COMPLETE STATUS SUMMARY")
        print("📊 ==========================================")
        print("📊 Time: \(Date())")
        print("📊 ")
        print("📊 APNs Token Received:  \(apnsTokenReceived ? "✅ YES" : "❌ NO")")
        print("📊 FCM Token Received:   \(fcmTokenReceived ? "✅ YES" : "❌ NO")")
        print("📊 Token Sent to Flutter: \(tokenSentToFlutter ? "✅ YES" : "❌ NO")")
        print("📊 ")
        print("📊 Overall Status: \(apnsTokenReceived && fcmTokenReceived && tokenSentToFlutter ? "✅ ALL WORKING" : "⚠️ ISSUES DETECTED")")
        print("📊 ==========================================\n")
    }
}