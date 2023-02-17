import SwiftUI

struct ContentView: View {
    @StateObject var contentModel: ContentModel
    @State private var selectedValue: RegistryValue.ID?
    @State private var currentPath: String = ""
    
    var body: some View {
        VStack {
            TextField("Path", text: $contentModel.currentPath)
            NavigationSplitView {
                List(self.contentModel.allKeys, id: \.self, children: \.children, selection: $contentModel.selectedKey) { item in
                    HStack {
                        Image(nsImage: NSImage(named: NSImage.folderName) ?? NSImage())
                            .resizable()
                            .frame(width: 16, height: 16)
                        Text(item.name).help(item.path)
                    }
                }
            } detail: {
                Table(self.contentModel.values, selection: $selectedValue) {
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
        ContentView(contentModel: ContentModel(isPreview: true))
    }
}
