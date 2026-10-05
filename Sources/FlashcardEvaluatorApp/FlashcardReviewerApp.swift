import SwiftUI

@main
struct FlashcardReviewerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 690)
                .preferredColorScheme(.light)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New session…") { model.showNewSession = true }
                    .keyboardShortcut("n", modifiers: [.command])
            }
        }
    }
}
