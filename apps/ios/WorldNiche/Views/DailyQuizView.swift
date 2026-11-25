import SwiftUI

struct DailyQuizView: View {
    @Environment(SocialStore.self) private var social
    @Environment(\.dismiss) private var dismiss
    var openCountry: (Country) -> Void
    @State private var reveal: Country?
    @State private var target: Country?
    @State private var spin = 0
    @State private var landed = false
    private var quiz: DailyQuizStore { social.quiz }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Eyebrow(text: quiz.now.formatted(Date.FormatStyle(timeZone: .gmt).month(.wide).day()) + "  ·  Daily quiz")
                    if let q = quiz.question {
                        if let attempt = quiz.today, let country = CountryRepository.country(id: q.answer) {
                            Label(attempt.correct ? "You got it!" : "Today’s answer", systemImage: attempt.correct ? "checkmark.circle.fill" : "globe")
                                .foregroundStyle(Palette.clay)
                            Text(country.name).scaledFont(size: 38, design: .serif)
                            if reveal != nil {
                                WorldGlobeView(countries: CountryRepository.countries, selectedCountry: target, spinToken: spin,
                                               allowsCountrySelection: false, onSpinFinished: { landed = true }, onSelect: { _ in })
                                    .allowsHitTesting(false)
                                    .frame(maxWidth: .infinity).frame(height: 270)
                                    .accessibilityLabel("Globe turning to \(country.name)")
                                    .task {
                                        do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                                        target = country
                                        spin += 1
                                    }
                                    .task(id: landed) {
                                        guard landed else { return }
                                        do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
                                        openCountry(country)
                                    }
                            } else {
                                Text(q.prompt).font(.body)
                                Button("Explore \(country.name)") { openCountry(country) }
                                    .buttonStyle(.borderedProminent)
                            }
                            Label("Today counts toward your streak.", systemImage: "flame.fill").foregroundStyle(Palette.clay)
                        } else {
                            Text(q.prompt).scaledFont(size: 30, design: .serif)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("quizQuestion")
                            ForEach(Array(q.options.enumerated()), id: \.element) { index, code in
                                if let country = CountryRepository.country(id: code) {
                                    Button {
                                        Task {
                                            if await quiz.answer(code, question: q, api: social.api) != nil {
                                                reveal = CountryRepository.country(id: q.answer)
                                            }
                                        }
                                    } label: {
                                        HStack(spacing: 14) {
                                            Text(["A","B","C","D"][index]).font(.caption.monospaced().bold())
                                                .foregroundStyle(Palette.muted)
                                            Text(country.name).font(.body.weight(.medium))
                                            Spacer()
                                        }
                                        .padding(16).background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
                                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.line))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("quizChoice-\(code)")
                                    .disabled(quiz.submitting || social.deletionPending)
                                }
                            }
                            if quiz.submitting { ProgressView("Checking answer") }
                            if let message = quiz.message { Text(message).foregroundStyle(Palette.clay) }
                            Text("One guess each day. Completing it keeps your streak. A correct answer earns a leaderboard point.")
                                .font(.footnote).foregroundStyle(Palette.muted)
                        }
                    } else {
                        Text("Today’s question is unavailable.").font(.headline)
                        Button("Try again") { Task { await quiz.refresh(api: social.api) } }
                    }
                }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .background(Palette.paper).foregroundStyle(Palette.pine)
            .navigationTitle("Daily country quiz").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}

struct QuizStreakView: View {
    @Environment(SocialStore.self) private var social
    @Environment(\.dismiss) private var dismiss
    private var quiz: DailyQuizStore { social.quiz }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Label("\(quiz.streak)-day streak", systemImage: "flame.fill")
                        .scaledFont(size: 32, design: .serif).foregroundStyle(Palette.clay)
                    VStack(alignment: .leading, spacing: 16) {
                        Eyebrow(text: "This week")
                        HStack {
                            ForEach(QuizClock.week(quiz.now), id: \.self) { date in
                                let hit = quiz.attempts[QuizClock.key(date)] != nil
                                let format = Date.FormatStyle(timeZone: .gmt)
                                VStack(spacing: 9) {
                                    Text(date.formatted(format.weekday(.narrow))).font(.caption.bold())
                                    Image(systemName: hit ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(hit ? Palette.clay : Palette.muted)
                                }.frame(maxWidth: .infinity)
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel(date.formatted(format.weekday(.wide)) + (hit ? ", completed" : ", incomplete"))
                            }
                        }
                        Text("A new quiz opens at midnight UTC.").font(.footnote).foregroundStyle(Palette.muted)
                    }.editorialCard()
                    Text("Friends leaderboard").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    Text("Correct answers this week · Monday to Sunday").font(.footnote).foregroundStyle(Palette.muted)
                    if quiz.owner == nil {
                        Text("Sign in from Profile and add friends to compare scores.")
                    } else if social.profile?.shareExploration != true || social.profile?.communityRestricted == true {
                        Text("Your score is private. Eligible friends appear when exploration sharing is on in Settings.")
                    } else if quiz.standingsUnavailable {
                        Button("Couldn’t load scores. Try again") { Task { await quiz.refresh(api: social.api) } }
                    } else {
                        ForEach(quiz.board) { row in
                            HStack {
                                Text("\(1 + quiz.board.prefix { $0.score > row.score }.count)").monospacedDigit().foregroundStyle(Palette.muted)
                                Text(row.id == quiz.owner ? "You" : row.name)
                                Spacer()
                                Text("\(row.score) / 7").monospacedDigit().bold()
                            }.padding(.vertical, 6)
                        }
                        if quiz.board.count == 1 { Text("Add a friend from Profile to compete.").font(.footnote) }
                    }
                }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .background(Palette.paper).foregroundStyle(Palette.pine)
            .navigationTitle("Your streak").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await quiz.refresh(api: social.api) }
            .refreshable { await quiz.refresh(api: social.api) }
        }
    }
}

struct QuizReminderSettings: View {
    @Environment(SocialStore.self) private var social
    @Environment(\.openURL) private var openURL
    private let notifications = QuizNotifications.shared
    var body: some View {
        Section {
            Toggle("Daily quiz reminder", isOn: Binding(get: { notifications.enabled }, set: { value in
                Task { await notifications.setEnabled(value, social: social) }
            })).disabled(notifications.working || social.api == nil)
            if notifications.blocked {
                Button("Open notification settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                }
            }
            if let message = notifications.message { Text(message).font(.footnote) }
        } header: { Text("Notifications") } footer: {
            Text("Get a reminder around 7 p.m. local time if you still have a guess to make.")
        }
    }
}
