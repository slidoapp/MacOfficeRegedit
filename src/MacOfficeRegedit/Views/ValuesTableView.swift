import SwiftUI

struct ValuesTableView: View {
    @EnvironmentObject var dataStore: DataStore
    
    @Environment(\.openWindow) var openWindow
    @State private var selectedValue: RegistryValueTableItem.ID?
    
    var body: some View {
        Table(self.dataStore.valueTableItems, selection: $selectedValue) {
            TableColumn("Name") { item in
                HStack {
                    Image(nsImage: NSImage(named: item.icon) ?? NSImage())
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text(item.name)
                }
                .contextMenu {
                    Button("Modify...") {
                        self.openWindow(id: item.modifyWindowId, value: item.id)
                    }
                    Button("Modify Binary Data...") { }.disabled(true)
                    Divider()
                    Button("Delete") { }.disabled(true)
                    Button("Rename") { }.disabled(true)
                }
            }
            TableColumn("Type", value: \.type)
                .width(min: 100, ideal: 100)
            TableColumn("Data", value: \.data)
        }
    }
}

struct ValuesTableView_Previews: PreviewProvider {
    static var previews: some View {
        ValuesTableView()
    }
}
