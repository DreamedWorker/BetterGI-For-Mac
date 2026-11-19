//
//  UserPreference.swift
//  BetterGI
//
//  Created by 鸢汐 on 2026/11/20.
//

import Foundation

struct AppPreferences {
    @Preference("isAppFirstOpen", defaultValue: true)
    static var isAppFirstOpen: Bool
}

@propertyWrapper
struct Preference<Value: Codable & Sendable> {

    private let key: String
    private let defaultValue: Value
    private let defaults: UserDefaults

    init(
        _ key: String,
        defaultValue: Value,
        defaults: UserDefaults = .standard
    ) {
        self.key = key
        self.defaultValue = defaultValue
        self.defaults = defaults
    }

    var wrappedValue: Value {
        get {
            guard let data = defaults.data(forKey: key),
                  let value = try? JSONDecoder().decode(
                    Value.self,
                    from: data
                  ) else {
                return defaultValue
            }

            return value
        }

        nonmutating set {
            guard let data = try? JSONEncoder().encode(newValue) else {
                return
            }

            defaults.set(data, forKey: key)
        }
    }
}

extension Preference {
    func reset() {
        defaults.removeObject(forKey: key)
    }
}
