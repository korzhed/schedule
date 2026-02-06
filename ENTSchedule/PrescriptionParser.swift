//
//  PrescriptionParser.swift
//  ENTSchedule
//
//  Created by vl.korzh on 30.01.2026.
//

import Foundation

struct PrescriptionParser {

    // MARK: - Словари синонимов и паттернов

    private let unitSynonyms: [String: String] = [
        "табл": "таблетки", "таб": "таблетки",
        "таблетка": "таблетки", "таблетки": "таблетки",
        "кап": "капли", "кап.": "капли", "капли": "капли",
        "капсул": "капсулы", "капсула": "капсулы", "капсулы": "капсулы",
        "впрыск": "впрыска", "впрыска": "впрыска", "впрысках": "впрыска",
        "пшик": "пшик", "пшика": "пшик", "пшиков": "пшик",
        "доза": "дозы", "дозы": "дозы"
    ]

    private let partOfDayPatterns: [(pattern: String, timesPerDay: Int)] = [
        ("утром и вечером", 2),
        ("утро и вечер", 2),
        ("утром, днем и вечером", 3),
        ("утром, днём и вечером", 3),
        ("утром днем и вечером", 3),
        ("утро, день, вечер", 3),
        ("только утром", 1),
        ("только вечером", 1)
    ]

    private let intervalHourPatterns: [(pattern: String, hours: Int)] = [
        ("каждые 3 час", 3),
        ("каждые три час", 3),
        ("каждые 4 час", 4),
        ("каждые четыре час", 4),
        ("каждые 6 час", 6),
        ("каждые шесть час", 6),
        ("каждые 8 час", 8),
        ("каждые восемь час", 8),
        ("каждые 12 час", 12),
        ("каждые двенадцать час", 12)
    ]

    // MARK: - Публичный API

    func parse(_ text: String) -> [MedicationItem] {
        let normalized = normalize(text)
        let items = splitIntoItems(normalized)
        var results: [MedicationItem] = []

        for item in items {
            if let med = parseItem(item) {
                results.append(med)
            }
        }

        return results
    }

    // MARK: - Предобработка

    private func normalize(_ text: String) -> String {
        var result = text
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .lowercased()

        // слова‑паразиты / междометия
        let fillerWords = [
            " ну ",
            " так ",
            " эээ ",
            " эм ",
            " э ",
            " значит ",
            " в общем ",
            " типа "
        ]

        for filler in fillerWords {
            result = result.replacingOccurrences(of: filler, with: " ")
        }

        // схлопываем повторы вроде "по по", "каждые каждые"
        let duplicateTokens = ["по", "каждые", "каждый", "каждую", "каждое"]
        for token in duplicateTokens {
            let pattern = " \(token) \(token) "
            while result.contains(pattern) {
                result = result.replacingOccurrences(of: pattern, with: " \(token) ")
            }
        }

        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }

        result = result
            .replacingOccurrences(of: " \n", with: "\n")
            .replacingOccurrences(of: "\n ", with: "\n")

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Разбиение на элементы

    /// Делим текст на отдельные назначения
    private func splitIntoItems(_ text: String) -> [String] {
        // сначала пробуем "умное" разбиение по названиям с открывающей скобкой
        let pattern = #"[а-яa-z][^()]{0,80}\("#
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let ns = text as NSString
            let fullRange = NSRange(location: 0, length: ns.length)
            let matches = regex.matches(in: text, range: fullRange)

            if matches.count >= 2 {
                var result: [String] = []
                var lastStart = matches[0].range.location

                for i in 1..<matches.count {
                    let start = matches[i].range.location
                    let chunkRange = NSRange(location: lastStart, length: start - lastStart)
                    let chunk = ns
                        .substring(with: chunkRange)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !chunk.isEmpty {
                        result.append(chunk)
                    }
                    lastStart = start
                }

                // хвост
                let tailRange = NSRange(location: lastStart, length: ns.length - lastStart)
                let tail = ns
                    .substring(with: tailRange)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !tail.isEmpty {
                    result.append(tail)
                }

                return result
            }
        }

