import Foundation
import Observation

@MainActor @Observable final class WorkspaceWorkDraft: Identifiable {
    struct Field: Identifiable {
        let id: String
        let label: String
        var required: Bool = false
        var maximum: Int = 8000
        var multiline: Bool = false
        var options: [WorkspaceWorkItem.Person] = []
    }
    let id: UUID = UUID()
    let title: String
    let audience: String
    let fields: [Field]
    let base: [String: Any]
    let suffix: String
    var values: [String: String]
    var approved: Bool = false
    var isSaving: Bool = false
    var errorText: String?
    var canSave: Bool { approved && !isSaving && fields.allSatisfy { field in let text = values[field.id] ?? ""; return text.utf16.count <= field.maximum && (!field.required || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } }
    init(title: String, audience: String, fields: [Field], values: [String: String] = [:], base: [String: Any], suffix: String = "") {
        self.title = title; self.audience = audience; self.fields = fields; self.values = values; self.base = base; self.suffix = suffix
    }
    func body() -> [String: Any] {
        var value = base
        fields.forEach { value[$0.id] = values[$0.id] ?? "" }
        if let days = values["turnaroundDays"] { value["turnaroundDays"] = Int(days) ?? 0 }
        value["confirm"] = true
        return value
    }
}
