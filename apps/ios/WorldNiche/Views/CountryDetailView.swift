import SwiftUI

struct CountryDetailView: View {
    let country: Country
    @Environment(\.dismiss) private var dismiss
    @Environment(DiscoveryJournal.self) private var journal
    @State private var music: FeedSnapshot<MusicTrack>?
    @State private var news: FeedSnapshot<NewsStory>?
    @State private var musicLoading = true
    @State private var newsLoading = true
    @State private var musicRequestID = UUID()
    @State private var newsRequestID = UUID()
    @State private var musicRefreshID = 0
    @State private var newsRefreshID = 0
    @State private var cultureReading: CultureReading?
    @State private var cultureMessage: String?
    @State private var cultureLoaded = false
    @State private var cultureLoading = false
    @State private var cultureRequestID = UUID()
    @State private var cultureRotation = 0
    @State private var cultureSessionID = UUID()
    @State private var showCompanion = false
    @State private var refreshID = 0
    private static let feedService = DiscoveryFeedService()
    private static let cultureService = LiveCultureService.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    countryHeader
                    liveCultureSection
                    musicSection
                    newsSection
                    Text("A country contains many cultures. Use these discoveries as invitations to ask, never assumptions about a person.")
                        .scaledFont(size: 12).lineSpacing(4).foregroundStyle(Palette.muted)
                        .padding(.horizontal, 4)
                    CountryFriendsView(country: country)
                }
                .padding(24)
                .padding(.bottom, 80)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
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
                    ShareLink(item: "I’m exploring \(country.name) with WorldNiche. \(cultureReading?.title ?? country.insights.first?.title ?? "A little more local.")") {
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
                .disabled(!cultureLoaded || cultureLoading)
                .padding(.horizontal, 24).padding(.bottom, 8)
            }
            .sheet(isPresented: $showCompanion) { CompanionView(country: country, feed: feed, reading: cultureReading) }
            .task(id: "\(country.id)-music-\(musicRefreshID)-\(refreshID)") {
                journal.visit(country)
                await loadMusic(forceRefresh: musicRefreshID > 0 || refreshID > 0)
            }
            .task(id: "\(country.id)-news-\(newsRefreshID)-\(refreshID)") {
                await loadNews(forceRefresh: newsRefreshID > 0 || refreshID > 0)
            }
            .refreshLiveContent { refreshID += 1 }
            .task(id: "\(country.id)-\(cultureRotation)-\(refreshID)") { await loadCulture(forceRefresh: cultureRotation > 0) }
            .refreshable {
                async let music: () = loadMusic(forceRefresh: true)
                async let news: () = loadNews(forceRefresh: true)
                async let culture: () = loadCulture(forceRefresh: true)
                _ = await (music, news, culture)
            }
        }
    }

    private func loadCulture(forceRefresh: Bool) async {
        let requestID = UUID()
        cultureRequestID = requestID
        cultureLoading = true
        let result = await Self.cultureService.fetch(for: country, rotation: cultureRotation, forceRefresh: forceRefresh, discoverySessionID: cultureSessionID)
        if !Task.isCancelled && cultureRequestID == requestID {
            cultureReading = result.reading
            cultureMessage = result.message
            cultureLoaded = true
            cultureLoading = false
        }
    }

    private var liveCultureSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            sectionHeading("The local lens", subtitle: cultureLoaded && cultureReading == nil ? "SAVED CULTURAL NOTE" : "TODAY’S CULTURAL DISCOVERY", icon: "book.pages")
            if let reading = cultureReading {
                if let image = reading.image {
                    cultureImage(image)
                }
                Text(reading.displayTitle).scaledFont(size: 24, design: .serif).foregroundStyle(Palette.pine)
                    .accessibilityIdentifier("liveCultureTitle")
                Text(reading.displayBody).scaledFont(size: 15).lineSpacing(5).foregroundStyle(Palette.muted)
                    .textSelection(.enabled)
                if let fact = reading.generatedFact, !fact.conversationStarter.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(text: "A conversation starter")
                        Text(fact.conversationStarter).scaledFont(size: 14).lineSpacing(4)
                            .foregroundStyle(Palette.pine)
                    }.padding(.vertical, 8)
                }
                Link("Read on Wikipedia", destination: reading.sourceURL).font(.footnote)
                    .frame(minHeight: 44, alignment: .leading)
                HStack(alignment: .top) {
                    Text(reading.generatedFact == nil ? "Wikipedia contributors · source excerpt" : "AI-selected detail · from the linked source")
                    Link("CC BY-SA 4.0", destination: URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!)
                }.font(.caption2).foregroundStyle(Palette.muted)
                updatedLabel(reading.fetchedAt)
            } else if !cultureLoaded {
                loadingRow("Following a local cultural thread…")
            }
            if let message = cultureMessage {
                Text(message).font(.footnote).foregroundStyle(Palette.muted)
            }
            if cultureLoaded && cultureReading == nil {
                Eyebrow(text: "Saved source note · reviewed Oct 17, 2026")
                if let insight = country.insights.first {
                    Text(insight.title).scaledFont(size: 24, design: .serif).foregroundStyle(Palette.pine)
                    Text(insight.body).scaledFont(size: 15).lineSpacing(5).foregroundStyle(Palette.muted)
                    Link(insight.sourceName, destination: insight.sourceURL).font(.footnote)
                }
            }
            if cultureLoaded {
                Button { cultureRotation += 1 } label: {
                    Label("Show me another", systemImage: "shuffle")
                }.font(.footnote).buttonStyle(.glass).controlSize(.regular)
                .disabled(cultureLoading)
                .accessibilityIdentifier("anotherDiscovery")
                if cultureLoading { ProgressView("Finding another thread…").font(.footnote) }
            }
        }.editorialCard()
    }

    private func cultureImage(_ image: CultureImage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: image.url) { phase in
                if let photo = phase.image {
                    photo.resizable().scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 210)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .accessibilityLabel("Photo illustrating \(cultureReading?.title ?? country.name)")
                }
            }
            HStack(alignment: .top, spacing: 6) {
                Link(image.attribution, destination: image.sourceURL)
                if let licenseURL = image.licenseURL {
                    Link(image.license, destination: licenseURL)
                }
            }.font(.caption2).foregroundStyle(Palette.muted)
        }
    }

    private var feed: CountryFeed? {
        guard music != nil || news != nil else { return nil }
        return CountryFeed(
            tracks: music?.items ?? [], stories: news?.items ?? [],
            musicFetchedAt: music?.fetchedAt, newsFetchedAt: news?.fetchedAt,
            musicUnavailable: music?.unavailable, newsUnavailable: news?.unavailable
        )
    }

    private func loadMusic(forceRefresh: Bool) async {
        let requestID = UUID()
        musicRequestID = requestID
        musicLoading = true
        let result = await Self.feedService.fetchMusic(for: country, forceRefresh: forceRefresh)
        if !Task.isCancelled && musicRequestID == requestID {
            music = result
            musicLoading = false
        }
    }

    private func loadNews(forceRefresh: Bool) async {
        let requestID = UUID()
        newsRequestID = requestID
        newsLoading = true
        let result = await Self.feedService.fetchNews(for: country, forceRefresh: forceRefresh)
        if !Task.isCancelled && newsRequestID == requestID {
            news = result
            newsLoading = false
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
            Label(country.capital, systemImage: "mappin")
                .scaledFont(size: 13).foregroundStyle(Palette.muted)
            Rectangle().fill(Palette.line).frame(height: 1).padding(.top, 8)
        }
    }

    private var musicSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeading("On repeat", subtitle: "APPLE MUSIC · \(country.name.uppercased())", icon: "waveform")
            if let music, !music.items.isEmpty {
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
                                }
                                Spacer(minLength: 4)
                            }.padding(.vertical, 10)
                        }
                        .accessibilityIdentifier("musicTrack-\(index)")
                        if index < min(music.items.count, 5) - 1 { Divider().overlay(Palette.line) }
                    }
                }
                Text("Most-played songs in this Apple Music storefront. One listening community, not a whole country.")
                    .scaledFont(size: 11).lineSpacing(3).foregroundStyle(Palette.muted)
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

    private var newsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeading("In the conversation", subtitle: "HEADLINES ABOUT \(country.name.uppercased())", icon: "text.alignleft")
            if let news, !news.items.isEmpty {
                ForEach(news.items.prefix(4)) { story in
                    Link(destination: story.url) {
                        VStack(alignment: .leading, spacing: 11) {
                            HStack {
                                Text(story.source.uppercased()).scaledFont(size: 11, weight: .medium, design: .monospaced).tracking(1)
                                Spacer()
                            }.foregroundStyle(Palette.muted)
                            Text(story.title).scaledFont(size: 19, design: .serif).foregroundStyle(Palette.pine).multilineTextAlignment(.leading)
                            if let date = story.publishedAt {
                                Text(date, style: .relative).scaledFont(size: 11).foregroundStyle(Palette.muted)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).editorialCard()
                    }.accessibilityIdentifier("newsStory-\(story.id)")
                }
                Text("English-language coverage via Google News. Headlines are links to reporting, not verified cultural facts.")
                    .scaledFont(size: 11).lineSpacing(3).foregroundStyle(Palette.muted)
                updatedLabel(news.fetchedAt)
            } else if newsLoading {
                loadingRow("Opening a window to today…").accessibilityIdentifier("newsLoading")
            } else {
                unavailable(news?.unavailable ?? "Headlines are unavailable right now.", retryID: "retryNews") {
                    newsRefreshID += 1
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
