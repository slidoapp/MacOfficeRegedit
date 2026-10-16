import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: RegistryStore
    @EnvironmentObject var officeApps: OfficeAppsMonitor

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
                        if !officeApps.runningApps.isEmpty && store.isOfficeRegistry {
                            OfficeRunningBanner(apps: officeApps.runningApps)
                            Divider()
                        }
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
        .sheet(item: $store.sheet) { sheet in
            SheetContent(sheet: sheet)
                .environmentObject(store)
        }
        .confirmationDialog(
            store.pendingDeletion?.title ?? "",
            isPresented: Binding(get: { store.pendingDeletion != nil }, set: { if !$0 { store.pendingDeletion = nil } }),
            presenting: store.pendingDeletion
        ) { deletion in
            Button("Delete", role: .destructive) {
                store.confirmDeletion(deletion)
            }
            Button("Cancel", role: .cancel) {}
        } message: { deletion in
            Text(deletion.message)
        }
        .confirmationDialog(
            "Import Registry File",
            isPresented: Binding(get: { store.pendingImport != nil }, set: { if !$0 { store.pendingImport = nil } }),
            presenting: store.pendingImport
        ) { pendingImport in
            Button("Import") {
                store.performImport(pendingImport)
            }
            Button("Cancel", role: .cancel) {}
        } message: { pendingImport in
            Text(importMessage(pendingImport))
        }
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

private func importMessage(_ pendingImport: RegistryStore.PendingImport) -> String {
    let keys = pendingImport.document.keys
    var message = "Adding information can unintentionally change or delete values and cause Office to stop working correctly. "
        + "Are you sure you want to import \(keys.filter { !$0.isDeletion }.count) key(s) from \"\(pendingImport.url.lastPathComponent)\"?"
    let deletions = keys.filter(\.isDeletion).map { RegistryPath.qualified($0.path) }
    if !deletions.isEmpty {
        let listed = deletions.prefix(5).joined(separator: "\n")
        let more = deletions.count > 5 ? "\n…and \(deletions.count - 5) more" : ""
        message += "\n\nThe file also DELETES these keys with all their subkeys:\n\(listed)\(more)"
    }
    let deletedValues = keys.flatMap(\.values).filter { $0.data == nil }.count
    if deletedValues > 0 {
        message += "\n\nIt deletes \(deletedValues) value(s)."
    }
    return message
}

private struct SheetContent: View {
    @EnvironmentObject var store: RegistryStore
    let sheet: RegistryStore.Sheet

    var body: some View {
        switch sheet {
        case .editValue(let value, let isNew):
            ValueEditorSheet(value: value, isNew: isNew) { edited in
                try store.saveValue(edited, originalName: isNew ? nil : value.name)
            }
        case .newKey(let parentId):
            NameSheet(title: "New Key", prompt: "Key name:", initialName: store.suggestedNewKeyName(parentId: parentId)) { name in
                try store.createKey(named: name, parentId: parentId)
            }
        case .renameKey(let key):
            NameSheet(title: "Rename Key", prompt: "Key name:", initialName: key.name) { name in
                try store.renameKey(key, to: name)
            }
        case .renameValue(let value):
            NameSheet(title: "Rename Value", prompt: "Value name:", initialName: value.name) { name in
                try store.renameValue(value, to: name)
            }
        case .find:
            FindView()
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

private struct OfficeRunningBanner: View {
    let apps: [String]

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text("\(ListFormatter.localizedString(byJoining: apps)) \(apps.count == 1 ? "is" : "are") running. Office reads these settings at launch and may overwrite changes when it quits — quit Office apps before editing.")
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.12))
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
            .environmentObject(OfficeAppsMonitor())
    }
}
