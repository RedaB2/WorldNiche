import AuthenticationServices
import LinkPresentation
import PhotosUI
import SwiftUI
import UIKit

struct ProfileView: View {
    @Environment(SocialStore.self) private var social
    @Environment(DiscoveryJournal.self) private var journal
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showEditor = false
    @State private var showSettings = false
    @State private var showSignIn = false
    @State private var selectedFriend: ExplorerFriend?
    @State private var sharedItem: ProfileSharedItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    if let profile = social.profile {
                        profileHeader(name: profile.displayName, avatar: profile.avatar)
                        if social.isSignedIn, profile.hasModerationNotice {
                            ProfileModerationNotice(profile: profile)
                                .editorialCard()
                        }
                        explorationSummary
                    } else {
                        welcome
                    }
                    friendsSection
                    if let message = social.errorMessage {
                        ProfileStatusMessage(message: message)
                    }
                }
                .padding(24)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(Palette.paper)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { showSettings = true }
                        .accessibilityIdentifier("profileSettings")
                }
            }
            .sheet(isPresented: $showEditor) { ProfileEditorView() }
            .sheet(isPresented: $showSettings) { ProfileSettingsView() }
            .sheet(isPresented: $showSignIn) { ProfileSignInView() }
            .sheet(item: $selectedFriend) { friend in ProfileFriendView(friend: friend) }
            .sheet(item: $sharedItem) { item in ProfileShareSheet(url: item.url) }
            .refreshable { await social.refresh() }
            .task { await social.refresh() }
        }
    }

    private func profileHeader(name: String, avatar: String) -> some View {
        HStack(alignment: .center, spacing: 17) {
            ProfilePhotoAvatar(symbol: avatar, path: social.profile?.avatarPath, localID: social.profile?.localAvatarID, size: 66)
            VStack(alignment: .leading, spacing: 6) {
                Text(name)
                    .scaledFont(size: 31, design: .serif)
                    .foregroundStyle(Palette.pine)
                    .accessibilityIdentifier("profileName")
                Button("Edit profile") { showEditor = true }
                    .font(.subheadline)
                    .frame(minHeight: 44, alignment: .leading)
                    .disabled(social.deletionPending)
                    .accessibilityIdentifier("editProfile")
            }
            Spacer(minLength: 0)
        }
    }

    private var explorationSummary: some View {
        VStack(alignment: .leading, spacing: 16) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 30))
            layout {
                profileCount(journal.visitedIDs.count, label: "Explored")
                profileCount(journal.savedIDs.count, label: "Saved")
                profileCount(social.friends.count, label: "Friends")
            }
            ProgressView(value: Double(journal.visitedIDs.count), total: 195)
                .tint(Palette.clay)
                .accessibilityLabel("Countries explored")
                .accessibilityValue("\(journal.visitedIDs.count) of 195")
            Text("Explored means discovering a country in WorldNiche. It doesn’t mean you’ve travelled there.")
                .font(.footnote)
                .foregroundStyle(Palette.muted)
        }
        .editorialCard()
    }

    private func profileCount(_ count: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(count, format: .number).scaledFont(size: 30, design: .serif)
            Text(label).font(.caption).foregroundStyle(Palette.muted)
        }
        .foregroundStyle(Palette.pine)
        .accessibilityElement(children: .combine)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 18) {
            ExplorerAvatar(avatar: "globe", size: 70)
            Text("A world to share.")
                .scaledFont(size: 37, design: .serif)
                .tracking(-1)
                .foregroundStyle(Palette.pine)
            Text("Keep your curiosity in one place. Add a name and a small symbol that feels like you.")
                .font(.subheadline).foregroundStyle(Palette.muted)
            Button("Create your profile") { showEditor = true }
                .buttonStyle(.glassProminent).tint(Palette.forest)
                .controlSize(.large)
                .disabled(social.deletionPending)
                .accessibilityIdentifier("createProfile")
            Text("Start on this device. An account is optional.")
                .font(.footnote).foregroundStyle(Palette.muted)
        }
    }

    @ViewBuilder
    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Curiosity, together.")
                .scaledFont(size: 28, design: .serif)
                .foregroundStyle(Palette.pine)
            if !social.isConfigured {
                Label("Friends are not available in this build yet.", systemImage: "person.2")
                    .font(.subheadline).foregroundStyle(Palette.muted)
                Text("Your profile, journal and saved countries still work on this device.")
                    .font(.footnote).foregroundStyle(Palette.muted)
                Button("Sign-in options", systemImage: "person.crop.circle") { showSignIn = true }
                    .buttonStyle(.glass).controlSize(.large)
                    .accessibilityIdentifier("signInForFriends")
            } else if social.profile == nil {
                Text("Sign in, then invite someone to discover the world with you.")
                    .font(.subheadline).foregroundStyle(Palette.muted)
                Button("Sign in to connect", systemImage: "person.crop.circle.badge.plus") { showSignIn = true }
                    .buttonStyle(.glass).controlSize(.large)
                    .accessibilityIdentifier("signInForFriends")
            } else if !social.isSignedIn {
                Text("Sign in to add friends and see the places they’ve explored. Your exploration stays private until you choose to share it.")
                    .font(.subheadline).foregroundStyle(Palette.muted)
                Button("Sign in to connect", systemImage: "person.crop.circle.badge.plus") { showSignIn = true }
                    .buttonStyle(.glass).controlSize(.large)
                    .accessibilityIdentifier("signInForFriends")
            } else {
                Button {
                    Task {
                        if let url = await social.createInvitation() {
                            sharedItem = ProfileSharedItem(url: url)
                        }
                    }
                } label: {
                    Label("Invite a friend", systemImage: "person.badge.plus")
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.glassProminent).tint(Palette.forest).controlSize(.large)
                .disabled(social.isBusy || social.deletionPending || social.profile?.communityRestricted == true)
                .accessibilityIdentifier("inviteFriend")
                Text("Send a private invitation link. Your friend opens it in WorldNiche to connect with you.")
                    .font(.footnote).foregroundStyle(Palette.muted)
                if social.friends.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "person.2").font(.title2.weight(.light))
                        Text("Your first fellow explorer is one link away.")
                            .font(.subheadline).multilineTextAlignment(.center)
                    }
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(social.friends, id: \.id) { friend in
                            Button { selectedFriend = friend } label: {
                                HStack(spacing: 13) {
                                    ProfilePhotoAvatar(symbol: friend.avatar, path: friend.avatarPath, size: 44)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(friend.displayName).font(.headline).foregroundStyle(Palette.pine)
                                        Text(friend.sharesExploration ? "\(friend.exploredCountryIDs.count) countries explored" : "Exploration is private")
                                            .font(.caption).foregroundStyle(Palette.muted)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .frame(minHeight: 68)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("friend-\(friend.id.uuidString)")
                            Divider().overlay(Palette.line)
                        }
                    }
                }
            }
        }
    }
}

