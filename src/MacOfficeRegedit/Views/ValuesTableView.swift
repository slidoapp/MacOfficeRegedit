import SwiftUI

/// Values of the selected key (right pane).
struct ValuesTableView: View {
    @EnvironmentObject var store: RegistryStore

    @State private var sortOrder: [KeyPathComparator<RegistryValue>] = []

    private var rows: [RegistryValue] {
        sortOrder.isEmpty ? store.values : store.values.sorted(using: sortOrder)
    }

    var body: some View {
        Table(rows, selection: $store.selectedValueIds, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.displayName) { value in
                HStack(spacing: 4) {
                    Image(value.iconName)
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text(value.displayName)
                }
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
        }
        .accessibilityIdentifier("valuesTable")
    }

    @ViewBuilder
    private func menu(for ids: Set<RegistryValue.ID>) -> some View {
        let selected = store.values.filter { ids.contains($0.id) }
        if !selected.isEmpty {
            Button("Copy Data") {
                store.selectedValueIds = ids
                store.copyValueData()
            }
        }
    }
}

struct ValuesTableView_Previews: PreviewProvider {
    static var previews: some View {
        ValuesTableView()
            .environmentObject(RegistryStore())
    }
}
