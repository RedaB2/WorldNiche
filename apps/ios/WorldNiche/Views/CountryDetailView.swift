import SwiftUI

struct CountryDetailView: View {
    let country: Country
    @Environment(\.dismiss) private var dismiss
    @Environment(DiscoveryJournal.self) private var journal
    @Environment(SocialStore.self) private var social
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var currentProgress = CountryReadingProgress()
    @State private var scrollPhase = ScrollPhase.idle
    @State private var bottomPull = false
    @State private var showsGlobe = true
    @State private var globeResetToken = 0
    @State private var music: FeedSnapshot<MusicTrack>?
    @State private var musicLoading = true
    @State private var musicRequestID = UUID()
    @State private var musicRefreshID = 0
    @State private var showCompanion = false
    @State private var refreshID = 0
    private static let feedService = DiscoveryFeedService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    countryHeader
                    historicalFactSection
                    musicSection
                    Text("A country contains many cultures. Use these discoveries as invitations to ask, never assumptions about a person.")
                        .scaledFont(size: 12).lineSpacing(4).foregroundStyle(Palette.muted)
                        .padding(.horizontal, 4)
                    CountryFriendsView(country: country)
                    CountryExplorationFinish(country: country, ready: readingProgress.isReady,
                        explored: isExplored, pulling: bottomPull && scrollPhase == .interacting,
                        onComplete: {
                            saveReadingProgress()
                            journal.completeExploration(country)
                        })
                }
                .padding(24)
                .padding(.bottom, 80)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("countryReadingScroll")
            .onScrollPhaseChange { _, phase in
                scrollPhase = phase
                if phase == .idle { saveReadingProgress() }
            }
            .onScrollGeometryChange(for: Double.self) { geometry in
                CountryReadingProgress.scrollFraction(offset: geometry.contentOffset.y,
                    contentHeight: geometry.contentSize.height, viewportHeight: geometry.containerSize.height,
                    topInset: geometry.contentInsets.top)
            } action: { _, fraction in
                guard scenePhase == .active, !showCompanion, !isExplored,
                      scrollPhase == .interacting || scrollPhase == .decelerating else { return }
                var progress = readingProgress
                progress.record(fraction)
                currentProgress = progress
                // Keep the bar continuous while coalescing persistent writes to whole percentages.
                if Int(progress.fraction * 100) > Int(journal.readingProgress(for: country.id).fraction * 100) {
                    saveReadingProgress()
                }
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                // SwiftUI's container size already excludes its content insets.
                let end = max(-geometry.contentInsets.top,
                    geometry.contentSize.height - geometry.containerSize.height - geometry.contentInsets.top)
                return geometry.contentOffset.y - end > 44
            } action: { _, pulling in bottomPull = pulling }
            .onDisappear { saveReadingProgress() }
            .onChange(of: scenePhase) { _, phase in if phase != .active { saveReadingProgress() } }
            .safeAreaInset(edge: .top, spacing: 0) {
                CountryReadingHeader(progress: readingProgress, explored: isExplored)
            }
            .background(Palette.paper)
            .navigationTitle("A little more local")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(journal.savedIDs.contains(country.id) ? "Unsave country" : "Save country", systemImage: journal.savedIDs.contains(country.id) ? "bookmark.fill" : "bookmark") {
                        journal.toggleSaved(country)
                    }.labelStyle(.iconOnly).accessibilityIdentifier("saveCountry")
                    ShareLink(item: "I’m exploring \(country.name) with WorldNiche. \(country.historicalFact?.title ?? "A little more local.")") {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button { showCompanion = true } label: {
                    HStack {
                        Image(systemName: "sparkle")
                        Text("Curious? Ask Niche").fontWeight(.medium)
                        Spacer()
                    }
                    .scaledFont(size: 14)
                    .padding(.horizontal, 20).padding(.vertical, 18)
                    .foregroundStyle(Palette.pine)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .accessibilityIdentifier("askNiche")
                .padding(.horizontal, 24).padding(.bottom, 8)
            }
            .sheet(isPresented: $showCompanion) { CompanionView(country: country, music: music) }
            .task(id: "\(country.id)-music-\(musicRefreshID)-\(refreshID)") {
                await loadMusic(forceRefresh: musicRefreshID > 0 || refreshID > 0)
            }
            .refreshLiveContent { refreshID += 1 }
            .refreshSocialProfiles(enabled: social.isSignedIn)
            .refreshable { await loadMusic(forceRefresh: true) }
        }
    }

    private var isExplored: Bool { journal.visitedIDs.contains(country.id) }
    private var readingProgress: CountryReadingProgress {
        var progress = currentProgress
        progress.record(journal.readingProgress(for: country.id).fraction)
        return progress
    }

    private func saveReadingProgress() {
        journal.saveReadingProgress(readingProgress, for: country)
    }

    @ViewBuilder
    private var historicalFactSection: some View {
        if let fact = country.historicalFact {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: "A little history")
                Text(fact.title)
                    .scaledFont(size: 26, design: .serif).foregroundStyle(Palette.pine)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("historicalFactTitle")
                Text(fact.body)
                    .scaledFont(size: 16).lineSpacing(5).foregroundStyle(Palette.pine)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("historicalFactBody")
                Link(destination: fact.sourceURL) {
                    Label(fact.sourceName, systemImage: "book")
                        .scaledFont(size: 13, weight: .medium)
                        .multilineTextAlignment(.leading)
                        .frame(minHeight: 44, alignment: .leading)
                }
                .accessibilityLabel("Historical source, \(fact.sourceName)")
                .accessibilityIdentifier("historicalFactSource")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .editorialCard()
        }
    }

    private func loadMusic(forceRefresh: Bool) async {
        #if DEBUG && targetEnvironment(simulator)
        if CountryReadingFixture.mode != nil {
            music = CountryReadingFixture.music()
            musicLoading = false
            return
        }
        #endif
        let requestID = UUID()
        musicRequestID = requestID
        musicLoading = true
        let result = await Self.feedService.fetchMusic(for: country, forceRefresh: forceRefresh)
        if !Task.isCancelled && musicRequestID == requestID {
            music = result
            musicLoading = false
        }
    }

    private var countryHeader: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Eyebrow(text: "\(country.region) · \(country.id)")
                Spacer()
                Text(country.flag).scaledFont(size: 44)
            }
            Text(country.name)
                .scaledFont(size: 48, weight: .regular, design: .serif)
                .tracking(-2).foregroundStyle(Palette.pine)
                .accessibilityIdentifier("countryTitle")
            Text(country.overview)
                .scaledFont(size: 16).lineSpacing(5).foregroundStyle(Palette.pine)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .accessibilityIdentifier("countryOverview")
            Link(country.overviewSourceName, destination: country.overviewSourceURL)
                .scaledFont(size: 13, weight: .medium)
                .accessibilityIdentifier("countryOverviewSource")
            countryLocation
            Rectangle().fill(Palette.line).frame(height: 1).padding(.top, 8)
        }
    }

    private var countryLocation: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                        showsGlobe.toggle()
                    }
                } label: {
                    Label(showsGlobe ? "Hide globe" : "Show on globe", systemImage: "globe.europe.africa")
                        .scaledFont(size: 13, weight: .medium)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("toggleCountryGlobe")
                .accessibilityValue(showsGlobe ? "Expanded" : "Collapsed")
                Spacer()
                if showsGlobe {
                    Button { globeResetToken += 1 } label: {
                        Image(systemName: "location")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                        .accessibilityLabel("Recenter")
                        .accessibilityHint("Return to \(country.name)")
                        .accessibilityIdentifier("recenterCountryGlobe")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.pine)

            if showsGlobe {
                WorldGlobeView(countries: [country], selectedCountry: country, spinToken: 0,
                    resetToken: globeResetToken, allowsCountrySelection: false, mode: .location,
                    onSelect: { _ in })
                    .frame(height: 250)
                    .frame(maxWidth: 420)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("countryLocationGlobe")
                    .accessibilityAction(named: "Recenter") { globeResetToken += 1 }
                Text("Drag to explore")
                    .scaledFont(size: 11)
                    .foregroundStyle(Palette.muted)
                    .padding(.top, 4)
                    .accessibilityHidden(true)
            }
        }
    }

    private var musicSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeading("On repeat", subtitle: "\(music?.items.first?.provider.rawValue.uppercased() ?? "MUSIC CHART") · \(country.name.uppercased())", icon: "waveform")
            if let music, let provider = music.items.first?.provider {
                VStack(spacing: 0) {
                    ForEach(Array(music.items.prefix(5).enumerated()), id: \.element.id) { index, track in
                        Link(destination: track.url) {
                            HStack(spacing: 12) {
                                Text(String(format: "%02d", index + 1))
                                    .scaledFont(size: 11, design: .monospaced)
                                    .foregroundStyle(Palette.muted).frame(width: 20)
                                AsyncImage(url: track.artworkURL) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    ZStack { Palette.pine.opacity(0.08); Image(systemName: "music.note").foregroundStyle(Palette.pine) }
                                }.frame(width: 49, height: 49).clipShape(RoundedRectangle(cornerRadius: 9))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(track.title).scaledFont(size: 14, weight: .medium).foregroundStyle(Palette.pine).lineLimit(1)
                                    Text(track.artist).scaledFont(size: 12).foregroundStyle(Palette.muted).lineLimit(1)
                                    if let sample = track.radioSample {
                                        Text(sample).scaledFont(size: 11).foregroundStyle(Palette.muted)
                                    }
                                }
                                Spacer(minLength: 4)
                            }.padding(.vertical, 10)
                        }
                        .accessibilityIdentifier("musicTrack-\(index)")
                        if index < min(music.items.count, 5) - 1 { Divider().overlay(Palette.line) }
                    }
                }
                Text(provider.chartDescription)
                    .scaledFont(size: 11).lineSpacing(3).foregroundStyle(Palette.muted)
                if provider == .tuneping {
                    Text("Tap a song to see its recording details on MusicBrainz.")
                        .scaledFont(size: 12).foregroundStyle(Palette.muted)
                    Link("Data by Tuneping", destination: URL(string: "https://tuneping.com")!)
                        .scaledFont(size: 13, weight: .medium)
                }
                updatedLabel(music.fetchedAt)
            } else if musicLoading {
                loadingRow("Finding the local soundtrack…").accessibilityIdentifier("musicLoading")
            } else {
                unavailable(music?.unavailable ?? "A chart isn’t available for this country right now.", retryID: "retryMusic") {
                    musicRefreshID += 1
                }
            }
        }
    }

    private func sectionHeading(_ title: String, subtitle: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).scaledFont(size: 28, design: .serif).tracking(-0.5)
                Spacer()
                Image(systemName: icon).scaledFont(size: 19, weight: .light).foregroundStyle(Palette.clay)
            }.foregroundStyle(Palette.pine)
            Eyebrow(text: subtitle)
        }
    }

    private func unavailable(_ message: String, retryID: String, retry: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message).scaledFont(size: 13).foregroundStyle(Palette.muted)
            Button("Try again", action: retry).scaledFont(size: 12, weight: .semibold)
                .accessibilityIdentifier(retryID)
        }.frame(maxWidth: .infinity, alignment: .leading).editorialCard()
    }

    private func loadingRow(_ title: String) -> some View {
        HStack(spacing: 12) { ProgressView(); Text(title).scaledFont(size: 13).foregroundStyle(Palette.muted) }
            .frame(maxWidth: .infinity, alignment: .leading).editorialCard()
    }

    private func updatedLabel(_ date: Date) -> some View {
        Text("Checked \(date.formatted(date: .abbreviated, time: .shortened))")
            .scaledFont(size: 11, design: .monospaced).foregroundStyle(Palette.muted)
    }
}