private struct ProfileModerationNotice: View {
    let profile: ExplorerProfile
    @Environment(SocialStore.self) private var social

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if profile.communityRestricted == true {
                Label("Sharing is paused", systemImage: "person.crop.circle.badge.exclamationmark")
                    .font(.headline)
                Text(profile.communityRestrictionNote ?? "Sharing and invitations are paused. Contact support if you think this is a mistake.")
                if let url = social.supportURL { Link("Contact support", destination: url) }
            }
            reviewStatus("Name", status: profile.nameModerationStatus, note: profile.nameModerationNote)
            reviewStatus("Photo", status: profile.photoModerationStatus, note: profile.photoModerationNote)
            Link("Community guidelines", destination: social.communityURL)
        }
        .font(.subheadline)
        .foregroundStyle(Palette.muted)
        .accessibilityIdentifier("profileModerationNotice")
    }

    @ViewBuilder
    private func reviewStatus(_ label: String, status: ProfileModerationStatus?, note: String?) -> some View {
        if status == .pending {
            Label("\(label) in review", systemImage: "clock")
                .font(.headline).foregroundStyle(Palette.pine)
            Text(note ?? "Your change stays private until it is reviewed. Friends continue to see your approved profile.")
        } else if status == .rejected {
            Label("Choose another \(label.lowercased())", systemImage: "exclamationmark.circle")
                .font(.headline).foregroundStyle(Palette.pine)
            Text(note ?? "This change was not approved. Edit your profile to choose something that follows our community guidelines.")
        }
    }
}

struct ExplorerAvatar: View {
    let avatar: String
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: SocialStore.symbol(for: avatar))
            .font(.system(size: size * 0.41, weight: .light))
            .foregroundStyle(Palette.pine)
            .frame(width: size, height: size)
            .background(Palette.pine.opacity(0.08), in: Circle())
            .accessibilityHidden(true)
    }
}

private struct ProfileEditorView: View {
    @Environment(SocialStore.self) private var social
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var avatar = "globe"
    @State private var sharing = false
    @State private var initialized = false
    @State private var attemptedSave = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedPhotoData: Data?
    @State private var removePhoto = false
    @State private var photoLoading = false
    @State private var photoError: String?
    @FocusState private var nameFocused: Bool

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasPhoto: Bool {
        selectedPhotoData != nil || (!removePhoto && (social.profile?.editableAvatarPath != nil || social.profile?.localAvatarID != nil))
    }

