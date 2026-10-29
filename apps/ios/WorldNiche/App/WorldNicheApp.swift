import SwiftUI
import AuthenticationServices

@main
struct WorldNicheApp: App {
    @State private var journal: DiscoveryJournal
    @State private var social: SocialStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG && targetEnvironment(simulator)
        if let fixture = SocialUITestFixture.make() {
            _journal = State(initialValue: fixture.journal)
            _social = State(initialValue: fixture.social)
            return
        }
        #endif
        let journal = DiscoveryJournal()
        _journal = State(initialValue: journal)
        _social = State(initialValue: SocialStore(journal: journal, appleCredentialIsAuthorized: { userID in
            guard let state = try? await AppleSignInCoordinator.credentialState(forUserID: userID) else { return nil }
            if state == .revoked || state == .notFound { return false }
            return state == .authorized ? true : nil
        }))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(journal)
                .environment(social)
                .tint(Palette.pine)
                .task { await restoreSession() }
                .task(id: journal.revision) {
                    try? await Task.sleep(for: .milliseconds(750))
                    if !Task.isCancelled { await social.synchronizeExploration() }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await restoreSession() } }
                }
                .onReceive(NotificationCenter.default.publisher(for: ASAuthorizationAppleIDProvider.credentialRevokedNotification)) { _ in
                    Task { await checkAppleAuthorization() }
                }
                .onChange(of: social.isBusy) { _, busy in
                    if !busy { Task { await social.resumeInvitation() } }
                }
                .onOpenURL { url in Task { await social.openInvitation(url) } }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { Task { await social.openInvitation(url) } }
                }
                .sheet(isPresented: $social.presentsInvitation, onDismiss: { social.dismissInvitation() }) {
                    FriendInvitationView()
                        .environment(social)
                        .environment(journal)
                }
        }
    }

    private func restoreSession() async {
        await social.refresh()
    }

    private func checkAppleAuthorization() async {
        guard let userID = social.appleUserID else { return }
        // A network failure leaves the saved session intact. Only a definitive
        // Apple revocation or missing credential requires a new sign-in.
        guard let state = try? await AppleSignInCoordinator.credentialState(forUserID: userID) else { return }
        if state == .revoked || state == .notFound {
            await social.invalidateAppleSession(userID: userID)
        }
    }
}

enum Palette {
    static let paper = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.09, green: 0.13, blue: 0.12, alpha: 1) : UIColor(red: 0.965, green: 0.957, blue: 0.925, alpha: 1) })
    static let card = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.13, green: 0.18, blue: 0.16, alpha: 1) : UIColor(red: 0.997, green: 0.991, blue: 0.969, alpha: 1) })
    static let pine = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.77, green: 0.86, blue: 0.76, alpha: 1) : UIColor(red: 0.13, green: 0.24, blue: 0.20, alpha: 1) })
    static let forest = Color(red: 0.13, green: 0.24, blue: 0.20)
    static let muted = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.65, green: 0.71, blue: 0.66, alpha: 1) : UIColor(red: 0.43, green: 0.48, blue: 0.43, alpha: 1) })
    static let clay = Color(red: 0.72, green: 0.36, blue: 0.23)
    static let line = pine.opacity(0.12)
}

extension View {
    /// Revalidate visible content on return, every 15 minutes, and at local midnight.
    func refreshLiveContent(perform action: @escaping () -> Void) -> some View {
        modifier(LiveRefreshModifier(action: action))
    }

    func scaledFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(ScaledAppFont(size: size, weight: weight, design: design))
    }

    func editorialCard() -> some View {
        padding(22)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Palette.line, lineWidth: 0.7))
    }
}

private struct LiveRefreshModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { action() }
            }
            .task {
                while !Task.isCancelled {
                    let now = Date()
                    let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now.addingTimeInterval(900)
                    do { try await Task.sleep(for: .seconds(max(1, min(900, midnight.timeIntervalSince(now))))) }
                    catch { return }
                    guard !Task.isCancelled else { return }
                    if scenePhase == .active { action() }
                }
            }
    }
}

private struct ScaledAppFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design) {
        _size = ScaledMetric(wrappedValue: max(11, size), relativeTo: size >= 28 ? .largeTitle : size >= 20 ? .title2 : size >= 14 ? .body : .caption)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .scaledFont(size: 11, weight: .semibold, design: .monospaced)
            .tracking(2)
            .foregroundStyle(Palette.muted)
    }
}
