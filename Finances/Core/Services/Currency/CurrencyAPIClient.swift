//
//  CurrencyAPIClient.swift
//  Finances
//
//  Запасной источник для валют, которых нет у ЦБ РФ (LKR, MYR и т.п.):
//  открытый currency-api (github.com/fawazahmed0/exchange-api), без ключа,
//  ежедневные снимки с марта 2024 года.
//

import Foundation

enum CurrencyAPIClient {
    private struct Response: Decodable {
        let rub: [String: Double]
    }

    /// Сколько рублей за 1 единицу каждой валюты на этот день.
    static func rubPerUnit(on date: Date) async throws -> [String: Double] {
        let day = dayFormatter.string(from: date)
        let mirrors = [
            "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@\(day)/v1/currencies/rub.min.json",
            "https://\(day).currency-api.pages.dev/v1/currencies/rub.min.json"
        ]

        var lastError: Error = URLError(.badServerResponse)
        for mirror in mirrors {
            guard let url = URL(string: mirror) else { continue }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                    throw URLError(.badServerResponse)
                }
                // В ответе — сколько единиц валюты за 1 рубль.
                let unitsPerRub = try JSONDecoder().decode(Response.self, from: data).rub
                var result: [String: Double] = [:]
                for (code, units) in unitsPerRub where units > 0 {
                    result[code.uppercased()] = 1 / units
                }
                return result
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
