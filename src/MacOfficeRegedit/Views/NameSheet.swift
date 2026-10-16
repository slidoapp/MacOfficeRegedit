import SwiftUI

/// Small dialog asking for a key or value name, used for "New Key" and "Rename".
struct NameSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let prompt: String
    let allowsEmpty: Bool
    let onCommit: (String) throws -> Void

    @State private var name: String
    @State private var errorMessage: String?

    init(title: String, prompt: String, initialName: String, allowsEmpty: Bool = false, onCommit: @escaping (String) throws -> Void) {
        self.title = title
        self.prompt = prompt
        self.allowsEmpty = allowsEmpty
        self.onCommit = onCommit
        _name = State(initialValue: initialName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(prompt)
            TextField("", text: $name)
                .onSubmit(commit)
                .accessibilityIdentifier("name")
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
                Button("OK", action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!allowsEmpty && name.isEmpty)
            }
        }
        .padding()
        .frame(width: 360)
    }

    private func commit() {
        guard allowsEmpty || !name.isEmpty else {
            return
        }
        do {
            try onCommit(name)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
