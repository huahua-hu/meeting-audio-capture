import Foundation
import Security

struct XFYunCredentials: Equatable, Sendable {
    let appID: String
    let appKey: String
}

enum XFYunCredentialStoreError: Error, LocalizedError {
    case keychain(OSStatus)
    case invalidEncoding

    var errorDescription: String? {
        switch self {
        case let .keychain(status):
            return SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)."
        case .invalidEncoding:
            return "The stored XFYun credentials are invalid."
        }
    }
}

struct XFYunCredentialStore: Sendable {
    private enum Account {
        static let appID = "xfyun-app-id"
        static let appKey = "xfyun-app-key"
    }

    private let service: String

    init(service: String = "org.meetingaudiocapture.xfyun") {
        self.service = service
    }

    func saveCredentials(_ credentials: XFYunCredentials) throws {
        try save(credentials.appID, account: Account.appID)
        do {
            try save(credentials.appKey, account: Account.appKey)
        } catch {
            try? delete(account: Account.appID)
            throw error
        }
    }

    func readCredentials() throws -> XFYunCredentials? {
        let appID = try read(account: Account.appID)
        let appKey = try read(account: Account.appKey)
        guard let appID, let appKey else { return nil }
        return XFYunCredentials(appID: appID, appKey: appKey)
    }

    func deleteCredentials() throws {
        try delete(account: Account.appID)
        try delete(account: Account.appKey)
    }

    private func save(_ value: String, account: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw XFYunCredentialStoreError.invalidEncoding
        }
        let query = baseQuery(account: account)
        let status = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else {
            throw XFYunCredentialStoreError.keychain(status)
        }
        var addition = query
        addition[kSecValueData as String] = data
        let addStatus = SecItemAdd(addition as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw XFYunCredentialStoreError.keychain(addStatus)
        }
    }

    private func read(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw XFYunCredentialStoreError.keychain(status)
        }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw XFYunCredentialStoreError.invalidEncoding
        }
        return value
    }

    private func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw XFYunCredentialStoreError.keychain(status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
    }
}
