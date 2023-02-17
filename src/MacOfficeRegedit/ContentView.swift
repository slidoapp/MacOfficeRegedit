import SwiftUI

struct ContentView: View {
    @State private var selectedKey: RegistryKey?
    @State private var selectedValue: RegistryValue.ID?
    var reader: Reader
    
    var body: some View {
        NavigationSplitView {
            List(self.reader.fetchKeys(), id: \.self, children: \.children, selection: $selectedKey) { item in
                Text(item.name)
            }
        } detail: {
            if let selectedKey {
                Table(self.reader.fetchValues(nodeId: selectedKey.id), selection: $selectedValue) {
                    TableColumn("Name", value: \.name)
                    TableColumn("Type", value: \.typeString)
                    TableColumn("Data", value: \.dataString)
                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(reader: Reader())
    }
}
