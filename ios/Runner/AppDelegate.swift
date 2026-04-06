import UIKit
import Flutter
import GoogleMaps
import FirebaseCore
import FirebaseMessaging
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {

    override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        print("\n🚀 App launch started")

        // Google Maps
        GMSServices.provideAPIKey("AIzaSyBn88TP5X-xaRCYo5gYxvGnVy_0WYotZWo")
        print("✅ Google Maps configured")

        // Firebase
        FirebaseApp.configure()
        print("✅ Firebase configured")

        // Foreground notification presentation
        UNUserNotificationCenter.current().delegate = self
        print("✅ UNUserNotificationCenter delegate set")

        // Flutter plugins
        GeneratedPluginRegistrant.register(with: self)
        print("✅ Flutter plugins registered")

        print("✅ App launch completed\n")

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // MARK: - APNs token received
    override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        #if DEBUG
        Messaging.messaging().setAPNSToken(deviceToken, type: .sandbox)
        print("✅ APNs token set in Firebase (sandbox)")
        #else
        Messaging.messaging().setAPNSToken(deviceToken, type: .prod)
        print("✅ APNs token set in Firebase (production)")
        #endif

        super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }

    // MARK: - APNs registration failed
    override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("❌ Failed to register for remote notifications: \(error.localizedDescription)")
        super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
    }

    // MARK: - Foreground notification display
    override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let content = notification.request.content
        print("📩 Foreground notification: \(content.title) | \(content.body)")

        if #available(iOS 14.0, *) {
            completionHandler([.banner, .sound, .badge])
        } else {
            completionHandler([.alert, .sound, .badge])
        }
    }

    // MARK: - Notification tap
    override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        print("👆 Notification tapped: \(response.notification.request.content.userInfo)")
        completionHandler()
    }

    // MARK: - Background / silent notification
    override func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        print("🌙 Background notification received: \(userInfo)")
        Messaging.messaging().appDidReceiveMessage(userInfo)
        completionHandler(.newData)
    }
}