    var body: some View {
        NavigationStack {
            Form {
                if social.isSignedIn, let profile = social.profile, profile.hasModerationNotice {
                    Section { ProfileModerationNotice(profile: profile) }
                }
                Section {
                    TextField("Your name", text: $name)
                        .textContentType(.nickname)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($nameFocused)
                        .accessibilityIdentifier("profileNameField")
                        .onChange(of: name) { _, value in
                            if value.count > 32 { name = String(value.prefix(32)) }
                        }
                } header: {
                    Text("What should we call you?")
                } footer: {
                    Text(social.isSignedIn ? "A first name or nickname is enough. New names are reviewed before friends can see them." : "A first name or nickname is enough. Your name stays on this device until you sign in.")
                }
                Section {
                    HStack {
                        Spacer()
                        ProfilePhotoAvatar(symbol: avatar,
                                           path: removePhoto ? nil : social.profile?.editableAvatarPath,
                                           localID: removePhoto ? nil : social.profile?.localAvatarID,
                                           previewData: selectedPhotoData, size: 96)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    PhotosPicker(selection: $selectedPhoto, matching: .images, preferredItemEncoding: .current) {
                        Label("Choose a photo", systemImage: "photo")
                    }
                    .disabled(photoLoading || social.isBusy)
                    .accessibilityIdentifier("chooseProfilePhoto")
                    if hasPhoto {
                        Button("Use a symbol instead", role: .destructive) {
                            selectedPhoto = nil
                            selectedPhotoData = nil
                            removePhoto = true
                            photoError = nil
                        }
                        .accessibilityIdentifier("removeProfilePhoto")
                    }
                    if photoLoading { ProgressView("Preparing your photo…") }
                    if let photoError { ProfileStatusMessage(message: photoError) }
                } header: {
                    Text("Your photo")
                } footer: {
                    Text(social.isSignedIn ? "New photos stay private while our team reviews them. Friends keep seeing your approved photo or symbol. We save a small version without location or camera metadata." : "Your photo stays on this device. We save a small version without location or camera metadata.")
                }
                Section("Or choose a symbol") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72))], spacing: 16) {
                        ForEach(SocialStore.avatars, id: \.self) { item in
                            Button {
                                avatar = item
                                selectedPhoto = nil
                                selectedPhotoData = nil
                                removePhoto = true
                                photoError = nil
                            } label: {
                                ExplorerAvatar(avatar: item, size: 56)
                                    .padding(4)
                                    .overlay(Circle().stroke(avatar == item && !hasPhoto ? Palette.pine : .clear, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(item.capitalized)
                            .accessibilityAddTraits(avatar == item && !hasPhoto ? [.isSelected] : [])
                        }
                    }
                    .padding(.vertical, 10)
                }
                Section {
                    Toggle("Share explored countries with friends", isOn: $sharing)
                        .accessibilityIdentifier("profileSharingToggle")
                        .disabled(!social.isSignedIn || social.profile?.communityRestricted == true)
                } footer: {
                    Text(social.isSignedIn ? "Only your friends can see this list. It records what you discover in the app, never your physical location. Saved countries stay private." : "Your profile starts privately on this device. Sign in later to choose what you share with friends.")
                }
                if social.isSignedIn {
                    Section {
                        Link("Community guidelines", destination: social.communityURL)
                    } footer: {
                        Text("Keep names and photos respectful. Sexual content, hate, threats, harassment, impersonation and spam are not allowed. Saving a name or photo submits it to our team for review.")
                    }
                }
                if attemptedSave, let message = social.errorMessage {
                    Section { ProfileStatusMessage(message: message) }
                }
            }
            .disabled(social.deletionPending)
            .scrollContentBackground(.hidden)
            .background(Palette.paper)
            .navigationTitle(social.profile == nil ? "Your profile" : "Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(social.isBusy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        nameFocused = false
                        attemptedSave = true
                        Task {
                            await social.saveProfile(name: trimmedName, avatar: avatar, sharing: sharing,
                                                     photoData: selectedPhotoData, removePhoto: removePhoto && selectedPhotoData == nil)
                            if social.errorMessage == nil { dismiss() }
                        }
                    }
                    .disabled(trimmedName.isEmpty || social.isBusy || social.deletionPending || photoLoading)
                    .accessibilityIdentifier("saveProfile")
                }
            }
            .interactiveDismissDisabled(social.isBusy || photoLoading)
            .task(id: selectedPhoto) {
                guard let selectedPhoto else { photoLoading = false; return }
                photoLoading = true
                photoError = nil
                defer { if self.selectedPhoto == selectedPhoto { photoLoading = false } }
                do {
                    guard let photo = try await selectedPhoto.loadTransferable(type: SelectedAvatarPhoto.self), !Task.isCancelled else { return }
                    selectedPhotoData = photo.data
                    removePhoto = false
                } catch {
                    guard !Task.isCancelled else { return }
                    photoError = "We couldn’t open that photo. Please choose another one."
                }
            }
            .onAppear {
                guard !initialized else { return }
                initialized = true
                if let profile = social.profile {
                    name = profile.editableDisplayName
                    avatar = profile.avatar
                    sharing = profile.shareExploration
                }
            }
        }
    }
}

