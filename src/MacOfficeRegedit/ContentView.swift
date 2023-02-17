import SwiftUI

struct ContentView: View {
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.openWindow) var openWindow

    @StateObject var model: ContentModel
    @State private var selectedValue: RegistryValue.ID?
    @State private var currentPath: String = ""
    
    var body: some View {
        VStack {
            TextField("Path", text: $model.currentPath)
            NavigationSplitView {
                List(self.model.allKeys, id: \.self, children: \.children, selection: $model.selectedKey) { item in
                    HStack {
                        Image(nsImage: NSImage(named: NSImage.folderName) ?? NSImage())
                            .resizable()
                            .frame(width: 16, height: 16)
                        Text(item.name).help(item.path)
                    }
                }
            } detail: {
                Table(self.model.values, selection: $selectedValue) {
                    TableColumn("Name") { item in
                        HStack {
                            Image(nsImage: NSImage(named: NSImage.computerName) ?? NSImage())
                                .resizable()
                                .frame(width: 16, height: 16)
                            Text(item.name)
                        }
                        .contextMenu {
                            Button("Modify...") {
                                self.openWindow(value: item.id)
                            }
                            Button("Modify Binary Data...") { }
                            Divider()
                            Button("Delete") { }
                            Button("Rename") { }
                        }
                    }
                    TableColumn("Type", value: \.typeString)
                    TableColumn("Data", value: \.dataString)
                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(model: ContentModel(isPreview: true))
    }
}
