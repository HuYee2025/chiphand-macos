import SwiftUI

@main
struct ChipHandApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("薯片手", id: "control") {
            MenuBarView(model: model)
        }
        .defaultSize(width: 380, height: 740)
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            Image(systemName: model.menuIcon)
        }
        .menuBarExtraStyle(.window)
    }
}
