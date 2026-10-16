import SwiftUI

/// Menu bar commands, mirroring the Windows regedit menus.
///
/// Commands are disabled while a dialog is showing: menu shortcuts are handled before text fields,
/// and assigning a new sheet would discard the edit in progress.
struct RegistryCommands: Commands {
    @ObservedObject var store: RegistryStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Menu("New") {
                Button("Key") {
                    store.beginNewKey()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(store.isModalActive || !store.canEdit || store.selectedKeyId == nil)
                Divider()
                ForEach(RegistryValueType.creatable, id: \.self) { type in
                    Button(type.newMenuTitle) {
                        store.beginNewValue(type: type)
                    }
                    .disabled(store.isModalActive || !store.canEditValuesOfSelectedKey)
                }
            }
            Divider()
            Button("Open Office Registry") {
                store.openOfficeRegistry()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .disabled(store.isModalActive)
            Button("Open Database…") {
                store.chooseDatabase()
            }
            .keyboardShortcut("o")
            .disabled(store.isModalActive)
        }

        CommandGroup(replacing: .importExport) {
            Button("Show Backups in Finder") {
                store.revealBackups()
            }
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Modify…") {
                if let value = store.selectedValues.first {
                    store.beginModify(value)
                }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(store.isModalActive || !store.canEdit || store.selectedValues.count != 1)
            Button("Rename") {
                store.beginRename()
            }
            .disabled(store.isModalActive || !store.canEdit)
            Button("Delete…") {
                store.beginDelete()
            }
            .disabled(store.isModalActive || !store.canEdit)
            Divider()
            Button("Copy Key Name") {
                store.copyKeyName()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(store.isModalActive || store.selectedKeyId == nil)
        }

        CommandGroup(after: .toolbar) {
            Button("Refresh") {
                store.reload()
            }
            .keyboardShortcut("r")
            .disabled(store.isModalActive || store.database == nil)
            Divider()
        }
    }
}
