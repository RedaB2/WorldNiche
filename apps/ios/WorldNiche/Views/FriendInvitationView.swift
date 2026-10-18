import SwiftUI

struct FriendInvitationView: View {
    @Environment(SocialStore.self) private var social
    @Environment(\.dismiss) private var dismiss
    @State private var showSignIn = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                if social.invitationConnected, let preview = social.pendingInvitation {
                    ExplorerAvatar(avatar: preview.avatar, size: 80)
                    Text("You’re friends with \(preview.displayName)")
                        .scaledFont(size: 32, design: .serif).multilineTextAlignment(.center)
                    Text("Explore the world together. Your discoveries stay private until you turn on sharing in Settings.")
                        .font(.body).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                    Button("Done") { social.dismissInvitation() }
                        .buttonStyle(.glassProminent).tint(Palette.forest)
                        .accessibilityIdentifier("friendInvitationDone")
                } else if !social.isConfigured {
                    ContentUnavailableView("Friends are coming", systemImage: "person.2", description: Text("Friend invitations aren’t available in this build yet. You can still explore the world and keep your own journal."))
                } else if social.deletionPending {
                    ContentUnavailableView("Finish account deletion", systemImage: "person.crop.circle.badge.exclamationmark", description: Text("Finish deleting your account in Settings before connecting with friends."))
                } else if !social.isSignedIn && social.hasPendingInvitation {
                    Image(systemName: "person.2.circle").font(.system(size: 66, weight: .ultraLight))
                    Text("A friend invited you").scaledFont(size: 32, design: .serif)
                    Text("Sign in and you’ll be connected automatically. Your discoveries stay private unless you choose to share them.")
                        .foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                    Button("Sign in to connect") { showSignIn = true }
                        .buttonStyle(.glassProminent).tint(Palette.forest)
                        .accessibilityIdentifier("signInForInvitation")
                } else if social.isConnectingInvitation || (social.hasPendingInvitation && social.invitationMessage == nil) {
                    ProgressView("Connecting you…").accessibilityIdentifier("connectingFriendInvitation")
                }
                if !social.invitationConnected, let message = social.invitationMessage {
                    Text(message).font(.callout).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                        .accessibilityIdentifier("invitationError")
                    if social.canRetryInvitation {
                        Button("Try again") { Task { await social.acceptInvitation() } }
                            .buttonStyle(.glassProminent).tint(Palette.forest)
                            .disabled(social.isBusy)
                            .accessibilityIdentifier("retryFriendInvitation")
                    }
                }
                Spacer()
            }.padding(28).foregroundStyle(Palette.pine).frame(maxWidth: .infinity)
                .background(Palette.paper)
                .navigationTitle("Friend invitation").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { social.dismissInvitation(); dismiss() } } }
                .sheet(isPresented: $showSignIn) { ProfileSignInView() }
        }
    }
}

struct CountryFriendsView: View {
    let country: Country
    @Environment(SocialStore.self) private var social
    @State private var showProfile = false

    private var explorers: [ExplorerFriend] { social.friendsWhoExplored(country.id) }

    var body: some View {
        if social.isSignedIn {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Explored together").scaledFont(size: 22, design: .serif)
                    Spacer()
                    Button("Friends") { showProfile = true }.font(.footnote).frame(minHeight: 44)
                }
                if explorers.isEmpty {
                    Text("No shared explorations here yet.").font(.footnote).foregroundStyle(Palette.muted)
                } else {
                    HStack(spacing: 10) {
                        ForEach(explorers.prefix(4)) { friend in
                            ProfilePhotoAvatar(symbol: friend.avatar, path: friend.avatarPath, size: 34).accessibilityLabel(friend.displayName)
                        }
                        Text(explorers.prefix(3).map(\.displayName).joined(separator: ", ") + (explorers.count > 3 ? " and \(explorers.count - 3) more" : ""))
                            .font(.subheadline).lineLimit(2)
                    }
                    Text("Opened \(country.name) in WorldNiche. This doesn’t indicate a physical visit.")
                        .font(.caption).foregroundStyle(Palette.muted)
                }
            }.foregroundStyle(Palette.pine).editorialCard()
                .accessibilityIdentifier("countryFriends")
                .task { await social.refresh() }
                .sheet(isPresented: $showProfile) { ProfileView() }
        }
    }
}
