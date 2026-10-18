import AuthenticationServices
import CryptoKit
import Security
import UIKit

/// Keeps a single native authorization challenge alive until Apple's response arrives.
/// Nonces and authorization codes are short-lived and are never written to disk.
@MainActor
final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate {
    struct Authorization: Sendable {
        let identityToken: String
        let authorizationCode: String
        let nonce: String
        let userID: String
        let name: String?
    }

    private struct Challenge {
        let nonce: String
        let state: String
    }

    private var challenge: Challenge?
    private var controller: ASAuthorizationController?
    private var operationID: UUID?
    private var continuation: CheckedContinuation<Authorization, Error>?
    private var presentationContext: PresentationContext?

    @MainActor
    private final class PresentationContext: NSObject, ASAuthorizationControllerPresentationContextProviding {
        let window: UIWindow

        init(window: UIWindow) { self.window = window }

        func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor { window }
    }

    func prepare(_ request: ASAuthorizationAppleIDRequest, scopes: [ASAuthorization.Scope] = [.email, .fullName]) throws {
        guard challenge == nil else { throw AuthorizationError.alreadyInProgress }
        let nonce = try Self.randomToken()
        let state = try Self.randomToken()
        challenge = Challenge(nonce: nonce, state: state)
        request.requestedScopes = scopes
        request.nonce = SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
        request.state = state
    }

    func complete(_ result: Result<ASAuthorization, Error>) throws -> Authorization {
        let expected = challenge
        challenge = nil
        let authorization = try result.get()
        guard let expected,
              let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              credential.state == expected.state,
              !credential.user.isEmpty,
              let identityToken = credential.identityToken.flatMap({ String(data: $0, encoding: .utf8) }),
              !identityToken.isEmpty,
              let authorizationCode = credential.authorizationCode.flatMap({ String(data: $0, encoding: .utf8) }),
              !authorizationCode.isEmpty else {
            throw AuthorizationError.invalidResponse
        }
        let name = credential.fullName.map { PersonNameComponentsFormatter().string(from: $0) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return Authorization(identityToken: identityToken, authorizationCode: authorizationCode,
                             nonce: expected.nonce, userID: credential.user,
                             name: name?.isEmpty == false ? name : nil)
    }

    /// Used when a destructive account action needs fresh Apple authorization.
    func authorize(scopes: [ASAuthorization.Scope] = []) async throws -> Authorization {
        guard continuation == nil, challenge == nil else { throw AuthorizationError.alreadyInProgress }
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .filter({ $0.activationState == .foregroundActive })
            .flatMap(\.windows).first(where: \.isKeyWindow) else {
            throw AuthorizationError.noPresentationWindow
        }
        let request = ASAuthorizationAppleIDProvider().createRequest()
        try prepare(request, scopes: scopes)
        let presentationContext = PresentationContext(window: window)
        self.presentationContext = presentationContext
        let operationID = UUID()
        self.operationID = operationID
        let controller = ASAuthorizationController(authorizationRequests: [request])
        self.controller = controller
        controller.delegate = self
        controller.presentationContextProvider = presentationContext
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                if Task.isCancelled {
                    finish(.failure(CancellationError()))
                } else {
                    controller.performRequests()
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.operationID == operationID else { return }
                self.controller?.cancel()
                self.finish(.failure(CancellationError()))
            }
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard self.controller === controller else { return }
        finish(.success(authorization))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        guard self.controller === controller else { return }
        finish(.failure(error))
    }

    private func finish(_ result: Result<ASAuthorization, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        operationID = nil
        controller = nil
        do { continuation.resume(returning: try complete(result)) }
        catch { continuation.resume(throwing: error) }
    }

    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        return (error as? ASAuthorizationError)?.code == .canceled
    }

    static func credentialState(forUserID userID: String) async throws -> ASAuthorizationAppleIDProvider.CredentialState {
        try await ASAuthorizationAppleIDProvider().credentialState(forUserID: userID)
    }

    private static func randomToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw AuthorizationError.secureRandomUnavailable
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private enum AuthorizationError: LocalizedError {
        case alreadyInProgress, invalidResponse, noPresentationWindow, secureRandomUnavailable

        var errorDescription: String? {
            switch self {
            case .alreadyInProgress: "An Apple sign-in is already open. Finish it before trying again."
            case .invalidResponse: "Apple sign-in couldn’t be verified. Please try again."
            case .noPresentationWindow: "Return to WorldNiche and try signing in again."
            case .secureRandomUnavailable: "A secure sign-in couldn’t be started. Please try again."
            }
        }
    }
}
