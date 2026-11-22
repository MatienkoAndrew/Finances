//
//  AnalyticsPeriodPicker.swift
//  Finances
//
//  Выбор месяца и года по касанию названия периода в аналитике и
//  закреплённые кнопки перехода по разделам отчёта.
//

import SwiftUI

/// Разделы отчёта, к которым можно перейти одним касанием.
enum AnalyticsReportSection: String, CaseIterable, Identifiable {
    case overview
    case categories
    case daily

    var id: String { rawValue }
}

/// Компактные кнопки «Обзор», «Категории», «По дням» над отчётом.
struct AnalyticsSectionBar: View {
    let dailyTitle: String
    let onSelect: (AnalyticsReportSection) -> Void

    var body: some View {
        HStack(spacing: 8) {
            button("Обзор", .overview)
            button("Категории", .categories)
            button(dailyTitle, .daily)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func button(_ title: String, _ section: AnalyticsReportSection) -> some View {
        Button {
            onSelect(section)
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Выбор месяца (а для масштаба «год» — года) из любого прошлого периода.
struct AnalyticsPeriodPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let scale: AnalyticsTimeScale
    /// Начало открытого сейчас периода.
    let current: Date
    /// Самый ранний год, за который есть операции.
    let earliestYear: Int
    let onSelect: (Date) -> Void

    @State private var year: Int = Calendar.current.component(.year, from: .now)

    private var calendar: Calendar { Calendar.current }
    private var thisYear: Int { calendar.component(.year, from: .now) }
    private var thisMonth: Int { calendar.component(.month, from: .now) }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "LLL"
        return formatter
    }()

    var body: some View {
        NavigationStack {
            Group {
                if scale == .year {
                    yearGrid
                } else {
                    monthGrid
                }
            }
            .padding(16)
            .frame(maxHeight: .infinity, alignment: .top)
            .navigationTitle(scale == .year ? "Год" : "Месяц")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сейчас") {
                        onSelect(.now)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear { year = calendar.component(.year, from: current) }
    }

    // MARK: - Months

    private var monthGrid: some View {
        VStack(spacing: 16) {
            HStack {
                yearArrow("chevron.left", isEnabled: year > earliestYear) { year -= 1 }
                Spacer()
                Text(String(year))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Spacer()
                yearArrow("chevron.right", isEnabled: year < thisYear) { year += 1 }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(1...12, id: \.self) { month in
                    monthCell(month)
                }
            }
        }
    }

    private func monthCell(_ month: Int) -> some View {
        let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? .now
        let isFuture = year > thisYear || (year == thisYear && month > thisMonth)
        let isSelected = calendar.isDate(date, equalTo: current, toGranularity: .month)

        return Button {
            onSelect(date)
            dismiss()
        } label: {
            Text(Self.monthFormatter.string(from: date).capitalized(with: Locale(identifier: "ru_RU")))
                .font(.body.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.white : (isFuture ? Color.secondary.opacity(0.5) : Color.primary))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    isSelected ? Color.accentColor : Color(.tertiarySystemFill),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
    }

    private func yearArrow(_ systemImage: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2), action)
        } label: {
            Image(systemName: systemImage)
                .font(.headline)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.3)
    }

    // MARK: - Years

    private var yearGrid: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach((min(earliestYear, thisYear)...thisYear).reversed(), id: \.self) { value in
                    let isSelected = value == calendar.component(.year, from: current)
                    Button {
                        onSelect(calendar.date(from: DateComponents(year: value, month: 1, day: 1)) ?? .now)
                        dismiss()
                    } label: {
                        Text(String(value))
                            .font(.body.weight(isSelected ? .semibold : .regular))
                            .monospacedDigit()
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(
                                isSelected ? Color.accentColor : Color(.tertiarySystemFill),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
