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

        
        WindowGroup(EditStringValueView.windowId, id: EditStringValueView.windowId, for: RegistryValueTableItem.ID.self) { $regValue in
            EditStringValueView(regValueId: regValue)
                .environmentObject(dataStore)
        }
        .windowResizabilityContentSize()

        WindowGroup(EditNumericValueView.windowId, id: EditNumericValueView.windowId, for: RegistryValueTableItem.ID.self) { $regValue in
            EditNumericValueView(regValueId: regValue)
                .environmentObject(dataStore)

        }
        .windowResizabilityContentSize()

        WindowGroup(EditBinaryValueView.windowId, id: EditBinaryValueView.windowId, for: RegistryValueTableItem.ID.self) { $regValue in
            EditBinaryValueView(regValueId: regValue)
                .environmentObject(dataStore)
        }
    }
}

extension Scene {
    func windowResizabilityContentSize() -> some Scene {
        if #available(macOS 13.0, *) {
            return windowResizability(.contentSize)
        } else {
            return self
        }
    }
}
