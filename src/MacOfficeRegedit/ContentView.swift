import SwiftUI

struct ContentView: View {
    @State private var selection: RegistryKey?
    var reader: Reader
    
    var body: some View {
        NavigationSplitView {
            List(self.reader.fetchKeys(), id: \.self, children: \.children, selection: $selection) { item in
                Text(item.name)
            }
        } detail: {
            Text("Detail")
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(reader: Reader())
    }
}
