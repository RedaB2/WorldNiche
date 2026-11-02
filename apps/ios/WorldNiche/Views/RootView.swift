import SwiftUI

struct RootView: View {
    @Environment(SocialStore.self) private var social
    @Environment(DiscoveryJournal.self) private var journal
    @State private var selectedTab = RootTab.discover
    @State private var introResolved = false
    @State private var presentsIntro = false
    @State private var presentsIntroSignIn = false
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
                    Tab("Discover", systemImage: "globe.europe.africa", value: RootTab.discover) { ExploreView() }
                    Tab("Atlas", systemImage: "square.grid.2x2", value: RootTab.atlas) { AtlasView() }
                    Tab("Journal", systemImage: "bookmark", value: RootTab.journal) { JournalView() }
                    Tab("Profile", systemImage: "person.crop.circle", value: RootTab.profile) { ProfileView() }
                }
                .tabBarMinimizeBehavior(.onScrollDown)
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
    @Environment(DiscoveryJournal.self) private var journal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected = CountryRepository.country(id: "MA") ?? CountryRepository.countries[0]
    @State private var spinToken = 0
    @State private var globeResetToken = 0
    @State private var hasTouchedGlobe = false
    @State private var isSpinning = false
    @State private var detail: Country?
    @State private var showAbout = false

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        masthead
                        Text("The world is full\nof little wonders.")
                            .scaledFont(size: 39, weight: .regular, design: .serif)
                            .tracking(-1.5)
                            .lineSpacing(-2)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Palette.pine)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("discoverHeadline")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 30)

                        HStack(spacing: 6) {
                            Image(systemName: "hand.draw").accessibilityHidden(true)
                            Text("Drag to turn. Pinch to zoom. Two fingers to move.")
                                .accessibilityIdentifier("discoverGuidance")
                        }
                        .scaledFont(size: 11)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Palette.muted)
                        .padding(.top, 12)

                        globe(height: max(200, min(geometry.size.width - 30, 355)))
                            .padding(.horizontal, -26)
                            .padding(.top, 2)

                        Button {
                            guard !isSpinning else { return }
                            isSpinning = true
                            selected = CountryRepository.random(excluding: selected.id)
                            spinToken += 1
                            journal.visit(selected)
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
                            .padding(.top, 13)
                            .padding(.bottom, 28)
                    }
                    .padding(.horizontal, 26)
                    .frame(maxWidth: 620)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
            .background(Palette.paper)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $detail) { CountryDetailView(country: $0) }
            .sheet(isPresented: $showAbout) { AboutView() }
        }
    }

    private var masthead: some View {
        HStack(alignment: .center) {
            Image("AppLogo")
                .renderingMode(.template)
                .resizable().scaledToFit()
                .frame(width: 52, height: 52)
                .accessibilityLabel("WorldNiche")
            Spacer()
            Button { showAbout = true } label: {
                Image(systemName: "info")
                    .scaledFont(size: 14, weight: .medium)
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("About WorldNiche")
        }
        .foregroundStyle(Palette.pine)
        .padding(.top, 12)
    }

    private func globe(height: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            WorldGlobeView(countries: CountryRepository.countries, selectedCountry: selected,
                           spinToken: spinToken, resetToken: globeResetToken,
                           onInteraction: { hasTouchedGlobe = true }) { country in
                selected = country
                journal.visit(country)
            }
            .accessibilityLabel("Interactive world globe")
            .accessibilityIdentifier("interactiveGlobe")
            .frame(height: height)

            Button { detail = selected } label: {
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
                Button {
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
