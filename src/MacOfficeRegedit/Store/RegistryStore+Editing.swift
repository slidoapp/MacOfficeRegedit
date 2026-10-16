import AppKit

extension RegistryStore {
    var canEdit: Bool { database != nil && !isReadOnly }

    var canEditValuesOfSelectedKey: Bool {
        canEdit && selectedKeyId != nil && selectedKeyId != RegistryKey.rootId
    }

    func beginNewKey() {
        guard canEdit, let parentId = selectedKeyId else {
            return
        }
        sheet = .newKey(parentId: parentId)
    }

    func beginNewValue(type: RegistryValueType) {
        guard canEditValuesOfSelectedKey, let keyId = selectedKeyId else {
            return
        }
        let name = uniqueName(base: "New Value", existing: values.map(\.name))
        sheet = .editValue(.makeNew(keyId: keyId, name: name, type: type), isNew: true)
    }

    func beginModify(_ value: RegistryValue) {
        guard canEdit else {
            return
        }
        sheet = .editValue(value, isNew: false)
    }

    /// The pane the user is working in, so menu commands act on what they are looking at.
    ///
    /// SwiftUI's `@FocusState` doesn't report focus for `List`/`Table` on macOS, so ask AppKit: both panes
    /// are table views, and the key tree is the one in sidebar (source list) style. Sidebars don't take
    /// keyboard focus on click, though, so otherwise use the pane that was clicked last (`focusedPane`).
    private var activePane: Pane {
        var view = NSApp?.keyWindow?.firstResponder as? NSView
        while let current = view {
            if let tableView = current as? NSTableView {
                return tableView.style == .sourceList || tableView.numberOfColumns == 1 ? .keys : .values
            }
            view = current.superview
        }
        return focusedPane
    }

    /// Renames the selected value or key. `pane` is given by context menus; menu commands use the focused pane.
    func beginRename(in pane: Pane? = nil) {
        guard canEdit else {
            return
        }
        if (pane ?? activePane) == .values {
            // Like Windows, the default value cannot be renamed.
            if selectedValues.count == 1, let value = selectedValues.first, !value.isDefault {
                sheet = .renameValue(value)
            }
        } else if let key = selectedKey, !key.isRoot {
            sheet = .renameKey(key)
        }
    }

    func beginDelete(in pane: Pane? = nil) {
        guard canEdit else {
            return
        }
        if (pane ?? activePane) == .values {
            // Never fall back to deleting the key when the values pane has focus.
            if !selectedValues.isEmpty {
                pendingDeletion = .values(selectedValues)
            }
        } else if let key = selectedKey, !key.isRoot {
            pendingDeletion = .key(key)
        }
    }

    func suggestedNewKeyName(parentId: Int64) -> String {
        uniqueName(base: "New Key", existing: children(of: parentId).map(\.name))
    }

    func createKey(named name: String, parentId: Int64) throws {
        let key = try write(verifying: parentId) { try $0.createKey(named: name, parentId: parentId) }
        reload()
        reveal(keyId: key.id)
    }

    func renameKey(_ key: RegistryKey, to newName: String) throws {
        guard newName != key.name else {
            return
        }
        try write(verifying: key.id) { try $0.renameKey(id: key.id, to: newName) }
        reload()
        updateAddress()
    }

    func saveValue(_ value: RegistryValue, originalName: String?) throws {
        try write(verifying: value.keyId) { database in
            if let originalName {
                try database.updateValue(value, originalName: originalName)
            } else {
                try database.insertValue(value)
            }
        }
        reload()
        selectedValueIds = [value.id]
    }

    func renameValue(_ value: RegistryValue, to newName: String) throws {
        guard newName != value.name else {
            return
        }
        try write(verifying: value.keyId) { try $0.renameValue(keyId: value.keyId, from: value.name, to: newName) }
        reload()
        selectedValueIds = [RegistryValue.ID(keyId: value.keyId, name: newName)]
    }

    func confirmDeletion(_ deletion: Deletion) {
        do {
            switch deletion {
            case .key(let key):
                try write(verifying: key.id) { try $0.deleteKey(id: key.id) }
                if let selectedKeyId, isKey(selectedKeyId, inSubtreeOf: key.id) {
                    self.selectedKeyId = key.parentId
                }
            case .values(let values):
                try write(verifying: values.first?.keyId) { database in
                    for value in values {
                        try database.deleteValue(keyId: value.keyId, name: value.name)
                    }
                }
            }
        } catch {
            show(error)
        }
        reload()
    }

    /// Performs a modification atomically, backing up the database first (once per opened database).
    ///
    /// `keyId` is checked to still be the key this store knows (same parent and name), so a dialog
    /// opened before Office changed the registry can't modify an unrelated key that reused the id.
    @discardableResult
    func write<T>(verifying keyId: Int64? = nil, _ operation: (RegistryDatabase) throws -> T) throws -> T {
        guard let database else {
            throw RegistryError.databaseNotFound(RegistryDatabase.officeRegistryURL)
        }
        if !hasBackedUp {
            try backup(database)
            hasBackedUp = true
        }
        var result: T?
        try database.transaction {
            if let keyId, keyId != RegistryKey.rootId {
                guard let key = keysById[keyId] else {
                    throw RegistryError.keyNotFound(keyId)
                }
                try database.verifyKey(key)
            }
            result = try operation(database)
        }
        return result!
    }

    func uniqueName(base: String, existing: [String]) -> String {
        let taken = Set(existing.map { $0.lowercased() })
        var index = 1
        while taken.contains("\(base) #\(index)".lowercased()) {
            index += 1
        }
        return "\(base) #\(index)"
    }
}
