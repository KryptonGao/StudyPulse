import Foundation

extension Notification.Name {
    static let mistakePatternStateDidChange = Notification.Name("mistakePatternStateDidChange")
}

@MainActor
final class MistakePatternResolutionStore {
    static let shared = MistakePatternResolutionStore()

    private let defaults: UserDefaults
    private let key = "mistakePattern.userStates.v1"
    private(set) var states: [UUID: MistakePatternUserState]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let encoded = try? JSONDecoder().decode([String: MistakePatternUserState].self, from: data) {
            self.states = Dictionary(encoded.compactMap { key, value in
                guard let id = UUID(uuidString: key) else { return nil }
                return (id, value)
            }, uniquingKeysWith: { first, _ in first })
        } else {
            self.states = [:]
        }
    }

    func set(_ state: MistakePatternUserState, for mistakeID: UUID) {
        states[mistakeID] = state
        save()
        NotificationCenter.default.post(name: .mistakePatternStateDidChange, object: mistakeID)
    }

    func clear(for mistakeID: UUID) {
        states.removeValue(forKey: mistakeID)
        save()
        NotificationCenter.default.post(name: .mistakePatternStateDidChange, object: mistakeID)
    }

    private func save() {
        let encoded = Dictionary(states.map { ($0.key.uuidString, $0.value) }, uniquingKeysWith: { first, _ in first })
        defaults.set(try? JSONEncoder().encode(encoded), forKey: key)
    }
}
