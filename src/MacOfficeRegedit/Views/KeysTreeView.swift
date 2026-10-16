import SwiftUI

/// The key hierarchy (left pane). Expansion is driven by the store so that "Go to", "Find" and the
/// address bar can reveal deeply nested keys.
struct KeysTreeView: View {
    @EnvironmentObject var store: RegistryStore
    /// `List` writes its selection during view updates; forwarding it from `onChange` keeps the store's
    /// resulting changes (values, address) out of the view update.
    @State private var selection: Int64?

    var body: some View {
        List(selection: $selection) {
            KeyNodeView(key: .root)
        }
        .listStyle(.sidebar)
        .onChange(of: selection) { selection in
            if store.selectedKeyId != selection {
                store.selectedKeyId = selection
            }
        }
        .onReceive(store.$selectedKeyId) { selectedKeyId in
            if selection != selectedKeyId {
                selection = selectedKeyId
            }
        }
        .onDeleteCommand {
            store.beginDelete(in: .keys)
        }
        .accessibilityIdentifier("keysTree")
    }
}

private struct KeyNodeView: View {
    @EnvironmentObject var store: RegistryStore
    let key: RegistryKey

    var body: some View {
        if store.hasChildren(key.id) {
            DisclosureGroup(isExpanded: expansion) {
                ForEach(store.children(of: key.id)) { child in
                    KeyNodeView(key: child)
                }
            } label: {
                KeyRowView(key: key)
            }
        } else {
            KeyRowView(key: key)
        }
    }

    private var expansion: Binding<Bool> {
        Binding(
            get: { store.expandedKeyIds.contains(key.id) },
            set: { isExpanded in
                // Avoid publishing a change when SwiftUI merely re-reports the current state.
                guard isExpanded != store.expandedKeyIds.contains(key.id) else {
                    return
                }
                if isExpanded {
                    store.expandedKeyIds.insert(key.id)
                } else {
                    store.expandedKeyIds.remove(key.id)
                }
            }
        )
    }
}

private struct KeyRowView: View {
    @EnvironmentObject var store: RegistryStore
    let key: RegistryKey

    var body: some View {
        Label {
            Text(key.name)
        } icon: {
            Image(nsImage: NSImage(named: key.isRoot ? NSImage.computerName : NSImage.folderName) ?? NSImage())
                .resizable()
                .frame(width: 16, height: 16)
        }
        .help(store.path(of: key.id))
        .tag(key.id)
        // Doesn't interfere with selection; records that the user is working in the tree.
        .simultaneousGesture(TapGesture().onEnded {
            store.focusedPane = .keys
        })
        .contextMenu {
            KeyContextMenu(key: key)
        }
    }
}

struct KeyContextMenu: View {
    @EnvironmentObject var store: RegistryStore
    let key: RegistryKey

    var body: some View {
        if store.hasChildren(key.id) {
            Button(store.expandedKeyIds.contains(key.id) ? "Collapse" : "Expand") {
                store.toggleExpanded(key.id)
            }
            Button("Expand All") {
                store.expandAll(under: key.id)
            }
        }
        Menu("New") {
            Button("Key") {
                store.selectedKeyId = key.id
                store.beginNewKey()
            }
            if !key.isRoot {
                Divider()
                ForEach(RegistryValueType.creatable, id: \.self) { type in
                    Button(type.newMenuTitle) {
                        store.selectedKeyId = key.id
                        store.beginNewValue(type: type)
                    }
                }
            }
        }
        .disabled(!store.canEdit)
        Button("Find…") {
            store.sheet = .find
        }
        Divider()
        Button("Delete") {
            store.selectedKeyId = key.id
            store.beginDelete(in: .keys)
        }
        .disabled(!store.canEdit || key.isRoot)
        Button("Rename") {
            store.selectedKeyId = key.id
            store.beginRename(in: .keys)
        }
        .disabled(!store.canEdit || key.isRoot)
        Divider()
        Button("Copy Key Name") {
            store.selectedKeyId = key.id
            store.copyKeyName()
        }
    }
}

struct KeysTreeView_Previews: PreviewProvider {
    static var previews: some View {
        KeysTreeView()
            .environmentObject(RegistryStore())
    }
}
