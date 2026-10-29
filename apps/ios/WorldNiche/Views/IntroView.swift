import SwiftUI

struct IntroView: View {
    let explore: () -> Void
    let createProfile: () -> Void
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var page = 0
    @State private var previews = IntroPreviewStore()

    private var reduceMotion: Bool {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-worldniche-intro-reduced-motion") { return true }
        #endif
        return systemReduceMotion
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if page > 0 {
                    Button("Back", systemImage: "chevron.left") { move(to: page - 1) }
                        .labelStyle(.iconOnly)
                        .frame(width: 44, height: 44)
                        .accessibilityIdentifier("introBack")
                } else {
                    Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
                }
                Spacer()
                Button("Skip", action: explore)
                    .font(.subheadline.weight(.medium))
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("introSkip")
            }
            .padding(.horizontal, 24)

            GeometryReader { geometry in
                TabView(selection: $page) {
                    globePage(size: geometry.size)
                        .tag(0)
                        .accessibilityHidden(page != 0)
                    discoveriesPage(wide: usesWideLayout(geometry.size))
                        .tag(1)
                        .accessibilityHidden(page != 1)
                    friendsPage(size: geometry.size)
                        .tag(2)
                        .accessibilityHidden(page != 2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
        .background(Palette.paper.ignoresSafeArea())
        .foregroundStyle(Palette.pine)
        .safeAreaInset(edge: .bottom, spacing: 0) { controls }
        .onDisappear { previews.cancelLoading() }
    }

    private var controls: some View {
        VStack(spacing: 18) {
            HStack(spacing: 7) {
                ForEach(0..<3) { index in
                    Capsule().fill(index == page ? Palette.pine : Palette.line)
                        .frame(width: index == page ? 20 : 6, height: 6)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(page + 1) of 3")
            .accessibilityIdentifier("introProgress")

            if page == 2 {
                Button("Create your profile", action: createProfile)
                    .buttonStyle(.glassProminent).tint(Palette.forest)
                    .controlSize(.large)
                    .accessibilityIdentifier("introCreateProfile")
                Button("Continue exploring", action: explore)
                    .font(.subheadline)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("introContinueExploring")
            } else {
                Button("Continue") { move(to: page + 1) }
                    .buttonStyle(.glassProminent).tint(Palette.forest)
                    .controlSize(.large)
                    .accessibilityIdentifier("introContinue")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(Palette.paper)
    }

    private func usesWideLayout(_ size: CGSize) -> Bool {
        size.width >= 720 && size.width > size.height * 1.3 && !dynamicTypeSize.isAccessibilitySize
    }

    private func globePage(size: CGSize) -> some View {
        let wide = usesWideLayout(size)
        return ScrollView {
            Group {
                if wide {
                    HStack(spacing: 36) {
                        globeIntroduction(logoSize: 70)
                            .frame(maxWidth: 390)
                        demoGlobe(height: max(220, min(320, size.height - 72)))
                            .frame(maxWidth: 360)
                    }
                    .frame(minHeight: max(0, size.height - 32))
                } else {
                    VStack(spacing: 20) {
                        globeIntroduction(logoSize: size.height < 480 ? 60 : 88)
                        demoGlobe(height: max(180, min(320, size.height * 0.45)))
                    }
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 20)
            .padding(.horizontal, 28)
            .frame(maxWidth: wide ? 900 : 560)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityIdentifier("introScroll0")
    }

    private func globeIntroduction(logoSize: CGFloat) -> some View {
        VStack(spacing: 20) {
            Image("AppLogo")
                .resizable().scaledToFit()
                .frame(width: logoSize, height: logoSize)
                .accessibilityHidden(true)
            introduction(title: "A little more world,\nevery day.",
                         detail: "Turn the globe or tap a country. Let curiosity choose your next stop.", index: 0)
        }
    }

    private func demoGlobe(height: CGFloat) -> some View {
        VStack(spacing: 20) {
            WorldGlobeView(countries: CountryRepository.countries, selectedCountry: nil, spinToken: 0,
                           allowsCountrySelection: false, onSelect: { _ in })
                .frame(height: height)
                .accessibilityIdentifier("introDemoGlobe")
            Text("Give it a spin.")
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
        }
    }

    private func discoveriesPage(wide: Bool) -> some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 12) {
                    discoverySection(.music, title: "A song to bring home", symbol: "music.note")
                    discoverySection(.news, title: "A new point of view", symbol: "newspaper")
                    discoverySection(.culture, title: "Something only locals know", symbol: "sparkle.magnifyingglass")
                }
                introduction(title: "Get to know\nthe little things.",
                             detail: "Hear what’s playing, catch up on local news, and discover the details that make a place its own.", index: 1)
            }
            .padding(.top, 24)
            .padding(.horizontal, 28)
            .padding(.bottom, 20)
            .frame(maxWidth: wide ? 680 : 560)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityIdentifier("introScroll1")
    }

    private func friendsPage(size: CGSize) -> some View {
        let wide = usesWideLayout(size)
        return ScrollView {
            Group {
                if wide {
                    HStack(spacing: 36) {
                        friendsIntroduction.frame(maxWidth: 370)
                        invitationPreview.frame(maxWidth: 430)
                    }
                    .frame(minHeight: max(0, size.height - 40))
                } else {
                    VStack(spacing: 28) {
                        friendsIntroduction
                        invitationPreview
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, wide ? 20 : 32)
            .padding(.bottom, 20)
            .frame(maxWidth: wide ? 900 : 560)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityIdentifier("introScroll2")
    }

    private var friendsIntroduction: some View {
        introduction(title: "Curiosity is better\ntogether.",
                     detail: "Choose your name, add a photo if you like, and discover what your friends are exploring.", index: 2)
    }

    private var invitationPreview: some View {
        VStack(spacing: 28) {
            IntroFriendConnection(isActive: page == 2, reduceMotion: reduceMotion)
                .frame(height: dynamicTypeSize.isAccessibilitySize ? 280 : 240)
            Text("Send a link. Share a little world.")
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
        }
    }

    private func introduction(title: String, detail: String, index: Int) -> some View {
        VStack(spacing: 18) {
            Text(title)
                .scaledFont(size: 38, design: .serif)
                .tracking(-1)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("introTitle\(index)")
            Text(detail)
                .font(.body)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
    }

    private func discoverySection(_ category: IntroPreviewCategory, title: String, symbol: String) -> some View {
        let expanded = previews.expanded == category
        return VStack(spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                    previews.toggle(category)
                }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: symbol).font(.title3).frame(width: 28)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: expanded ? "minus" : "plus")
                        .font(.caption.weight(.semibold))
                        .accessibilityHidden(true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            .accessibilityHint(expanded ? "Hide this preview." : "Show a preview from the United States.")
            .accessibilityIdentifier(buttonID(category))
            if expanded {
                VStack(alignment: .leading, spacing: 14) {
                    Divider().overlay(Palette.line)
                    switch category {
                    case .music: musicPreview
                    case .news: newsPreview
                    case .culture: culturePreview
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(contentID(category))
                .transition(.opacity)
            }
        }
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Palette.line, lineWidth: 0.7))
    }

    @ViewBuilder
    private var musicPreview: some View {
        previewHeading("Top five in the United States", source: "Apple Music chart")
        if previews.musicLoading {
            ProgressView("Finding what’s playing…").font(.subheadline)
        } else if previews.musicUnavailable {
            previewRetry("The chart couldn’t load. Try again when you’re connected.", id: "introMusicRetry", action: previews.retryMusic)
        } else {
            ForEach(Array(previews.tracks.enumerated()), id: \.element.id) { index, track in
                HStack(alignment: .center, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Palette.muted)
                        .frame(width: 16)
                    AsyncImage(url: track.artworkURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 7).fill(Palette.line)
                            .overlay(Image(systemName: "music.note").foregroundStyle(Palette.pine))
                    }
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title).font(.subheadline.weight(.medium))
                        Text(track.artist).font(.caption).foregroundStyle(Palette.muted)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("introTrack\(index)")
            }
            if let fetchedAt = previews.musicFetchedAt, !previews.tracks.isEmpty {
                Text("Updated \(fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2).foregroundStyle(Palette.muted)
            }
        }
    }

    @ViewBuilder
    private var newsPreview: some View {
        previewHeading("A view of the United States", source: "Recent headlines · Google News")
        if previews.newsLoading {
            ProgressView("Finding the latest stories…").font(.subheadline)
        } else if previews.newsUnavailable {
            previewRetry("The headlines couldn’t load. You can try again in a moment.", id: "introNewsRetry", action: previews.retryNews)
        } else {
            ForEach(Array(previews.stories.enumerated()), id: \.element.id) { index, story in
                Link(destination: story.url) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(story.title).font(.subheadline.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(story.source).font(.caption).foregroundStyle(Palette.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5)
                }
                .accessibilityIdentifier("introStory\(index)")
            }
            if let fetchedAt = previews.newsFetchedAt, !previews.stories.isEmpty {
                Text("Updated \(fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2).foregroundStyle(Palette.muted)
            }
        }
    }

    @ViewBuilder
    private var culturePreview: some View {
        if let insight = CountryRepository.insightsByCountry["US"]?.first {
            previewHeading("A little more local", source: "United States")
            Text(insight.title).font(.headline)
            Text(insight.body).font(.subheadline)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            Link(insight.sourceName, destination: insight.sourceURL)
                .font(.caption.weight(.medium))
        } else {
            Text("Every place has its own everyday rituals. Discover one when you start exploring.")
                .font(.subheadline).foregroundStyle(Palette.muted)
        }
    }

    private func previewHeading(_ title: String, source: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(source).font(.caption).foregroundStyle(Palette.muted)
        }
    }

    private func previewRetry(_ message: String, id: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message).font(.subheadline).foregroundStyle(Palette.muted)
            Button("Try again", action: action)
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
                .accessibilityIdentifier(id)
        }
    }

    private func buttonID(_ category: IntroPreviewCategory) -> String {
        switch category {
        case .music: "introMusicPreview"
        case .news: "introNewsPreview"
        case .culture: "introCulturePreview"
        }
    }

    private func contentID(_ category: IntroPreviewCategory) -> String {
        switch category {
        case .music: "introMusicContent"
        case .news: "introNewsContent"
        case .culture: "introCultureContent"
        }
    }

    private func move(to nextPage: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { page = nextPage }
    }
}

private struct IntroFriendConnection: View {
    let isActive: Bool
    let reduceMotion: Bool
    @State private var beganAt = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || !isActive)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(beganAt)).truncatingRemainder(dividingBy: 6)
            let travel = min(1, max(0, (elapsed - 0.7) / 2.4))
            let connected = reduceMotion || elapsed >= 3.1
            VStack(spacing: 26) {
                HStack(alignment: .center, spacing: 12) {
                    friend("Ari", image: "IntroAvatarA", connected: connected)
                    GeometryReader { geometry in
                        let distance = max(0, geometry.size.width - 30)
                        ZStack {
                            Capsule().fill(Palette.pine.opacity(connected ? 0.35 : 0.12))
                                .frame(height: 2)
                            Image(systemName: reduceMotion ? "link" : "envelope.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(Palette.pine)
                                .frame(width: 38, height: 38)
                                .background(Palette.card, in: Circle())
                                .overlay(Circle().stroke(Palette.line, lineWidth: 1))
                                .offset(x: reduceMotion ? 0 : (travel - 0.5) * distance,
                                        y: reduceMotion ? 0 : -sin(travel * .pi) * 12)
                                .opacity(reduceMotion || elapsed < 3.1 ? 1 : 0)
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                    .frame(height: 90)
                    friend("Sam", image: "IntroAvatarB", connected: connected)
                }
                Text(connected ? "You’re connected" : "An invite is on its way")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.muted)
                    .contentTransition(.opacity)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: 430, maxHeight: .infinity)
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("An invitation connects two friends")
        .accessibilityValue(reduceMotion ? "Connected" : "Invitation animation")
        .accessibilityIdentifier("introInviteAnimation")
        .onChange(of: isActive) { _, active in
            if active { beganAt = Date() }
        }
    }

    private func friend(_ name: String, image: String, connected: Bool) -> some View {
        VStack(spacing: 10) {
            Image(image)
                .resizable().scaledToFit()
                .frame(width: 100, height: 100)
                .offset(y: 12)
                .frame(width: 100, height: 100)
                .background(Palette.card, in: Circle())
                .clipShape(Circle())
                .overlay(Circle().stroke(Palette.pine.opacity(connected ? 0.35 : 0.12), lineWidth: 2))
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 25, height: 25)
                        .background(Palette.forest, in: Circle())
                        .opacity(connected ? 1 : 0)
                }
            Text(name).font(.subheadline.weight(.medium))
        }
        .frame(width: 100)
    }
}
