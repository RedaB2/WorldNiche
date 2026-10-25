import SwiftUI

/// Remote photos are held only by the visible view and discarded as soon as access changes.
struct ProfilePhotoAvatar: View {
    @Environment(SocialStore.self) private var social
    @Environment(\.scenePhase) private var scenePhase
    let symbol: String
    var path: String? = nil
    var localID: String? = nil
    var previewData: Data? = nil
    var size: CGFloat = 44
    @State private var remoteData: Data?
    @State private var photoLoadID: UUID?
    @State private var retryGeneration = 0

    private var canReadRemote: Bool {
        guard social.isSignedIn, !social.deletionPending, let path else { return false }
        return social.profile?.referencesPhoto(path) == true || social.friends.contains { $0.avatarPath == path }
    }
    private var accessID: String {
        "\(social.profile?.id?.uuidString ?? "guest")|\(canReadRemote)|\(path ?? "")|\(retryGeneration)"
    }
    private var imageData: Data? {
        if let previewData { return previewData }
        if let localID { return AvatarPhotoFiles.load(localID) }
        return canReadRemote ? remoteData : nil
    }

    var body: some View {
        Group {
            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: size, height: size).clipShape(Circle())
            } else {
                ExplorerAvatar(avatar: symbol, size: size)
            }
        }
        .accessibilityHidden(true)
        .onChange(of: social.profilePhotoRefreshID) { _, _ in retryFailedPhoto() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { retryFailedPhoto() }
        }
        .task(id: accessID) {
            let loadID = UUID()
            photoLoadID = loadID
            defer { if photoLoadID == loadID { photoLoadID = nil } }
            remoteData = nil
            guard canReadRemote, let path else { return }
            let data = await social.avatarData(path: path)
            guard !Task.isCancelled, canReadRemote else { return }
            remoteData = data
        }
    }

    private func retryFailedPhoto() {
        guard scenePhase == .active, canReadRemote, remoteData == nil,
              previewData == nil, localID == nil, photoLoadID == nil else { return }
        retryGeneration += 1
    }
}
