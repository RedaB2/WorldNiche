import Foundation
import Observation

struct QuizQuestion: Codable, Sendable, Identifiable {
    let id: String
    let day: String
    let prompt: String
    let options: [String]
    let answer: String

    static let edition: [String: QuizQuestion] = {
        guard let url = Bundle.main.url(forResource: "daily-quiz", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let rows = try? JSONDecoder().decode([Self].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.day, $0) })
    }()

    var valid: Bool {
        !prompt.isEmpty && Set(options).count == 4 && options.count == 4 && options.contains(answer)
            && options.allSatisfy { CountryRepository.country(id: $0) != nil }
    }
}

struct QuizAttempt: Codable, Sendable {
    let day: String
    let choice: String
    let correct: Bool
}

struct QuizRank: Decodable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let score: Int
}

struct QuizStandings: Decodable, Sendable {
    let attempts: [QuizAttempt]
    let board: [QuizRank]
}

enum QuizClock {
    static var calendar: Calendar {
        var result = Calendar(identifier: .iso8601)
        result.timeZone = .gmt
        return result
    }
    static func key(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle().year().month().day().dateSeparator(.dash))
    }
    static func week(_ date: Date) -> [Date] {
        let start = calendar.dateInterval(of: .weekOfYear, for: date)!.start
        return (0..<7).map { start.addingTimeInterval(Double($0) * 86400) }
    }
    static func streak(days: Set<String>, on date: Date) -> Int {
        var cursor = date
        if !days.contains(key(cursor)) { cursor = cursor.addingTimeInterval(-86400) }
        var length = 0
        while days.contains(key(cursor)) {
            length += 1
            cursor = cursor.addingTimeInterval(-86400)
        }
        return length
    }
}

@MainActor @Observable
final class DailyQuizStore {
    private let clock: () -> Date
    private let defaults: UserDefaults
    private(set) var owner: UUID?
    private(set) var question: QuizQuestion?
    private(set) var attempts: [String: QuizAttempt] = [:]
    private(set) var board: [QuizRank] = []
    private(set) var now = Date()
    private(set) var submitting = false
    private(set) var standingsUnavailable = false
    var message: String?
    private var generation = UUID()
    private var standingsRequest = UUID()
    private var cacheKey: String { "niche.quiz." + (owner?.uuidString ?? "guest") }
    var day: String { QuizClock.key(now) }
    var today: QuizAttempt? { attempts[day] }
    var streak: Int { QuizClock.streak(days: Set(attempts.keys), on: now) }

    init(defaults: UserDefaults, clock: @escaping () -> Date = Date.init) {
        self.clock = clock
        self.defaults = defaults
        activate(defaults.string(forKey: "niche.localOwnerID").flatMap(UUID.init(uuidString:)))
    }

    func activate(_ owner: UUID?) {
        self.owner = owner
        generation = UUID()
        standingsRequest = UUID()
        submitting = false
        board = []
        message = nil
        standingsUnavailable = false
        attempts = defaults.data(forKey: cacheKey).flatMap { try? JSONDecoder().decode([String: QuizAttempt].self, from: $0) } ?? [:]
        tick()
    }

    func tick() {
        let date = clock()
        let changed = day != QuizClock.key(date)
        now = date
        if changed || question == nil { question = QuizQuestion.edition[day] }
        if changed { board = []; message = nil }
    }

    func refresh(api: SocialAPI?) async {
        tick()
        let current = generation, requestedDay = day
        if question == nil, let api, let remote = try? await api.publishedQuiz(),
           generation == current, day == requestedDay, remote.day == requestedDay, remote.valid {
            question = remote
        }
        guard let owner, let api, generation == current else { return }
        let request = UUID()
        standingsRequest = request
        do {
            let result = try await api.quizStandings(owner: owner)
            guard generation == current, request == standingsRequest, requestedDay == day, !Task.isCancelled else { return }
            for attempt in result.attempts { attempts[attempt.day] = attempt }
            persist()
            board = result.board
            standingsUnavailable = false
        } catch {
            guard generation == current, request == standingsRequest, !Task.isCancelled else { return }
            board = []
            standingsUnavailable = true
        }
    }

    func answer(_ choice: String, question q: QuizQuestion, api: SocialAPI?) async -> QuizAttempt? {
        tick()
        guard q.day == day, question?.id == q.id, q.options.contains(choice),
              today == nil, !submitting else { return nil }
        let current = generation
        submitting = true
        message = nil
        defer { if generation == current { submitting = false } }
        do {
            let attempt: QuizAttempt
            if let owner {
                guard let api else { throw SocialError.unavailable }
                attempt = try await api.submitQuiz(owner: owner, day: q.day, choice: choice)
            } else {
                attempt = QuizAttempt(day: q.day, choice: choice, correct: choice == q.answer)
            }
            guard generation == current else { return nil }
            attempts[attempt.day] = attempt
            persist()
            return attempt
        } catch {
            if generation == current { message = "Couldn’t confirm your answer. Check your connection and try again." }
            return nil
        }
    }

    private func persist() { defaults.set(try? JSONEncoder().encode(attempts), forKey: cacheKey) }
}
