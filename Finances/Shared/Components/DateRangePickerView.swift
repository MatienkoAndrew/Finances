//
//  DateRangePickerView.swift
//  Finances
//
//  Created by Андрей Матиенко on 20.03.2026.
//


import SwiftUI

struct DateRangePickerView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selection: DateRangeSelection

    @State private var tempStartDate: Date?
    @State private var tempEndDate: Date?

    let availableDates: [Date]

    private var calendar: Calendar { .current }

    private var displayedMonths: [MonthSelection] {
        let months = availableDates.map {
            let comps = calendar.dateComponents([.year, .month], from: $0)
            return MonthSelection(year: comps.year ?? 2000, month: comps.month ?? 1)
        }

        return Array(Set(months)).sorted {
            if $0.year != $1.year { return $0.year > $1.year }
            return $0.month > $1.month
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ForEach(displayedMonths) { month in
                        MonthRangeCalendarView(
                            month: month,
                            startDate: tempStartDate,
                            endDate: tempEndDate,
                            onSelectDate: handleTap
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("Выбери диапазон")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") {
                        selection.startDate = tempStartDate
                        selection.endDate = tempEndDate
                        dismiss()
                    }
                    .disabled(tempStartDate == nil || tempEndDate == nil)
                }
            }
            .onAppear {
                tempStartDate = selection.startDate
                tempEndDate = selection.endDate
            }
        }
    }

    private func handleTap(_ date: Date) {
        let tapped = calendar.startOfDay(for: date)

        if tempStartDate == nil || (tempStartDate != nil && tempEndDate != nil) {
            tempStartDate = tapped
            tempEndDate = nil
            return
        }

        if let start = tempStartDate, tempEndDate == nil {
            if tapped < start {
                tempEndDate = start
                tempStartDate = tapped
            } else {
                tempEndDate = tapped
            }
        }
    }
}