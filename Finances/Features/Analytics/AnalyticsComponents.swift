//
//  AnalyticsComponents.swift
//  Finances
//
//  Детали экрана аналитики: карточки на сгруппированном фоне, плашка тренда,
//  плитки показателей и полоски долей — в одном стиле с экраном настроек.
//

import SwiftUI

extension View {
    /// Карточка раздела: светлая подложка на сгруппированном фоне.
    func analyticsCard(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// Переключатель неделя / месяц / год: капсула со скользящим выделением.
struct AnalyticsScaleTabs: View {
    @Binding var selection: AnalyticsTimeScale
    @Namespace private var namespace

    /// Выделение как у системного сегмента: белое днём, светло-серое ночью.
    private static let selectionFill = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .systemGray3 : .white
    })

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AnalyticsTimeScale.allCases) { scale in
                let isSelected = selection == scale

                Button {
                    withAnimation(.snappy(duration: 0.28)) {
                        selection = scale
                    }
                } label: {
                    Text(scale.tabTitle)
                        .font(.subheadline.weight(isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Self.selectionFill)
                                    .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
                                    .matchedGeometryEffect(id: "scale", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color(.tertiarySystemFill), in: Capsule())
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Плашка изменения к прошлому периоду: рост трат — красная, снижение — зелёная.
struct AnalyticsTrendBadge: View {
    let delta: Double

    private var isUp: Bool { delta > 0 }
    private var color: Color { isUp ? .red : .green }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                .font(.caption2.weight(.bold))
            Text(abs(delta).formatted(.percent.precision(.fractionLength(0))))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.14), in: Capsule())
    }
}

/// Плитка показателя в шапке: значение крупно, подпись мелко.
struct AnalyticsMetricTile: View {
    let value: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Color(.tertiarySystemFill).opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Тонкая полоска доли от максимума.
struct AnalyticsShareBar: View {
    let share: Double
    let color: Color
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(color.opacity(0.14))
                Capsule()
                    .fill(color.gradient)
                    .frame(width: max(geometry.size.width * min(max(share, 0), 1), share > 0 ? height : 0))
            }
        }
        .frame(height: height)
    }
}

/// Иконка категории в скруглённом квадрате — как иконки строк в настройках.
struct AnalyticsCategoryIcon: View {
    let category: ExpenseCategoryItem?
    var size: CGFloat = 32

    private var color: Color {
        category.flatMap { Color(hex: $0.colorHex) } ?? .gray
    }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay {
                if let emoji = category?.emoji, !emoji.isEmpty {
                    Text(emoji)
                        .font(.system(size: size * 0.52))
                } else {
                    Image(systemName: category?.iconName ?? "questionmark")
                        .font(.system(size: size * 0.46, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .accessibilityHidden(true)
    }
}