struct ProfileSettingsView: View {
    @Environment(SocialStore.self) private var social
    @Environment(\.dismiss) private var dismiss
    @State private var showSignIn = false
    @State private var showClearConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var showRevokeConfirmation = false
    @State private var showManualRevocationConfirmation = false
    @State private var showDeletionAlternatives = false
    @State private var apple = AppleSignInCoordinator()
    @State private var authorizingApple = false
    @State private var deletionError: String?
    @State private var sharedItem: ProfileSharedItem?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if social.isSignedIn {
                        Label("Signed in", systemImage: "checkmark.circle")
                        Button("Sign out") { Task { await social.signOut() } }
                            .disabled(social.isBusy || social.deletionPending)
                    } else {
                        Button("Sign in with Apple or email") { showSignIn = true }
                            .disabled(social.isBusy)
                            .accessibilityIdentifier("settingsSignIn")
                        if !social.isConfigured {
                            Text("Your profile is saved on this device.").foregroundStyle(Palette.muted)
                        }
                    }
                } header: { Text("Account") } footer: {
                    Text("An account is optional. Discover, Atlas and your journal work without one.")
                }
                Section {
                    Toggle("Share explored countries with friends", isOn: Binding(
                        get: { social.profile?.shareExploration ?? false },
                        set: { value in
                            guard let profile = social.profile else { return }
                            Task { await social.saveProfile(name: profile.editableDisplayName, avatar: profile.avatar, sharing: value) }
                        }
                    ))
                    .disabled(!social.isSignedIn || social.profile == nil || social.isBusy || social.deletionPending || social.profile?.communityRestricted == true)
                    .accessibilityIdentifier("settingsSharingToggle")
                    if social.isSignedIn {
                        Button("Revoke invitation links") { showRevokeConfirmation = true }
                            .disabled(social.isBusy)
                    }
                } header: { Text("Sharing") } footer: {
                    Text(social.isSignedIn ? "Friends can see your shared exploration list. Saved countries are private. Revoking links prevents unused invitations from connecting new friends." : "Sign in to share explored countries with friends. Your local profile and journal stay private.")
                }
                Section {
                    NavigationLink("Privacy & your data") { ProfilePrivacyView() }
                    if let url = social.privacyPolicyURL {
                        Link("Privacy policy", destination: url)
                    }
                    if let url = social.supportURL {
                        Link("Contact support", destination: url)
                    }
                    Link("Community guidelines", destination: social.communityURL)
                    Button("Export my data", systemImage: "square.and.arrow.up") {
                        Task {
                            if let url = await social.exportData() { sharedItem = ProfileSharedItem(url: url) }
                        }
                    }
                    .disabled(social.isBusy || social.deletionPending)
                    .accessibilityIdentifier("exportMyData")
                } header: { Text("Privacy") }
                Section {
                    Button("Clear data on this device", role: .destructive) { showClearConfirmation = true }
                        .disabled(social.isBusy || social.deletionPending)
                        .accessibilityIdentifier("clearLocalData")
                    if social.isSignedIn || social.deletionPending {
                        Button(social.deletionPending ? "Finish deleting account and data" : "Delete account and all data", role: .destructive) {
                            showDeleteConfirmation = true
                        }
                        .disabled(social.isBusy)
                        .accessibilityIdentifier("deleteAccountAndData")
                    }
                } header: { Text("Data controls") } footer: {
                    Text("Clearing this device removes its profile and journal. It does not delete an online account. Account deletion removes your account, profile, friendships and shared exploration, then clears this device. It needs an internet connection.")
                }
                if authorizingApple {
                    Section { ProgressView("Confirming your Apple account…") }
                }
                if social.deletionPending {
                    Section {
                        Label("Account deletion hasn’t finished. Reconnect and try again to remove your online data.", systemImage: "exclamationmark.circle")
                            .font(.footnote)
                    }
                }
                if (showDeletionAlternatives || social.deletionPending) && social.requiresAppleAuthorizationForDeletion {
                    Section {
                        Button("Delete without Apple authorization…", role: .destructive) {
                            showManualRevocationConfirmation = true
                        }
                        .disabled(social.isBusy || authorizingApple)
                        .accessibilityIdentifier("deleteWithManualAppleRevocation")
                    } footer: {
                        Text("If you can’t confirm with Apple, you can still delete your WorldNiche account. You’ll then remove WorldNiche from Sign in with Apple in your Apple Account settings.")
                    }
                }
                if social.appleRevocationNeedsManualAction {
                    Section("One Apple setting to finish") {
                        Text("Your WorldNiche account and data have been deleted. Open the Settings app, tap your name, then Sign in with Apple. Select WorldNiche and choose Delete to stop using Apple sign-in for this app.")
                            .font(.subheadline)
                        Link("Apple’s instructions", destination: URL(string: "https://support.apple.com/102571")!)
                        Button("I’ve finished this step") { social.dismissAppleRevocationNotice() }
                            .accessibilityIdentifier("dismissAppleRevocationNotice")
                    }
                    .accessibilityIdentifier("manualAppleRevocationInstructions")
                }
                if let message = deletionError ?? social.errorMessage {
                    Section { ProfileStatusMessage(message: message) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.paper)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .disabled(authorizingApple)
            .interactiveDismissDisabled(authorizingApple || social.isBusy)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(authorizingApple || social.isBusy) } }
            .sheet(isPresented: $showSignIn) { ProfileSignInView() }
            .sheet(item: $sharedItem) { item in ProfileShareSheet(url: item.url) }
            .confirmationDialog("Clear data on this device?", isPresented: $showClearConfirmation, titleVisibility: .visible) {
                Button("Clear device data", role: .destructive) {
                    Task { await social.clearLocalData() }
                }
            } message: {
                Text("This removes your local profile, explored countries and saved countries, and signs you out on this device. An online account and its shared data will remain until you sign in and delete it.")
            }
            .confirmationDialog("Delete your account and all data?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete account and all data", role: .destructive) { deleteAccount() }
            } message: {
                Text("Your account, profile, friends, invitation links and shared exploration will be permanently removed, along with your profile and journal on this device. This can’t be undone.")
            }
            .confirmationDialog("Delete WorldNiche data and finish Apple removal manually?", isPresented: $showManualRevocationConfirmation, titleVisibility: .visible) {
                Button("Delete account and all data", role: .destructive) {
                    deletionError = nil
                    Task { await social.deleteAccountAndData(appleManualRevocation: true) }
                }
            } message: {
                Text("This permanently deletes your WorldNiche account and data. After it succeeds, we’ll show how to remove WorldNiche from your Apple Account. This can’t be undone.")
            }
            .confirmationDialog("Revoke your invitation links?", isPresented: $showRevokeConfirmation, titleVisibility: .visible) {
                Button("Revoke links", role: .destructive) { Task { await social.revokeInvitations() } }
            } message: {
                Text("Unused links will stop working. Your existing friendships stay connected. You can create a new invitation at any time.")
            }
        }
    }

    private func deleteAccount() {
        deletionError = nil
        Task {
            if social.deletionPending || !social.requiresAppleAuthorizationForDeletion {
                // A previous request may have deleted the account and revoked
                // Apple access. Confirm it with retained proof before asking
                // Apple for another authorization that may no longer exist.
                let result = await social.deleteAccountAndData()
                guard result == .appleAuthorizationRequired else { return }
            }
            showDeletionAlternatives = true
            authorizingApple = true
            do {
                let authorization = try await apple.authorize()
                authorizingApple = false
                await social.deleteAccountAndData(appleAuthorizationCode: authorization.authorizationCode,
                                                  appleNonce: authorization.nonce)
            } catch {
                authorizingApple = false
                if !AppleSignInCoordinator.isCancellation(error) {
                    deletionError = "Apple authorization couldn’t be completed. Try again, or delete your WorldNiche account and finish Apple removal manually."
                }
            }
        }
    }
}