        // если не нашли несколько названий — старая логика по строкам
        return legacySplitIntoItems(text)
    }

    /// Старая построчная логика
    private func legacySplitIntoItems(_ text: String) -> [String] {
        let rawLines = text.components(separatedBy: .newlines)

        let lines = rawLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var result: [String] = []
        var current: [String] = []

        func closeCurrent() {
            guard !current.isEmpty else { return }
            let joined = current.joined(separator: " ")
            result.append(joined)
            current.removeAll()
        }

        for (index, line) in lines.enumerated() {
            let lower = line.lowercased()
            let isLastLine = index == lines.indices.last

            let serviceLineMarkers = [
                "жалобы:",
                "анамнез:",
                "осмотр:",
                "рекомендации:",
                "рекомендация:",
                "заключение:",
                "диагноз:"
            ]
            let isServiceLine = serviceLineMarkers.contains { lower.hasPrefix($0) }
            if isServiceLine {
                if isLastLine { closeCurrent() }
                continue
            }

            let looksLikeNewMedicationLine: Bool = {
                let components = lower.components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }
                guard components.count >= 2 else { return false }

                let first = components[0]
                let second = components[1]

                let isFirstNumeric = Int(first) != nil
                let isSecondNumericOrPo = Int(second) != nil || second == "по"

                if first == "каждые", Int(second) != nil {
                    return true
                }

                return !first.isEmpty && !isFirstNumeric && isSecondNumericOrPo
            }()

            let isDurationLine =
                lower.contains(" день") ||
                lower.contains(" дней") ||
                lower.contains(" неделю") ||
                lower.contains(" недели") ||
                lower.contains(" недель") ||
                lower.contains(" месяц") ||
                lower.contains(" месяцев")

            if looksLikeNewMedicationLine {
                closeCurrent()
                current.append(line)
            } else if isDurationLine {
                if current.isEmpty {
                    current.append(line)
                } else {
                    current.append(line)
                }
                if isLastLine {
                    closeCurrent()
                }
            } else {
                current.append(line)
                if isLastLine {
                    closeCurrent()
                }
            }
        }

        closeCurrent()
        return result
    }

    // MARK: - Разбор одного назначения

    private func parseItem(_ text: String) -> MedicationItem? {
        let words = text
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }

        guard !words.isEmpty else { return nil }

        var name: String? = extractPrimaryName(from: words, fullText: text)

        if let quoted = extractQuotedName(from: text) {
            name = quoted
        }

        if name == nil {
            name = extractNameAfterDosage(from: words)
        }

        if name == nil {
            name = extractNameFallback(from: words)
        }

        guard let finalNameRaw = name else { return nil }

        let finalName = finalNameRaw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let badNames: Set<String> = ["доз", "доза", "дозы", "кап", "кап.", "капли"]
        if finalName.count < 3 || badNames.contains(finalName) {
            return nil
        }

        let dosage = extractDosage(from: text) ?? "1 доза"
        let timesPerDay = extractTimesPerDay(from: text) ?? 1
        let durationInDays = extractDuration(from: text) ?? 7
        let comment = extractComment(from: text)

        return MedicationItem(
            id: UUID(),
            name: finalNameRaw,
            dosage: dosage,
            timesPerDay: timesPerDay,
            durationInDays: durationInDays,
            comment: comment
        )
    }

    // MARK: - Имя препарата

    private func extractPrimaryName(from words: [String], fullText: String) -> String? {
        let lower = words.map { $0.lowercased() }

        // шаблон: "каждые 2 часа пурпурин ..."
        if lower.count >= 4,
           lower[0] == "каждые",
           Int(lower[1]) != nil,
           (lower[2].hasPrefix("час") || lower[2].hasPrefix("ч")) {

            if lower.count >= 5,
               lower[3].trimmingCharacters(in: .punctuationCharacters).isEmpty {
                return words[4]
            } else {
                return words[3]
            }
        }

        if let compound = extractCompoundName(from: words) {
            return compound
        }

        return extractNameFallback(from: words)
    }

    private func extractCompoundName(from words: [String]) -> String? {
        if words.isEmpty { return nil }

        let stopTokens: Set<String> = [
            "по", "в", "во", "на",
            "раз", "раза", "раз,", "раза,",
            "день", "дня", "дней",
            "дня,", "дней,",
            "каждые", "каждый", "каждую", "каждое",
            "утром", "днем", "днём", "вечером", "ночью",
            "до", "после", "во", "во время", "перед"
        ]

        let doseLikeTokensPrefixes = [
            "табл", "таблетк",
            "капл", "кап.", "капли",
            "капсул", "капсула", "капсулы",
            "впрыск", "пшик", "доза", "дозы",
            "мг", "мкг", "г", "мл", "ед", "%"
        ]

        var collected: [String] = []

        for word in words {
            let lower = word.lowercased().trimmingCharacters(in: .punctuationCharacters)

            if lower.isEmpty { continue }

            if Int(lower) != nil {
                break
            }

            if stopTokens.contains(lower) {
                break
            }

            if doseLikeTokensPrefixes.contains(where: { lower.hasPrefix($0) }) {
                break
            }

            collected.append(word)

            if collected.count == 3 {
                break
            }
        }

        guard !collected.isEmpty else { return nil }

        let genericForms: Set<String> = [
            "спрей", "раствор", "мазь", "гель", "сироп", "капли", "таблетки"
        ]
        let firstLower = collected[0].lowercased().trimmingCharacters(in: .punctuationCharacters)
        if genericForms.contains(firstLower), collected.count == 1 {
            return nil
        }

        return collected.joined(separator: " ")
    }

    private func extractQuotedName(from text: String) -> String? {
        if let name = firstMatch(pattern: "«([^»]+)»", in: text, group: 1) {
            return name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let name = firstMatch(pattern: "\"([^\"]+)\"", in: text, group: 1) {
            return name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private func extractNameAfterDosage(from words: [String]) -> String? {
        let doseKeywords = [
            "табл", "таблетк",
            "капл", "кап.", "капли",
            "капсул", "капсула", "капсулы",
            "впрыск", "впрыска", "пшик", "доза", "дозы"
        ]

        let numericWords: Set = [
            "один", "одна", "одно",
            "два", "две",
            "три",
            "четыре",
            "пять",
            "шесть"
        ]

        for (index, word) in words.enumerated() {
            let lower = word.lowercased()
            if doseKeywords.contains(where: { lower.hasPrefix($0) }) {
                let nextIndex = index + 1
                if nextIndex < words.count {
                    let nextWord = words[nextIndex]
                    let lowerNext = nextWord.lowercased()
                    if Int(nextWord) == nil && !numericWords.contains(lowerNext) {
                        return nextWord
                    }
                }
            }
        }
        return nil
    }

    private func extractNameFallback(from words: [String]) -> String? {
        let stopWords: Set<String> = [
            "по", "по-", "в", "во", "на", "раз", "раза", "раз,", "раза,",
            "день", "дня", "дней",
            "таблетки", "таблетка", "табл", "капли", "капля", "кап", "кап.",
            "капсулы", "капсула", "капсул",
            "спрей", "раствор", "мазь", "гель", "сироп",
            "каждые",
            "утром", "днем", "днём", "вечером", "ночью",
            "до", "после", "перед", "во", "во время",
            "доза", "дозы", "доз.", "доз"
        ]

        return words.first { word in
            let lower = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
            return !stopWords.contains(lower) && Int(lower) == nil
        }
    }

    // MARK: - Комментарии

    private func extractComment(from text: String) -> String? {
        var comment: String? = nil

        func add(_ note: String) {
            if comment == nil {
                comment = note
            } else {
                comment! += "; " + note
            }
        }

        let lower = text.lowercased()

        if lower.contains("через день") {
            add("Приём через день")
        }
        if lower.contains("по необходимости") || lower.contains("по требованию") {
            add("По необходимости")
        }
        if lower.contains("потом") {
            add("Схема меняется со временем")
        }

        let commentPatterns: [(substr: String, note: String)] = [
            ("после еды", "Принимать после еды"),
            ("до еды", "Принимать до еды"),
            ("во время еды", "Принимать во время еды"),
            ("натощак", "Принимать натощак"),
            ("перед сном", "Принимать перед сном"),
            ("на ночь", "Принимать на ночь"),
            ("в каждый носовой ход", "В каждый носовой ход"),
            ("в оба уха", "В оба уха"),
            ("в оба носовых хода", "В оба носовых хода")
        ]

        for (substr, note) in commentPatterns {
            if lower.contains(substr) {
                add(note)
            }
        }

        return comment
    }

    // MARK: - Дозировка

    private func extractDosage(from text: String) -> String? {
        let numericPatterns = [
            #"(?:по\s*)?(\d+)\s*(капл[иья]|кап\.?)"#,
            #"(?:по\s*)?(\d+)\s*(доз[аы])"#,
            #"(?:по\s*)?(\d+)\s*(табл[еа-яё]*|таб\.?)"#,
            #"(?:по\s*)?(\d+)\s*(капсул[аы]?)"#,
            #"(?:по\s*)?(\d+)\s*мл"#,
            #"(?:по\s*)?(\d+)\s*(пшик[aов]?|впрыск[аов]?)"#
        ]

        for pattern in numericPatterns {
            if let full = firstMatch(pattern: pattern, in: text, group: 0) {
                let parts = full
                    .trimmingCharacters(in: .whitespaces)
                    .components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }

                if parts.count >= 2,
                   let amount = Int(parts[0]) {
                    let rawUnit = parts[1]
                    let unit = normalizeUnit(rawUnit)
                    return "\(amount) \(unit)"
                }
                return full.trimmingCharacters(in: .whitespaces)
            }
        }

        if let (number, unitRaw) = extractTextualDosage(from: text) {
            let unit = normalizeUnit(unitRaw)
            return "\(number) \(unit)"
        }

        return nil
    }

    private func normalizeUnit(_ raw: String) -> String {
        let key = raw
            .replacingOccurrences(of: ".", with: "")
            .lowercased()
        return unitSynonyms[key] ?? raw
    }

    private func extractTextualDosage(from text: String) -> (Int, String)? {
        let mapping: [String: Int] = [
            "одна": 1, "одну": 1, "один": 1,
            "две": 2, "два": 2,
            "три": 3,
            "четыре": 4,
            "пять": 5,
            "шесть": 6
        ]

        let patterns = [
            #"по\s+([а-яё]+)\s+(капл[иья])"#,
            #"по\s+([а-яё]+)\s+(доз[аы])"#,
            #"по\s+([а-яё]+)\s+(табл[еа-яё]*)"#,
            #"по\s+([а-яё]+)\s+(капсул[аы]?)"#,
            #"по\s+([а-яё]+)\s+(пшик[аов]?|впрыск[аов]?)"#,
            #"([а-яё]+)\s+(капл[иья])"#,
            #"([а-яё]+)\s+(доз[аы])"#,
            #"([а-яё]+)\s+(табл[еа-яё]*)"#,
            #"([а-яё]+)\s+(капсул[аы]?)"#,
            #"([а-яё]+)\s+(пшик[аов]?|впрыск[аов]?)"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                continue
            }

            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, range: range),
               match.numberOfRanges >= 3,
               let wordRange = Range(match.range(at: 1), in: text),
               let unitRange = Range(match.range(at: 2), in: text) {
                let word = String(text[wordRange])
                let unit = String(text[unitRange])
                if let number = mapping[word] {
                    return (number, unit)
                }
            }
        }

        return nil
    }

    // MARK: - Кратность в день

    private func extractTimesPerDay(from text: String) -> Int? {
        let lower = text.lowercased()

        let numericPatterns = [
            #"(\d+)\s*раз[аы]?\s*(в\s*день)?"#,
            #"(\d+)\s*р/д"#
        ]

        for pattern in numericPatterns {
            if let numberString = firstMatch(pattern: pattern, in: lower, group: 1),
               let number = Int(numberString) {
                return number
            }
        }

        let wordToNumber: [String: Int] = [
            "один": 1, "одна": 1, "одно": 1,
            "два": 2, "две": 2,
            "три": 3,
            "четыре": 4
        ]

        if let word = firstMatch(
            pattern: #"([а-яё]+)\s+раз[аы]?\s*(в\s*день)?"#,
            in: lower,
            group: 1
        ), let number = wordToNumber[word] {
            return number
        }

        if let hoursString = firstMatch(
            pattern: #"каждые\s+(\d+)\s*час"#,
            in: lower,
            group: 1
        ), let hours = Int(hoursString), hours > 0 {
            return max(1, 24 / hours)
        }

        for (pattern, tpd) in partOfDayPatterns {
            if lower.contains(pattern) {
                return tpd
            }
        }

        for (pattern, hours) in intervalHourPatterns {
            if lower.contains(pattern) {
                let tpd = max(1, 24 / max(1, hours))
                return tpd
            }
        }

        return nil
    }

    // MARK: - Длительность

    private func extractDuration(from text: String) -> Int? {
        let lower = text.lowercased()

        if let rangeDays = extractDaysRange(from: lower) {
            return rangeDays
        }

        if let weeks = extractWeeks(from: lower) {
            return weeks * 7
        }

        if let months = extractMonths(from: lower) {
            return months * 30
        }

        if let days = extractDays(from: lower) {
            return days
        }

        return nil
    }

    private func extractDaysRange(from text: String) -> Int? {
        if let upper = firstMatch(
            pattern: #"курс:\s*\d+\s*[–-]\s*(\d+)\s*дн"#,
            in: text,
            group: 1
        ), let value = Int(upper) {
            return value
        }
        if let upper2 = firstMatch(
            pattern: #"(\d+)\s*[–-]\s*(\d+)\s*дн"#,
            in: text,
            group: 2
        ), let value2 = Int(upper2) {
            return value2
        }
        return nil
    }

    private func extractWeeks(from text: String) -> Int? {
        let weekTextPatterns: [(String, Int)] = [
            ("одну недел", 1),
            ("одна недел", 1),
            ("две недел", 2),
            ("три недел", 3),
            ("четыре недел", 4),
            ("пять недел", 5),
            ("шесть недел", 6)
        ]

        for (pattern, value) in weekTextPatterns {
            if text.contains(pattern) {
                return value
            }
        }

        if let numberString = firstMatch(
            pattern: #"(\d+)\s*недел[ьияюе]"#,
            in: text,
            group: 1
        ), let number = Int(numberString) {
            return number
        }

        return nil
    }

    private func extractMonths(from text: String) -> Int? {
        let monthTextPatterns: [(String, Int)] = [
            ("один месяц", 1),
            ("один мес", 1),
            ("два месяц", 2),
            ("два мес", 2),
            ("три месяц", 3),
            ("три мес", 3),
            ("четыре месяц", 4),
            ("четыре мес", 4)
        ]

        for (pattern, value) in monthTextPatterns {
            if text.contains(pattern) {
                return value
            }
        }

        if let numberString = firstMatch(
            pattern: #"(\d+)\s*месяц[аеов]?"#,
            in: text,
            group: 1
        ), let number = Int(numberString) {
            return number
        }

        return nil
    }

    private func extractDays(from text: String) -> Int? {
        if let numberString = firstMatch(
            pattern: #"(\d+)\s*дн(?:я|ей|ень)?"#,
            in: text,
            group: 1
        ), let number = Int(numberString) {
            return number
        }
        return nil
    }

    // MARK: - Regex helper

    private func firstMatch(pattern: String, in text: String, group: Int) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              group < match.numberOfRanges
        else {
            return nil
        }

        guard let swiftRange = Range(match.range(at: group), in: text) else {
            return nil
        }

        return String(text[swiftRange])
    }
}
