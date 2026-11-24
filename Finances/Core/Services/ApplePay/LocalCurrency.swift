//
//  LocalCurrency.swift
//  Finances
//
//  Валюта страны, где сейчас телефон, — по его часовому поясу (в поездке
//  iPhone переводит часы сам). Нужна, когда «Команды» передают сумму оплаты
//  числом без валюты: платят почти всегда в местной валюте, а точную сумму
//  в тенге потом даст выписка.
//

import Foundation

nonisolated enum LocalCurrency {
    /// Код валюты по часовому поясу; nil — пояс неизвестен.
    static func code(for timeZone: TimeZone = .current) -> String? {
        let identifier = timeZone.identifier
        if let code = byTimeZone[identifier] { return code }

        // Большинство поясов Европы — евро, кроме перечисленных выше.
        if identifier.hasPrefix("Europe/") { return "EUR" }
        // Поясы США.
        if identifier.hasPrefix("America/"), usTimeZones.contains(identifier) { return "USD" }
        return nil
    }

    private static let usTimeZones: Set<String> = [
        "America/New_York", "America/Chicago", "America/Denver", "America/Los_Angeles",
        "America/Phoenix", "America/Anchorage", "America/Detroit", "America/Boise",
        "America/Indiana/Indianapolis", "America/Kentucky/Louisville"
    ]

    private static let byTimeZone: [String: String] = [
        // Казахстан
        "Asia/Almaty": "KZT", "Asia/Qostanay": "KZT", "Asia/Aqtobe": "KZT", "Asia/Aqtau": "KZT",
        "Asia/Atyrau": "KZT", "Asia/Oral": "KZT", "Asia/Qyzylorda": "KZT",
        // Россия
        "Europe/Moscow": "RUB", "Europe/Kaliningrad": "RUB", "Europe/Samara": "RUB",
        "Europe/Volgograd": "RUB", "Europe/Saratov": "RUB", "Europe/Ulyanovsk": "RUB",
        "Europe/Astrakhan": "RUB", "Europe/Kirov": "RUB", "Asia/Yekaterinburg": "RUB",
        "Asia/Omsk": "RUB", "Asia/Novosibirsk": "RUB", "Asia/Barnaul": "RUB", "Asia/Tomsk": "RUB",
        "Asia/Novokuznetsk": "RUB", "Asia/Krasnoyarsk": "RUB", "Asia/Irkutsk": "RUB",
        "Asia/Chita": "RUB", "Asia/Yakutsk": "RUB", "Asia/Vladivostok": "RUB",
        "Asia/Magadan": "RUB", "Asia/Sakhalin": "RUB", "Asia/Kamchatka": "RUB",
        // Азия
        "Asia/Taipei": "TWD", "Asia/Ho_Chi_Minh": "VND", "Asia/Saigon": "VND",
        "Asia/Bangkok": "THB", "Asia/Tokyo": "JPY", "Asia/Seoul": "KRW",
        "Asia/Shanghai": "CNY", "Asia/Urumqi": "CNY", "Asia/Hong_Kong": "HKD", "Asia/Macau": "MOP",
        "Asia/Singapore": "SGD", "Asia/Kuala_Lumpur": "MYR", "Asia/Manila": "PHP",
        "Asia/Jakarta": "IDR", "Asia/Makassar": "IDR", "Asia/Jayapura": "IDR",
        "Asia/Phnom_Penh": "KHR", "Asia/Vientiane": "LAK", "Asia/Yangon": "MMK",
        "Asia/Kolkata": "INR", "Asia/Calcutta": "INR", "Asia/Colombo": "LKR",
        "Asia/Kathmandu": "NPR", "Indian/Maldives": "MVR",
        "Asia/Dubai": "AED", "Asia/Qatar": "QAR", "Asia/Riyadh": "SAR", "Asia/Jerusalem": "ILS",
        "Asia/Tbilisi": "GEL", "Asia/Yerevan": "AMD", "Asia/Baku": "AZN",
        "Asia/Tashkent": "UZS", "Asia/Samarkand": "UZS", "Asia/Bishkek": "KGS",
        "Asia/Dushanbe": "TJS", "Asia/Ulaanbaatar": "MNT",
        // Европа не в евро
        "Europe/London": "GBP", "Europe/Istanbul": "TRY", "Europe/Zurich": "CHF",
        "Europe/Prague": "CZK", "Europe/Warsaw": "PLN", "Europe/Budapest": "HUF",
        "Europe/Belgrade": "RSD", "Europe/Bucharest": "RON", "Europe/Sofia": "BGN",
        "Europe/Stockholm": "SEK", "Europe/Oslo": "NOK", "Europe/Copenhagen": "DKK",
        "Europe/Kyiv": "UAH", "Europe/Kiev": "UAH", "Europe/Minsk": "BYN", "Europe/Chisinau": "MDL",
        "Atlantic/Reykjavik": "ISK",
        // Прочее
        "Africa/Cairo": "EGP", "Australia/Sydney": "AUD", "Australia/Melbourne": "AUD",
        "Pacific/Auckland": "NZD", "Pacific/Honolulu": "USD", "America/Toronto": "CAD",
        "America/Vancouver": "CAD", "America/Mexico_City": "MXN", "America/Cancun": "MXN"
    ]
}
