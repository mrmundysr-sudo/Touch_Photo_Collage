import SwiftUI

@main
struct TouchPhotoCollageApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .preferredColorScheme(model.theme.colorScheme)
                .tint(Palette.primary)
        }
    }
}
