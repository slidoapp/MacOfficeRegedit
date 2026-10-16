import AppKit
import UniformTypeIdentifiers

extension UTType {
    static let registryFile = UTType(filenameExtension: "reg", conformingTo: .text) ?? .plainText
}

extension RegistryStore {
    /// Builds a `.reg` document of the key and all of its subkeys.
    func exportDocument(keyId: Int64) throws -> RegFileDocument {
        guard let database else {
            throw RegistryError.databaseNotFound(RegistryDatabase.officeRegistryURL)
        }
        let valuesByKey = Dictionary(grouping: try database.fetchAllValues(), by: \.keyId)
        var keys = [RegFileDocument.Key]()
        var stack = [keyId]
        while let id = stack.popLast() {
            let values = (valuesByKey[id] ?? []).sorted(by: RegistryStore.windowsOrder).map {
                RegFileDocument.Value(name: $0.name, type: $0.type, data: $0.data)
            }
            keys.append(RegFileDocument.Key(path: pathComponents(of: id), isDeletion: false, values: values))
            stack.append(contentsOf: children(of: id).reversed().map(\.id))
        }
        return RegFileDocument(keys: keys)
    }

    func exportSelectedKey() {
        guard let keyId = selectedKeyId else {
            return
        }
        let panel = NSSavePanel()
        panel.title = "Export Registry File"
        panel.allowedContentTypes = [.registryFile]
        panel.nameFieldStringValue = (keyId == RegistryKey.rootId ? RegistryPath.hive : keysById[keyId]?.name ?? "Export") + ".reg"
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        do {
            let text = RegFile.serialize(try exportDocument(keyId: keyId))
            try RegFile.encode(text).write(to: url, options: .atomic)
        } catch {
            show(error)
        }
    }

    func beginImport() {
        guard canEdit else {
            return
        }
        let panel = NSOpenPanel()
        panel.title = "Import Registry File"
        panel.allowedContentTypes = [.registryFile, .plainText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        do {
            let document = try RegFile.parse(try RegFile.decode(try Data(contentsOf: url)))
            pendingImport = PendingImport(url: url, document: document)
        } catch {
            show(error)
        }
    }

    func performImport(_ pendingImport: PendingImport) {
        do {
            try write { database in
                try RegistryStore.apply(pendingImport.document, to: database)
            }
            reload()
            alertMessage = "The keys and values contained in \(pendingImport.url.lastPathComponent) have been successfully added to the registry."
        } catch {
            reload()
            show(error)
        }
    }

    /// Applies a `.reg` document atomically: either everything is imported or nothing.
    nonisolated static func apply(_ document: RegFileDocument, to database: RegistryDatabase) throws {
        try database.transaction {
            for key in document.keys {
                if key.isDeletion {
                    if !key.path.isEmpty, let id = try keyId(atPath: key.path, in: database) {
                        try database.deleteKey(id: id)
                    }
                    continue
                }
                let keyId = try database.createKeyPath(key.path)
                for value in key.values {
                    guard keyId != RegistryKey.rootId else {
                        throw RegistryError.cannotModifyRoot
                    }
                    if let data = value.data {
                        try database.upsertValue(RegistryValue(keyId: keyId, name: value.name, type: value.type, data: data))
                    } else if try database.fetchValue(keyId: keyId, name: value.name) != nil {
                        try database.deleteValue(keyId: keyId, name: value.name)
                    }
                }
            }
        }
    }

    private nonisolated static func keyId(atPath path: [String], in database: RegistryDatabase) throws -> Int64? {
        var id = RegistryKey.rootId
        for name in path {
            guard let child = try database.childKeyId(parentId: id, name: name) else {
                return nil
            }
            id = child
        }
        return id
    }
}
