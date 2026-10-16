import SwiftUI

/// Called when the user confirms an editor. Throws to keep the editor open and show the error inline.
typealias ValueCommitHandler = (RegistryValue) throws -> Void

/// Shared layout of all value editors, modelled after the Windows regedit dialogs:
/// "Value name" on top, type-specific data editor in the middle, OK/Cancel at the bottom.
struct ValueEditorForm<DataEditor: View>: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    @Binding var name: String
    let isNameEditable: Bool
    let canCommit: Bool
    let commit: () throws -> Void
    @ViewBuilder let dataEditor: () -> DataEditor

    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            Text("Value name:")
            TextField("", text: $name)
                .disabled(!isNameEditable)
                .accessibilityIdentifier("valueName")

            dataEditor()

            if let errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("OK") {
                    do {
                        try commit()
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canCommit)
            }
        }
        .padding()
    }
}

/// Picks the editor matching the value's data, like double-clicking a value in Windows regedit.
struct ValueEditorSheet: View {
    let value: RegistryValue
    let isNew: Bool
    let onCommit: ValueCommitHandler

    var body: some View {
        // A value that is not set has no data to go by, so pick the editor (and storage) by its type.
        let value = value.data == .none
            ? RegistryValue(keyId: value.keyId, name: value.name, type: value.type, data: value.type.defaultData)
            : value
        switch value.data {
        case .dword, .qword:
            EditNumericValueView(value: value, isNew: isNew, onCommit: onCommit)
        case .multiString:
            EditMultiStringValueView(value: value, isNew: isNew, onCommit: onCommit)
        case .binary:
            EditBinaryValueView(value: value, isNew: isNew, onCommit: onCommit)
        case .string, .none:
            EditStringValueView(value: value, isNew: isNew, onCommit: onCommit)
        }
    }
}
