import SwiftUI

struct ModifyRegValueView: View {
    @EnvironmentObject var dataStore: DataStore
    let regValueId: String?
    
    var body: some View {
        Text(/*@START_MENU_TOKEN@*/"Hello, World!"/*@END_MENU_TOKEN@*/)
        // TODO: https://github.com/NilCoalescing/SwiftUI-Code-Examples/blob/main/Programmatically-open-a-new-window-on-macOS/Programmatically-open-a-new-window-on-macOS.swift
    }
}

struct ModifyRegValueView_Previews: PreviewProvider {
    static var previews: some View {
        ModifyRegValueView(regValueId: nil)
    }
}
