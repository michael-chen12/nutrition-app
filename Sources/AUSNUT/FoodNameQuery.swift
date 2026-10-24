/// The words of a food search, and the one rule for whether a food's name matches them: every query word begins a
/// word of the name, ignoring case and accents, and a plural matches its singular ("curries" finds "Curry").
///
/// AUSNUT search finds foods by it, and the backend's food search applies it to both sources' results to rank
/// name matches first (ADR 0006).
public struct FoodNameQuery: Sendable {
    let words: [String]

    public init(_ query: String) {
        self.init(words: Self.words(in: query))
    }

    private init(words: [String]) {
        self.words = words
    }

    /// True when the query has no letters or digits.
    public var isEmpty: Bool { words.isEmpty }

    public func isMatched(byName name: String) -> Bool {
        unmatchedWordCount(inName: Self.words(in: name)) != nil
    }

    /// How many of the name's words no query word matches, or nil when the name lacks a query word.
    func unmatchedWordCount(inName nameWords: [String]) -> Int? {
        guard words.allSatisfy({ queryWord in nameWords.contains { Self.word($0, matches: queryWord) } })
        else { return nil }
        return nameWords.filter { nameWord in !words.contains { Self.word(nameWord, matches: $0) } }.count
    }

    /// The query with each one of its words left out in turn; none for a query of one word.
    var withOneWordLeftOut: [FoodNameQuery] {
        guard words.count > 1 else { return [] }
        return words.indices.map { left in
            FoodNameQuery(words: words.indices.filter { $0 != left }.map { words[$0] })
        }
    }

    static func words(in text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    private static func word(_ nameWord: String, matches queryWord: String) -> Bool {
        singularForms(of: queryWord).contains { nameWord.hasPrefix($0) }
    }

    /// The word and, for an English plural, its possible singulars: "curries" → "curry", "potatoes" → "potato",
    /// "dumplings" → "dumpling".
    private static func singularForms(of word: String) -> [String] {
        guard word.count > 2, word.hasSuffix("s") else { return [word] }
        var forms = [word, String(word.dropLast())]
        if word.hasSuffix("es") { forms.append(String(word.dropLast(2))) }
        if word.hasSuffix("ies") { forms.append(word.dropLast(3) + "y") }
        return forms
    }
}
