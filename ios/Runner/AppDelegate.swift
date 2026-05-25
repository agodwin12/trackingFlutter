import UIKit
import Flutter
import GoogleMaps
import FirebaseCore
import UserNotifications
import Firebase
import FirebaseMessaging

@main
@objc class AppDelegate: FlutterAppDelegate {

    override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        print("\n🚀 App launch started")

        // Google Maps
        GMSServices.provideAPIKey("YOUR_GOOGLE_MAPS_API_KEY")
        print("✅ Google Maps configured")

        // Firebase native config
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
            print("✅ Firebase configured")
        } else {
            print("ℹ️ Firebase already configured")
        }

        // Required for foreground notification callbacks
        if #available(iOS 10.0, *) {
            UNUserNotificationCenter.current().delegate = self
            print("✅ UNUserNotificationCenter delegate set")
        }

        GeneratedPluginRegistrant.register(with: self)
        print("✅ Flutter plugins registered")

        DispatchQueue.main.async {
            application.registerForRemoteNotifications()
            print("✅ registerForRemoteNotifications() called")
        }

        print("✅ App launch completed\n")

        return super.application(
            application,
            didFinishLaunchingWithOptions: launchOptions
        )
    }

    override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("✅ APNs token received: \(token)")

        Messaging.messaging().setAPNSToken(deviceToken, type: .unknown)
        print("✅ APNs token set in Firebase")

        super.application(
            application,
            didRegisterForRemoteNotificationsWithDeviceToken: deviceToken
        )
    }

    override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("❌ Failed to register for remote notifications: \(error.localizedDescription)")

        super.application(
            application,
            didFailToRegisterForRemoteNotificationsWithError: error
        )
    }

    override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        print("👆 Notification tapped: \(response.notification.request.content.userInfo)")

        super.userNotificationCenter(
            center,
            didReceive: response,
            withCompletionHandler: completionHandler
        )
    }

    override func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        print("🌙 Background notification received: \(userInfo)")

        super.application(
            application,
            didReceiveRemoteNotification: userInfo,
            fetchCompletionHandler: completionHandler
        )
    }
}