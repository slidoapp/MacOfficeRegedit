import SwiftUI

struct ContentView: View {
    @EnvironmentObject var dataStore: DataStore
    
    @State private var currentPath: String = ""
    
    var body: some View {
        VStack {
            TextField("Path", text: $dataStore.currentPath)
            NavigationSplitView {
                KeysTreeView()
            } detail: {
                ValuesTableView()
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
