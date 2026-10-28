import SwiftUI

struct IntroView: View {
    let explore: () -> Void
    let createProfile: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0

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

            TabView(selection: $page) {
                introPage(title: "A little more world,\nevery day.",
                          detail: "Turn the globe or tap a country. Let curiosity choose your next stop.",
                          index: 0) {
                    Image("AppLogo")
                        .resizable().scaledToFit()
                        .frame(width: 155, height: 155)
                        .accessibilityHidden(true)
                }
                .tag(0)

                introPage(title: "Get to know\nthe little things.",
                          detail: "Hear what’s playing, catch up on local news, and discover the details that make a place its own.",
                          index: 1) {
                    VStack(spacing: 12) {
                        discoveryRow("A song to bring home", symbol: "music.note")
                        discoveryRow("A new point of view", symbol: "newspaper")
                        discoveryRow("Something only locals know", symbol: "sparkle.magnifyingglass")
                    }
                    .frame(maxWidth: 360)
                    .accessibilityHidden(true)
                }
                .tag(1)

                introPage(title: "Curiosity is better\ntogether.",
                          detail: "Choose your name, add a photo if you like, and discover what your friends are exploring.",
                          index: 2) {
                    Image(systemName: "person.2.circle")
                        .font(.system(size: 108, weight: .ultraLight))
                        .foregroundStyle(Palette.pine)
                        .frame(height: 160)
                        .accessibilityHidden(true)
                }
                .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .background(Palette.paper.ignoresSafeArea())
        .foregroundStyle(Palette.pine)
        .safeAreaInset(edge: .bottom, spacing: 0) {
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
    }

    private func introPage<Illustration: View>(title: String, detail: String, index: Int,
                                               @ViewBuilder illustration: () -> Illustration) -> some View {
        ScrollView {
            VStack(spacing: 28) {
                illustration().padding(.top, 24)
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
            .frame(maxWidth: 520)
            .padding(.horizontal, 28)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func discoveryRow(_ title: String, symbol: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.title3).frame(width: 28)
            Text(title).font(.subheadline.weight(.medium))
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private func move(to nextPage: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { page = nextPage }
    }
}
