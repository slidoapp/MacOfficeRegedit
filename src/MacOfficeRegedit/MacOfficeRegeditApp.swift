import SwiftUI

@main
struct MacOfficeRegeditApp: App {
    @StateObject private var dataStore = DataStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dataStore)
                .navigationTitle("Regedit")
        }
        WindowGroup("RegValue", for: RegistryValue.ID.self) { $regValue in 
            ModifyRegValueView(regValueId: regValue)
                .environmentObject(dataStore)
                .navigationTitle("Modify")
        }
    }
}
