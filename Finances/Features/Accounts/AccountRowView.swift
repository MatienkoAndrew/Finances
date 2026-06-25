//
//  AccountRowView.swift
//  Finances
//
//  Created by Андрей Матиенко on 30.03.2026.
//


import SwiftUI

struct AccountRowView: View {
    let account: Account
    let balance: Double

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: account.type.systemImage)
                .font(.title3)
                .frame(width: 36, height: 36)
                .background(Color.gray.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(account.name)
                    .font(.headline)

                Text(account.type.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let note = account.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(formattedAmount(balance, currency: account.currencyCode))
                    .font(.headline)
                    .foregroundStyle(balanceColor(balance))

                Text(account.currencyCode)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func formattedAmount(_ value: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = " "
        formatter.decimalSeparator = ","

        let sign = value < 0 ? "-" : ""
        let number = formatter.string(from: NSNumber(value: abs(value))) ?? "\(abs(value))"
        return "\(sign)\(number) \(currency)"
    }

    private func balanceColor(_ value: Double) -> Color {
        if value < 0 {
            return .red
        } else if value > 0 {
            return .primary
        } else {
            return .secondary
        }
    }
}