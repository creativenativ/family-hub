import Foundation

enum EmailEventCategory: String, CaseIterable, Identifiable {
    case medical
    case delivery
    case extracurricular
    case appointment
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .medical: "Medical"
        case .delivery: "Delivery"
        case .extracurricular: "Activity"
        case .appointment: "Appointment"
        case .other: "Other"
        }
    }

    var icon: String {
        switch self {
        case .medical: "cross.case.fill"
        case .delivery: "shippingbox.fill"
        case .extracurricular: "figure.run"
        case .appointment: "calendar.badge.clock"
        case .other: "envelope.fill"
        }
    }

    var defaultTitlePrefix: String {
        switch self {
        case .medical: "Appointment"
        case .delivery: "Delivery"
        case .extracurricular: "Activity"
        case .appointment: "Appointment"
        case .other: "From email"
        }
    }
}

struct ParsedEmailEvent: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var location: String
    var notes: String
    var category: EmailEventCategory
    var confidence: Double
    var isSelected: Bool = true

    static func == (lhs: ParsedEmailEvent, rhs: ParsedEmailEvent) -> Bool {
        lhs.id == rhs.id
    }
}

enum EmailEventParser {
    private static let medicalKeywords = [
        "dentist", "dental", "doctor", "physician", "pediatric", "appointment",
        "checkup", "check-up", "clinic", "orthodont", "optometrist", "hospital",
        "physical therapy", "dermatolog", "obgyn", "vaccine", "immunization",
    ]

    private static let deliveryKeywords = [
        "amazon", "delivered", "delivery", "out for delivery", "package",
        "shipment", "shipped", "arriving", "arrives", "fedex", "ups", "usps",
        "tracking", "order is arriving", "expected delivery", "doorstep",
    ]

    private static let activityKeywords = [
        "practice", "game", "recital", "lesson", "rehearsal", "tournament",
        "soccer", "baseball", "basketball", "football", "swim", "dance",
        "music lesson", "piano", "guitar", "club meeting", "field trip",
        "extracurricular", "tryout", "match",
    ]

    private static let appointmentKeywords = [
        "meeting", "reservation", "scheduled", "confirm", "confirmation",
        "booked", "visit", "consultation",
    ]

    static func parse(_ rawText: String, referenceDate: Date = Date()) -> [ParsedEmailEvent] {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > 20 else { return [] }

        let category = detectCategory(in: text)
        let dates = detectDates(in: text, referenceDate: referenceDate)
        let location = detectLocation(in: text)
        let title = makeTitle(from: text, category: category)

        guard !dates.isEmpty else {
            // No date found — offer an all-day placeholder on the selected/reference day
            let start = Calendar.current.startOfDay(for: referenceDate)
            let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
            return [
                ParsedEmailEvent(
                    title: title,
                    startDate: start,
                    endDate: end,
                    isAllDay: true,
                    location: location,
                    notes: trimmedNotes(from: text),
                    category: category,
                    confidence: category == .other ? 0.35 : 0.55
                ),
            ]
        }

        return dates.prefix(5).enumerated().map { index, dateInfo in
            let start = dateInfo.start
            let end = dateInfo.end ?? Calendar.current.date(byAdding: .hour, value: 1, to: start) ?? start
            let eventTitle = dates.count > 1 ? "\(title) (\(index + 1))" : title
            return ParsedEmailEvent(
                title: eventTitle,
                startDate: start,
                endDate: end,
                isAllDay: dateInfo.isAllDay,
                location: location,
                notes: trimmedNotes(from: text),
                category: category,
                confidence: dateInfo.isAllDay ? 0.7 : 0.85
            )
        }
    }

    // MARK: - Detection

    private static func detectCategory(in text: String) -> EmailEventCategory {
        let lower = text.lowercased()
        let scores: [(EmailEventCategory, Int)] = [
            (.medical, keywordHits(lower, medicalKeywords)),
            (.delivery, keywordHits(lower, deliveryKeywords)),
            (.extracurricular, keywordHits(lower, activityKeywords)),
            (.appointment, keywordHits(lower, appointmentKeywords)),
        ]
        let best = scores.max(by: { $0.1 < $1.1 })
        if let best, best.1 > 0 {
            // Prefer medical over generic appointment when both match
            if scores[0].1 > 0 { return .medical }
            return best.0
        }
        return .other
    }

    private static func keywordHits(_ text: String, _ keywords: [String]) -> Int {
        keywords.reduce(0) { $0 + (text.contains($1) ? 1 : 0) }
    }

    private struct DetectedDate {
        let start: Date
        let end: Date?
        let isAllDay: Bool
    }

