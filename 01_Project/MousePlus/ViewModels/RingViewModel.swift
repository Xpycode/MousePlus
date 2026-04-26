import SwiftUI
import Combine

/// Main view model for the ring menu
@MainActor
@Observable
final class RingViewModel {
    var items: [RingMenuItem] = RingMenuItem.sampleItems
    var selectedItem: RingMenuItem?
    var hoveredItem: RingMenuItem?
    var isVisible = false
    var currentSubItems: [RingMenuItem]?

    private let actionService = ActionService()
    private var cancellables = Set<AnyCancellable>()

    var displayItems: [RingMenuItem] {
        currentSubItems ?? items
    }

    var isShowingSubMenu: Bool {
        currentSubItems != nil
    }

    func show(at point: NSPoint) {
        isVisible = true
        currentSubItems = nil
        selectedItem = nil
    }

    func hide() {
        isVisible = false
        currentSubItems = nil
        selectedItem = nil
        hoveredItem = nil
    }

    func selectItem(_ item: RingMenuItem) {
        if item.hasSubItems {
            // Show sub-menu
            currentSubItems = item.subItems
            selectedItem = nil
        } else {
            // Execute action
            Task {
                try? await actionService.execute(item)
            }
            hide()
        }
    }

    func goBack() {
        currentSubItems = nil
    }

    func hoverItem(_ item: RingMenuItem?) {
        hoveredItem = item
    }
}
