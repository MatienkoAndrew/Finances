import Foundation
import CryptoKit

/// Снимок транзакции — всё, что нужно для сопоставления со строкой выписки или другой транзакцией.
struct TransactionSnapshot {
    let date: Date
    let details: String
    /// Сумма в валюте счёта без знака.
    let amount: Double
    let currencyCode: String
    let foreignAmount: Double?
    let foreignCurrencyCode: String?
    /// -1 — списание со счёта, +1 — зачисление.
    let direction: Int
    /// Транзакция создана импортом (а не вручную).
    let wasImported: Bool
}

/// Сопоставляет строки выписки с уже сохранёнными транзакциями, чтобы повторный
/// импорт той же или пересекающейся выписки не создавал дублей.
///
/// Почему не хэш от всех полей (как было раньше):
/// - последние дни выписки Kaspi показывает с предварительной суммой в тенге
///   для валютных операций; в следующей выписке сумма уже другая
///   (−64 681,66 ₸ → −63 431,07 ₸ при тех же −3 428 444 VND). Поэтому для валютных
///   операций ключ строится по сумме в валюте, а не в тенге;
/// - одинаковые покупки в один день (4 кофе по 7 000 KRW) — это разные операции.
///   Хэш склеивал их в одну. Здесь сравниваются количества: если в выписке
///   4 одинаковые строки, а в базе 1 — импортируются 3.
enum StatementDeduplicator {
    struct Match {
        let rowIndex: Int
        let existingIndex: Int
    }

    struct Result {
        let matches: [Match]
        let unmatchedRowIndices: [Int]
    }

    private struct AmountKey: Hashable {
        let currency: String
        let cents: Int
    }

    private struct GroupKey: Hashable {
        let details: String
        let amount: AmountKey
    }

    private struct Candidate {
        /// Порядковый номер дня — чтобы считать разницу в днях без возни с датами.
        let day: Int
        let group: GroupKey
        let direction: Int
        let accountAmount: Double
    }

    static func match(
        rows: [ParsedStatementRow],
        existing: [TransactionSnapshot],
        calendar: Calendar = .current
    ) -> Result {
        let incoming = rows.map { row in
            TransactionSnapshot(
                date: row.date,
                details: row.details,
                amount: abs(row.amount),
                currencyCode: row.accountCurrency,
                foreignAmount: row.foreignAmount.map(abs),
                foreignCurrencyCode: row.foreignCurrency,
                direction: row.amount >= 0 ? 1 : -1,
                wasImported: true
            )
        }

        return match(incoming, against: existing, matchRenamed: true, calendar: calendar)
    }

    /// Сопоставляет два набора транзакций. Внутри одного набора одинаковые операции
    /// считаются разными (это разные покупки), между наборами — одной и той же.
    ///
    /// - Parameter matchRenamed: разрешить пары с разным описанием (тот же день и сумма),
    ///   если транзакция из `existing` была импортирована — пользователь мог её переименовать.
    static func match(
        _ incomingSnapshots: [TransactionSnapshot],
        against existing: [TransactionSnapshot],
        matchRenamed: Bool,
        calendar: Calendar = .current
    ) -> Result {
        func candidate(_ snapshot: TransactionSnapshot) -> Candidate {
            Candidate(
                day: dayNumber(of: snapshot, calendar: calendar),
                group: GroupKey(
                    details: normalizedDetails(snapshot.details),
                    amount: amountKey(
                        amount: snapshot.amount,
                        currency: snapshot.currencyCode,
                        foreignAmount: snapshot.foreignAmount,
                        foreignCurrency: snapshot.foreignCurrencyCode
                    )
                ),
                direction: snapshot.direction,
                accountAmount: snapshot.amount
            )
        }

        let incoming = incomingSnapshots.map(candidate)
        let stored = existing.map(candidate)

        var rowToStored: [Int: Int] = [:]

        // 1. Тот же день, описание и сумма. Допуска «± день» нет намеренно: иначе проезд
        //    в последний день одной выписки съедал бы такой же проезд в первый день
        //    следующей. Сдвиг дат у старых импортов учитывает `dayNumber`.
        let storedByGroup = Dictionary(grouping: stored.indices, by: { stored[$0].group })
        let incomingByGroup = Dictionary(grouping: incoming.indices, by: { incoming[$0].group })

        for (group, rowIndices) in incomingByGroup {
            guard let storedIndices = storedByGroup[group] else { continue }
            for (rowIndex, storedIndex) in align(rowIndices, storedIndices, incoming: incoming, stored: stored) {
                rowToStored[rowIndex] = storedIndex
            }
        }

        // 2. Тот же день и сумма, но описание другое — пользователь мог переименовать
        //    импортированную операцию. Только среди импортированных, не ручных.
        var matchedStored = Set(rowToStored.values)

        for (rowIndex, row) in incoming.enumerated() where matchRenamed && rowToStored[rowIndex] == nil {
            let best = stored.indices
                .filter { index in
                    !matchedStored.contains(index)
                        && existing[index].wasImported
                        && stored[index].day == row.day
                        && stored[index].group.amount == row.group.amount
                }
                .min { pairCost(row, stored[$0]) < pairCost(row, stored[$1]) }

            if let best {
                matchedStored.insert(best)
                rowToStored[rowIndex] = best
            }
        }

        let matches = rowToStored
            .map { Match(rowIndex: $0.key, existingIndex: $0.value) }
            .sorted { $0.rowIndex < $1.rowIndex }

        let unmatched = incoming.indices.filter { rowToStored[$0] == nil }

        return Result(matches: matches, unmatchedRowIndices: unmatched)
    }

