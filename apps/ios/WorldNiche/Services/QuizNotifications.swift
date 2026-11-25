import UIKit
import UserNotifications
import Observation

@MainActor @Observable
final class QuizNotifications {
    static let shared = QuizNotifications()
    private let defaults = UserDefaults.standard
    private let center = UNUserNotificationCenter.current()
    private(set) var enabled: Bool
    private(set) var blocked = false
    private(set) var working = false
    private(set) var message: String?
    var openQuiz: UUID?
    private var token: String?
    private var revision = 0
    private var syncing = false
    private weak var social: SocialStore?
    private var retryTask: Task<Void, Never>?
    private var installation: UUID {
        if let raw = defaults.string(forKey: "niche.reminder.installation"), let id = UUID(uuidString: raw) { return id }
        let id = UUID()
        defaults.set(id.uuidString, forKey: "niche.reminder.installation")
        return id
    }

    private init() {
        enabled = defaults.bool(forKey: "niche.reminder.enabled")
    }

    func refresh(_ social: SocialStore) async {
        self.social = social
        let settings = await center.notificationSettings()
        blocked = settings.authorizationStatus == .denied
        if enabled && [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) {
            UIApplication.shared.registerForRemoteNotifications()
        }
        if enabled && blocked { setPreference(false) }
        await synchronize()
    }

    func setEnabled(_ value: Bool, social: SocialStore) async {
        guard !working else { return }
        working = true
        defer { working = false }
        self.social = social
        message = nil
        if value {
            do {
                guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                    blocked = true
                    return
                }
                blocked = false
                setPreference(true)
                UIApplication.shared.registerForRemoteNotifications()
            } catch { message = "Couldn’t request notification permission. Please try again." }
        } else {
            setPreference(false)
            center.removeAllDeliveredNotifications()
            UIApplication.shared.unregisterForRemoteNotifications()
        }
        await synchronize()
    }

    private func setPreference(_ value: Bool) {
        enabled = value
        defaults.set(value, forKey: "niche.reminder.enabled")
        defaults.set(true, forKey: "niche.reminder.needsSync")
    }

    func clearPreference() {
        if enabled || defaults.bool(forKey: "niche.reminder.needsSync") {
            setPreference(false)
            center.removeAllDeliveredNotifications()
            UIApplication.shared.unregisterForRemoteNotifications()
            Task { await synchronize() }
        }
    }

    func receivedToken(_ data: Data) {
        token = data.map { String(format: "%02x", $0) }.joined()
        Task { await synchronize() }
    }

    func registrationFailed() {
        if enabled { message = "Couldn’t connect to Apple Push Notifications. Reopen the app to retry." }
    }

    // Serialize preference changes so a slow enable request cannot win after an opt-out.
    func synchronize() async {
        revision += 1
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }
        while let social, let api = social.api {
            let version = revision
            let wantsPush = enabled && !social.deletionPending
            guard wantsPush || defaults.bool(forKey: "niche.reminder.needsSync") else { return }
            guard !wantsPush || token != nil else { return }
            #if DEBUG
            let sandbox = true
            #else
            let sandbox = false
            #endif
            do {
                try await api.setQuizReminder(installation: installation, token: token, sandbox: sandbox,
                    zone: TimeZone.current.identifier, enabled: wantsPush, completed: social.quiz.today?.day,
                    owner: wantsPush ? social.quiz.owner : nil)
                if revision == version {
                    defaults.set(false, forKey: "niche.reminder.needsSync")
                    message = nil
                    retryTask?.cancel()
                    return
                }
            } catch {
                if revision == version {
                    message = "Reminder settings are waiting to sync."
                    defaults.set(true, forKey: "niche.reminder.needsSync")
                    retryTask?.cancel()
                    retryTask = Task {
                        do { try await Task.sleep(for: .seconds(60)) } catch { return }
                        await synchronize()
                    }
                    return
                }
            }
        }
    }
}

final class QuizAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        QuizNotifications.shared.receivedToken(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        QuizNotifications.shared.registrationFailed()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping @Sendable () -> Void) {
        let opensQuiz = response.notification.request.content.userInfo["quizDay"] != nil
        Task { @MainActor in
            if opensQuiz { QuizNotifications.shared.openQuiz = UUID() }
            // UIKit updates its scene snapshot from this completion handler.
            completionHandler()
        }
    }
}
