import AppKit
import Foundation

/// Application state: the open database, the key tree, the selection and all user operations.
@MainActor
final class RegistryStore: ObservableObject {
    // MARK: - State

    @Published private(set) var database: RegistryDatabase?
    @Published private(set) var openError: String?

    @Published private(set) var keysById: [Int64: RegistryKey] = [:]
    /// Child keys of each key, sorted by name like Windows regedit.
    @Published private(set) var childrenById: [Int64: [RegistryKey]] = [:]
    @Published var expandedKeyIds: Set<Int64> = [RegistryKey.rootId]
    @Published var selectedKeyId: Int64? {
        didSet {
            if selectedKeyId != oldValue {
                selectedKeyChanged()
            }
        }
    }

    @Published private(set) var values: [RegistryValue] = []
    @Published var selectedValueIds: Set<RegistryValue.ID> = []

    /// Path of the selected key; updated on selection changes only, so typing in the
    /// address bar is not overwritten by background reloads.
    @Published private(set) var addressText = RegistryPath.display([])
    @Published var alertMessage: String?

    // MARK: - Opening

    var isReadOnly: Bool { database?.isReadOnly ?? true }

    var databaseName: String { database?.url.lastPathComponent ?? "" }

    var isOfficeRegistry: Bool {
        database?.url == RegistryDatabase.officeRegistryURL.resolvingSymlinksInPath()
    }

    func openOfficeRegistry() {
        open(url: RegistryDatabase.officeRegistryURL)
    }

    func open(url: URL, readOnly: Bool = false) {
        do {
            let database = try RegistryDatabase(url: url, readOnly: readOnly)
            self.database = database
            openError = nil
            selectedKeyId = nil
            expandedKeyIds = [RegistryKey.rootId]
            reload()
            selectedKeyId = RegistryKey.rootId
        } catch {
            database = nil
            keysById = [:]
            childrenById = [:]
            values = []
            openError = error.localizedDescription
        }
    }

    /// Reloads keys and values from disk, keeping the selection and expansion where possible.
    func reload() {
        guard let database else {
            return
        }
        do {
            let keys = try database.fetchAllKeys()
            var byId = [RegistryKey.rootId: RegistryKey.root]
            var children = [Int64: [RegistryKey]]()
            for key in keys {
                byId[key.id] = key
                children[key.parentId, default: []].append(key)
            }
            for parentId in children.keys {
                children[parentId]?.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            }
            keysById = byId
            childrenById = children
            expandedKeyIds = expandedKeyIds.filter { byId[$0] != nil }

            if let selectedKeyId, byId[selectedKeyId] == nil {
                self.selectedKeyId = RegistryKey.rootId
            } else {
                reloadValues()
            }
        } catch {
            show(error)
        }
    }

    // MARK: - Tree queries

    func children(of keyId: Int64) -> [RegistryKey] {
        childrenById[keyId] ?? []
    }

    func hasChildren(_ keyId: Int64) -> Bool {
        !(childrenById[keyId]?.isEmpty ?? true)
    }

    var selectedKey: RegistryKey? {
        selectedKeyId.flatMap { keysById[$0] }
    }

    var selectedValues: [RegistryValue] {
        values.filter { selectedValueIds.contains($0.id) }
    }

    /// Key names from the hive down to the key.
    func pathComponents(of keyId: Int64) -> [String] {
        var components = [String]()
        var current = keysById[keyId]
        var visited = Set<Int64>()
        while let key = current, !key.isRoot, visited.insert(key.id).inserted {
            components.insert(key.name, at: 0)
            current = keysById[key.parentId]
        }
        return components
    }

    func isKey(_ keyId: Int64, inSubtreeOf ancestorId: Int64) -> Bool {
        var current: Int64? = keyId
        var visited = Set<Int64>()
        while let id = current, visited.insert(id).inserted {
            if id == ancestorId {
                return true
            }
            current = id == RegistryKey.rootId ? nil : keysById[id]?.parentId
        }
        return false
    }

    func path(of keyId: Int64) -> String {
        RegistryPath.display(pathComponents(of: keyId))
    }

    func key(atPath components: [String]) -> RegistryKey? {
        var current = RegistryKey.root
        for name in components {
            let siblings = children(of: current.id)
            // Prefer SQLite's (ASCII-only) case folding, then fall back to a lenient match for typed paths.
            let normalized = Array(RegistryValue.normalize(name).utf8)
            guard let next = siblings.first(where: { Array(RegistryValue.normalize($0.name).utf8) == normalized })
                ?? siblings.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                return nil
            }
            current = next
        }
        return current
    }

    // MARK: - Navigation

    /// Selects the key at `path` (address bar syntax), expanding its ancestors. Returns `false` if not found.
    @discardableResult
    func navigate(to path: String) -> Bool {
        guard let components = RegistryPath.components(of: path), let key = key(atPath: components) else {
            return false
        }
        reveal(keyId: key.id)
        return true
    }

    func reveal(keyId: Int64, valueName: String? = nil) {
        var ancestor = keysById[keyId]?.parentId
        while let id = ancestor, let key = keysById[id] {
            expandedKeyIds.insert(id)
            ancestor = key.isRoot ? nil : key.parentId
        }
        expandedKeyIds.insert(RegistryKey.rootId)
        selectedKeyId = keyId
        if let valueName {
            selectedValueIds = [RegistryValue.ID(keyId: keyId, name: valueName)]
        }
    }

    func expandAll(under keyId: Int64) {
        var stack = [keyId]
        while let id = stack.popLast() {
            if hasChildren(id) {
                expandedKeyIds.insert(id)
                stack.append(contentsOf: children(of: id).map(\.id))
            }
        }
    }

    func toggleExpanded(_ keyId: Int64) {
        if expandedKeyIds.contains(keyId) {
            expandedKeyIds.remove(keyId)
        } else {
            expandedKeyIds.insert(keyId)
        }
    }

    private func selectedKeyChanged() {
        selectedValueIds = []
        reloadValues()
        updateAddress()
    }

    private func updateAddress() {
        addressText = selectedKeyId.map(path(of:)) ?? RegistryPath.display([])
    }

    private func reloadValues() {
        guard let database, let keyId = selectedKeyId, keyId != RegistryKey.rootId else {
            values = []
            return
        }
        do {
            values = try database.fetchValues(keyId: keyId).sorted(by: RegistryStore.windowsOrder)
            let ids = Set(values.map(\.id))
            selectedValueIds = selectedValueIds.filter(ids.contains)
        } catch {
            values = []
            show(error)
        }
    }

    /// The default value first, then by name.
    nonisolated static func windowsOrder(_ lhs: RegistryValue, _ rhs: RegistryValue) -> Bool {
        if lhs.isDefault != rhs.isDefault {
            return lhs.isDefault
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    // MARK: - Clipboard

    func copyKeyName() {
        guard let keyId = selectedKeyId else {
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(RegistryPath.qualified(pathComponents(of: keyId)), forType: .string)
    }

    func copyValueData() {
        guard !selectedValues.isEmpty else {
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(selectedValues.map(\.data.displayString).joined(separator: "\n"), forType: .string)
    }

    // MARK: - Open panel

    func chooseDatabase() {
        let panel = NSOpenPanel()
        panel.title = "Open Registry Database"
        panel.message = "Choose an Office registry database (MicrosoftRegistrationDB.reg) or a copy of it."
        panel.allowsMultipleSelection = false
        panel.directoryURL = RegistryDatabase.officeRegistryURL.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        open(url: url)
    }

    // MARK: - Errors

    func show(_ error: Error) {
        alertMessage = error.localizedDescription
    }
}
