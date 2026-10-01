//
//  SettingsComponents.swift
//  Finances
//
//  Детали экрана настроек: карточки-группы, строки с цветной иконкой
//  в скруглённом квадрате и заголовки разделов — в стиле экранов меток и аналитики.
//

import SwiftUI

/// Иконка строки: белый символ на цветном скруглённом квадрате.
struct SettingsIcon: View {
    let systemImage: String
    let color: Color
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Группа строк на одной карточке с разделителями после иконки.
struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(Color(.secondarySystemGroupedBackground))
        // Подсветка нажатой строки не вылезает за скругление карточки.
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// Строка-переход: иконка, название, значение справа и шеврон.
struct SettingsRow: View {
    let title: String
    let systemImage: String
    let color: Color
    var value: String?
    var showsChevron = true

    var body: some View {
        HStack(spacing: 14) {
            SettingsIcon(systemImage: systemImage, color: color)

            Text(title)
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            if let value {
                Text(value)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

/// Разделитель внутри карточки — начинается после иконки, как в системных настройках.
struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 62)
    }
}

/// Заголовок раздела над карточкой.
struct SettingsSectionHeader: View {
    let title: String
    var trailing: AnyView?

    init(_ title: String) {
        self.title = title
    }

    init<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = AnyView(trailing())
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.semibold))
            Spacer()
            trailing
        }
        .padding(.horizontal, 4)
    }
}

/// Лёгкое «вдавливание» строк и плиток при нажатии.
struct SettingsPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color(.systemFill) : Color.clear)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}
