import SwiftUI
import UIKit

struct ProportionalSwipeInfo {
    let distance: CGFloat
    let velocity: CGFloat
    let duration: TimeInterval
    let direction: SwipeDirection

    enum SwipeDirection {
        case forward   // влево = вперёд во времени
        case backward  // вправо = назад во времени
    }

    var intensity: SwipeIntensity {
        let absVelocity = abs(velocity)
        let absDistance = abs(distance)

        if absVelocity > 1500 && absDistance > 150 {
            return .strong
        } else if absVelocity > 800 && absDistance > 100 {
            return .medium
        } else if absDistance > 50 {
            return .light
        } else {
            return .minimal
        }
    }

    enum SwipeIntensity {
        case minimal
        case light
        case medium
        case strong
    }
}

enum PeriodSwipeResult {
    case applied
    case blockedAtFuture
    case cancelled
}

struct InteractiveBarChartView: View {
    let points: [AnalyticsChartPoint]
    @Binding var selectedPointID: String?

    let onSelectionChanged: (AnalyticsChartPoint?) -> Void
    let onPeriodDragBegan: () -> Void
    let onPeriodDragChanged: (CGFloat) -> Void
    let onPeriodSwipeEnded: (ProportionalSwipeInfo) -> PeriodSwipeResult

    @State private var dragMode: DragMode?
    @State private var animatedHeights: [String: CGFloat] = [:]
    @State private var didRunInitialEntranceAnimation = false

    @State private var dragStartTime: Date?
    @State private var livePagingOffset: CGFloat = 0
    @State private var edgeBounceAmount: CGFloat = 0
    @State private var didFirePagingStartHaptic = false

    private enum DragMode {
        case selection
        case paging
    }

    private let bottomPagingZoneHeight: CGFloat = 28
    private let labelsTopSpacing: CGFloat = 4

    // Ширина правого отступа под подписи оси значений (как в Health).
    private let axisGutter: CGFloat = 46

    private struct AxisLevel: Identifiable {
        let id = UUID()
        let value: Double
        let dimmed: Bool
    }