    private static func detectDates(in text: String, referenceDate: Date) -> [DetectedDate] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return []
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = detector.matches(in: text, options: [], range: range)

        var results: [DetectedDate] = []
        var seenDays = Set<Date>()

        for match in matches {
            guard let date = match.date else { continue }

            // Skip very old dates (likely order history)
            let daysFromNow = Calendar.current.dateComponents([.day], from: referenceDate.startOfDay, to: date.startOfDay).day ?? 0
            if daysFromNow < -14 { continue }
            if daysFromNow > 365 { continue }

            // NSDataDetector often sets time even for date-only; check hour components from match
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            let hour = components.hour ?? 0
            let minute = components.minute ?? 0
            // Midnight often means date-only extraction
            let isAllDay = (hour == 0 && minute == 0 && match.duration == 0) || !hasMeaningfulTime(in: text, around: match)

            let dayKey = date.startOfDay
            if seenDays.contains(dayKey) && isAllDay { continue }
            seenDays.insert(dayKey)

            let end: Date?
            if match.duration > 0 {
                end = date.addingTimeInterval(match.duration)
            } else if isAllDay {
                end = Calendar.current.date(byAdding: .day, value: 1, to: dayKey)
            } else {
                end = Calendar.current.date(byAdding: .hour, value: 1, to: date)
            }

            results.append(DetectedDate(start: isAllDay ? dayKey : date, end: end, isAllDay: isAllDay))
        }

        return results.sorted { $0.start < $1.start }
    }

    private static func looksLikeTimedDate(_ match: NSTextCheckingResult, in text: String) -> Bool {
        guard let range = Range(match.range, in: text) else { return false }
        let snippet = String(text[range]).lowercased()
        return snippet.contains("am") || snippet.contains("pm") || snippet.contains(":")
    }

    private static func hasMeaningfulTime(in text: String, around match: NSTextCheckingResult) -> Bool {
        guard let range = Range(match.range, in: text) else { return false }
        let lower = text.lowercased()
        // Expand window around match
        let start = text.index(range.lowerBound, offsetBy: -20, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: 20, limitedBy: text.endIndex) ?? text.endIndex
        let window = String(lower[start..<end])
        if window.contains("am") || window.contains("pm") { return true }
        if window.range(of: #"\d{1,2}:\d{2}"#, options: .regularExpression) != nil { return true }
        // Delivery emails often say "arriving today by 10 PM"
        if window.contains("by ") && (window.contains("am") || window.contains("pm")) { return true }
        return looksLikeTimedDate(match, in: text)
    }

    private static func detectLocation(in text: String) -> String {
        let patterns = [
            #"(?i)(?:location|address|at|where)\s*[:\-]?\s*([^\n,]{5,60})"#,
            #"(?i)\d{1,5}\s+[A-Za-z0-9.'\- ]+(?:St|Street|Ave|Avenue|Rd|Road|Blvd|Dr|Drive|Way|Ln|Lane)\.?"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               match.numberOfRanges >= 1 {
                let rangeIndex = match.numberOfRanges > 1 ? 1 : 0
                if let swiftRange = Range(match.range(at: rangeIndex), in: text) {
                    let value = String(text[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if value.count >= 4 { return String(value.prefix(80)) }
                }
            }
        }
        return ""
    }

    private static func makeTitle(from text: String, category: EmailEventCategory) -> String {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Prefer subject-like first short line
        if let first = lines.first, first.count <= 80, !first.lowercased().hasPrefix("hi "), !first.lowercased().hasPrefix("hello") {
            return refineTitle(first, category: category)
        }

        let lower = text.lowercased()
        if category == .delivery {
            if lower.contains("amazon") { return "Amazon delivery" }
            if lower.contains("package") { return "Package delivery" }
            return "Delivery"
        }
        if category == .medical {
            if lower.contains("dentist") { return "Dentist appointment" }
            if lower.contains("doctor") || lower.contains("physician") { return "Doctor appointment" }
            return "Medical appointment"
        }
        if category == .extracurricular {
            for keyword in ["soccer", "baseball", "basketball", "swim", "dance", "piano", "practice", "game", "recital"] {
                if lower.contains(keyword) {
                    return keyword.capitalized
                }
            }
            return "Activity"
        }
        return category.defaultTitlePrefix
    }

    private static func refineTitle(_ raw: String, category: EmailEventCategory) -> String {
        var title = raw
            .replacingOccurrences(of: #"^(re:|fw:|fwd:)\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if title.count > 60 {
            title = String(title.prefix(57)) + "…"
        }
        if title.count < 3 {
            return category.defaultTitlePrefix
        }
        return title
    }

    private static func trimmedNotes(from text: String) -> String {
        let collapsed = text
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(collapsed.prefix(500))
    }
}
