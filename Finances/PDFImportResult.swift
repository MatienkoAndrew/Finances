//
//  PDFImportResult.swift
//  Finances
//
//  Created by Андрей Матиенко on 31.03.2026.
//


import Foundation

struct PDFImportResult {
    let accountsToCreate: [Account]
    let transactions: [Transaction]
}