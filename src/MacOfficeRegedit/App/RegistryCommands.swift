import SwiftUI

/// Menu bar commands, mirroring the Windows regedit menus.
struct RegistryCommands: Commands {
    @ObservedObject var store: RegistryStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Office Registry") {
                store.openOfficeRegistry()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            Button("Open Database…") {
                store.chooseDatabase()
            }
            .keyboardShortcut("o")
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Copy Key Name") {
                store.copyKeyName()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(store.selectedKeyId == nil)
        }

        CommandGroup(after: .toolbar) {
            Button("Refresh") {
                store.reload()
            }
            .keyboardShortcut("r")
            .disabled(store.database == nil)
            Divider()
        }
    }
}
