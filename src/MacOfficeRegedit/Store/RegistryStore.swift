import AppKit
import Foundation
import Observation

/// Application state: the open database, the key tree, the selection and all user operations.
@MainActor
@Observable
final class RegistryStore {
    enum Sheet: Identifiable {
        case editValue(RegistryValue, isNew: Bool)
        case newKey(parentId: Int64)
        case renameKey(RegistryKey)
        case renameValue(RegistryValue)
        case find

        var id: String {
            switch self {
            case .editValue(let value, let isNew): return "edit-\(value.keyId)-\(value.name)-\(isNew)"
            case .newKey(let parentId): return "newKey-\(parentId)"
            case .renameKey(let key): return "renameKey-\(key.id)"
            case .renameValue(let value): return "renameValue-\(value.keyId)-\(value.name)"
            case .find: return "find"
            }
        }
    }

    enum Deletion {
        case key(RegistryKey)
        case values([RegistryValue])

        var title: String {
            switch self {
            case .key: return "Confirm Key Delete"
            case .values(let values): return values.count == 1 ? "Confirm Value Delete" : "Confirm Values Delete"
            }
        }

        var message: String {
            switch self {
            case .key(let key):
                return "Are you sure you want to permanently delete \"\(key.name)\" and all of its subkeys?"
            case .values(let values):
                return values.count == 1
                    ? "Deleting \"\(values[0].displayName)\" might cause Office to behave unexpectedly. Are you sure you want to permanently delete this value?"
                    : "Deleting these \(values.count) values might cause Office to behave unexpectedly. Are you sure you want to permanently delete them?"
            }
        }
    }

    enum Pane {
        case keys, values
    }

    struct PendingImport {
        let url: URL
        let document: RegFileDocument
    }

    // MARK: - State

    private(set) var database: RegistryDatabase?
    private(set) var openError: String?

    private(set) var keysById: [Int64: RegistryKey] = [:]
    /// Child keys of each key, sorted by name like Windows regedit.
    private(set) var childrenById: [Int64: [RegistryKey]] = [:]
    var expandedKeyIds: Set<Int64> = [RegistryKey.rootId]
    var selectedKeyId: Int64? {
        didSet {
            if selectedKeyId != oldValue {
                selectedKeyChanged()
            }
        }
    }

    private(set) var values: [RegistryValue] = []
    var selectedValueIds: Set<RegistryValue.ID> = []
    /// Pane the user last worked in; used when the keyboard focus can't be determined (see `activePane`).
    /// Not observed: no view depends on it, and it is set from gestures during view updates.
    @ObservationIgnored var focusedPane: Pane = .keys

    /// Path of the selected key; updated on selection changes and renames only, so typing in the
    /// address bar is not overwritten by background reloads.
    private(set) var addressText = RegistryPath.display([])
    var sheet: Sheet? {
        didSet { resumeDeferredReload() }
    }
    var pendingDeletion: Deletion? {
        didSet { resumeDeferredReload() }
    }
    var pendingImport: PendingImport? {
        didSet { resumeDeferredReload() }
    }
    var alertMessage: String?

    var searchResults: [SearchResult] = []
    @ObservationIgnored var searchResultIndex = -1

    /// Where a copy of the database is saved before the first modification.
    @ObservationIgnored var backupsDirectory = RegistryStore.defaultBackupsDirectory

    @ObservationIgnored private var watcher: FileWatcher?
    /// Watches the folder holding the opened path: Office may point the symlink at a new file without
    /// touching the old one, which the file watcher (on the resolved file) would never notice.
    @ObservationIgnored private var directoryWatcher: FileWatcher?
    @ObservationIgnored var hasBackedUp = false
    /// The URL as opened (e.g. the Office symlink), to detect when it starts pointing to another file.
    @ObservationIgnored private var openedURL: URL?
    /// External changes are not applied while a dialog is open, since it holds ids and data from before.
    @ObservationIgnored private var needsReload = false

    /// A dialog or confirmation is showing; menu commands that would replace it are disabled.
    var isModalActive: Bool { sheet != nil || pendingDeletion != nil || pendingImport != nil }

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
            // Anything still showing refers to keys of the previous database.
            sheet = nil
            pendingDeletion = nil
            pendingImport = nil
            needsReload = false
            self.database = database
            openedURL = url
            openError = nil
            hasBackedUp = false
            searchResults = []
            selectedKeyId = nil
            expandedKeyIds = [RegistryKey.rootId]
            watcher = FileWatcher(url: database.url) { [weak self] in
                Task { @MainActor in
                    self?.externalChange()
                }
            }
            directoryWatcher = FileWatcher(url: url.deletingLastPathComponent()) { [weak self] in
                Task { @MainActor in
                    self?.directoryChanged()
                }
            }
            reload()
            selectedKeyId = RegistryKey.rootId
        } catch {
            database = nil
            watcher = nil
            directoryWatcher = nil
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

    /// View ▸ Refresh: also picks up a database file Office swapped in without a change notification.
    func refresh() {
        if !reopenIfReplaced() {
            reload()
        }
    }

    private func externalChange() {
        guard database != nil else {
            return
        }
        if isModalActive {
            needsReload = true
        } else {
            refresh()
        }
    }

    /// Other files in the folder change often (Office keeps lock files there), so only check whether
    /// the database itself was replaced instead of reloading.
    private func directoryChanged() {
        guard database != nil else {
            return
        }
        if isModalActive {
            needsReload = true
        } else {
            reopenIfReplaced()
        }
    }

    private func resumeDeferredReload() {
        if needsReload, !isModalActive {
            needsReload = false
            refresh()
        }
    }

    /// Office may replace the database file or point the symlink to a new file. The open connection
    /// would keep using the old, unlinked file, so reopen. Returns `true` if it reopened.
    @discardableResult
    func reopenIfReplaced() -> Bool {
        guard let database, let openedURL else {
            return false
        }
        guard RegistryDatabase.fileIdentity(of: openedURL) != database.fileIdentity else {
            return false
        }
        let selection = selectedKeyId.map(pathComponents(of:))
        open(url: openedURL, readOnly: database.isReadOnly)
        if let selection, let key = key(atPath: selection) {
            reveal(keyId: key.id)
        }
        return true
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
            focusedPane = .values
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

    func updateAddress() {
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
