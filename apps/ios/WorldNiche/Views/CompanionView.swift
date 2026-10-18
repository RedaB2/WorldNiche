import SwiftUI

struct CompanionView: View {
    let country: Country
    let feed: CountryFeed?
    var reading: CultureReading? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var companion = CompanionService()
    @State private var question = ""
    @FocusState private var composerFocused: Bool

    private let paper = Palette.paper
    private let pine = Palette.pine
    private let clay = Palette.clay

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        introduction
                        if !companion.availability.isAvailable {
                            unavailableActions
                        }
                        if companion.messages.isEmpty {
                            if companion.availability.isAvailable {
                                suggestions
                            }
                            sources
                        } else {
                            conversation
                            if !companion.isGenerating { sources }
                        }
                        if let error = companion.errorMessage {
                            VStack(alignment: .leading, spacing: 12) {
                                Label(error, systemImage: "info.circle")
                                    .font(.footnote)
                                if companion.availability.isAvailable,
                                   let previousQuestion = companion.messages.last(where: { $0.isUser })?.text {
                                    Button("Try again") { send(previousQuestion) }
                                        .font(.footnote.weight(.semibold))
                                        .disabled(companion.isGenerating)
                                }
                            }
                            .foregroundStyle(pine.opacity(0.8))
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(clay.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
                            .accessibilityAddTraits(.updatesFrequently)
                        }
                        Color.clear.frame(height: 1).id("conversation-end")
                    }
                    .padding(24)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: companion.messages.count) {
                    withAnimation(.easeOut(duration: 0.25)) {
                        scroll.scrollTo("conversation-end", anchor: .bottom)
                    }
                }
                .onChange(of: companion.isGenerating) { _, generating in
                    if !generating {
                        withAnimation(.easeOut(duration: 0.25)) {
                            scroll.scrollTo("conversation-end", anchor: .bottom)
                        }
                    }
                }
            }
            .background(paper)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if companion.availability.isAvailable || companion.isGenerating { composer }
            }
            .navigationTitle("Ask Niche")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("Close companion")
                }
            }
        }
        .tint(pine)
        .foregroundStyle(pine)
        .presentationDragIndicator(.visible)
        .task(id: contextID) {
            question = ""
            companion.reset()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { companion.refreshAvailability() }
        }
        .onDisappear { companion.cancel() }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text(country.flag)
                Text(country.name.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(1.7)
                Spacer()
                Image(systemName: "sparkles")
                    .foregroundStyle(clay)
                    .accessibilityHidden(true)
            }
            Text(companion.availability.title)
                .scaledFont(size: 34, weight: .regular, design: .serif)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(introductionDetail)
                .font(.subheadline)
                .foregroundStyle(pine.opacity(0.7))
                .lineSpacing(4)
        }
    }

    private var introductionDetail: String {
        if companion.availability.isAvailable, let reading {
            return "Ask about “\(reading.title)” and the music or headlines loaded here."
        }
        return companion.availability.detail
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FOLLOW YOUR CURIOSITY")
                .font(.caption2.weight(.semibold))
                .tracking(1.5)
                .foregroundStyle(pine.opacity(0.55))
            ForEach(suggestedQuestions, id: \.self) { suggestion in
                Button {
                    send(suggestion)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text(suggestion)
                            .font(.subheadline)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 17))
                    .overlay(RoundedRectangle(cornerRadius: 17).stroke(pine.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .disabled(companion.isGenerating)
            }
        }
    }

    private var suggestedQuestions: [String] {
        var result: [String] = []
        if let reading {
            result.append("What does “\(reading.title)” mean in this excerpt?")
            result.append("How could I bring this up in a conversation?")
        } else if let insight = country.insights.first {
            result.append("Tell me more about “\(insight.title)”.")
            result.append("How could I bring this up in a conversation?")
        }
        if feed?.tracks.isEmpty == false {
            result.append("What does this chart tell us about \(country.name)’s music?")
        } else if result.isEmpty {
            result.append("What can we learn from the sources here?")
        }
        return result
    }

    private var unavailableActions: some View {
        Button {
            companion.refreshAvailability()
        } label: {
            Label("Check again", systemImage: "arrow.clockwise")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
    }

    private var conversation: some View {
        LazyVStack(alignment: .leading, spacing: 24) {
            ForEach(companion.messages) { message in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        if !message.isUser {
                            Image(systemName: "sparkles").foregroundStyle(clay)
                        }
                        Text(message.isUser ? "YOU" : "COMPANION · ON DEVICE")
                            .tracking(1.3)
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(pine.opacity(0.55))
                    if message.text.isEmpty {
                        ProgressView("Thinking locally…")
                            .font(.subheadline)
                            .tint(clay)
                    } else {
                        Text(message.text)
                            .font(message.isUser ? .body.weight(.medium) : .body)
                            .lineSpacing(5)
                            .textSelection(.enabled)
                            .accessibilityIdentifier(message.isUser ? "userMessage" : "assistantMessage")
                    }
                    if message.wasInterrupted {
                        Text("Response stopped")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(message.isUser ? 16 : 0)
                .background(message.isUser ? pine.opacity(0.05) : .clear,
                            in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 10) {
            HStack(alignment: .bottom, spacing: 12) {
                TextField("Ask about \(country.name)…", text: $question, axis: .vertical)
                    .accessibilityIdentifier("questionInput")
                    .font(.body)
                    .lineLimit(1...4)
                    .focused($composerFocused)
                    .padding(.vertical, 12)
                    .padding(.leading, 16)
                    .submitLabel(.send)
                    .onSubmit { send(question) }
                    .disabled(companion.isGenerating)
                if companion.isGenerating {
                    Button {
                        companion.cancel()
                    } label: {
                        Image(systemName: "stop.fill")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Stop response")
                } else {
                    Button {
                        send(question)
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(paper)
                            .frame(width: 44, height: 44)
                            .background(pine, in: Circle())
                    }
                    .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || question.count > CompanionService.questionLimit)
                    .opacity(question.isEmpty || question.count > CompanionService.questionLimit ? 0.35 : 1)
                    .accessibilityLabel("Send question")
                }
            }
            .padding(5)
            .background(paper, in: RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(pine.opacity(0.1)))
            Text(question.count > CompanionService.questionLimit
                 ? "Please keep your question under \(CompanionService.questionLimit) characters."
                 : "On-device AI · Check details with the sources.")
                .font(.caption2)
                .foregroundStyle(pine.opacity(0.6))
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var sources: some View {
        if !sourceLinks.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("GO TO THE SOURCE")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.5)
                    .foregroundStyle(pine.opacity(0.55))
                ForEach(sourceLinks) { source in
                    Link(destination: source.url) {
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: source.symbol)
                                .font(.subheadline)
                                .frame(width: 20)
                                .foregroundStyle(clay)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(source.title)
                                    .font(.subheadline)
                                    .lineLimit(2)
                                Text(source.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(pine.opacity(0.55))
                            }
                            Spacer(minLength: 2)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                }
            }
            .padding(.top, 2)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(feed == nil ? "Waiting for the source material" : "No source material loaded yet")
                    .font(.system(.headline, design: .serif))
                Text(feed == nil
                     ? "Music and headlines are still loading. You can return to the country to check their progress."
                     : "Return to the country and try loading its cultural reading, music, and headlines again.")
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private struct SourceLink: Identifiable {
        var id: String { url.absoluteString }
        let title: String
        let subtitle: String
        let symbol: String
        let url: URL
    }

    private var sourceLinks: [SourceLink] {
        var links: [SourceLink] = []
        if let reading {
            let fetched = reading.fetchedAt.formatted(date: .abbreviated, time: .shortened)
            links.append(SourceLink(title: reading.title, subtitle: "Wikipedia · Retrieved \(fetched)", symbol: "book.pages", url: reading.sourceURL))
        } else if let insight = country.insights.first {
            links.append(SourceLink(title: insight.title, subtitle: "Saved note · \(insight.sourceName)", symbol: "book.closed", url: insight.sourceURL))
        }
        links += feed?.tracks.prefix(3).map {
            SourceLink(title: $0.title, subtitle: $0.artist, symbol: "music.note", url: $0.url)
        } ?? []
        links += feed?.stories.prefix(3).map {
            SourceLink(title: $0.title, subtitle: $0.source, symbol: "newspaper", url: $0.url)
        } ?? []
        var seen = Set<String>()
        return links.filter { seen.insert($0.id).inserted }
    }

    // A new displayed article starts a new conversation; answers about the
    // previous topic must not silently become evidence for this one.
    private var contextID: String {
        "\(country.id)|\(reading?.sourceURL.absoluteString ?? "saved-note")"
    }

    private func send(_ text: String) {
        if companion.send(text, country: country, feed: feed, reading: reading) {
            question = ""
            composerFocused = false
        }
    }
}
