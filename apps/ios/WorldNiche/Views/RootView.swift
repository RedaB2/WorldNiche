import SwiftUI

struct RootView: View {
    @Environment(SocialStore.self) private var social
    @Environment(DiscoveryJournal.self) private var journal
    @State private var selectedTab = RootTab.discover
    @State private var introResolved = false
    @State private var presentsIntro = false
    @State private var presentsIntroSignIn = false
    @State private var notificationQuiz = false
    @State private var notificationNavigationID = 0
    private let introProgress = IntroProgress.appProgress()

    var body: some View {
        Group {
            if !introResolved {
                Palette.paper.ignoresSafeArea()
            } else if presentsIntro {
                IntroView(explore: { finishIntro() }, createProfile: {
                    finishIntro()
                    selectedTab = .profile
                    presentsIntroSignIn = true
                })
            } else {
                TabView(selection: $selectedTab) {
                    Tab("Discover", systemImage: "globe.europe.africa", value: RootTab.discover) { ExploreView(showQuiz: $notificationQuiz) }
                    Tab("Atlas", systemImage: "square.grid.2x2", value: RootTab.atlas) { AtlasView() }
                    Tab("Journal", systemImage: "bookmark", value: RootTab.journal) { JournalView() }
                    Tab("Profile", systemImage: "person.crop.circle", value: RootTab.profile) { ProfileView() }
                }
                .tabBarMinimizeBehavior(.onScrollDown)
                .id(notificationNavigationID)
            }
        }
        .onChange(of: QuizNotifications.shared.openQuiz, initial: true) { _, request in
            if request != nil {
                finishIntro()
                presentsIntroSignIn = false
                notificationNavigationID += 1
                selectedTab = .discover
                notificationQuiz = true
                QuizNotifications.shared.openQuiz = nil
            }
        }
        .sheet(isPresented: $presentsIntroSignIn) { ProfileSignInView() }
        .onAppear {
            guard !introResolved else { return }
            introProgress.prepareFirstAppearance()
            presentsIntro = introProgress.shouldPresent(hasProfile: social.profile != nil || social.isSignedIn,
                                                       hasJournal: !journal.visitedIDs.isEmpty || !journal.savedIDs.isEmpty,
                                                       hasInvitation: social.presentsInvitation)
            if !presentsIntro, !introProgress.skipsPresentation { introProgress.complete() }
            introResolved = true
        }
        .onChange(of: social.presentsInvitation) { _, presenting in
            if presenting {
                finishIntro()
                presentsIntroSignIn = false
            }
        }
        .onChange(of: social.isSignedIn) { _, signedIn in
            if signedIn, presentsIntro, !introProgress.ignoresExistingActivity { finishIntro() }
        }
    }

    private func finishIntro() {
        introProgress.complete()
        presentsIntro = false
    }

    private enum RootTab: Hashable { case discover, atlas, journal, profile }
}

