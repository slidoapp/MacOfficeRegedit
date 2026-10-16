import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: RegistryStore

    var body: some View {
        Group {
            if let openError = store.openError {
                DatabaseUnavailableView(message: openError)
            } else {
                NavigationSplitView {
                    KeysTreeView()
                        .navigationSplitViewColumnWidth(min: 200, ideal: 300)
                } detail: {
                    VStack(spacing: 0) {
                        AddressBar()
                        Divider()
                        ValuesTableView()
                        Divider()
                        StatusBar()
                    }
                }
            }
        }
        .navigationTitle("Registry Editor")
        .navigationSubtitle(store.isReadOnly && store.database != nil ? "\(store.databaseName) — Read-Only" : store.databaseName)
        .frame(minWidth: 760, minHeight: 420)
        .alert(
            "Registry Editor",
            isPresented: Binding(get: { store.alertMessage != nil }, set: { if !$0 { store.alertMessage = nil } }),
            presenting: store.alertMessage
        ) { _ in
            Button("OK") {}
        } message: { message in
            Text(message)
        }
    }
}

/// Windows-style address bar showing (and accepting) the path of the selected key.
private struct AddressBar: View {
    @EnvironmentObject var store: RegistryStore
    /// Local, so typing doesn't publish store changes (which would re-render the whole tree).
    @State private var text = ""

    var body: some View {
        TextField("Path", text: $text)
            .textFieldStyle(.roundedBorder)
            .font(.body.monospaced())
            .onReceive(store.$addressText) { text = $0 }
            .onSubmit {
                if !store.navigate(to: text) {
                    NSSound.beep()
                }
            }
            .accessibilityIdentifier("addressBar")
            .padding(8)
    }
}

private struct StatusBar: View {
    @EnvironmentObject var store: RegistryStore

    var body: some View {
        HStack {
            if let key = store.selectedKey, !key.isRoot {
                Text(store.values.count == 1 ? "1 value" : "\(store.values.count) values")
                if let writeTime = key.writeTime {
                    Text("·")
                    Text("Last modified \(writeTime.formatted(date: .abbreviated, time: .standard))")
                }
            }
            Spacer()
            if store.isReadOnly {
                Label("Read-only", systemImage: "lock.fill")
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }
}

private struct DatabaseUnavailableView: View {
    @EnvironmentObject var store: RegistryStore
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "externaldrive.badge.xmark")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Cannot Open Registry")
                .font(.title2)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .frame(maxWidth: 420)
            HStack {
                Button("Try Again") {
                    store.openOfficeRegistry()
                }
                Button("Open Other Database…") {
                    store.chooseDatabase()
                }
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(RegistryStore())
    }
}
