import SwiftUI
import UsageCore

struct RingLayoutSettings: View {
    @ObservedObject var store: UsageStore
    let date: Date
    @State private var expandedSlot: Int?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(store.ringOrder.enumerated()), id: \.offset) { index, service in
                EditableUsageRing(store: store, service: service, index: index, date: date,
                                  isExpanded: Binding(
                                    get: { expandedSlot == index },
                                    set: { expandedSlot = $0 ? index : nil }
                                  ))
            }
        }
    }
}
