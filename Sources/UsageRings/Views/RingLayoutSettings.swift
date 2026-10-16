import SwiftUI
import UsageCore

struct RingLayoutSettings: View {
    @ObservedObject var store: UsageStore
    let date: Date
    let selectedService: UsageService?
    let onSelectService: (UsageService) -> Void

    var body: some View {
        UsageRingsLayout(ringOrder: store.ringOrder) { service, size in
            if let index = store.ringOrder.firstIndex(of: service) {
                EditableUsageRing(store: store, service: service, index: index,
                                  date: date, size: size, isSelected: selectedService == service) {
                    onSelectService(service)
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: store.ringOrder)
        .padding(18)
        .frame(height: 200)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 28))
    }
}
