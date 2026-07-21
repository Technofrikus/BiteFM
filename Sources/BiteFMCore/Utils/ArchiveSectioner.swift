import Foundation

// MARK: - ArchiveSectioner

/// Deep module for archive sectioning logic.
///
/// Owns two entry points — `sectionByLetter(_:)` and `sectionByDay(_:)` — each with its own
/// memo-cache (signature comparison). Both views (`ArchiveView`, `ArchiveNew`) share a single
/// instance via `@State` and call into it during `body`; the module compares signatures internally
/// and only recomputes when the underlying data actually changes.
///
/// Static helpers (`indexLetter`, `newArchiveDaySectionHeader`, `archiveLetterSectionLabel`) are
/// also consolidated here, replacing the old `ArchiveSectionHelpers` enum.
@MainActor
final class ArchiveSectioner {

    // MARK: - Letter sections (by show title, for ArchiveView)

    private var letterSectionsCache: (signature: LetterSignature, sections: [(letter: String, shows: [Show])])?

    struct LetterSignature: Equatable {
        struct Row: Equatable {
            let id: Int
            let title: String
        }
        let rows: [Row]

        init(_ shows: [Show]) {
            self.rows = shows.map { Row(id: $0.id, title: $0.titel) }
        }
    }

    func sectionByLetter(_ shows: [Show]) -> [(letter: String, shows: [Show])] {
        let signature = LetterSignature(shows)
        if letterSectionsCache?.signature != signature {
            letterSectionsCache = (signature, computeLetterSections(from: shows))
        }
        return letterSectionsCache!.sections
    }

    private func computeLetterSections(from shows: [Show]) -> [(letter: String, shows: [Show])] {
        let grouped = Dictionary(grouping: shows) { Self.indexLetter(forShowTitle: $0.titel) }
        let de = Locale(identifier: "de_DE")
        let keys = grouped.keys.sorted { lhs, rhs in
            let pL = letterSortRank(lhs)
            let pR = letterSortRank(rhs)
            if pL != pR { return pL < pR }
            return lhs.compare(rhs, options: [.caseInsensitive], range: nil, locale: de) == .orderedAscending
        }
        return keys.map { letter in
            let list = (grouped[letter] ?? []).sorted {
                $0.titel.localizedCaseInsensitiveCompare($1.titel) == .orderedAscending
            }
            return (letter, list)
        }
    }

    private func letterSortRank(_ key: String) -> Int {
        key == "#" ? 0 : 1
    }

    // MARK: - Day sections (by broadcast date, for ArchiveNew)

    private var daySectionsCache: (signature: DaySignature, sections: [(dayStart: Date, header: String, items: [StoredArchiveItem])])?

    struct DaySignature: Equatable {
        struct Row: Equatable {
            let terminID: Int
            let startTime: String
            let day: TimeInterval
        }
        let rows: [Row]

        init(_ items: [StoredArchiveItem]) {
            let cal = Calendar.current
            self.rows = items.map {
                Row(terminID: $0.terminID, startTime: $0.startTime, day: cal.startOfDay(for: $0.broadcastDate).timeIntervalSince1970)
            }
        }
    }

    func sectionByDay(_ items: [StoredArchiveItem]) -> [(dayStart: Date, header: String, items: [StoredArchiveItem])] {
        let signature = DaySignature(items)
        if daySectionsCache?.signature != signature {
            daySectionsCache = (signature, computeDaySections(from: items))
        }
        return daySectionsCache!.sections
    }

    private func computeDaySections(from items: [StoredArchiveItem]) -> [(dayStart: Date, header: String, items: [StoredArchiveItem])] {
        let cal = Calendar.current
        let byDay = Dictionary(grouping: items) { cal.startOfDay(for: $0.broadcastDate) }
        let days = byDay.keys.sorted(by: >)
        return days.map { day in
            let rowItems = (byDay[day] ?? []).sorted { lhs, rhs in
                if lhs.startTime != rhs.startTime {
                    return lhs.startTime > rhs.startTime
                }
                return lhs.terminID > rhs.terminID
            }
            let header = Self.newArchiveDaySectionHeader(for: day)
            return (dayStart: day, header: header, items: rowItems)
        }
    }
}

// MARK: - Static helpers (folded in from ArchiveSectionHelpers)

extension ArchiveSectioner {

    /// Abschnittstitel für „Neu im Archiv": Heute/Gestern/Vorgestern + Datum, sonst Wochentag + Datum.
    static func newArchiveDaySectionHeader(for dayStart: Date) -> String {
        let cal = Calendar.current
        let day = cal.startOfDay(for: dayStart)

        let mediumDate: String = {
            let df = DateFormatter()
            df.locale = Locale(identifier: "de_DE")
            df.dateStyle = .medium
            df.timeStyle = .none
            return df.string(from: day)
        }()

        if cal.isDateInToday(day) {
            return "Heute, \(mediumDate)"
        }
        if cal.isDateInYesterday(day) {
            return "Gestern, \(mediumDate)"
        }
        if let vorgestern = cal.date(byAdding: .day, value: -2, to: cal.startOfDay(for: Date())),
           cal.isDate(day, inSameDayAs: vorgestern) {
            return "Vorgestern, \(mediumDate)"
        }

        let df = DateFormatter()
        df.locale = Locale(identifier: "de_DE")
        df.dateFormat = "EEEE, d. MMMM yyyy"
        return df.string(from: day)
    }

    /// Gruppierung für das Sendungs-Archiv: Ziffern und Nicht-Buchstaben → „#", sonst erster Buchstabe (de_DE).
    static func indexLetter(forShowTitle title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "#" }
        let s = String(first).uppercased(with: Locale(identifier: "de_DE"))
        guard let ch = s.first,
              let scalar = ch.unicodeScalars.first else { return "#" }
        if CharacterSet.decimalDigits.contains(scalar) {
            return "#"
        }
        if CharacterSet.letters.contains(scalar) {
            return String(ch)
        }
        return "#"
    }

    /// Kurze Anzeige für Abschnitts-Header und Index (nur das Sektionskürzel).
    static func archiveLetterSectionLabel(_ sectionID: String) -> String {
        sectionID
    }
}