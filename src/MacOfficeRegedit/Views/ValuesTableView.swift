import SwiftUI

/// Values of the selected key (right pane).
struct ValuesTableView: View {
    @Environment(RegistryStore.self) private var store

    @State private var sortOrder: [KeyPathComparator<RegistryValue>] = []

    private var rows: [RegistryValue] {
        sortOrder.isEmpty ? store.values : store.values.sorted(using: sortOrder)
    }

    var body: some View {
        @Bindable var store = store
        Table(rows, selection: $store.selectedValueIds, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.displayName) { value in
                HStack(spacing: 4) {
                    Image(value.iconName)
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text(value.displayName)
                }
                .simultaneousGesture(TapGesture().onEnded {
                    store.focusedPane = .values
                })
            }
            .width(min: 120, ideal: 220)
            TableColumn("Type", value: \.type.name)
                .width(min: 90, ideal: 110)
            TableColumn("Data", value: \.data.displayString) { value in
                Text(value.data.displayString)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(value.data.displayString)
            }
        }
        .contextMenu(forSelectionType: RegistryValue.ID.self) { ids in
            menu(for: ids)
        } primaryAction: { ids in
            if let value = store.values.first(where: { ids.contains($0.id) }) {
                store.beginModify(value)
            }
        }
        .onDeleteCommand {
            store.beginDelete(in: .values)
        }
        .onChange(of: store.selectedValueIds) { _, ids in
            if !ids.isEmpty {
                store.focusedPane = .values
            }
        }
        .overlay {
            emptyState
                // Let clicks through, so the empty table's context menu (New ▸) still works.
                .allowsHitTesting(false)
        }
        .accessibilityIdentifier("valuesTable")
    }

    @ViewBuilder
    private var emptyState: some View {
        if store.selectedKey?.isRoot == true {
            ContentUnavailableView(
                RegistryPath.hive,
                systemImage: "folder",
                description: Text("Select a key to see its values.")
            )
        } else if store.selectedKey != nil, store.values.isEmpty {
            ContentUnavailableView(
                "No Values",
                systemImage: "tray",
                description: Text(store.canEdit ? "Right-click to add a value." : "This key has no values.")
            )
        }
    }

    @ViewBuilder
    private func menu(for ids: Set<RegistryValue.ID>) -> some View {
        let selected = store.values.filter { ids.contains($0.id) }
        if selected.isEmpty {
            Menu("New") {
                Button("Key") {
                    store.beginNewKey()
                }
                Divider()
                ForEach(RegistryValueType.creatable, id: \.self) { type in
                    Button(type.newMenuTitle) {
                        store.beginNewValue(type: type)
                    }
                    .disabled(!store.canEditValuesOfSelectedKey)
                }
            }
            .disabled(!store.canEdit)
        } else {
            Button("Modify…") {
                store.beginModify(selected[0])
            }
            .disabled(selected.count != 1 || !store.canEdit)
            Divider()
            Button("Delete") {
                store.selectedValueIds = ids
                store.beginDelete(in: .values)
            }
            .disabled(!store.canEdit)
            Button("Rename") {
                store.selectedValueIds = ids
                store.beginRename(in: .values)
            }
            .disabled(selected.count != 1 || !store.canEdit)
            Divider()
            Button("Copy Data") {
                store.selectedValueIds = ids
                store.copyValueData()
            }
        }
    }
}

// RegistryStore.preview() exists in Debug builds only.
#if DEBUG
#Preview("Values") {
    ValuesTableView()
        .environment(RegistryStore.preview())
        .frame(width: 700, height: 300)
}

#Preview("No values") {
    ValuesTableView()
        .environment(RegistryStore.preview(selecting: "Software\\Microsoft\\Office\\16.0"))
        .frame(width: 700, height: 300)
}
#endif
