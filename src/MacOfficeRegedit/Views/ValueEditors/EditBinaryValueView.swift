import SwiftUI

struct EditBinaryValueView: View {
    static let windowId = "EditBinaryValue"
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataStore: DataStore
    
    let regValueId: RegistryValueTableItem.ID?
    
    init(regValueId: RegistryValueTableItem.ID?) {
        self.regValueId = regValueId
    }
    
    var body: some View {
        Text(/*@START_MENU_TOKEN@*/"Hello, World!"/*@END_MENU_TOKEN@*/)
            .navigationTitle("Edit Binary Value")
    }
}

struct EditBinaryValueView_Previews: PreviewProvider {
    static let previewDataStore = DataStore(isPreview: true)
    static var previews: some View {
        EditBinaryValueView(regValueId: previewDataStore.valueTableItems[0].id)
            .environmentObject(DataStore(isPreview: true))
    }
}
