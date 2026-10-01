import Foundation
import Security

/// A place the desk keeps the fixture secret. The desk names one account, the identity's
/// identifier, under one service. Implementations delete only that record.
public protocol SecretStore: Sendable {
    func write(_ data: Data, account: String) throws(TrustDeskError)
    func read(account: String) throws(TrustDeskError) -> Data?
    func remove(account: String) throws(TrustDeskError)
}

/// The in-memory store tests and the unavailable path use. It is not the keychain.
public final class MemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var records: [String: Data] = [:]

    public init() {}

    public func write(_ data: Data, account: String) throws(TrustDeskError) {
        lock.lock()
        defer { lock.unlock() }
        records[account] = data
    }

    public func read(account: String) throws(TrustDeskError) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return records[account]
    }

    public func remove(account: String) throws(TrustDeskError) {
        lock.lock()
        defer { lock.unlock() }
        records[account] = nil
    }
}

/// A store that always refuses. Opening the sealed record then writes nothing.
public struct UnavailableSecretStore: SecretStore {
    public var reason: String

    public init(reason: String = "The keychain is not available.") {
        self.reason = reason
    }

    public func write(_ data: Data, account: String) throws(TrustDeskError) {
        throw .secretStoreUnavailable(reason)
    }

    public func read(account: String) throws(TrustDeskError) -> Data? {
        throw .secretStoreUnavailable(reason)
    }

    public func remove(account: String) throws(TrustDeskError) {
        throw .secretStoreUnavailable(reason)
    }
}

/// The fixture secret, stored as a generic password in this app's keychain.
///
/// The record is this service and this account only: it is not synchronizable, and its
/// accessibility is "when unlocked, this device only". A passkey is never stored here.
public struct KeychainSecretStore: SecretStore {
    public let service: String

    public init(service: String = TrustDeskFixture.keychainService) {
        self.service = service
    }

    public func write(_ data: Data, account: String) throws(TrustDeskError) {
        try remove(account: account)
        var protected = attributes(account: account, dataProtection: true)
        protected[kSecValueData] = data
        protected[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        protected[kSecAttrLabel] = "Trust Desk fixture secret"
        let status = SecItemAdd(protected as CFDictionary, nil)
        // A process without a keychain access group cannot use the data-protection keychain
        // (errSecMissingEntitlement, -34018). The sandboxed app can. The fallback is still one
        // service and one account, and it is not synchronizable.
        if status == errSecMissingEntitlement {
            var legacy = attributes(account: account, dataProtection: false)
            legacy[kSecValueData] = data
            legacy[kSecAttrLabel] = "Trust Desk fixture secret"
            try check(SecItemAdd(legacy as CFDictionary, nil))
            return
        }
        try check(status)
    }

    public func read(account: String) throws(TrustDeskError) -> Data? {
        if let data = try copy(account: account, dataProtection: true) { return data }
        return try copy(account: account, dataProtection: false)
    }

    public func remove(account: String) throws(TrustDeskError) {
        let protected = SecItemDelete(attributes(account: account, dataProtection: true) as CFDictionary)
        if protected == errSecSuccess { return }
        if protected != errSecMissingEntitlement && protected != errSecItemNotFound {
            try check(protected)
        }
        try check(SecItemDelete(attributes(account: account, dataProtection: false) as CFDictionary), allowing: [errSecItemNotFound])
    }

    private func copy(account: String, dataProtection: Bool) throws(TrustDeskError) -> Data? {
        var query = attributes(account: account, dataProtection: dataProtection)
        query[kSecReturnData] = kCFBooleanTrue as Any
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound || status == errSecMissingEntitlement { return nil }
        try check(status)
        return result as? Data
    }

    private func attributes(account: String, dataProtection: Bool) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: kCFBooleanFalse as Any,
        ]
        if dataProtection {
            query[kSecUseDataProtectionKeychain] = kCFBooleanTrue as Any
        }
        return query
    }

    private func check(_ status: OSStatus, allowing allowed: [OSStatus] = []) throws(TrustDeskError) {
        if status == errSecSuccess || allowed.contains(status) { return }
        throw .secretStoreUnavailable("OSStatus \(status)")
    }
}
