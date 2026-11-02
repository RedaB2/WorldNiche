import SwiftUI

struct CountryReadingViewport: Equatable {
    var sections: [CountryReadingSection: CGRect] = [:]
    var viewport = CGRect.zero
    var readySections: Set<CountryReadingSection> = []
    var canRead = false
}

struct CountryReadingHeader: View {
    let progress: CountryReadingProgress
    let explored: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(explored ? "A new perspective" : "Your discovery")
                Spacer()
                if explored {
                    Label("Explored", systemImage: "checkmark")
                } else {
                    Text("\(Int(progress.fraction * 100))%")
                        .monospacedDigit()
                }
            }
            .scaledFont(size: 11, weight: .medium)
            .foregroundStyle(Palette.muted)
            HStack(spacing: 4) {
                ForEach(CountryReadingSection.allCases, id: \.self) { section in
                    GeometryReader { geometry in
                        Capsule().fill(Palette.line)
                            .overlay(alignment: .leading) {
                                Capsule().fill(explored ? Palette.pine : Palette.clay)
                                    .frame(width: geometry.size.width * (explored ? 1 : progress.fraction(for: section)))
                            }
                    }.frame(height: 3)
                }
            }
        }
        .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 12)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .background(Palette.paper)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Discovery progress")
        .accessibilityValue(explored ? "Explored" : "\(Int(progress.fraction * 100)) percent. " + CountryReadingSection.allCases.map {
            "\($0.title) \(Int(progress.fraction(for: $0) * 100)) percent"
        }.joined(separator: ". "))
        .accessibilityIdentifier("countryReadingProgress")
    }
}

struct CountryExplorationFinish: View {
    let country: Country
    let ready: Bool
    let explored: Bool
    let pulling: Bool
    let onContinue: () -> Void
    let onComplete: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var pressing = false
    @State private var ringFill = 0.0
    private let holdDuration = 0.9

    private var holding: Bool { (pressing || pulling) && ready && !explored && scenePhase == .active }

    var body: some View {
        VStack(spacing: 14) {
            Rectangle().fill(Palette.line).frame(height: 1).padding(.bottom, 16)
            if ready || explored {
                VStack(spacing: 13) {
                    ZStack {
                        Circle().fill(Palette.clay.opacity(0.07))
                        Circle().stroke(Palette.line, lineWidth: 2)
                        Circle().trim(from: 0, to: explored ? 1 : ringFill)
                            .stroke(explored ? Palette.pine : Palette.clay,
                                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Image(systemName: explored ? "checkmark" : "leaf")
                            .scaledFont(size: 25, weight: .light)
                            .foregroundStyle(explored ? Palette.pine : Palette.clay)
                            .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                    }
                    .frame(width: 64, height: 64)
                    .scaleEffect(holding && !reduceMotion ? 1.06 : 1)
                    Text(explored ? "\(country.name), explored." : holding ? "Stay a little longer…" : "Hold to mark explored")
                        .scaledFont(size: 23, design: .serif)
                        .foregroundStyle(Palette.pine)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: holdDuration, maximumDistance: 24) {
                    complete()
                } onPressingChanged: { pressing = $0 }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(explored ? "\(country.name), explored" : "Mark \(country.name) explored")
                .accessibilityHint(explored ? "Saved to your journal" : "Completes this discovery and saves it to your journal")
                .accessibilityAddTraits(explored ? .isStaticText : .isButton)
                .accessibilityAction { complete() }
                .accessibilityIdentifier(explored ? "countryExplored" : "completeCountryExploration")
                Text(explored ? "A new perspective, saved to your journal." : "Or keep pulling up and hold.")
                    .scaledFont(size: 12).foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
            } else {
                Text("There’s a little more to discover.")
                    .scaledFont(size: 23, design: .serif).foregroundStyle(Palette.pine)
                    .multilineTextAlignment(.center)
                Text("Take a moment with the culture, music and local perspectives. Your progress is saved as you go.")
                    .scaledFont(size: 13).foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center).lineSpacing(3)
                Button("Continue exploring", action: onContinue)
                    .scaledFont(size: 13, weight: .medium).buttonStyle(.glass)
                    .accessibilityIdentifier("continueCountryReading")
            }
        }
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .onChange(of: holding) { _, active in
            withAnimation(reduceMotion ? nil : .linear(duration: active ? holdDuration : 0.18)) {
                ringFill = active ? 1 : 0
            }
        }
        .task(id: pulling && ready && !explored && scenePhase == .active) {
            guard pulling && ready && !explored && scenePhase == .active else { return }
            do { try await Task.sleep(for: .seconds(holdDuration)) } catch { return }
            guard !Task.isCancelled else { return }
            complete()
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { pressing = false } }
        .sensoryFeedback(.success, trigger: explored)
    }

    private func complete() {
        guard ready && !explored && scenePhase == .active else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { onComplete() }
    }
}
