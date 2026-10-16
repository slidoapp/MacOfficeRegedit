import SwiftUI

/// Editor for `REG_MULTI_SZ` values – one string per line.
struct EditMultiStringValueView: View {
    let original: RegistryValue
    let isNew: Bool
    let onCommit: ValueCommitHandler

    @State private var name: String
    @State private var text: String

    init(value: RegistryValue, isNew: Bool, onCommit: @escaping ValueCommitHandler) {
        self.original = value
        self.isNew = isNew
        self.onCommit = onCommit
        _name = State(initialValue: value.name)
        if case .multiString(let strings) = value.data {
            _text = State(initialValue: strings.joined(separator: "\n"))
        } else {
            _text = State(initialValue: "")
        }
    }

    var body: some View {
        ValueEditorForm(
            title: "Edit Multi-String",
            name: $name,
            isNameEditable: isNew,
            canCommit: true,
            commit: {
                var value = original
                value.name = name
                // Windows drops empty lines, since an empty string would terminate the list.
                value.data = .multiString(text.components(separatedBy: .newlines).filter { !$0.isEmpty })
                try onCommit(value)
            }
        ) {
            Text("Value data:")
            TextEditor(text: $text)
                .font(.body.monospaced())
                .frame(minHeight: 160)
                .border(Color(nsColor: .separatorColor))
                .accessibilityIdentifier("valueData")
        }
        .frame(width: 440)
    }
}

struct EditMultiStringValueView_Previews: PreviewProvider {
    static var previews: some View {
        EditMultiStringValueView(
            value: RegistryValue(keyId: 1, name: "Paths", type: .REG_MULTI_SZ, data: .multiString(["a", "b"])),
            isNew: false,
            onCommit: { _ in }
        )
    }
}
