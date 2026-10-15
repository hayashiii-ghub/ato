import SwiftUI
import UsageCore

struct RingLayoutSettings: View {
    @ObservedObject var store: UsageStore
    let date: Date

    var body: some View {
        GeometryReader { geometry in
            let size = max(1, min((geometry.size.width - 48) / 4, geometry.size.height * 0.62))
            HStack(alignment: .top, spacing: 16) {
                ForEach(Array(store.ringOrder.enumerated()), id: \.element) { item in
                    EditableUsageRing(store: store, service: item.element, index: item.offset,
                                      date: date, size: size)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.18), value: store.ringOrder)
        }
        .padding(24)
        .frame(height: 244)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 28))
    }
}
