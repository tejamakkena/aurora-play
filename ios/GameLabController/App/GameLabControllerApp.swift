import SwiftUI

@main
struct GameLabControllerApp: App {
    var body: some Scene {
        WindowGroup {
            RootControllerView()
                .onAppear {
                    VoicePack.selfCheck()
                    GameSocketManager.shared.connect(to: AppConstants.serverURL)
                }
                .preferredColorScheme(.dark)
        }
    }
}