struct ExploreView: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(SocialStore.self) private var social
    @Binding var showQuiz: Bool
    @State private var showStreak = false
    @State private var nextCountry: Country?
    @State private var selected = CountryRepository.country(id: "MA") ?? CountryRepository.countries[0]
    @State private var spinToken = 0
    @State private var globeResetToken = 0
    @State private var hasTouchedGlobe = false
    @State private var isSpinning = false
    @State private var detail: Country?
    @State private var showAbout = false

    private var usesColumns: Bool { verticalSizeClass == .compact && !dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    sections {
                        masthead
                        Text("The world is full\nof little wonders.")
                            .scaledFont(size: 39, weight: .regular, design: .serif)
                            .fixedSize(horizontal: false, vertical: true)
                            .tracking(-1.5)
                            .lineSpacing(-2)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Palette.pine)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("discoverHeadline")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 12)

                        if social.quiz.today == nil {
                            Button.haptic {
                                showQuiz = true
                            } label: {
                                Label("Play today’s quiz", systemImage: "questionmark.circle")
                                    .scaledFont(size: 15, weight: .semibold)
                                    .padding(.horizontal, 16).frame(minHeight: 44)
                                    .background(Palette.pine.opacity(0.08), in: Capsule())
                            }
                            .buttonStyle(.plain).foregroundStyle(Palette.pine)
                            .accessibilityIdentifier("dailyQuiz")
                            .padding(.top, 10)
                        }

                        HStack(spacing: 6) {
                            Image(systemName: "hand.draw").accessibilityHidden(true)
                            Text("Drag to turn. Pinch to zoom. Two fingers to move.")
                                .accessibilityIdentifier("discoverGuidance")
                        }
                        .scaledFont(size: 11)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(Palette.muted)
                        .padding(.top, 12)
                    } destination: {
                        globe(preferredHeight: max(200, min(geometry.size.width - 30, 355)))
                            .layoutPriority(-1)
                            .padding(.horizontal, usesColumns ? 0 : -26)
                            .padding(.top, 2)

                        Button {
                            guard !isSpinning else { return }
                            isSpinning = true
                            selected = CountryRepository.random(excluding: selected.id)
                            spinToken += 1
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "shuffle")
                                Text(isSpinning ? "Finding your somewhere…" : "Take me somewhere")
                                    .scaledFont(size: 15, weight: .semibold)
                            }
                            .padding(.horizontal, 23)
                            .frame(maxWidth: .infinity, minHeight: 57)
                            .foregroundStyle(.white)
                            .background(Palette.forest, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .fixedSize(horizontal: false, vertical: true)
                        .disabled(isSpinning)
                        .accessibilityIdentifier("spinButton")
                        .sensoryFeedback(.impact(weight: .light), trigger: spinToken)
                        .task(id: spinToken) {
                            guard isSpinning else { return }
                            try? await Task.sleep(for: .seconds(reduceMotion ? 0.2 : 1.8))
                            if !Task.isCancelled { isSpinning = false }
                        }

                        Text("195 countries. Endless ways to connect.")
                            .scaledFont(size: 11)
                            .foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 13)
                            .padding(.bottom, usesColumns ? 8 : 28)
                    }
                    .frame(idealHeight: dynamicTypeSize.isAccessibilitySize ? nil : geometry.size.height)
                    .padding(.horizontal, 26)
                    .frame(maxWidth: usesColumns ? .infinity : 620)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .vertical)
                .scrollIndicators(.hidden)
            }
            .background(Palette.paper)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $detail) { CountryDetailView(country: $0) }
            .sheet(isPresented: $showQuiz, onDismiss: {
                if let country = nextCountry { selected = country; detail = country; nextCountry = nil }
            }) {
                DailyQuizView { country in nextCountry = country; showQuiz = false }
                    .id(social.quiz.owner)
                    .id(social.quiz.day)
            }
            .sheet(isPresented: $showStreak) { QuizStreakView() }
            .sheet(isPresented: $showAbout) { AboutView() }
        }
    }

    private func sections<Heading: View, Destination: View>(
        @ViewBuilder heading: () -> Heading, @ViewBuilder destination: () -> Destination
    ) -> some View {
        let layout = usesColumns ? AnyLayout(HStackLayout(spacing: 24)) : AnyLayout(VStackLayout(spacing: 0))
        return layout {
            VStack(spacing: 0, content: heading)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0, content: destination)
                .frame(maxWidth: .infinity)
        }
    }

    private var masthead: some View {
        ZStack {
            Image("AppLogo")
                .renderingMode(.template)
                .resizable().scaledToFit()
                .frame(width: 52, height: 52)
                .accessibilityLabel("WorldNiche")
            HStack {
                Button.haptic { showStreak = true } label: {
                    Label("\(social.quiz.streak)", systemImage: "flame.fill")
                        .font(.headline.monospacedDigit()).foregroundStyle(Palette.clay)
                        .padding(.horizontal, 10).frame(minHeight: 44)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("\(social.quiz.streak)-day streak")
                .accessibilityIdentifier("quizStreak")
                Spacer()
                Button.haptic { showAbout = true } label: {
                    Image(systemName: "info")
                        .scaledFont(size: 14, weight: .medium)
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("About WorldNiche")
            }
        }
        .foregroundStyle(Palette.pine)
        .padding(.top, 12)
    }

    private func globe(preferredHeight: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            WorldGlobeView(countries: CountryRepository.countries, selectedCountry: selected,
                           spinToken: spinToken, resetToken: globeResetToken,
                           onInteraction: { hasTouchedGlobe = true }) { country in
                selected = country
            }
            .accessibilityLabel("Interactive world globe")
            .accessibilityIdentifier("interactiveGlobe")
            .frame(minHeight: 160, idealHeight: preferredHeight, maxHeight: preferredHeight)

            Button.haptic { detail = selected } label: {
                HStack(spacing: 12) {
                    Text(selected.flag).scaledFont(size: 26)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selected.name).scaledFont(size: 16, weight: .semibold, design: .serif)
                        Text(selected.region.uppercased())
                            .scaledFont(size: 11, weight: .medium, design: .monospaced).tracking(1.5)
                    }
                }
                .foregroundStyle(Palette.pine)
                .padding(.horizontal, 18).padding(.vertical, 12)
                .glassEffect(.regular, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("landingCountry")
            .accessibilityHint("Opens discoveries from \(selected.name).")
            .padding(.bottom, 13)
        }
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 3) {
                Text(String(format: "%.1f° %@", abs(selected.latitude), selected.latitude >= 0 ? "N" : "S"))
                Text(String(format: "%.1f° %@", abs(selected.longitude), selected.longitude >= 0 ? "E" : "W"))
            }
            .scaledFont(size: 11, design: .monospaced)
            .foregroundStyle(Palette.muted.opacity(0.8))
            .padding(.leading, 30).padding(.top, 25)
            .accessibilityHidden(true)
        }
        .overlay(alignment: .topTrailing) {
            if hasTouchedGlobe {
                Button.haptic {
                    hasTouchedGlobe = false
                    globeResetToken += 1
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .foregroundStyle(Palette.pine)
                .accessibilityLabel("Reset globe view")
                .accessibilityHint("Zooms out and centers \(selected.name).")
                .accessibilityIdentifier("resetGlobe")
                .padding(.trailing, 24).padding(.top, 18)
            }
        }
    }
}
