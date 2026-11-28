import SwiftUI
import UIKit

@MainActor private let buttonImpact = UIImpactFeedbackGenerator(style: .light)

// Fire on activation so a cancelled press or a scroll stays silent.
@MainActor private func hapticAction(_ action: @escaping () -> Void) -> @MainActor () -> Void {
    {
        buttonImpact.impactOccurred()
        action()
    }
}

@MainActor extension Button {
    static func haptic(action: @escaping () -> Void, @ViewBuilder label: () -> Label) -> Self {
        Self(action: hapticAction(action), label: label)
    }
}

@MainActor extension Button where Label == Text {
    static func haptic(_ title: LocalizedStringKey, role: ButtonRole? = nil, action: @escaping () -> Void) -> Self {
        Self(title, role: role, action: hapticAction(action))
    }
}

@MainActor extension Button where Label == SwiftUI.Label<Text, Image> {
    static func haptic(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> Self {
        Self(title, systemImage: systemImage, action: hapticAction(action))
    }
}
