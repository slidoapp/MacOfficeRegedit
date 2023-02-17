import SwiftUI

@main
struct MacOfficeRegeditApp: App {
    let contentModel = ContentModel()

    var body: some Scene {
        WindowGroup {
            ContentView(contentModel: contentModel)
        }
    }
}
