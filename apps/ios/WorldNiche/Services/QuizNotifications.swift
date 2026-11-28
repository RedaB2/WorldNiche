import UIKit
import UserNotifications
import Observation

@MainActor @Observable
final class QuizNotifications {
    static let shared = QuizNotifications()
    private let defaults: UserDefaults
    private let center = UNUserNotificationCenter.current()
    private var preference: Bool?
    var enabled: Bool { preference == true }
    var presentsReminderOffer = false
    private(set) var blocked = false
    private var permissionRequest: UUID?
    var working: Bool { permissionRequest != nil }
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
        #if DEBUG && targetEnvironment(simulator)
        defaults = SocialUITestFixture.reminderDefaults ?? .standard
        #else
        defaults = .standard
        #endif
        // Version 1.1 left this key absent until the person chose a preference.
        preference = defaults.object(forKey: "niche.reminder.enabled") as? Bool
    }

    func refresh(_ social: SocialStore) async {
        self.social = social
        guard social.api != nil else { return }
        let settings = await center.notificationSettings()
        guard !Task.isCancelled, !working else { return }
        blocked = settings.authorizationStatus == .denied
        if blocked {
            setPreference(false)
        } else if enabled && !social.deletionPending && [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) {
            UIApplication.shared.registerForRemoteNotifications()
        }
        let needsPermission = settings.authorizationStatus == .notDetermined && preference != false
        presentsReminderOffer = !social.deletionPending && (preference == nil || needsPermission)
        await synchronize()
    }

    func setEnabled(_ value: Bool, social: SocialStore) async {
        self.social = social
        message = nil
        if !value {
            clearPreference()
            return
        }
        guard !working, social.api != nil, !social.deletionPending else { return }
        presentsReminderOffer = false
        let request = UUID()
        permissionRequest = request
        defer { if permissionRequest == request { permissionRequest = nil } }
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            guard permissionRequest == request, !social.deletionPending else { return }
            blocked = !granted
            setPreference(granted)
            if granted { UIApplication.shared.registerForRemoteNotifications() }
        } catch {
            if permissionRequest == request { message = "Couldn’t request notification permission. Please try again." }
            return
        }
        await synchronize()
    }

    private func setPreference(_ value: Bool) {
        guard preference != value else { return }
        revision += 1
        if enabled != value { defaults.set(true, forKey: "niche.reminder.needsSync") }
        preference = value
        defaults.set(value, forKey: "niche.reminder.enabled")
    }

    func clearPreference() {
        permissionRequest = nil
        presentsReminderOffer = false
        setPreference(false)
        if defaults.bool(forKey: "niche.reminder.needsSync") {
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