    private static let axisValueFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = "\u{00A0}"
        return formatter
    }()

    private func axisValueLabel(_ value: Double) -> String {
        Self.axisValueFormatter.string(from: NSNumber(value: value.rounded())) ?? "0"
    }

    // Верхняя граница оси: округляем максимум бара вверх до следующего
    // «круглого» шага своего порядка (22к → 30к, 15к → 20к, 1.8М → 2М).
    private func niceAxisMaximum(for value: Double) -> Double {
        guard value > 0 else { return 0 }
        let exponent = floor(log10(value))
        let step = pow(10, exponent)
        return (floor(value / step) + 1) * step
    }

    // Уровни правой оси: верхнее значение, его половина и еле заметный ноль.
    private func makeAxisLevels(axisMax: Double) -> [AxisLevel] {
        guard axisMax > 0 else { return [AxisLevel(value: 0, dimmed: true)] }

        return [
            AxisLevel(value: axisMax, dimmed: false),
            AxisLevel(value: axisMax / 2, dimmed: false),
            AxisLevel(value: 0, dimmed: true)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: labelsTopSpacing) {
            GeometryReader { geometry in
                let chartHeight = geometry.size.height
                let chartWidth = geometry.size.width
                let maxValue = max(points.map(\.total).max() ?? 0, 1)
                let axisMax = max(niceAxisMaximum(for: maxValue), 1)

                let plotWidth = max(chartWidth - axisGutter, 1)
                let slotWidth = plotWidth / CGFloat(max(points.count, 1))
                let selectedWidth = min(max(slotWidth * 0.92, 20), 46)
                let regularWidth = min(max(slotWidth * 0.84, 16), 42)

                let barsAreaHeight = max(chartHeight - bottomPagingZoneHeight, 1)
                let usableHeight = max(barsAreaHeight - 6, 1)

                let axisLevels = makeAxisLevels(axisMax: axisMax)

                ZStack(alignment: .bottomLeading) {
                    HStack(spacing: 0) {
                        ForEach(points) { _ in
                            VerticalDashedLine()
                                .stroke(
                                    Color.secondary.opacity(0.18),
                                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                                )
                                .frame(width: 1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(width: plotWidth, height: barsAreaHeight, alignment: .bottomLeading)
                    .allowsHitTesting(false)

                    // Правая ось значений + горизонтальные линии сетки (стиль Health).
                    ForEach(axisLevels) { level in
                        let ratio = min(CGFloat(level.value / axisMax), 1)
                        let lineY = barsAreaHeight - ratio * usableHeight
                        let labelY = min(max(lineY, 8), barsAreaHeight)

                        Path { path in
                            path.move(to: CGPoint(x: 0, y: lineY))
                            path.addLine(to: CGPoint(x: plotWidth, y: lineY))
                        }
                        .stroke(
                            Color.secondary.opacity(level.dimmed ? 0.10 : 0.16),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                        )
                        .allowsHitTesting(false)

                        Text(axisValueLabel(level.value))
                            .font(.caption2)
                            .foregroundStyle(Color.secondary.opacity(level.dimmed ? 0.4 : 0.65))
                            .lineLimit(1)
                            .frame(width: axisGutter - 4, alignment: .trailing)
                            .position(x: plotWidth + (axisGutter - 4) / 2, y: labelY)
                            .allowsHitTesting(false)
                    }

                    ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                        let isSelected = selectedPointID == point.id
                        let barWidth = isSelected ? selectedWidth : regularWidth
                        let normalizedHeight = CGFloat(point.total / axisMax)
                        let targetBarHeight = max(normalizedHeight * usableHeight, point.total > 0 ? 4 : 1)
                        let currentBarHeight = animatedHeights[point.id] ?? (didRunInitialEntranceAnimation ? targetBarHeight : 0)
                        let centerX = slotWidth * (CGFloat(index) + 0.5)

                        RoundedRectangle(cornerRadius: isSelected ? 4 : 3)
                            .fill(
                                LinearGradient(
                                    colors: isSelected
                                    ? [Color.red, Color.red.opacity(0.82)]
                                    : [Color.red.opacity(0.90), Color.red.opacity(0.74)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: barWidth, height: currentBarHeight)
                            .position(
                                x: centerX,
                                y: barsAreaHeight - currentBarHeight / 2
                            )
                            .scaleEffect(
                                isSelected ? 1.0 : (dragMode == .selection ? 0.965 : 1.0),
                                anchor: .bottom
                            )
                            .opacity(
                                selectedPointID == nil ? 1.0 : (isSelected ? 1.0 : 0.52)
                            )
                            .blur(radius: selectedPointID == nil ? 0 : (isSelected ? 0 : 0.45))
                            .onAppear {
                                if didRunInitialEntranceAnimation {
                                    animatedHeights[point.id] = targetBarHeight
                                } else {
                                    withAnimation(
                                        .spring(
                                            response: 0.58,
                                            dampingFraction: 0.78,
                                            blendDuration: 0
                                        )
                                        .delay(Double(index) * 0.028)
                                    ) {
                                        animatedHeights[point.id] = targetBarHeight
                                    }
                                }
                            }
                            .onChange(of: targetBarHeight) { _, newHeight in
                                if dragMode == .paging {
                                    animatedHeights[point.id] = newHeight
                                } else {
                                    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                                        animatedHeights[point.id] = newHeight
                                    }
                                }
                            }
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if dragMode == nil {
                                dragMode = value.startLocation.y <= barsAreaHeight ? .selection : .paging
                                dragStartTime = value.time
                            }

                            switch dragMode {
                            case .selection:
                                handleSelectionDragChanged(value: value, plotWidth: plotWidth)

                            case .paging:
                                handlePagingDragChanged(value: value)

                            case .none:
                                break
                            }
                        }
                        .onEnded { value in
                            defer {
                                dragMode = nil
                                dragStartTime = nil
                                didFirePagingStartHaptic = false
                            }

                            switch dragMode {
                            case .selection:
                                handleSelectionEnded()

                            case .paging:
                                handlePagingEnded(value: value)

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
                        .foregroundStyle(selectedPointID == point.id ? .primary : .secondary)
                        .fontWeight(selectedPointID == point.id ? .semibold : .regular)
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .animation(.spring(response: 0.26, dampingFraction: 0.84), value: selectedPointID)
                }
            }
            .padding(.trailing, axisGutter)
        }
        .offset(x: livePagingOffset + edgeBounceAmount)
        .onAppear {
            DispatchQueue.main.async {
                didRunInitialEntranceAnimation = true
            }
        }
    }

    private func handleSelectionDragChanged(value: DragGesture.Value, plotWidth: CGFloat) {
        guard !points.isEmpty else { return }

        let clampedX = min(max(value.location.x, 0), max(plotWidth - 1, 0))
        let rawIndex = Int((clampedX / max(plotWidth, 1)) * CGFloat(points.count))
        let index = min(max(rawIndex, 0), points.count - 1)
        let point = points[index]

        if selectedPointID != point.id {
            selectedPointID = point.id
            onSelectionChanged(point)

            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred(intensity: 0.72)
        }
    }

    private func handleSelectionEnded() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            selectedPointID = nil
        }
        onSelectionChanged(nil)
    }

    private func handlePagingDragChanged(value: DragGesture.Value) {
        let horizontal = value.translation.width
        let vertical = value.translation.height

        guard abs(horizontal) >= abs(vertical) else { return }

        if !didFirePagingStartHaptic {
            didFirePagingStartHaptic = true
            onPeriodDragBegan()

            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred(intensity: 0.55)
        }

        livePagingOffset = visualPagingOffset(for: horizontal)
        onPeriodDragChanged(horizontal)
    }

    private func handlePagingEnded(value: DragGesture.Value) {
        let horizontal = value.translation.width
        let vertical = value.translation.height

        guard abs(horizontal) > abs(vertical) else {
            resetPagingVisuals()
            return
        }

        guard abs(horizontal) > 18 else {
            resetPagingVisuals()
            return
        }

        let startTime = dragStartTime ?? value.time
        let duration = max(value.time.timeIntervalSince(startTime), 0.01)
        let velocity = horizontal / duration
        let direction: ProportionalSwipeInfo.SwipeDirection = horizontal < 0 ? .forward : .backward

        let swipeInfo = ProportionalSwipeInfo(
            distance: horizontal,
            velocity: velocity,
            duration: duration,
            direction: direction
        )

        let result = onPeriodSwipeEnded(swipeInfo)

        switch result {
        case .applied:
            fireCompletionHaptic(for: swipeInfo.intensity)
            runSuccessBounce(for: horizontal)

        case .blockedAtFuture:
            let warning = UINotificationFeedbackGenerator()
            warning.notificationOccurred(.warning)
            runBoundaryBounce(for: horizontal)

        case .cancelled:
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred(intensity: 0.5)
        }

        resetPagingVisuals()
    }

    private func fireCompletionHaptic(for intensity: ProportionalSwipeInfo.SwipeIntensity) {
        switch intensity {
        case .minimal, .light:
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred(intensity: 0.82)

        case .medium:
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()

        case .strong:
            let impact = UIImpactFeedbackGenerator(style: .rigid)
            impact.impactOccurred(intensity: 1.0)
        }
    }

    private func visualPagingOffset(for translation: CGFloat) -> CGFloat {
        let damped = translation * 0.22
        return min(max(damped, -44), 44)
    }

    private func resetPagingVisuals() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            livePagingOffset = 0
        }
    }

    private func runSuccessBounce(for translation: CGFloat) {
        let bounce: CGFloat = translation < 0 ? -10 : 10

        withAnimation(.spring(response: 0.18, dampingFraction: 0.70)) {
            edgeBounceAmount = bounce
        }

        withAnimation(.spring(response: 0.30, dampingFraction: 0.84).delay(0.04)) {
            edgeBounceAmount = 0
        }
    }

    private func runBoundaryBounce(for translation: CGFloat) {
        let bounce: CGFloat = translation < 0 ? 12 : -12

        withAnimation(.spring(response: 0.16, dampingFraction: 0.68)) {
            edgeBounceAmount = bounce
        }

        withAnimation(.spring(response: 0.30, dampingFraction: 0.82).delay(0.04)) {
            edgeBounceAmount = 0
        }
    }
}

/// Вертикальная линия по центру своей области — для пунктирных разделителей баров.
private struct VerticalDashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}
