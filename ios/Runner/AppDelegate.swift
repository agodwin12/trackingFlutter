import UIKit
import Flutter
import GoogleMaps
import FirebaseCore
import FirebaseMessaging
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, MessagingDelegate {

    override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        // Google Maps
        GMSServices.provideAPIKey("AIzaSyBn88TP5X-xaRCYo5gYxvGnVy_0WYotZWo")

        // Firebase
        FirebaseApp.configure()

        // Delegates
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self

        // Ask notification permission
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { granted, error in
            print("🔔 Notification permission granted: \(granted), error: \(String(describing: error))")
        }

        // Register for APNs
        application.registerForRemoteNotifications()

        // Flutter plugins
        GeneratedPluginRegistrant.register(with: self)

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // MARK: - APNs token -> Firebase
    override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // IMPORTANT: set token type correctly (Debug = sandbox, Release/TestFlight = prod)
        #if DEBUG
        Messaging.messaging().setAPNSToken(deviceToken, type: .sandbox)
        #else
        Messaging.messaging().setAPNSToken(deviceToken, type: .prod)
        #endif

        // Also set apnsToken (safe to keep)
        Messaging.messaging().apnsToken = deviceToken

        let hexToken = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("✅ APNs token registered: \(hexToken)")

        super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }

    override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("❌ Failed to register for remote notifications: \(error)")
        super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
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

    // MARK: - Background / data messages (helps for data-only or background handling)
    override func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable : Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        print("🌙 didReceiveRemoteNotification: \(userInfo)")
        completionHandler(.newData)
    }

    // MARK: - FCM token
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        print("✅ Firebase registration token (FCM): \(String(describing: fcmToken))")
        // If you send token to backend, do it here.
    }
}