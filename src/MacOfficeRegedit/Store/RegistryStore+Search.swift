import Foundation

extension RegistryStore {
    struct SearchOptions: Equatable {
        var text = ""
        var keys = true
        var values = true
        var data = true
        var matchWholeString = false
    }

    struct SearchResult: Identifiable, Hashable {
        enum Kind: String {
            case key = "Key", value = "Value", data = "Data"
        }

        let id = UUID()
        let kind: Kind
        let keyId: Int64
        let valueName: String?
        let path: String
        let match: String
    }

    func search(_ options: SearchOptions) {
        guard let database, !options.text.isEmpty else {
            searchResults = []
            return
        }
        let needle = options.text
        func matches(_ haystack: String) -> Bool {
            options.matchWholeString
                ? haystack.caseInsensitiveCompare(needle) == .orderedSame
                : haystack.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }

        var results = [SearchResult]()
        var valuesByKey = [Int64: [RegistryValue]]()
        if options.values || options.data {
            do {
                valuesByKey = Dictionary(grouping: try database.fetchAllValues(), by: \.keyId)
            } catch {
                show(error)
            }
        }

        // Depth-first in tree order, like Windows "Find Next".
        var stack = children(of: RegistryKey.rootId).reversed().map(\.id)
        while let id = stack.popLast() {
            guard let key = keysById[id] else {
                continue
            }
            let path = self.path(of: id)
            if options.keys, matches(key.name) {
                results.append(SearchResult(kind: .key, keyId: id, valueName: nil, path: path, match: key.name))
            }
            for value in (valuesByKey[id] ?? []).sorted(by: RegistryStore.windowsOrder) {
                if options.values, matches(value.name) {
                    results.append(SearchResult(kind: .value, keyId: id, valueName: value.name, path: path, match: value.displayName))
                } else if options.data, let text = RegistryStore.searchableText(value.data), matches(text) {
                    results.append(SearchResult(kind: .data, keyId: id, valueName: value.name, path: path, match: "\(value.displayName) = \(value.data.displayString)"))
                }
            }
            stack.append(contentsOf: children(of: id).reversed().map(\.id))
        }
        searchResults = results
        searchResultIndex = -1
    }

    nonisolated static func searchableText(_ data: RegistryData) -> String? {
        switch data {
        case .none: return nil
        case .string(let string): return string
        case .multiString(let strings): return strings.joined(separator: "\n")
        case .dword, .qword: return data.displayString
        case .binary(let bytes):
            // Many Office binary values hold UTF-16LE text (e.g. JSON).
            return RegistryData.string(fromUTF16LE: bytes)
        }
    }

    func showSearchResult(_ result: SearchResult) {
        if let index = searchResults.firstIndex(of: result) {
            searchResultIndex = index
        }
        reveal(keyId: result.keyId, valueName: result.valueName)
        if result.valueName == nil {
            focusedPane = .keys
        }
    }

    var canFindNext: Bool { !searchResults.isEmpty }

    func findNext() {
        guard !searchResults.isEmpty else {
            sheet = .find
            return
        }
        searchResultIndex = (searchResultIndex + 1) % searchResults.count
        showSearchResult(searchResults[searchResultIndex])
    }
}
