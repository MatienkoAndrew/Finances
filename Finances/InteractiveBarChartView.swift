import SwiftUI

/// Информация о пропорциональном свайпе для плавного скролла графика
struct ProportionalSwipeInfo {
    let distance: CGFloat          // Дистанция свайпа в пикселях
    let velocity: CGFloat          // Скорость в пикселях/секунду
    let duration: TimeInterval     // Длительность жеста
    let direction: SwipeDirection  // Направление свайпа
    
    enum SwipeDirection {
        case forward   // Влево (вперёд во времени)
        case backward  // Вправо (назад во времени)
    }
    
    /// Категория силы свайпа на основе дистанции и скорости
    var intensity: SwipeIntensity {
        let absVelocity = abs(velocity)
        let absDistance = abs(distance)
        
        // Высокая скорость = сильный свайп, даже при небольшой дистанции
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
        case minimal  // < 50px или очень медленно
        case light    // 50-150px, медленная скорость
        case medium   // 150-250px, средняя скорость или быстро
        case strong   // > 250px, высокая скорость
    }
}

struct InteractiveBarChartView: View {
    let points: [AnalyticsChartPoint]
    @Binding var selectedPointID: String?
    let onSelectionChanged: (AnalyticsChartPoint?) -> Void
    let onPeriodSwipe: (ProportionalSwipeInfo) -> Void

    @State private var dragMode: DragMode?
    @State private var animatedHeights: [String: CGFloat] = [:]
    @State private var hasAppeared = false
    @State private var edgeBounceAmount: CGFloat = 0
    @State private var dragStartTime: Date = .now

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

                    // Бары с плавной анимацией появления
                    ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                        let isSelected = selectedPointID == point.id
                        let barWidth = isSelected ? selectedWidth : regularWidth
                        let usableHeight = max(barsAreaHeight - 6, 1)
                        let normalizedHeight = CGFloat(point.total / maxValue)
                        let targetBarHeight = max(normalizedHeight * usableHeight, point.total > 0 ? 4 : 1)
                        let currentBarHeight = animatedHeights[point.id] ?? (hasAppeared ? targetBarHeight : 0)
                        let centerX = slotWidth * (CGFloat(point.index) + 0.5)

                        RoundedRectangle(cornerRadius: isSelected ? 8 : 6)
                            .fill(
                                LinearGradient(
                                    colors: isSelected 
                                        ? [Color.red, Color.red.opacity(0.8)]
                                        : [Color.red.opacity(0.9), Color.red.opacity(0.75)],
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
                                isSelected ? 1.0 : (dragMode == .selection ? 0.96 : 1.0),
                                anchor: .bottom
                            )
                            .opacity(
                                selectedPointID == nil ? 1.0 : (isSelected ? 1.0 : 0.5)
                            )
                            .blur(radius: selectedPointID == nil ? 0 : (isSelected ? 0 : 0.5))
                            .onAppear {
                                // Плавная анимация появления с задержкой для каждого бара
                                withAnimation(
                                    .spring(
                                        response: 0.6,
                                        dampingFraction: 0.75,
                                        blendDuration: 0
                                    )
                                    .delay(Double(index) * 0.03)
                                ) {
                                    animatedHeights[point.id] = targetBarHeight
                                }
                            }
                            .onChange(of: targetBarHeight) { _, newHeight in
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                    animatedHeights[point.id] = newHeight
                                }
                            }
                    }
                }
                .contentShape(Rectangle())
                // Bounce-эффект при достижении края
                .offset(x: edgeBounceAmount)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if dragMode == nil {
                                // Определяем режим в зависимости от зоны начала свайпа
                                dragMode = value.startLocation.y <= barsAreaHeight
                                    ? .selection
                                    : .paging
                                
                                // Запоминаем время начала для расчёта velocity
                                dragStartTime = .now
                                
                                // Лёгкая вибрация при начале свайпа в режиме пролистывания
                                if dragMode == .paging {
                                    let impact = UIImpactFeedbackGenerator(style: .light)
                                    impact.impactOccurred(intensity: 0.5)
                                }
                            }

                            guard dragMode == .selection else { return }
                            guard !points.isEmpty else { return }

                            let clampedX = min(max(value.location.x, 0), chartWidth - 1)
                            let rawIndex = Int((clampedX / chartWidth) * CGFloat(points.count))
                            let index = min(max(rawIndex, 0), points.count - 1)
                            let point = points[index]

                            if selectedPointID != point.id {
                                // Haptic feedback при выборе нового бара
                                let impact = UIImpactFeedbackGenerator(style: .light)
                                impact.impactOccurred(intensity: 0.7)
                                
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                    selectedPointID = point.id
                                }
                                onSelectionChanged(point)
                            }
                        }
                        .onEnded { value in
                            defer {
                                dragMode = nil
                            }

                            switch dragMode {
                            case .selection:
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                    selectedPointID = nil
                                }
                                onSelectionChanged(nil)

                            case .paging:
                                let horizontal = value.translation.width
                                let vertical = value.translation.height

                                // Проверяем, что свайп горизонтальный
                                guard abs(horizontal) > abs(vertical) else {
                                    return
                                }
                                
                                // Минимальный порог для срабатывания
                                guard abs(horizontal) > 20 else {
                                    return
                                }

                                // Рассчитываем параметры свайпа
                                let distance = horizontal
                                let duration = Date.now.timeIntervalSince(dragStartTime)
                                let velocity = duration > 0 ? distance / duration : 0
                                let direction: ProportionalSwipeInfo.SwipeDirection = horizontal < 0 ? .forward : .backward
                                
                                let swipeInfo = ProportionalSwipeInfo(
                                    distance: distance,
                                    velocity: velocity,
                                    duration: duration,
                                    direction: direction
                                )
                                
                                // Haptic feedback в зависимости от интенсивности свайпа
                                switch swipeInfo.intensity {
                                case .minimal, .light:
                                    let impact = UIImpactFeedbackGenerator(style: .light)
                                    impact.impactOccurred(intensity: 0.8)
                                case .medium:
                                    let impact = UIImpactFeedbackGenerator(style: .medium)
                                    impact.impactOccurred()
                                case .strong:
                                    let impact = UIImpactFeedbackGenerator(style: .rigid)
                                    impact.impactOccurred(intensity: 1.0)
                                }
                                
                                // Bounce-эффект при смене страницы
                                let bounceDirection: CGFloat = horizontal < 0 ? -10 : 10
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                                    edgeBounceAmount = bounceDirection
                                }
                                
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.75).delay(0.08)) {
                                    edgeBounceAmount = 0
                                }

                                // Передаём информацию о свайпе для пропорционального скролла
                                onPeriodSwipe(swipeInfo)

                            case .none:
                                break
                            }
                        }
                )
            }
            .frame(height: 220)
            .onAppear {
                hasAppeared = true
            }

            HStack(alignment: .top, spacing: 0) {
                ForEach(points) { point in
                    Text(point.axisLabel)
                        .font(.caption)
                        .foregroundStyle(selectedPointID == point.id ? .primary : .secondary)
                        .fontWeight(selectedPointID == point.id ? .semibold : .regular)
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedPointID)
                }
            }
            .padding(.horizontal, 2)
        }
    }
}
