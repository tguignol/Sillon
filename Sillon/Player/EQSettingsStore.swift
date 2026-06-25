import Foundation
import SwiftData

/// Accès à l'unique enregistrement `EQSettings` (singleton), créé à la demande.
@MainActor
enum EQSettingsStore {
    static func load(_ context: ModelContext) -> EQSettings {
        let id = EQSettings.singletonID
        if let existing = try? context.fetch(FetchDescriptor<EQSettings>(predicate: #Predicate { $0.id == id })).first {
            return existing
        }
        let created = EQSettings()
        context.insert(created)
        try? context.save()
        return created
    }
}
