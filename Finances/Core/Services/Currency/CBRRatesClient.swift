//
//  CBRRatesClient.swift
//  Finances
//
//  Официальные курсы ЦБ РФ к рублю: без ключа, на любую дату.
//  XML_daily — все валюты на день, XML_dynamic — одна валюта за период.
//  ЦБ даёт курс за «номинал» (100 KZT, 10 000 VND), здесь он делится на номинал.
//

import Foundation

enum CBRRatesClient {
    struct DailyRate {
        let id: String
        let code: String
        let rubPerUnit: Double
    }

    enum ClientError: LocalizedError {
        case badResponse

        var errorDescription: String? { "ЦБ РФ не ответил" }
    }

    /// Все валюты ЦБ на день (без даты — на сегодня) и день, с которого действует курс.
    static func daily(on date: Date? = nil) async throws -> (day: Date, rates: [DailyRate]) {
        var components = URLComponents(string: "https://www.cbr.ru/scripts/XML_daily.asp")!
        if let date {
            components.queryItems = [URLQueryItem(name: "date_req", value: requestFormatter.string(from: date))]
        }
        let document = try await load(components.url!)

        let rates = document.elements.compactMap { element -> DailyRate? in
            guard element.name == "Valute",
                  let id = element.attributes["ID"],
                  let code = element.children["CharCode"],
                  let rate = rubPerUnit(element) else { return nil }
            return DailyRate(id: id, code: code.uppercased(), rubPerUnit: rate)
        }
        let day = document.rootAttributes["Date"].flatMap(responseFormatter.date(from:)) ?? date ?? .now
        return (Calendar.current.startOfDay(for: day), rates)
    }

    /// Курсы одной валюты (по её ID у ЦБ, например R01335 для KZT) за период.
    static func dynamic(id: String, from: Date, to: Date) async throws -> [(day: Date, rubPerUnit: Double)] {
        var components = URLComponents(string: "https://www.cbr.ru/scripts/XML_dynamic.asp")!
        components.queryItems = [
            URLQueryItem(name: "date_req1", value: requestFormatter.string(from: from)),
            URLQueryItem(name: "date_req2", value: requestFormatter.string(from: to)),
            URLQueryItem(name: "VAL_NM_RQ", value: id)
        ]
        let document = try await load(components.url!)

        return document.elements.compactMap { element in
            guard element.name == "Record",
                  let day = element.attributes["Date"].flatMap(responseFormatter.date(from:)),
                  let rate = rubPerUnit(element) else { return nil }
            return (Calendar.current.startOfDay(for: day), rate)
        }
    }

    // MARK: - Private

    nonisolated private static func rubPerUnit(_ element: XMLRecords.Element) -> Double? {
        guard let value = element.children["Value"].flatMap(number),
              let nominal = element.children["Nominal"].flatMap(number),
              nominal > 0, value > 0 else { return nil }
        return value / nominal
    }

    nonisolated private static func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    private static func load(_ url: URL) async throws -> XMLRecords {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw ClientError.badResponse
        }
        // Ответ в windows-1251 — перекодируем, чтобы XMLParser не спотыкался о кодировку.
        let text = String(data: data, encoding: .windowsCP1251) ?? String(decoding: data, as: UTF8.self)
        let utf8 = text.replacingOccurrences(of: "encoding=\"windows-1251\"", with: "encoding=\"UTF-8\"")
        return XMLRecords(data: Data(utf8.utf8))
    }

    /// Дата в запросе: 20/09/2026.
    private static let requestFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter
    }()

    /// Дата в ответе: 20.09.2026.
    private static let responseFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter
    }()
}

/// Плоский XML ЦБ: корень, под ним записи (Valute/Record) с простыми дочерними полями.
private final class XMLRecords: NSObject, XMLParserDelegate {
    struct Element {
        let name: String
        let attributes: [String: String]
        var children: [String: String] = [:]
    }

    private(set) var rootAttributes: [String: String] = [:]
    private(set) var elements: [Element] = []

    private var depth = 0
    private var current: Element?
    private var text = ""

    init(data: Data) {
        super.init()
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        depth += 1
        text = ""
        switch depth {
        case 1: rootAttributes = attributeDict
        case 2: current = Element(name: elementName, attributes: attributeDict)
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if depth == 3 {
            current?.children[elementName] = text.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if depth == 2, let current {
            elements.append(current)
            self.current = nil
        }
        depth -= 1
    }
}
