import Foundation

enum ExchangeRateServiceError: LocalizedError {
    case badURL
    case badResponse
    case decodeFailed
    case rateNotFound(String)

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "Ошибка URL"
        case .badResponse:
            return "Ошибка ответа сервера"
        case .decodeFailed:
            return "Ошибка разбора ответа"
        case .rateNotFound(let code):
            return "Курс \(code) не найден"
        }
    }
}

enum ExchangeRateService {
    private static let apiKey = "c6ad4549a29729606c160d47"

    struct Response: Decodable {
        let result: String
        let conversion_rates: [String: Double]
    }
    
    static func fetchCurrentKztPerUnit(for code: String) async throws -> Double {
        let uppercasedCode = code.uppercased()
        let urlString = "https://v6.exchangerate-api.com/v6/\(apiKey)/latest/USD"

        guard let url = URL(string: urlString) else {
            throw ExchangeRateServiceError.badURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let http = response as? HTTPURLResponse,
              200..<300 ~= http.statusCode else {
            throw ExchangeRateServiceError.badResponse
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)

        guard decoded.result == "success" else {
            throw ExchangeRateServiceError.decodeFailed
        }

        guard let usdToKzt = decoded.conversion_rates["KZT"] else {
            throw ExchangeRateServiceError.rateNotFound("KZT")
        }

        guard let usdToTarget = decoded.conversion_rates[uppercasedCode] else {
            throw ExchangeRateServiceError.rateNotFound(uppercasedCode)
        }

        guard usdToTarget > 0 else {
            throw ExchangeRateServiceError.rateNotFound(uppercasedCode)
        }

        // если:
        // 1 USD = 480.95 KZT
        // 1 USD = 83.63 RUB
        // то 1 RUB = 480.95 / 83.63 KZT
        return usdToKzt / usdToTarget
    }


    static func fetchCurrentRubPerUnit(for code: String) async throws -> Double {
        let uppercasedCode = code.uppercased()
        let urlString = "https://v6.exchangerate-api.com/v6/\(apiKey)/latest/USD"

        guard let url = URL(string: urlString) else {
            throw ExchangeRateServiceError.badURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let http = response as? HTTPURLResponse,
              200..<300 ~= http.statusCode else {
            throw ExchangeRateServiceError.badResponse
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)

        guard decoded.result == "success" else {
            throw ExchangeRateServiceError.decodeFailed
        }

        guard let usdToRub = decoded.conversion_rates["RUB"] else {
            throw ExchangeRateServiceError.rateNotFound("RUB")
        }

        guard let usdToTarget = decoded.conversion_rates[uppercasedCode] else {
            throw ExchangeRateServiceError.rateNotFound(uppercasedCode)
        }

        guard usdToTarget > 0 else {
            throw ExchangeRateServiceError.rateNotFound(uppercasedCode)
        }

        // 1 target currency = usdToRub / usdToTarget RUB
        return usdToRub / usdToTarget
    }

    static func fetchCurrentRates(for codes: [String]) async throws -> [String: Double] {
        var result: [String: Double] = [:]

        for code in Set(codes.map { $0.uppercased() }) {
            let rate = try await fetchCurrentRubPerUnit(for: code)
            result[code] = rate
        }

        return result
    }
}
