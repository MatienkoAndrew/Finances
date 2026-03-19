//
//  AnalyticsCardView.swift
//  Finances
//
//  Created by Андрей Матиенко on 19.03.2026.
//


import SwiftUI

struct AnalyticsCardView: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.title3.bold())
            }

            Spacer()
        }
        .padding()
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}