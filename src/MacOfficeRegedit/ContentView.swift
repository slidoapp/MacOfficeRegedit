import SwiftUI

struct ContentView: View {
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.openWindow) var openWindow

    @StateObject var model = ContentModel()
    @State private var selectedValue: RegistryValue.ID?
    @State private var currentPath: String = ""
    
    var body: some View {
        VStack {
            TextField("Path", text: $model.currentPath)
            NavigationSplitView {
                List(self.model.allKeys, id: \.self, children: \.subKeys, selection: $model.selectedKey) { item in
                    HStack {
                        Image(nsImage: NSImage(named: NSImage.folderName) ?? NSImage())
                            .resizable()
                            .frame(width: 16, height: 16)
                        Text(item.name).help(item.path)
                    }
                    .contextMenu {
                        Group {
                            Button("Expand...") { }
                            Button("New") { }
                            Button("Find...") { }
                        }
                        Divider()
                        Group {
                            Button("Delete") { }
                            Button("Rename") { }
                        }
                        Divider()
                        Group {
                            Button("Export") { }
                            Button("Permissions") { }
                        }
                        Divider()
                        Group {
                            Button("Copy Key Name") { }
                            Button("Go to") { }
                        }
                    }
                }
            } detail: {
                Table(self.model.values, selection: $selectedValue) {
                    TableColumn("Name") { item in
                        HStack {
                            Image(nsImage: NSImage(named: NSImage.computerName) ?? NSImage())
                                .resizable()
                                .frame(width: 16, height: 16)
                            Text(item.nameString)
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
