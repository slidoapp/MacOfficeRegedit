import SwiftUI

struct EditStringValueView: View {
    static let windowId = "EditStringValue"

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataStore: DataStore
    @State var valueName: String = ""
    @State var valueData: String = ""
    
    let regValueId: RegistryValueTableItem.ID?
    
    init(regValueId: RegistryValueTableItem.ID?) {
        self.regValueId = regValueId
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Value name:")
            TextField("", text: $valueName)
                .disabled(true)
            Text("Value data:")
            TextField("", text: $valueData)
            HStack {
                Spacer()
                Button("OK") {}
                Button("Cancel") {
                    dismiss()
                }
            }
        }
        .padding(.all)
        .frame(width: 400, height: 200)
        .navigationTitle("Edit String")
        .onAppear {
            loadState()
        }
    }
    
    private func loadState() {
        guard let regValueItem = self.dataStore.valueTableItems.first(where: { $0.id == regValueId }),
              let regValue = self.dataStore.regValues.first(where: { $0.name == regValueItem.name  }) else {
            return
        }
        
        self.valueName = regValue.name
        self.valueData = regValue.value as! String
    }
}

struct EditStringView_Previews: PreviewProvider {
    static let previewDataStore = DataStore(isPreview: true)
    static var previews: some View {
        EditStringValueView(regValueId: previewDataStore.valueTableItems[0].id)
            .environmentObject(DataStore(isPreview: true))
    }
}