struct ProfileSignInView: View {
    @Environment(SocialStore.self) private var social
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var email = ""
    @State private var code = ""
    @State private var showingCode = false
    @State private var apple = AppleSignInCoordinator()
    @State private var authorizingApple = false
    @State private var localError: String?
    @State private var lastSubmittedCode: String?
    @FocusState private var focusedField: Field?
    private enum Field { case email, code }

    private var cleanedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var emailLooksValid: Bool {
        cleanedEmail.utf8.count <= 254 && cleanedEmail.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
    }
    private var working: Bool { social.isBusy || authorizingApple }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: showingCode ? "envelope.badge" : "person.crop.circle")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(Palette.pine)
                            .accessibilityHidden(true)
                        Text(showingCode ? "Check your inbox." : "Your world, connected.")
                            .scaledFont(size: 31, design: .serif).foregroundStyle(Palette.pine)
                        Text(showingCode ? "Enter the six-digit code sent to \(social.emailForCode ?? cleanedEmail)." : "Choose Apple or your email. No password to remember, and your email stays private from friends.")
                            .font(.subheadline).foregroundStyle(Palette.muted)
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }
                if !social.isConfigured {
                    Section {
                        Label("Sign-in will be available once the account service is connected. You can keep exploring without an account.", systemImage: "info.circle")
                            .font(.footnote).foregroundStyle(Palette.muted)
                            .accessibilityIdentifier("signInNotConfigured")
                    }
                }
                if showingCode { codeSection } else { signInOptions }
                if working {
                    Section { ProgressView(authorizingApple ? "Connecting with Apple…" : "One moment…") }
                }
                if let message = localError ?? social.errorMessage {
                    Section { ProfileStatusMessage(message: message) }
                }
                Section {
                    NavigationLink("Privacy & your data") { ProfilePrivacyView() }
                } footer: {
                    Text(social.deletionPending
                         ? "Use the existing account’s email to finish deletion. If it has already been removed or you can’t receive a code, contact support to confirm completion."
                         : "New here? Signing in creates your private account. You stay signed in on this device, and can sign out or delete your account and data in Settings.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.paper)
            .navigationTitle(showingCode ? "Email sign-in" : "Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(working)
                }
            }
            .interactiveDismissDisabled(working)
            .onAppear {
                social.errorMessage = nil
                if let pendingEmail = social.emailForCode {
                    email = pendingEmail
                    showingCode = true
                }
            }
        }
    }

    private var signInOptions: some View {
        Group {
            Section {
                SignInWithAppleButton(.continue) { request in
                    focusedField = nil
                    localError = nil
                    social.errorMessage = nil
                    authorizingApple = true
                    do { try apple.prepare(request) }
                    catch { localError = error.localizedDescription }
                } onCompletion: { result in
                    do {
                        let authorization = try apple.complete(result)
                        Task {
                            await social.signInWithApple(identityToken: authorization.identityToken,
                                                         nonce: authorization.nonce, name: authorization.name)
                            authorizingApple = false
                            if social.isSignedIn { dismiss() }
                        }
                    } catch {
                        authorizingApple = false
                        if !AppleSignInCoordinator.isCancellation(error) {
                            localError = "Apple sign-in couldn’t be completed. Please try again."
                        }
                    }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .disabled(working || !social.isAppleSignInAvailable || social.deletionPending)
                .accessibilityIdentifier("signInWithApple")
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } footer: {
                if social.deletionPending {
                    Text("Use an email code to finish deleting your existing account.")
                } else if social.isConfigured && !social.isAppleSignInAvailable {
                    Text("Apple sign-in is not available yet. You can use an email code.")
                        .accessibilityIdentifier("appleSignInNotConfigured")
                }
            }
            Section("Or use your email") {
                TextField("you@example.com", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($focusedField, equals: .email)
                    .disabled(working)
                    .onSubmit { if emailLooksValid && !working { requestCode() } }
                    .accessibilityIdentifier("signInEmailField")
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = resendSeconds(at: context.date)
                    Button(remaining > 0 ? "Send code in \(remaining)s" : "Email me a code") { requestCode() }
                        .disabled(!emailLooksValid || working || !social.isConfigured || remaining > 0)
                        .accessibilityIdentifier("requestEmailCode")
                }
            }
        }
    }

    private var codeSection: some View {
        Group {
            Section("Six-digit code") {
                TextField("000000", text: $code)
                    .font(.system(.title, design: .monospaced).weight(.medium))
                    .tracking(8)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .code)
                    .disabled(working)
                    .accessibilityLabel("Six-digit email code")
                    .accessibilityIdentifier("emailCodeField")
                    .onChange(of: code) { _, value in
                        let digits = String(value.filter { $0.isASCII && $0.isNumber }.prefix(6))
                        if code != digits { code = digits }
                        if digits.count < 6 { lastSubmittedCode = nil }
                        if digits.count == 6, digits != lastSubmittedCode, !working { verifyCode(digits) }
                    }
                Button("Continue") { verifyCode(code) }
                    .disabled(code.count != 6 || working || !social.isConfigured)
                    .accessibilityIdentifier("verifyEmailCode")
            }
            Section {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = resendSeconds(at: context.date)
                    Button(remaining > 0 ? "Send another code in \(remaining)s" : "Send another code") { requestCode() }
                        .disabled(working || !social.isConfigured || remaining > 0)
                        .accessibilityIdentifier("resendEmailCode")
                }
                Button("Use a different email") {
                    showingCode = false
                    code = ""
                    lastSubmittedCode = nil
                    localError = nil
                    social.errorMessage = nil
                    focusedField = .email
                }
                .disabled(working)
                .accessibilityIdentifier("changeSignInEmail")
            } footer: {
                Text("Check your spam folder too. Only your most recent code will work.")
            }
        }
    }

    private func resendSeconds(at date: Date) -> Int {
        max(0, Int(ceil((social.emailCodeResendAvailableAt ?? .distantPast).timeIntervalSince(date))))
    }

    private func requestCode() {
        guard social.isConfigured, !working, emailLooksValid else { return }
        localError = nil
        focusedField = nil
        Task {
            await social.requestCode(email: cleanedEmail)
            if social.errorMessage == nil, social.emailForCode != nil {
                code = ""
                lastSubmittedCode = nil
                showingCode = true
                focusedField = .code
            }
        }
    }

    private func verifyCode(_ value: String) {
        guard value.count == 6, !working, social.isConfigured else { return }
        lastSubmittedCode = value
        localError = nil
        focusedField = nil
        Task {
            await social.verifyCode(code: value)
            if social.isSignedIn { dismiss() }
            else { focusedField = .code }
        }
    }
}

