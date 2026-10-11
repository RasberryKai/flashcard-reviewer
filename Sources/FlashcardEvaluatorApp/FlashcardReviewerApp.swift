import Foundation
import SwiftUI

@main
struct FlashcardReviewerApp: App {
    @StateObject private var model: AppModel
    @AppStorage(ReviewerAppearance.storageKey) private var appearance: ReviewerAppearance = .dark

    init() {
        let storageDirectory = ProcessInfo.processInfo.environment["FLASHCARD_REVIEWER_STORAGE_DIRECTORY"]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { path in
                path.isEmpty ? nil : URL(fileURLWithPath: path, isDirectory: true)
            }
        _model = StateObject(wrappedValue: AppModel(storageDirectory: storageDirectory))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 690)
                .preferredColorScheme(appearance.colorScheme)
                .onAppear { NSApp.appearance = appearance.nativeAppearance }
                .onChange(of: appearance) { _, value in
                    NSApp.appearance = value.nativeAppearance
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New session…") { model.showNewSession = true }
                    .keyboardShortcut("n", modifiers: [.command])
                    .disabled(model.showExport)
            }
        }
    }
}
