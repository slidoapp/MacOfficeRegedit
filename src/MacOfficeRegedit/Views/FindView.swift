import SwiftUI

/// Search over key names, value names and value data. Results stay available for "Find Next" (⌘G).
struct FindView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RegistryStore.self) private var store

    @AppStorage("find.keys") private var keys = true
    @AppStorage("find.values") private var values = true
    @AppStorage("find.data") private var data = true
    @AppStorage("find.wholeString") private var wholeString = false
    @AppStorage("find.text") private var text = ""
    @State private var selection: RegistryStore.SearchResult.ID?
    @State private var hasSearched = false

    private var options: RegistryStore.SearchOptions {
        RegistryStore.SearchOptions(text: text, keys: keys, values: values, data: data, matchWholeString: wholeString)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Find")
                .font(.headline)
            HStack {
                Text("Find what:")
                TextField("", text: $text)
                    .onSubmit(search)
                    .accessibilityIdentifier("findText")
                Button("Find", action: search)
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.isEmpty || !(keys || values || data))
            }
            HStack(spacing: 16) {
                Text("Look at:")
                Toggle("Keys", isOn: $keys)
                Toggle("Values", isOn: $values)
                Toggle("Data", isOn: $data)
                Spacer()
                Toggle("Match whole string only", isOn: $wholeString)
            }

            Table(store.searchResults, selection: $selection) {
                TableColumn("Kind") { Text($0.kind.rawValue) }
                    .width(50)
                TableColumn("Match") { Text($0.match).lineLimit(1) }
                    .width(min: 120, ideal: 220)
                TableColumn("Key") { Text($0.path).lineLimit(1).truncationMode(.head).help($0.path) }
            }
            .contextMenu(forSelectionType: RegistryStore.SearchResult.ID.self) { _ in
            } primaryAction: { ids in
                if let id = ids.first {
                    go(to: id)
                }
            }
            .frame(minHeight: 240)

            HStack {
                if hasSearched {
                    Text(store.searchResults.isEmpty ? "Finished searching through the registry. No matches." : "\(store.searchResults.count) matches. Double-click to go to a match; ⌘G finds the next one.")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                Spacer()
                Button("Close", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Go To") {
                    if let selection {
                        go(to: selection)
                    }
                }
                .disabled(selection == nil)
            }
        }
        .padding()
        .frame(width: 720, height: 460)
    }

    private func search() {
        guard !text.isEmpty else {
            return
        }
        store.search(options)
        hasSearched = true
    }

    private func go(to id: RegistryStore.SearchResult.ID) {
        guard let result = store.searchResults.first(where: { $0.id == id }) else {
            return
        }
        store.showSearchResult(result)
        dismiss()
    }
}
