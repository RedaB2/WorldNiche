import SwiftUI

struct AtlasView: View {
    @State private var search = ""
    @State private var region = "All"
    @State private var detail: Country?
    private let regions = ["All", "Africa", "Asia", "Europe", "Americas", "Oceania"]

    private var countries: [Country] {
        CountryRepository.countries.filter {
            matchesRegion($0) &&
            (search.isEmpty || $0.name.localizedStandardContains(search) || $0.capital.localizedStandardContains(search))
        }
    }

    private func matchesRegion(_ country: Country) -> Bool {
        if region == "All" { return true }
        if region == "Americas" { return country.region.contains("America") || country.region == "Caribbean" }
        if region == "Oceania" { return ["Australia and New Zealand", "Melanesia", "Micronesia", "Polynesia"].contains(country.region) }
        return country.region.localizedCaseInsensitiveContains(region)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 23) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Find yourself somewhere.")
                            .scaledFont(size: 35, design: .serif).tracking(-1).foregroundStyle(Palette.pine)
                        Text("195 countries. Start with one you’re curious about.")
                            .scaledFont(size: 13).foregroundStyle(Palette.muted)
                    }
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(regions, id: \.self) { item in
                                Button { region = item } label: {
                                    Text(item).scaledFont(size: 12, weight: .medium)
                                        .padding(.horizontal, 16).padding(.vertical, 10)
                                        .frame(minHeight: 44)
                                        .background(region == item ? Palette.forest : Palette.card, in: Capsule())
                                        .foregroundStyle(region == item ? .white : Palette.pine)
                                }.buttonStyle(.plain)
                            }
                        }
                    }.scrollIndicators(.hidden)
                    if countries.isEmpty {
                        ContentUnavailableView.search(text: search)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(countries) { country in
                                Button { detail = country } label: { CountryRow(country: country) }.buttonStyle(.plain)
                                Divider().overlay(Palette.line)
                            }
                        }
                    }
                }.padding(24).frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .background(Palette.paper)
            .navigationTitle("Atlas")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "A country or a capital")
            .sheet(item: $detail) { CountryDetailView(country: $0) }
        }
    }
}

struct CountryRow: View {
    let country: Country
    var body: some View {
        HStack(spacing: 16) {
            Text(country.flag).scaledFont(size: 31).frame(width: 45)
            VStack(alignment: .leading, spacing: 5) {
                Text(country.name).scaledFont(size: 19, design: .serif).foregroundStyle(Palette.pine)
                Text(country.capital).scaledFont(size: 11).foregroundStyle(Palette.muted)
            }
            Spacer()
            if !country.insights.isEmpty {
                Image(systemName: "sparkle").scaledFont(size: 12).foregroundStyle(Palette.clay)
                    .accessibilityLabel("Includes a researched cultural note")
            }
            Image(systemName: "chevron.right").scaledFont(size: 11).foregroundStyle(Palette.muted)
        }.padding(.vertical, 16).contentShape(Rectangle())
    }
}

struct JournalView: View {
    @Environment(DiscoveryJournal.self) private var journal
    @State private var detail: Country?
    @State private var showSaved = true

    private var countries: [Country] {
        if showSaved { return CountryRepository.countries.filter { journal.savedIDs.contains($0.id) } }
        return journal.visitedIDs.compactMap { CountryRepository.country(id: $0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Eyebrow(text: "Keep a little of everywhere")
                    Text("Your world,\ngetting bigger.")
                        .scaledFont(size: 38, design: .serif).tracking(-1.2).foregroundStyle(Palette.pine)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(journal.visitedIDs.count)").scaledFont(size: 48, design: .serif).foregroundStyle(Palette.clay)
                        Text("of 195 countries explored").scaledFont(size: 13).foregroundStyle(Palette.muted)
                    }
                    ProgressView(value: Double(journal.visitedIDs.count), total: 195).tint(Palette.clay)
                    Picker("Collection", selection: $showSaved) {
                        Text("Saved").tag(true)
                        Text("Recently explored").tag(false)
                    }.pickerStyle(.segmented)
                    if countries.isEmpty {
                        VStack(spacing: 15) {
                            Image(systemName: showSaved ? "bookmark" : "globe.europe.africa").scaledFont(size: 30, weight: .ultraLight)
                            Text(showSaved ? "Some places stay with you." : "A whole world is waiting.")
                                .scaledFont(size: 23, design: .serif)
                            Text(showSaved ? "Tap the bookmark on a country to keep it here." : "Open a country or spin the globe to begin.")
                                .scaledFont(size: 13).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                        }.foregroundStyle(Palette.pine).frame(maxWidth: .infinity).padding(.vertical, 35).editorialCard()
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(countries) { country in
                                Button { detail = country } label: { CountryRow(country: country) }.buttonStyle(.plain)
                                Divider()
                            }
                        }
                    }
                }.padding(24).frame(maxWidth: 760).frame(maxWidth: .infinity)
            }.background(Palette.paper)
                .navigationTitle("Journal").navigationBarTitleDisplayMode(.inline)
                .sheet(item: $detail) { CountryDetailView(country: $0) }
        }
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    Image("AppLogo").resizable().scaledToFit()
                        .frame(width: 180, height: 180)
                        .padding(.leading, -25)
                        .accessibilityLabel("WorldNiche")
                    Text("A little more local.").scaledFont(size: 21, design: .serif).italic()
                    Text("Small discoveries that make the world feel closer. Find a song, learn a local ritual, and have a better question to ask the next person you meet.")
                    Divider()
                    Text("A world of perspectives").scaledFont(size: 24, design: .serif)
                    Text("The atlas includes 193 UN member states plus Palestine and the Holy See. Borders follow Natural Earth’s cartographic dataset and aren’t a statement of political recognition. Cultural discoveries rotate daily from live sources. Music and headlines refresh throughout the day; coverage varies by provider.")
                    Text("Built for curiosity, with privacy").scaledFont(size: 24, design: .serif)
                    Text("Saved countries and your journal stay on this device. An optional account connects you with friends; sharing explored countries is off until you choose to enable it. Ask Niche uses Apple Intelligence on supported devices. The app requests public content directly from Apple, Google and Wikimedia. No analytics SDK or location permission. Profile settings include privacy details, export and deletion controls.")
                    Text("Sources & credits").scaledFont(size: 24, design: .serif)
                    Link("Natural Earth · public-domain map data", destination: URL(string: "https://www.naturalearthdata.com/about/terms-of-use/")!)
                    Link("Country data · mledoze/countries · ODbL", destination: URL(string: "https://github.com/mledoze/countries")!)
                    Link("Open Database License", destination: URL(string: "https://opendatacommons.org/licenses/odbl/1-0/")!)
                    Text("Cultural sources are linked on each note. Live cultural reading comes from Wikipedia contributors under CC BY-SA 4.0. Apple Music charts reflect that service’s listeners. English headlines come via Google News. TikTok trends aren’t included yet.")
                    Link("Wikipedia text · CC BY-SA 4.0", destination: URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!)
                    Text("WorldNiche · 1.0").scaledFont(size: 11, design: .monospaced).tracking(2).padding(.top, 12)
                }.scaledFont(size: 14).lineSpacing(5).foregroundStyle(Palette.pine).padding(26).frame(maxWidth: 650).frame(maxWidth: .infinity)
            }.background(Palette.paper)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
