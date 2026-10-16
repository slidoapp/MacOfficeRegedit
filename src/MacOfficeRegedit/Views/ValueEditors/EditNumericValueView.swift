import SwiftUI

/// Editor for `REG_DWORD` and `REG_QWORD` values.
struct EditNumericValueView: View {
    enum Base: Hashable {
        case hexadecimal, decimal

        var radix: Int { self == .hexadecimal ? 16 : 10 }
    }

    let original: RegistryValue
    let isNew: Bool
    let onCommit: ValueCommitHandler

    @State private var name: String
    @State private var text: String
    @State private var base = Base.hexadecimal

    init(value: RegistryValue, isNew: Bool, onCommit: @escaping ValueCommitHandler) {
        self.original = value
        self.isNew = isNew
        self.onCommit = onCommit
        _name = State(initialValue: value.name)
        _text = State(initialValue: String(EditNumericValueView.number(of: value.data), radix: 16))
    }

    private var isQword: Bool {
        if case .qword = original.data {
            return true
        }
        return false
    }

    private var maximum: UInt64 { isQword ? UInt64.max : UInt64(UInt32.max) }

    private var parsed: UInt64? { EditNumericValueView.parse(text, base: base, maximum: maximum) }

    var body: some View {
        ValueEditorForm(
            title: isQword ? "Edit QWORD (64-bit) Value" : "Edit DWORD (32-bit) Value",
            name: $name,
            isNameEditable: isNew,
            canCommit: parsed != nil,
            commit: {
                guard let number = parsed else {
                    throw RegistryError.invalidData("The value data is not a valid number.")
                }
                var value = original
                value.name = name
                value.data = isQword ? .qword(number) : .dword(UInt32(number))
                try onCommit(value)
            }
        ) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading) {
                    Text("Value data:")
                    TextField("", text: $text)
                        .font(.body.monospaced())
                        .accessibilityIdentifier("valueData")
                    if parsed == nil {
                        Text(text.isEmpty ? "Enter a number." : "Must be a \(base == .hexadecimal ? "hexadecimal" : "decimal") number up to \(String(maximum, radix: base.radix)).")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                Picker("Base", selection: $base) {
                    Text("Hexadecimal").tag(Base.hexadecimal)
                    Text("Decimal").tag(Base.decimal)
                }
                .pickerStyle(.radioGroup)
                .onChange(of: base) { [base] newBase in
                    // Convert the current number like Windows does when switching base.
                    if let number = EditNumericValueView.parse(text, base: base, maximum: maximum) {
                        text = String(number, radix: newBase.radix)
                    }
                }
            }
        }
        .frame(width: 440)
    }

    nonisolated static func number(of data: RegistryData) -> UInt64 {
        switch data {
        case .dword(let number): return UInt64(number)
        case .qword(let number): return number
        default: return 0
        }
    }

    /// Parses user input; accepts an optional `0x` prefix in hexadecimal mode. Empty input means 0, like Windows.
    nonisolated static func parse(_ text: String, base: Base, maximum: UInt64) -> UInt64? {
        var digits = text.trimmingCharacters(in: .whitespaces)
        if base == .hexadecimal, digits.lowercased().hasPrefix("0x") {
            digits.removeFirst(2)
        }
        if digits.isEmpty {
            return 0
        }
        guard let number = UInt64(digits, radix: base.radix), number <= maximum else {
            return nil
        }
        return number
    }
}

struct EditNumericValueView_Previews: PreviewProvider {
    static var previews: some View {
        EditNumericValueView(
            value: RegistryValue(keyId: 1, name: "Lcid", type: .REG_DWORD, data: .dword(1051)),
            isNew: false,
            onCommit: { _ in }
        )
    }
}
