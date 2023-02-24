import SwiftUI

struct EditNumericValueView: View {
    static let windowId = "EditNumericValue"
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataStore: DataStore
    @State var valueName: String = ""
    @State var valueData: Int64 = 0
    @State var valueDataString: String = ""
    @State var base = EditorBase.Hexadecimal
    @State var windowTitle = ""
    
    let regValueId: RegistryValueTableItem.ID?
    
    init(regValueId: RegistryValueTableItem.ID?) {
        self.regValueId = regValueId
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Value name:")
            TextField("", text: $valueName)
                .disabled(true)
            HStack {
                VStack(alignment: .leading) {
                    Text("Value data:")
                    TextField("", text: $valueDataString)
                }
                Picker(selection: $base, label: Text("Base")) {
                    Text("Hexadecimal").tag(EditorBase.Hexadecimal)
                    Text("Decimal").tag(EditorBase.Decimal)
                }
                .padding(.all)
                .pickerStyle(.radioGroup)
                .onChange(of: base) {
                    self.valueDataString = self.getValueString(base: $0)
                }
            }
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
        .navigationTitle(self.windowTitle)
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
        self.valueData = regValue.value as! Int64
        self.valueDataString = getValueString(base: self.base)
        self.windowTitle = regValue.type == .REG_QWORD
            ? "Edit QWORD (64-bit) Value"
            : "Edit DWORD (32-bit) Value"
    }
    
    private func getValueString(base: EditorBase) -> String {
        let radix = base == .Decimal ? 10 : 16
        return String(self.valueData, radix: radix)
    }
    
    enum EditorBase {
        case Hexadecimal, Decimal
    }
}

struct EditNumericValueView_Previews: PreviewProvider {
    static let previewDataStore = DataStore(isPreview: true)
    static var previews: some View {
        EditNumericValueView(regValueId: previewDataStore.valueTableItems[0].id)
            .environmentObject(DataStore(isPreview: true))
    }
}
