import SwiftUI

@MainActor
enum OnboardingGallery {
    static let entries: [GalleryEntry] = OnboardingStep.allCases.flatMap { step in
        OnboardingPhase.allCases.map { phase in
            GalleryEntry(surface: "onboarding", state: step.rawValue + "-" + phase.rawValue,
                         title: "首次引导 · " + step.title + " · " + phase.title) {
                AnyView(OnboardingDemo(step: step, phase: phase).id(step.rawValue + phase.rawValue))
            }
        }
    }
}
