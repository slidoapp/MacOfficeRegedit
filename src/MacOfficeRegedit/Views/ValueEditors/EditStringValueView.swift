import SwiftUI

/// Editor for `REG_SZ` and `REG_EXPAND_SZ` values.
struct EditStringValueView: View {
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
        if case .string(let string) = value.data {
            _text = State(initialValue: string)
        } else {
            _text = State(initialValue: "")
        }
    }

    var body: some View {
        ValueEditorForm(
            title: original.type == .REG_EXPAND_SZ ? "Edit Expandable String" : "Edit String",
            name: $name,
            isNameEditable: isNew,
            canCommit: true,
            commit: {
                var value = original
                value.name = name
                value.data = .string(text)
                try onCommit(value)
            }
        ) {
            Text("Value data:")
            TextField("", text: $text)
                .accessibilityIdentifier("valueData")
        }
        .frame(width: 420)
    }
}

struct EditStringValueView_Previews: PreviewProvider {
    static var previews: some View {
        EditStringValueView(
            value: RegistryValue(keyId: 1, name: "Greeting", type: .REG_SZ, data: .string("Hello")),
            isNew: false,
            onCommit: { _ in }
        )
    }
}
