import SwiftUI

@main
struct GestureControlApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("手势控制", id: "control") {
            MenuBarView(model: model)
        }
        .defaultSize(width: 348, height: 680)
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            Image(systemName: model.menuIcon)
        }
        .menuBarExtraStyle(.window)
    }
}