private struct ProfileFriendView: View {
    private let friendID: UUID
    init(friend: ExplorerFriend) { friendID = friend.id }
    @Environment(SocialStore.self) private var social
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCountry: Country?
    @State private var showRemove = false
    @State private var showBlock = false
    @State private var showReport = false

    private var friend: ExplorerFriend {
        social.friends.first { $0.id == friendID } ?? ExplorerFriend(
            id: friendID, displayName: "Profile unavailable", avatar: "globe",
            shareExploration: false, countryIds: [], exploredCount: 0)
    }

    private var countries: [Country] {
        guard friend.sharesExploration else { return [] }
        return friend.exploredCountryIDs.compactMap(CountryRepository.country(id:))
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 15) {
                        ProfilePhotoAvatar(symbol: friend.avatar, path: friend.avatarPath, size: 66)
                        Text(friend.displayName).scaledFont(size: 33, design: .serif).foregroundStyle(Palette.pine)
                    }
                    if !friend.sharesExploration {
                        Label("Their exploration is private.", systemImage: "lock")
                            .font(.subheadline).foregroundStyle(Palette.muted)
                    } else if countries.isEmpty {
                        Text("A whole world is waiting. Their shared discoveries will appear here.")
                            .font(.subheadline).foregroundStyle(Palette.muted)
                    } else {
                        Text("\(countries.count) countries explored in WorldNiche")
                            .font(.subheadline).foregroundStyle(Palette.muted)
                        LazyVStack(spacing: 0) {
                            ForEach(countries) { country in
                                Button { selectedCountry = country } label: { CountryRow(country: country) }
                                    .buttonStyle(.plain)
                                Divider()
                            }
                        }
                    }
                    Text("Exploration reflects curiosity in the app, not travel or physical location.")
                        .font(.footnote).foregroundStyle(Palette.muted)
                    if let message = social.errorMessage { ProfileStatusMessage(message: message) }
                }
                .padding(24).frame(maxWidth: 720).frame(maxWidth: .infinity)
            }
            .background(Palette.paper)
            .navigationTitle("Friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Friend options", systemImage: "ellipsis") {
                        Button("Report profile", systemImage: "flag") { showReport = true }
                        Button("Remove friend", systemImage: "person.badge.minus", role: .destructive) { showRemove = true }
                        Button("Block person", systemImage: "hand.raised", role: .destructive) { showBlock = true }
                    }.disabled(social.isBusy || !social.friends.contains(where: { $0.id == friendID }))
                }
            }
            .sheet(item: $selectedCountry) { CountryDetailView(country: $0) }
            .sheet(isPresented: $showReport) { ProfileReportView(friend: friend) }
            .onChange(of: social.friends.map(\.id)) { _, ids in
                if !ids.contains(friendID) { dismiss() }
            }
            .confirmationDialog("Remove \(friend.displayName)?", isPresented: $showRemove, titleVisibility: .visible) {
                Button("Remove friend", role: .destructive) {
                    Task {
                        await social.removeFriend(id: friend.id)
                        if social.errorMessage == nil { dismiss() }
                    }
                }
            } message: {
                Text("You’ll stop seeing each other’s shared exploration. You can connect again with a new invitation.")
            }
            .confirmationDialog("Block \(friend.displayName)?", isPresented: $showBlock, titleVisibility: .visible) {
                Button("Block person", role: .destructive) {
                    Task {
                        await social.blockFriend(id: friend.id)
                        if social.errorMessage == nil { dismiss() }
                    }
                }
            } message: {
                Text("This removes your friendship and prevents this person from connecting with you through an invitation.")
            }
        }
    }
}

