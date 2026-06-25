//
//  CategoryNameNormalizer.swift
//  Finances
//
//  Created by Андрей Матиенко on 21.03.2026.
//


import Foundation

enum CategoryNameNormalizer {
    static func normalize(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}