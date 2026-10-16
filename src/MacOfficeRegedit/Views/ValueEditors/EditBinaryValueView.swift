import SwiftUI

/// Editor for `REG_BINARY` (and other raw) values, modelled after Windows regedit's "Edit Binary Value" dialog.
///
/// The bytes are edited as hex text (pasting from other tools works as long as it is plain hex), and a live
/// read-only hex dump with offsets and ASCII shows how the input is interpreted.
struct EditBinaryValueView: View {
    let original: RegistryValue
    let isNew: Bool
    let onCommit: ValueCommitHandler

    @State private var name: String
    @State private var text: String
    @State private var showsText = false

    init(value: RegistryValue, isNew: Bool, onCommit: @escaping ValueCommitHandler) {
        self.original = value
        self.isNew = isNew
        self.onCommit = onCommit
        _name = State(initialValue: value.name)
        _text = State(initialValue: HexFormatting.format(value.data.rawBytes))
    }

    var body: some View {
        let parsed = Result { try HexFormatting.parse(text) }
        let bytes = try? parsed.get()
        ValueEditorForm(
            title: "Edit Binary Value",
            name: $name,
            isNameEditable: isNew,
            canCommit: bytes != nil,
            commit: {
                let bytes = try HexFormatting.parse(text)
                var value = original
                value.name = name
                value.data = .binary(bytes)
                try onCommit(value)
            }
        ) {
            Text("Value data:")
            HStack(alignment: .top, spacing: 8) {
                TextEditor(text: $text)
                    .font(.body.monospaced())
                    .autocorrectionDisabled()
                    .frame(width: 230)
                    .border(Color(nsColor: .separatorColor))
                    .accessibilityIdentifier("valueData")
                dumpView(bytes)
                    .border(Color(nsColor: .separatorColor))
            }
            .frame(height: 240)

            HStack {
                switch parsed {
                case .success(let bytes):
                    Text(bytes.count == 1 ? "1 byte" : "\(bytes.count) bytes (0x\(String(bytes.count, radix: 16, uppercase: true)))")
                        .foregroundColor(.secondary)
                case .failure(let error):
                    Text(error.localizedDescription)
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Reformat") {
                    if let bytes {
                        text = HexFormatting.format(bytes)
                    }
                }
                .disabled(bytes == nil)
                .help("Lay out the hex digits as 8 bytes per line")
            }
            .font(.caption)

            if let bytes, HexFormatting.looksLikeUTF16LEText(bytes) {
                Toggle("Show as UTF-16LE text", isOn: $showsText)
                if showsText {
                    ScrollView {
                        Text(RegistryData.string(fromUTF16LE: bytes))
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(4)
                    }
                    .frame(height: 120)
                    .border(Color(nsColor: .separatorColor))
                }
            }
        }
        .frame(width: 660)
    }

    @ViewBuilder
    private func dumpView(_ bytes: [UInt8]?) -> some View {
        if let bytes, !bytes.isEmpty {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(HexFormatting.dumpLines(bytes)) { line in
                        Text(line.text)
                            .lineLimit(1)
                    }
                }
                .font(.body.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }
            .accessibilityIdentifier("hexDump")
        } else {
            Text(bytes == nil ? "Invalid hex data." : "(zero-length binary value)")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview("Binary") {
    EditBinaryValueView(
        value: RegistryValue(keyId: 1, name: "Data", type: .REG_BINARY, data: .binary(Array(0...40))),
        isNew: false,
        onCommit: { _ in }
    )
}

#Preview("UTF-16 text") {
    EditBinaryValueView(
        value: RegistryValue(
            keyId: 1,
            name: "Settings",
            type: .REG_BINARY,
            data: .binary(RegistryData.utf16LEBytes("{\"enabled\":true,\"items\":[1,2,3]}", terminated: true))
        ),
        isNew: true,
        onCommit: { _ in }
    )
}