    /// Оптимально сопоставляет строки одной группы (одно описание и сумма):
    /// максимум пар в один и тот же день, при равенстве — минимальная суммарная
    /// «стоимость» (несовпадение суммы в тенге и знака). Обе стороны отсортированы,
    /// пары не пересекаются — поэтому хватает простой динамики.
    private static func align(
        _ rowIndices: [Int],
        _ storedIndices: [Int],
        incoming: [Candidate],
        stored: [Candidate]
    ) -> [(Int, Int)] {
        func order(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
            (lhs.day, lhs.direction, lhs.accountAmount) < (rhs.day, rhs.direction, rhs.accountAmount)
        }

        let rows = rowIndices.sorted { order(incoming[$0], incoming[$1]) }
        let olds = storedIndices.sorted { order(stored[$0], stored[$1]) }
        let n = rows.count
        let m = olds.count

        struct Cell {
            var pairs = 0
            var cost = 0.0

            func isBetter(than other: Cell) -> Bool {
                pairs != other.pairs ? pairs > other.pairs : cost < other.cost
            }
        }

        var dp = Array(repeating: Array(repeating: Cell(), count: m + 1), count: n + 1)

        for i in 0...n {
            for j in 0...m where i > 0 || j > 0 {
                var best = Cell(pairs: -1, cost: 0)
                if i > 0, dp[i - 1][j].isBetter(than: best) { best = dp[i - 1][j] }
                if j > 0, dp[i][j - 1].isBetter(than: best) { best = dp[i][j - 1] }

                if i > 0, j > 0 {
                    let row = incoming[rows[i - 1]]
                    let old = stored[olds[j - 1]]
                    if row.day == old.day {
                        let paired = Cell(pairs: dp[i - 1][j - 1].pairs + 1, cost: dp[i - 1][j - 1].cost + pairCost(row, old))
                        if paired.isBetter(than: best) { best = paired }
                    }
                }

                dp[i][j] = best
            }
        }

        var result: [(Int, Int)] = []
        var i = n
        var j = m

        while i > 0, j > 0 {
            let row = incoming[rows[i - 1]]
            let old = stored[olds[j - 1]]
            let cell = dp[i][j]

            if row.day == old.day,
               cell.pairs == dp[i - 1][j - 1].pairs + 1,
               abs(cell.cost - (dp[i - 1][j - 1].cost + pairCost(row, old))) < 1e-6 {
                result.append((rows[i - 1], olds[j - 1]))
                i -= 1
                j -= 1
            } else if cell.pairs == dp[i - 1][j].pairs, cell.cost == dp[i - 1][j].cost {
                i -= 1
            } else {
                j -= 1
            }
        }

        return result
    }

