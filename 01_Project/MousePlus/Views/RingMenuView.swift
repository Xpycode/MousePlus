import SwiftUI

/// The main radial menu view
struct RingMenuView: View {
    @Bindable var viewModel: RingViewModel

    private let ringRadius: CGFloat = 120
    private let itemSize: CGFloat = 60

    var body: some View {
        ZStack {
            // Background blur
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: ringRadius * 2 + itemSize, height: ringRadius * 2 + itemSize)

            // Center indicator
            Circle()
                .fill(.secondary.opacity(0.3))
                .frame(width: 20, height: 20)

            // Menu items arranged in a circle
            ForEach(Array(viewModel.displayItems.enumerated()), id: \.element.id) { index, item in
                RingItemView(
                    item: item,
                    isHovered: viewModel.hoveredItem?.id == item.id,
                    angle: angle(for: index),
                    radius: ringRadius
                )
                .onTapGesture {
                    viewModel.selectItem(item)
                }
                .onHover { hovering in
                    viewModel.hoverItem(hovering ? item : nil)
                }
            }

            // Back button when in sub-menu
            if viewModel.isShowingSubMenu {
                Button(action: { viewModel.goBack() }) {
                    Image(systemName: "arrow.left.circle.fill")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: ringRadius * 2 + itemSize + 20, height: ringRadius * 2 + itemSize + 20)
    }

    private func angle(for index: Int) -> Angle {
        let count = viewModel.displayItems.count
        let slice = 360.0 / Double(count)
        // Start from top (-90 degrees)
        return .degrees(slice * Double(index) - 90)
    }
}

/// Individual item in the ring
struct RingItemView: View {
    let item: RingMenuItem
    let isHovered: Bool
    let angle: Angle
    let radius: CGFloat

    private let itemSize: CGFloat = 60

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(isHovered ? Color.accentColor : Color.secondary.opacity(0.2))
                    .frame(width: itemSize, height: itemSize)

                Image(systemName: item.icon)
                    .font(.title2)
                    .foregroundStyle(isHovered ? .white : .primary)
            }

            Text(item.label)
                .font(.caption)
                .foregroundStyle(.primary)
        }
        .offset(x: cos(angle.radians) * radius, y: sin(angle.radians) * radius)
    }
}

#Preview {
    RingMenuView(viewModel: RingViewModel())
        .frame(width: 400, height: 400)
        .background(.black.opacity(0.5))
}
