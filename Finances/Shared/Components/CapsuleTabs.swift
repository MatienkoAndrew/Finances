//
//  CapsuleTabs.swift
//  Finances
//
//  Переключатель-капсула со скользящим выделением: неделя / месяц / год
//  в аналитике, виды операций на экране транзакций.
//

import SwiftUI

struct CapsuleTabs<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    /// Растянуть вкладки на всю ширину — когда переключатель стоит отдельной строкой.
    var fillsWidth = false
    let title: (Value) -> String

    @Namespace private var namespace

    /// Выделение как у системного сегмента: белое днём, светло-серое ночью.
    private static var selectionFill: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? .systemGray3 : .white
        })
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let isSelected = selection == option

                Button {
                    withAnimation(.snappy(duration: 0.28)) {
                        selection = option
                    }
                } label: {
                    Text(title(option))
                        .font(.subheadline.weight(isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, fillsWidth ? 6 : 14)
                        .padding(.vertical, fillsWidth ? 7 : 6)
                        .frame(maxWidth: fillsWidth ? .infinity : nil)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Self.selectionFill)
                                    .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color(.tertiarySystemFill), in: Capsule())
        .sensoryFeedback(.selection, trigger: selection)
    }
}
