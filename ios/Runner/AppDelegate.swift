import UIKit
import Flutter
import GoogleMaps
import FirebaseCore
import FirebaseMessaging
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, MessagingDelegate {

    private var methodChannel: FlutterMethodChannel?

    override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        // Google Maps
        GMSServices.provideAPIKey("AIzaSyBn88TP5X-xaRCYo5gYxvGnVy_0WYotZWo")

        // Firebase - MUST be first
        FirebaseApp.configure()

        // Set delegates BEFORE requesting permissions
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self

        // Setup Flutter Method Channel
        let controller = window?.rootViewController as! FlutterViewController
        methodChannel = FlutterMethodChannel(
            name: "com.proxym.tracking/fcm",
            binaryMessenger: controller.binaryMessenger
        )

        // Request notification permissions
        if #available(iOS 10.0, *) {
            UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            ) { granted, error in
                print("🔔 Notification permission granted: \(granted)")
                if granted {
                    DispatchQueue.main.async {
                        application.registerForRemoteNotifications()
                    }
                }
            }
        } else {
            let settings = UIUserNotificationSettings(types: [.alert, .badge, .sound], categories: nil)
            application.registerUserNotificationSettings(settings)
            application.registerForRemoteNotifications()
        }

        // Flutter plugins
        GeneratedPluginRegistrant.register(with: self)

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // MARK: - APNs token -> Firebase
    override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        print("📱 APNs device token received")

        // Set APNs token with correct type
        #if DEBUG
        Messaging.messaging().setAPNSToken(deviceToken, type: .sandbox)
        print("🔧 Environment: DEBUG (Sandbox)")
        #else
        Messaging.messaging().setAPNSToken(deviceToken, type: .prod)
        print("🔧 Environment: RELEASE (Production)")
        #endif

        let hexToken = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("✅ APNs token set: \(hexToken)")
    }

    override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("❌ Failed to register for remote notifications: \(error.localizedDescription)")
    }

    // MARK: - Foreground notification display
    override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        print("📩 Notification received in foreground: \(userInfo)")

        if #available(iOS 14.0, *) {
            completionHandler([.banner, .sound, .badge])
        } else {
            completionHandler([.alert, .sound, .badge])
        }
    }

    // MARK: - User tapped notification
    override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        print("👆 Notification tapped: \(userInfo)")
        completionHandler()
    }

    // MARK: - Background / data messages
    override func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable : Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        print("🌙 Background notification: \(userInfo)")
        Messaging.messaging().appDidReceiveMessage(userInfo)
        completionHandler(.newData)
    }

    // MARK: - FCM token
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        print("✅ FCM token received: \(fcmToken ?? "nil")")

        guard let token = fcmToken else {
            print("⚠️ FCM token is nil")
            return
        }

        // Send to Flutter via Method Channel
        methodChannel?.invokeMethod("onTokenRefresh", arguments: token)
        print("📤 FCM token sent to Flutter: \(token)")
    }
}