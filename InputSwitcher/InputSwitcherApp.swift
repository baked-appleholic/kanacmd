import SwiftUI

@main
struct InputSwitcherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // メニューバーアプリのためウィンドウは不要
        Settings {
            EmptyView()
        }
    }
}
