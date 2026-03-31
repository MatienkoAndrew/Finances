import SwiftUI

struct InteractiveBarChartView: View {
    let points: [AnalyticsChartPoint]
    @Binding var selectedPointID: String?
    let onSelectionChanged: (AnalyticsChartPoint?) -> Void
    let onPeriodSwipe: (Int) -> Void

    @State private var dragMode: DragMode?

    private enum DragMode {
        case selection
        case paging
    }

    private let bottomPagingZoneHeight: CGFloat = 26
    private let labelsTopSpacing: CGFloat = 4

    var body: some View {
        VStack(alignment: .leading, spacing: labelsTopSpacing) {
            GeometryReader { geometry in
                let chartHeight = geometry.size.height
                let chartWidth = geometry.size.width
                let maxValue = max(points.map(\.total).max() ?? 0, 1)

                let slotWidth = chartWidth / CGFloat(max(points.count, 1))
                let selectedWidth = min(max(slotWidth * 0.82, 16), 28)
                let regularWidth = min(max(slotWidth * 0.68, 12), 24)

                let barsAreaHeight = max(chartHeight - bottomPagingZoneHeight, 1)

                ZStack(alignment: .bottomLeading) {
                    // Вертикальные разделители как в Health
                    HStack(spacing: 0) {
                        ForEach(points) { _ in
                            Rectangle()
                                .fill(Color.secondary.opacity(0.10))
                                .frame(width: 1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(height: barsAreaHeight, alignment: .bottom)
                    .allowsHitTesting(false)

                    // Нижняя базовая линия
                    Rectangle()
                        .fill(Color.secondary.opacity(0.12))
                        .frame(height: 1)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .offset(y: -bottomPagingZoneHeight)
                        .allowsHitTesting(false)

                    // Бары
                    ForEach(points) { point in
                        let isSelected = selectedPointID == point.id
                        let barWidth = isSelected ? selectedWidth : regularWidth
                        let usableHeight = max(barsAreaHeight - 6, 1)
                        let normalizedHeight = CGFloat(point.total / maxValue)
                        let barHeight = max(normalizedHeight * usableHeight, point.total > 0 ? 4 : 1)
                        let centerX = slotWidth * (CGFloat(point.index) + 0.5)

                        RoundedRectangle(cornerRadius: isSelected ? 7 : 5)
                            .fill(isSelected ? Color.blue : Color.blue.opacity(0.88))
                            .frame(width: barWidth, height: barHeight)
                            .position(
                                x: centerX,
                                y: barsAreaHeight - barHeight / 2
                            )
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if dragMode == nil {
                                dragMode = value.startLocation.y <= barsAreaHeight
                                    ? .selection
                                    : .paging
                            }

                            guard dragMode == .selection else { return }
                            guard !points.isEmpty else { return }

                            let clampedX = min(max(value.location.x, 0), chartWidth - 1)
                            let rawIndex = Int((clampedX / chartWidth) * CGFloat(points.count))
                            let index = min(max(rawIndex, 0), points.count - 1)
                            let point = points[index]

                            if selectedPointID != point.id {
                                selectedPointID = point.id
                                onSelectionChanged(point)
                            }
                        }
                        .onEnded { value in
                            defer {
                                dragMode = nil
                            }

                            switch dragMode {
                            case .selection:
                                selectedPointID = nil
                                onSelectionChanged(nil)

                            case .paging:
                                let horizontal = value.translation.width
                                let vertical = value.translation.height

                                guard abs(horizontal) > abs(vertical), abs(horizontal) > 36 else {
                                    return
                                }

                                if horizontal < 0 {
                                    onPeriodSwipe(1)
                                } else {
                                    onPeriodSwipe(-1)
                                }

                            case .none:
                                break
                            }
                        }
                )
            }
            .frame(height: 220)

            HStack(alignment: .top, spacing: 0) {
                ForEach(points) { point in
                    Text(point.axisLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .padding(.horizontal, 2)
        }
        .animation(.snappy(duration: 0.25, extraBounce: 0.03), value: points.map(\.total))
        .animation(.snappy(duration: 0.16), value: selectedPointID)
    }
}
