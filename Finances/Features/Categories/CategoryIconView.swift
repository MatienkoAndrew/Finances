//
//  CategoryIconView.swift
//  Finances
//
//  Created by Андрей Матиенко on 01.04.2026.
//


import SwiftUI

struct CategoryIconView: View {
    let category: ExpenseCategoryItem
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(Color(hex: category.colorHex) ?? .gray)
            .frame(width: size, height: size)
            .overlay {
                if let emoji = category.emoji, !emoji.isEmpty {
                    Text(emoji)
                        .font(.system(size: size * 0.5))
                } else {
                    Image(systemName: category.iconName)
                        .font(.system(size: size * 0.4, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
    }
}