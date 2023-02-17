import SwiftUI

@main
struct MacOfficeRegeditApp: App {
    let reader = Reader()

    var body: some Scene {
        WindowGroup {
            ContentView(reader: reader)
        }
    }
}
