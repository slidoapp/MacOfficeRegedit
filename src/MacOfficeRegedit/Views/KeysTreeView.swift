
import SwiftUI

struct KeysTreeView: View {
    @EnvironmentObject var dataStore: DataStore
    
    var body: some View {
        List(self.dataStore.allKeys, id: \.self, children: \.children, selection: $dataStore.selectedKey) { item in
            HStack {
                Image(nsImage: NSImage(named: NSImage.folderName) ?? NSImage())
                    .resizable()
                    .frame(width: 16, height: 16)
                Text(item.name).help(item.path)
            }
            .contextMenu {
                Group {
                    Button("Expand...") { }.disabled(true)
                    Button("New") { }.disabled(true)
                    Button("Find...") { }.disabled(true)
                }
                Divider()
                Group {
                    Button("Delete") { dataStore.deleteKey(id: item.id) }
                    Button("Rename") { }.disabled(true)
                }
                Divider()
                Group {
                    Button("Export") { }.disabled(true)
                    Button("Permissions") { }.disabled(true)
                }
                Divider()
                Group {
                    Button("Copy Key Name") { }.disabled(true)
                    Button("Go to") { }.disabled(true)
                }
            }
        }
    }
}

struct KeysTreeView_Previews: PreviewProvider {
    static var previews: some View {
        KeysTreeView()
    }
}