private struct ProfileReportView: View {
    let friend: ExplorerFriend
    @Environment(SocialStore.self) private var social
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ProfileReportReason.inappropriateName
    @State private var submitted = false
    @State private var details = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Reason", selection: $reason) {
                        ForEach(ProfileReportReason.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                } header: { Text("Report \(friend.displayName)") } footer: {
                    Text("Your report includes this profile’s account identifier, the reason you choose and any details you add. The other person won’t see who reported them. You can also block them from their profile.")
                }
                Section {
                    TextField("Anything else we should know?", text: $details, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityIdentifier("reportDetails")
                        .onChange(of: details) { _, value in
                            if value.count > 500 { details = String(value.prefix(500)) }
                        }
                } header: { Text("Details, optional") } footer: {
                    Text("Please leave out passwords, private contact details and other sensitive information.")
                }
                if let message = social.errorMessage { Section { ProfileStatusMessage(message: message) } }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.paper)
            .navigationTitle("Report profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(social.isBusy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        Task {
                            await social.reportFriend(id: friend.id, reason: reason.rawValue, details: details)
                            if social.errorMessage == nil { submitted = true }
                        }
                    }.disabled(social.isBusy)
                }
            }
            .alert("Report sent", isPresented: $submitted) {
                Button("Done") { dismiss() }
            } message: {
                Text("Your report is saved for our team to review. The other person will not be notified. You can block them from their profile at any time.")
            }
            .interactiveDismissDisabled(social.isBusy)
        }
    }
}

