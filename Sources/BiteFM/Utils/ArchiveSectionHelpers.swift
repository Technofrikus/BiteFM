import Foundation

enum ArchiveSectionHelpers {
    
    /// Abschnittstitel für „Neu im Archiv“: Heute/Gestern/Vorgestern + Datum, sonst Wochentag + Datum.
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
    
    /// Gruppierung für das Sendungs-Archiv: Ziffern und Nicht-Buchstaben → „#“, sonst erster Buchstabe (de_DE).
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
