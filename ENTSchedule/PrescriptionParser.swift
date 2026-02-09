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
        "доза": "дозы", "дозы": "дозы",
        "мг": "мг", "мкг": "мкг", "г": "г", "мл": "мл", "ед": "ед", "%": "%",
        "мг/кг": "мг/кг", "мг/кг/д": "мг/кг/д"
    ]

    // Расширенная карта текстовых числительных с разными формами склонений
    private let textNumberWords: [String: Int] = [
        "один": 1, "одна": 1, "одно": 1, "одну": 1,
        "два": 2, "две": 2,
        "три": 3,
        "четыре": 4,
        "пять": 5,
        "шесть": 6,
        "семь": 7,
        "восемь": 8,
        "девять": 9,
        "десять": 10,
        // для длительности также добавим формы:
        "первый": 1, "первая": 1, "первое": 1,
        "второй": 2, "вторая": 2,
        "третий": 3, "третья": 3,
        "четвертый": 4, "четвертая": 4
    ]

    private let partOfDayPatterns: [(pattern: String, timesPerDay: Int)] = [
        ("утром и вечером", 2),
        ("утро и вечер", 2),
        ("утром, днем и вечером", 3),
        ("утром, днём и вечером", 3),
        ("утром днем и вечером", 3),
        ("утро, день, вечер", 3),
        ("только утром", 1),
        ("только вечером", 1),
        ("вечером", 1),
        ("утром", 1),
        ("днём", 1),
        ("днем", 1),
        ("ночью", 1),
        ("по ночам", 1),
        ("на ночь", 1),
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
        ("каждые двенадцать час", 12),
        ("через 3 час", 3),
        ("через три час", 3),
        ("через 4 час", 4),
        ("через четыре час", 4),
        ("через 6 час", 6),
        ("через шесть час", 6),
        ("через 8 час", 8),
        ("через восемь час", 8),
        ("через 12 час", 12),
        ("через двенадцать час", 12)
    ]

    // MARK: - Публичный API

    func parse(_ text: String) -> [MedicationItem] {
        // Нормализуем текст сразу при входе для унификации и упрощения разбора
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

        // Добавляем пробелы вокруг чисел и букв, чтобы распознавать "500мг" как "500 мг"
        // и "0.5г" как "0.5 г"
        result = fixSpacingAroundNumbersAndUnits(in: result)

        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }

        result = result
            .replacingOccurrences(of: " \n", with: "\n")
            .replacingOccurrences(of: "\n ", with: "\n")

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Вспомогательная функция для добавления пробелов между числом и единицей измерения (например, "500мг" -> "500 мг")
    private func fixSpacingAroundNumbersAndUnits(in text: String) -> String {
        // Добавляем пробел между цифрами (возможны десятичные) и буквами с русскими/латинскими символами
        var result = text

        let patterns = [
            #"(\d)([а-яa-z%]+)"#,      // 500мг, 10мл, 5мг/кг
            #"(\d+[\.,]?\d*)\s*\/\s*([а-яa-z]+)"#, // для дробных единиц типа 5мг/кг
            #"([а-яa-z%]+)(\d)"#       // если написано наоборот, например мг5 (редко, но чтобы избежать ошибок)
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            var offset = 0
            regex.enumerateMatches(in: result, options: [], range: range) { match, _, _ in
                guard let match = match else { return }
                if pattern == #"(\d)([а-яa-z%]+)"#,
                   let digitRange = Range(match.range(at: 1), in: result),
                   let unitRange = Range(match.range(at: 2), in: result) {
                    let digitStr = String(result[digitRange])
                    let unitStr = String(result[unitRange])
                    let replacement = "\(digitStr) \(unitStr)"
                    let totalRange = match.range(at: 0)
                    if let swiftRange = Range(totalRange, in: result) {
                        let startIndex = result.index(swiftRange.lowerBound, offsetBy: offset)
                        let endIndex = result.index(startIndex, offsetBy: totalRange.length)
                        result.replaceSubrange(startIndex..<endIndex, with: replacement)
                        offset += replacement.count - totalRange.length
                    }
                }
                else if pattern == #"([а-яa-z%]+)(\d)"#,
                        let unitRange = Range(match.range(at: 1), in: result),
                        let digitRange = Range(match.range(at: 2), in: result) {
                    let unitStr = String(result[unitRange])
                    let digitStr = String(result[digitRange])
                    let replacement = "\(unitStr) \(digitStr)"
                    let totalRange = match.range(at: 0)
                    if let swiftRange = Range(totalRange, in: result) {
                        let startIndex = result.index(swiftRange.lowerBound, offsetBy: offset)
                        let endIndex = result.index(startIndex, offsetBy: totalRange.length)
                        result.replaceSubrange(startIndex..<endIndex, with: replacement)
                        offset += replacement.count - totalRange.length
                    }
                }
            }
        }

        // Обрабатываем кейсы "0.5г" -> "0.5 г" (дробные числа)
        let decimalPattern = #"(\d+[.,]\d+)([а-яa-z%]+)"#
        if let regex = try? NSRegularExpression(pattern: decimalPattern, options: .caseInsensitive) {
            let range = NSRange(result.startIndex..., in: result)
            var offset = 0
            regex.enumerateMatches(in: result, options: [], range: range) { match, _, _ in
                guard let match = match else { return }
                if let numberRange = Range(match.range(at: 1), in: result),
                   let unitRange = Range(match.range(at: 2), in: result) {
                    let numberStr = String(result[numberRange])
                    let unitStr = String(result[unitRange])
                    let replacement = "\(numberStr) \(unitStr)"
                    let totalRange = match.range(at: 0)
                    if let swiftRange = Range(totalRange, in: result) {
                        let startIndex = result.index(swiftRange.lowerBound, offsetBy: offset)
                        let endIndex = result.index(startIndex, offsetBy: totalRange.length)
                        result.replaceSubrange(startIndex..<endIndex, with: replacement)
                        offset += replacement.count - totalRange.length
                    }
                }
            }
        }

        return result
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

                let isFirstNumeric = Int(first) != nil || textNumberWords[first] != nil
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

    /// Разбор элемента с учетом всех параметров в произвольном порядке (особенно для голосового ввода)
    /// Сначала ищем дозировку, кратность, длительность, потом оставшееся - название.
    /// Комментарии собираем из остатка и известных ключевых слов.
    private func parseItem(_ text: String) -> MedicationItem? {
        // Нормализуем пробелы и приводим к нижнему регистру перед разбором
        let normalizedText = normalize(text)

        // Для парсинга параметров используем отдельные методы
        let dosage = extractDosage(from: normalizedText) ?? "1 доза"

        // Если найдены оба варианта, сохраняем основной и альтернативный
        let timesResult = extractTimesPerDayWithAlternative(from: normalizedText)
        let timesPerDay = timesResult?.timesPerDay ?? 1

        let durationInDays = extractDuration(from: normalizedText) ?? 7
        let comment = extractComment(from: normalizedText)

        // Собираем все слова из параметров в множестве для фильтрации из названия, с учётом пунктуации и склонений
        var parameterWords = Set<String>()

        // Функция для добавления слов из строки в множество с очисткой от пунктуации и приведение к нижнему регистру
        func addParameterWords(from string: String) {
            let words = string
                .lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
                .map { $0.trimmingCharacters(in: .punctuationCharacters) }
                .filter { !$0.isEmpty }
            for w in words {
                parameterWords.insert(w)
            }
        }

        // Добавляем дозировку слова
        addParameterWords(from: dosage)

        // Добавляем timesPerDay фразы
        addParameterWords(from: timesPerDayPhrases(timesPerDay).joined(separator: " "))

        // Добавляем числовые фразы кратности, например "3 раза", "1 раз в день"
        if let timesPhrase = extractTimesPerDayRaw(from: normalizedText) {
            addParameterWords(from: timesPhrase)
        }

        // Добавляем длительность, например "7 дней", "на 1 неделю" и т.п.
        if let durationRaw = extractDurationRaw(from: normalizedText) {
            addParameterWords(from: durationRaw)
        }

        // Добавляем отдельные ключевые служебные слова, чтобы убрать их из названия
        let stopWords = [
            "каждые", "каждый", "каждую", "каждое",
            "раз", "раза", "разы",
            "в", "день", "дн", "дней",
            "через", "по", "необходимости", "требованию",
            "сутки", "суток", "сут",
            "таблетка", "таблеток", "таблетки", "табл",
            "капля", "капель", "капли", "кап",
            "после", "еды", "еда",
            "потом",
            "курс",
            "неделя", "недели", "недель", "недел",
            "месяц", "месяца", "месяцев", "мес",
            "час", "часов",
            "доза", "дозы",
            "пшик", "впрыск", "капсул", "капсула", "капсулы"
        ]
        for word in stopWords {
            parameterWords.insert(word)
        }

        // Новое: добавляем паттерны с интервалом времени "каждые N:00" и "через N:00" в список исключаемых
        if let timeIntervalPattern = extractTimeIntervalPattern(from: normalizedText) {
            // разбиваем паттерн на слова и символы
            let intervalWords = timeIntervalPattern
                .lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
                .map { $0.trimmingCharacters(in: .punctuationCharacters) }
                .filter { !$0.isEmpty }
            for w in intervalWords {
                parameterWords.insert(w)
            }
        }

        // Убираем все вхождения слов из исходного текста
        // Токенизируем исходный текст
        let originalWords = normalizedText
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }

        // Фильтруем слова - убираем те, что есть в параметрах и числах
        let filteredWords = originalWords.filter { word in
            if parameterWords.contains(word) { return false }
            // также исключаем слова, которые являются числами или текстовыми числительными
            if Int(word) != nil { return false }
            if textNumberWords[word] != nil { return false }
            return true
        }

        // Собираем название из оставшихся слов
        var name = filteredWords.joined(separator: " ")

        // Убираем лишние пробелы
        while name.contains("  ") {
            name = name.replacingOccurrences(of: "  ", with: " ")
        }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)

        // Если название пустое, пытаемся извлечь из кавычек
        if name.isEmpty {
            if let quotedName = extractQuotedName(from: normalizedText) {
                name = quotedName
            }
        }

        // Фильтрация плохих названий
        if let n = name.lowercased() as String? {
            let badNames: Set<String> = ["доз", "доза", "дозы", "кап", "кап.", "капли"]
            if n.count < 3 || badNames.contains(n) {
                return nil
            }
        } else {
            return nil
        }

        // Комментарий: реализована агрессивная фильтрация параметров из названия
        return MedicationItem(
            id: UUID(),
            name: name,
            dosage: dosage,
            timesPerDay: timesPerDay,
            durationInDays: durationInDays,
            comment: comment
        )
    }

    /// Пытается извлечь из текста исходную фразу кратности приема (например "3 раза в день")
    private func extractTimesPerDayRaw(from text: String) -> String? {
        let patterns = [
            #"(\d+\s*раз[аы]?\s*(в\s*день)?)"#,
            #"([а-яё]+\s*раз[аы]?\s*(в\s*день)?)"#,
            #"(\d+\s*р/д)"#,
            #"([а-яё]+\s*р/д)"#
        ]

        let lower = text.lowercased()

        for pattern in patterns {
            if let match = firstMatch(pattern: pattern, in: lower, group: 0) {
                return match
            }
        }

        return nil
    }

    /// Новая функция для извлечения паттерна с интервалом в формате "каждые N:00" или "через N:00"
    private func extractTimeIntervalPattern(from text: String) -> String? {
        // Поддерживаются интервалы как в текстовой, так и в цифровой форме (например "каждые 3:00", "через 6:00")
        let pattern = #"(каждые|через)\s+(\d+):00"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)
        if let match = regex.firstMatch(in: text, range: range),
           match.numberOfRanges >= 3,
           let fullRange = Range(match.range(at: 0), in: text) {
            return String(text[fullRange])
        }

        return nil
    }

    // Убирает все вхождения паттерна в тексте (регекс)
    private func removePattern(_ text: String, pattern: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }

    private func timesPerDayPhrases(_ times: Int) -> [String] {
        // Возвращает набор текстовых фраз, которые могут обозначать количество приемов в день
        switch times {
        case 1:
            return ["утром", "вечером", "днём", "днем", "ночью", "по ночам", "на ночь", "только утром", "только вечером"]
        case 2:
            return ["утром и вечером", "утро и вечер"]
        case 3:
            return ["утром, днем и вечером", "утром, днём и вечером", "утром днем и вечером", "утро, день, вечер"]
        default:
            return []
        }
    }

    // MARK: - Имя препарата

    private func extractQuotedName(from text: String) -> String? {
        if let name = firstMatch(pattern: "«([^»]+)»", in: text, group: 1) {
            return name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let name = firstMatch(pattern: "\"([^\"]+)\"", in: text, group: 1) {
            return name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    // MARK: - Комментарии

    /// Собираем комментарии из известных паттернов и добавляем нераспознанные части для информативности
    private func extractComment(from text: String) -> String? {
        var comment: String? = nil

        // Избегаем шумных комментариев на слишком коротких строках
        if text.count < 8 {
            return nil
        }

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
        if lower.contains("по необходимости") || lower.contains("по требованию") || lower.contains("при необходимости") {
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

    /// Улучшенное извлечение дозировки с поддержкой чисел без пробелов, дробных значений и текстовых числительных
    private func extractDosage(from text: String) -> String? {
        // Паттерны для дозировки с пробелами, например "5 капл", "2 дозы"
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

        // Распознаём дозировку с дробными значениями и писаной без пробелов: "500мг", "0.5 г", "5мг/кг", "10мл"
        if let dose = extractCompactDosage(from: text) {
            return dose
        }

        // Текстовые числительные плюс единицы, например "по одной таблетке"
        if let (number, unitRaw) = extractTextualDosage(from: text) {
            let unit = normalizeUnit(unitRaw)
            return "\(number) \(unit)"
        }

        return nil
    }

    /// Распознаём дозировки в формате без пробелов, включая дробные числа и составные единицы
    private func extractCompactDosage(from text: String) -> String? {
        // Паттерн для чисел с дробной частью и единицами (пример: 0.5 г, 5мг/кг, 100мл)
        // Комментарий: поддерживаются десятичные числа с точкой или запятой, единицы с возможным слэшем
        let pattern = #"(\d+[.,]?\d*)\s*([а-яёa-z%]+(?:\/[а-яёa-z%]+)?)"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)
        if let match = regex.firstMatch(in: text, range: range),
           match.numberOfRanges >= 3,
           let numberRange = Range(match.range(at: 1), in: text),
           let unitRange = Range(match.range(at: 2), in: text) {
            var numberStr = String(text[numberRange])
            let unitStr = String(text[unitRange])
            // Заменяем запятую на точку для единообразия
            numberStr = numberStr.replacingOccurrences(of: ",", with: ".")
            let unitNormalized = normalizeUnit(unitStr)
            return "\(numberStr) \(unitNormalized)"
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
                let word = String(text[wordRange]).lowercased()
                let unit = String(text[unitRange])
                if let number = textNumberWords[word] {
                    return (number, unit)
                }
            }
        }

        return nil
    }

    // MARK: - Кратность в день

    /// Расширенное извлечение кратности приема с учетом числовых и текстовых числительных, временных фраз и интервалов
    /// Возвращает кортеж (основная кратность, альтернативная кратность)
    /// Если оба варианта найдены одновременно, UI должен спросить пользователя, какой считать основным.
    private func extractTimesPerDayWithAlternative(from text: String) -> (timesPerDay: Int, alternativeTimesPerDay: Int?)? {
        let lower = text.lowercased()

        // Попытка найти timesPerDay из интервала времени "каждые N:00" или "через N:00"
        var intervalTimesPerDay: Int? = nil
        if let regex = try? NSRegularExpression(pattern: #"(каждые|через)\s+(\d{1,2}):00"#, options: .caseInsensitive) {
            let range = NSRange(lower.startIndex..., in: lower)
            if let match = regex.firstMatch(in: lower, range: range),
               match.numberOfRanges >= 3,
               let hourRange = Range(match.range(at: 2), in: lower) {
                let hourStr = String(lower[hourRange])
                if let hours = Int(hourStr), hours > 0 {
                    // Вычисляем timesPerDay = 24 / hours
                    intervalTimesPerDay = max(1, 24 / hours)
                }
            }
        }

        // Попытка найти timesPerDay из явного количества "N раз в день" или текстовых числительных
        var explicitTimesPerDay: Int? = nil
        let explicitPatterns = [
            #"(\d+)\s*раз[аы]?\s*(в\s*день)?"#,
            #"(\d+)\s*р/д"#,
            #"([а-яё]+)\s*раз[аы]?\s*(в\s*день)?"#,
            #"([а-яё]+)\s*р/д"#
        ]

        for pattern in explicitPatterns {
            if let numberString = firstMatch(pattern: pattern, in: lower, group: 1) {
                if let number = Int(numberString) {
                    explicitTimesPerDay = number
                    break
                } else if let numWord = textNumberWords[numberString] {
                    explicitTimesPerDay = numWord
                    break
                }
            }
        }

        // Если оба варианта найдены и отличаются, возвращаем оба
        if let interval = intervalTimesPerDay, let explicit = explicitTimesPerDay {
            if interval != explicit {
                // Возвращаем explicit как основной, interval как альтернативный (или наоборот по логике)
                // Комментарий: UI должен спросить пользователя, какой считать основным.
                return (timesPerDay: explicit, alternativeTimesPerDay: interval)
            } else {
                // Если совпадают, возвращаем одно значение
                return (timesPerDay: explicit, alternativeTimesPerDay: nil)
            }
        }

        // Если найден только интервал
        if let interval = intervalTimesPerDay {
            return (timesPerDay: interval, alternativeTimesPerDay: nil)
        }

        // Если найден только явный
        if let explicit = explicitTimesPerDay {
            return (timesPerDay: explicit, alternativeTimesPerDay: nil)
        }

        // Далее ищем интервалы в часах ("каждые шесть часов" и т.п.)
        if let hoursString = firstMatch(
            pattern: #"(?:каждые|через)\s+(\d+|[а-яё]+)\s*час"#,
            in: lower,
            group: 1
        ) {
            var hours: Int? = nil
            if let num = Int(hoursString) {
                hours = num
            } else if let numWord = textNumberWords[hoursString] {
                hours = numWord
            }
            if let h = hours, h > 0 {
                let interval = max(1, 24 / max(1, h))
                // Проверяем, есть ли явное значение для timesPerDay (оно уже присвоено выше), если нет — возвращаем interval
                if let explicit = explicitTimesPerDay {
                    if interval != explicit {
                        return (timesPerDay: explicit, alternativeTimesPerDay: interval)
                    } else {
                        return (timesPerDay: explicit, alternativeTimesPerDay: nil)
                    }
                }
                return (timesPerDay: interval, alternativeTimesPerDay: nil)
            }
        }

        // Времена дня (утро, вечер и т.п.) - суммируем кратность в зависимости от фраз
        var times = 0
        for (pattern, tpd) in partOfDayPatterns {
            if lower.contains(pattern) {
                times = max(times, tpd)
            }
        }
        if times > 0 {
            if let explicit = explicitTimesPerDay {
                if times != explicit {
                    return (timesPerDay: explicit, alternativeTimesPerDay: times)
                } else {
                    return (timesPerDay: times, alternativeTimesPerDay: nil)
                }
            }
            return (timesPerDay: times, alternativeTimesPerDay: nil)
        }

        // Интервалы по часам (например "каждые 8 час")
        for (pattern, hours) in intervalHourPatterns {
            if lower.contains(pattern) {
                let tpd = max(1, 24 / max(1, hours))
                if let explicit = explicitTimesPerDay {
                    if tpd != explicit {
                        return (timesPerDay: explicit, alternativeTimesPerDay: tpd)
                    } else {
                        return (timesPerDay: tpd, alternativeTimesPerDay: nil)
                    }
                }
                return (timesPerDay: tpd, alternativeTimesPerDay: nil)
            }
        }

        return nil
    }

    // MARK: - Длительность

    /// Улучшенное извлечение длительности включая числовые и текстовые числительные и разные формы
    private func extractDuration(from text: String) -> Int? {
        let lower = text.lowercased()

        // Проверка интервалов приема "через X дней" - интерпретируем как длительность приема
        if let daysInterval = firstMatch(pattern: #"через\s+(\d+|[а-яё]+)\s*дн"#, in: lower, group: 1) {
            var days: Int? = nil
            if let num = Int(daysInterval) {
                days = num
            } else if let numWord = textNumberWords[daysInterval] {
                days = numWord
            }
            if let d = days {
                return d
            }
        }

        // Проверяем диапазон дней "курс: 5-7 дн"
        if let rangeDays = extractDaysRange(from: lower) {
            return rangeDays
        }

        // "на 1 неделю", "на 2 месяца" и подобные формы
        if let afterPreposition = extractDurationAfterPreposition(from: lower) {
            return afterPreposition
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

    /// Извлечение длительности из диапазона дней
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

    /// Извлечение длительности после предлога "на", например "на 1 неделю", "на 2 месяца"
    private func extractDurationAfterPreposition(from text: String) -> Int? {
        // Комментарий: улучшена поддержка длительности с предлогом "на"
        let pattern = #"на\s+(\d+|[а-яё]+)\s*(дн|день|дня|дней|недел|неделя|неделю|недель|мес|месяц|месяца|месяцев)"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)
        if let match = regex.firstMatch(in: text, range: range),
           match.numberOfRanges >= 3,
           let numberRange = Range(match.range(at: 1), in: text),
           let unitRange = Range(match.range(at: 2), in: text) {
            let numberStr = String(text[numberRange])
            let unitStr = String(text[unitRange]).lowercased()
            var number: Int? = nil
            if let n = Int(numberStr) {
                number = n
            } else if let nWord = textNumberWords[numberStr] {
                number = nWord
            }
            guard let num = number else { return nil }

            if unitStr.contains("дн") || unitStr.contains("день") {
                return num
            }
            if unitStr.contains("недел") {
                return num * 7
            }
            if unitStr.contains("мес") {
                return num * 30
            }
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
            pattern: #"(\d+|[а-яё]+)\s*недел[ьияюе]"#,
            in: text,
            group: 1
        ) {
            if let num = Int(numberString) {
                return num
            } else if let numWord = textNumberWords[numberString] {
                return numWord
            }
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
            pattern: #"(\d+|[а-яё]+)\s*месяц[аеов]?"#,
            in: text,
            group: 1
        ) {
            if let num = Int(numberString) {
                return num
            } else if let numWord = textNumberWords[numberString] {
                return numWord
            }
        }

        return nil
    }

    private func extractDays(from text: String) -> Int? {
        if let numberString = firstMatch(
            pattern: #"(\d+|[а-яё]+)\s*дн(?:я|ей|ень)?"#,
            in: text,
            group: 1
        ) {
            if let num = Int(numberString) {
                return num
            } else if let numWord = textNumberWords[numberString] {
                return numWord
            }
        }
        return nil
    }

    /// Извлекает исходную текстовую часть длительности для удаления из названия
    private func extractDurationRaw(from text: String) -> String? {
        // Попытка найти выражения "на X дней", "через X дней", "X дней", "X недель", "X месяцев"
        let patterns = [
            #"на\s+\d+\s*(дн|день|дня|дней|недел|неделя|неделю|недель|мес|месяц|месяца|месяцев)"#,
            #"через\s+\d+\s*дн"#,
            #"(\d+)\s*дн(?:я|ей|ень)?"#,
            #"(\d+)\s*недел[ьияюе]"#,
            #"(\d+)\s*месяц[аеов]?"#
        ]

        for pattern in patterns {
            if let fullMatch = firstMatch(pattern: pattern, in: text, group: 0) {
                return fullMatch
            }
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

// /// Модель одного назначенного лекарства
// struct MedicationItem: Identifiable {
//     let id: UUID
//     let name: String
//     let dosage: String
//     let timesPerDay: Int
//     /// Опциональная альтернативная кратность приема, если в тексте найдены два варианта кратности (например, интервал и явное количество раз в день).
//     /// UI должен спросить пользователя, какую кратность считать основной.
//     let alternativeTimesPerDay: Int?
//     let durationInDays: Int
//     let comment: String?
// }

