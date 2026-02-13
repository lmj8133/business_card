import Contacts

extension BusinessCard {
    /// Convert to a CNMutableContact for saving to iOS Contacts.
    func toCNContact() -> CNMutableContact {
        let contact = CNMutableContact()

        // Name: try to split into given/family name
        let nameParts = splitName(name)
        contact.givenName = nameParts.given
        contact.familyName = nameParts.family

        if let company {
            contact.organizationName = company
        }

        if let position {
            contact.jobTitle = position
        }

        if let email {
            contact.emailAddresses = [
                CNLabeledValue(label: CNLabelWork, value: email as NSString),
            ]
        }

        // Add a note about the source
        contact.note = "Scanned from business card on \(capturedAt.formatted(date: .abbreviated, time: .shortened))"

        return contact
    }

    /// Best-effort name splitting.
    /// Handles: "John Smith", "MJ Li", "王大明"
    private func splitName(_ fullName: String) -> (given: String, family: String) {
        let trimmed = fullName.trimmingCharacters(in: .whitespaces)

        // If name contains CJK characters, first character is likely the family name
        if trimmed.unicodeScalars.contains(where: { CharacterSet.cjkUnified.contains($0) }) {
            let first = String(trimmed.prefix(1))
            let rest = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
            return (given: rest, family: first)
        }

        // Western name: split by last space
        let parts = trimmed.split(separator: " ", maxSplits: .max, omittingEmptySubsequences: true)
        if parts.count >= 2 {
            let family = String(parts.last!)
            let given = parts.dropLast().joined(separator: " ")
            return (given: given, family: family)
        }

        // Single word — put it in given name
        return (given: trimmed, family: "")
    }
}

// MARK: - CJK Character Set

private extension CharacterSet {
    /// CJK Unified Ideographs (U+4E00–U+9FFF) — covers most Chinese/Japanese/Korean characters.
    static let cjkUnified = CharacterSet(charactersIn: "\u{4E00}"..."\u{9FFF}")
}
