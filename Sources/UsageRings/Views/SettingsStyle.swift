import SwiftUI

enum SettingsStyle {
    static let body = Font.system(size: 13)
    static let heading = Font.system(size: 12, weight: .semibold)
    static let caption = Font.system(size: 11)
    static let statusSymbol = Font.system(size: 12, weight: .medium)
}

struct SettingsIcon: View {
    let name: String
    var isDisclosure = false

    var body: some View {
        Image(systemName: name)
            .font(.system(size: isDisclosure ? 12 : 14, weight: isDisclosure ? .semibold : .medium))
            .frame(width: isDisclosure ? 32 : 28, height: isDisclosure ? 32 : 28)
            .contentShape(Rectangle())
    }
}