    /// Идентификаторы для новых строк выписки. Одинаковые строки получают порядковый
    /// номер, и номер подбирается так, чтобы не совпасть с уже занятыми (`used`):
    /// если в базе 1 кофе из прошлой выписки, а в новой их 2, новый получит номер 1, а не 0.
    static func fingerprints(
        for rows: [ParsedStatementRow],
        avoiding used: Set<String>
    ) -> [String] {
        let calendar = KaspiStatementParser.calendar
        var taken = used

        return rows.map { row in
            let day = calendar.dateComponents([.year, .month, .day], from: row.date)
            let amount = amountKey(
                amount: row.amount,
                currency: row.accountCurrency,
                foreignAmount: row.foreignAmount,
                foreignCurrency: row.foreignCurrency
            )

            let base = [
                "kaspi-v2",
                "\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0)",
                row.operationType.rawValue,
                normalizedDetails(row.details),
                row.amount >= 0 ? "+" : "-",
                "\(amount.currency):\(amount.cents)"
            ].joined(separator: "|")

            var occurrence = 0
            var fingerprint = hash("\(base)|\(occurrence)")
            while taken.contains(fingerprint) {
                occurrence += 1
                fingerprint = hash("\(base)|\(occurrence)")
            }
            taken.insert(fingerprint)
            return fingerprint
        }
    }

    private static func hash(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Только буквы и цифры в верхнем регистре: «7-ELEVEN», «7 ELEVEN» и «7eleven»
    /// считаются одним и тем же. Старый экстрактор терял пунктуацию, новый — нет,
    /// и уже сохранённые операции должны совпадать с новыми.
    static func normalizedDetails(_ details: String) -> String {
        String(details.uppercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains).map(Character.init))
    }

    /// Для валютных операций — сумма в валюте (она не меняется между выписками),
    /// иначе — сумма в валюте счёта.
    private static func amountKey(
        amount: Double,
        currency: String,
        foreignAmount: Double?,
        foreignCurrency: String?
    ) -> AmountKey {
        if let foreignAmount, let foreignCurrency {
            return AmountKey(
                currency: CurrencyDisplay.normalizedCode(from: foreignCurrency),
                cents: Int((abs(foreignAmount) * 100).rounded())
            )
        }

        return AmountKey(
            currency: CurrencyDisplay.normalizedCode(from: currency),
            cents: Int((abs(amount) * 100).rounded())
        )
    }

    /// Номер дня по григорианскому календарю (алгоритм days_from_civil).
    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra
    }

    /// День транзакции для сопоставления.
    ///
    /// Импортированные — по времени Kaspi. Новые импорты хранят полдень, старые —
    /// полночь того пояса, где делался импорт: по времени Kaspi это 00:00–06:00,
    /// если импорт был западнее (Москва), или 18:00–24:00 предыдущего дня,
    /// если восточнее (Корея, Вьетнам). Во втором случае настоящий день — следующий.
    /// Ручные транзакции — по местному календарю, как их ввёл пользователь.
    static func dayNumber(of snapshot: TransactionSnapshot, calendar: Calendar = .current) -> Int {
        guard snapshot.wasImported else {
            return dayNumber(snapshot.date, calendar: calendar)
        }

        let kaspiCalendar = KaspiStatementParser.calendar
        let hour = kaspiCalendar.component(.hour, from: snapshot.date)
        return dayNumber(snapshot.date, calendar: kaspiCalendar) + (hour >= 18 ? 1 : 0)
    }

    // `ordinality(of: .day, in: .era)` для даты ровно в полночь возвращает
    // предыдущий день, поэтому номер дня считается из компонентов.
    private static func dayNumber(_ date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return daysFromCivil(year: components.year ?? 0, month: components.month ?? 1, day: components.day ?? 1)
    }

    /// Чем меньше, тем лучше пара: сначала точное совпадение суммы в тенге,
    /// затем знак (почти не штрафуется — старые импорты записывали «Курсовую разницу»
    /// и возвраты с неверным знаком), затем ближайшая сумма.
    private static func pairCost(_ row: Candidate, _ candidate: Candidate) -> Double {
        let amountDifference = abs(candidate.accountAmount - row.accountAmount)
        let amountCost = amountDifference < 0.005 ? 0.0 : 2.0
        let directionCost = candidate.direction == row.direction ? 0.0 : 0.5
        let tieBreak = min(amountDifference, 1_000_000) * 1e-9
        return amountCost + directionCost + tieBreak
    }
}