private struct ProfilePrivacyView: View {
    @Environment(SocialStore.self) private var social

    var body: some View {
        List {
            Section("On this device") {
                Text("Your profile, explored countries and saved countries are stored on this device. WorldNiche doesn’t request your physical location or contacts. The system photo picker shares only the photo you choose, without giving WorldNiche access to your photo library.")
            }
            Section("When you connect") {
                Text("An optional account uses Sign in with Apple or an email code to sign you in. Apple can keep your personal email hidden. Your profile name, chosen symbol or photo, friends, invitations and sharing preference are stored online. New names and photos are reviewed by our team before they become visible to friends. Photos are saved without their original camera or location metadata. Your email isn’t shown to friends.")
                Text("Exploration sharing is off by default. If you turn it on, friends can see the countries you explore in WorldNiche. This is app activity, not a record of travel. Saved countries stay private.")
                Text("The account service also stores invitation links, blocks and reports used to protect the community. A first name or nickname is enough; you don’t need to share your real name.")
            }
            Section("Content and conversations") {
                Text("Public music, news and cultural content is requested directly from Apple, Google and Wikimedia. These services receive network requests. Ask Niche uses Apple Intelligence on supported devices; the app doesn’t send that conversation to a remote AI service.")
                Text("WorldNiche doesn’t include advertising, tracking or an analytics SDK.")
            }
            Section("Your choices") {
                Text("Change sharing, revoke invitation links, export your data or delete it from Settings. You can remove, block or report a friend from their profile.")
                Text("Clear device data removes local information and signs you out. To remove an online account and its data, use Delete account and all data while connected to the internet. We show a deletion error if it hasn’t completed.")
            }
            if let url = social.privacyPolicyURL {
                Section { Link("Read the privacy policy", destination: url) }
            }
            if let url = social.supportURL {
                Section { Link("Contact support", destination: url) }
            }
        }
        .font(.subheadline)
        .scrollContentBackground(.hidden)
        .background(Palette.paper)
        .navigationTitle("Privacy & your data")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ProfileStatusMessage: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.footnote)
            .foregroundStyle(Palette.muted)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("profileStatusMessage")
    }
}

private struct ProfileSharedItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ProfileShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let item: Any
        if url.scheme == "https",
           InvitationLink.token(from: url, allowedHost: "worldniche.app") != nil {
            item = ProfileInviteShareSource(url: url)
        } else {
            item = url
        }
        return UIActivityViewController(activityItems: [item], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

@MainActor
private final class ProfileInviteShareSource: NSObject, @MainActor UIActivityItemSource {
    private let url: URL
    private let metadata: LPLinkMetadata

    init(url: URL) {
        self.url = url
        let metadata = LPLinkMetadata()
        metadata.originalURL = url
        metadata.url = url
        metadata.title = "WorldNiche · Explore together"
        if let logo = UIImage(named: "AppLogo") {
            metadata.iconProvider = NSItemProvider(object: logo)
            metadata.imageProvider = NSItemProvider(object: logo)
        }
        self.metadata = metadata
        super.init()
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        url
    }

    func activityViewController(_ activityViewController: UIActivityViewController,
                                itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        url
    }

    func activityViewController(_ activityViewController: UIActivityViewController,
                                subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        "Join me on WorldNiche"
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        // Supply local artwork and text so the share sheet never needs to preview the token URL.
        metadata
    }
}
