import SwiftUI

@main
struct GameLabTVApp: App {
    var body: some Scene {
        WindowGroup {
            RootTVView()
                .onAppear {
                    VoicePack.selfCheck()
                    GameSocketManager.shared.connect(to: AppConstants.serverURL)
                }
        }
    }
}
