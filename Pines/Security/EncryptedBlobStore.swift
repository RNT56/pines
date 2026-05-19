import CryptoKit
import Foundation

struct EncryptedBlobMetadata: Hashable, Codable, Sendable {
    var id: String
    var contentType: String
    var byteCount: Int
    var sha256: String
    var keyID: String
    var relativePath: String
}

struct EncryptedBlobStore {
    private static let directoryName = "EncryptedBlobs"

    let secureKeyStore: SecureKeyStore
    let fileManager: FileManager

    init(secureKeyStore: SecureKeyStore, fileManager: FileManager = .default) {
        self.secureKeyStore = secureKeyStore
        self.fileManager = fileManager
    }

    func write(_ data: Data, id: String = UUID().uuidString, contentType: String) async throws -> EncryptedBlobMetadata {
        let directory = try encryptedBlobDirectory()
        let key = try await secureKeyStore.dataKey(purpose: .encryptedBlob, keyID: SecureKeyStore.blobKeyID)
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else {
            throw EncryptedBlobStoreError.sealFailed
        }
        let fileName = "\(id).blob"
        let url = directory.appending(path: fileName)
        try combined.write(to: url, options: [.atomic, .completeFileProtection])
        try excludeFromBackup(url)
        return EncryptedBlobMetadata(
            id: id,
            contentType: contentType,
            byteCount: data.count,
            sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            keyID: SecureKeyStore.blobKeyID,
            relativePath: fileName
        )
    }

    func read(_ metadata: EncryptedBlobMetadata) async throws -> Data {
        let url = try encryptedBlobDirectory().appending(path: metadata.relativePath)
        let combined = try Data(contentsOf: url)
        let box = try AES.GCM.SealedBox(combined: combined)
        let key = try await secureKeyStore.dataKey(purpose: .encryptedBlob, keyID: metadata.keyID)
        let data = try AES.GCM.open(box, using: key)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == metadata.sha256 else {
            throw EncryptedBlobStoreError.checksumMismatch
        }
        return data
    }

    func delete(_ metadata: EncryptedBlobMetadata) throws {
        let url = try fileURL(for: metadata)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    func fileURL(for metadata: EncryptedBlobMetadata) throws -> URL {
        try encryptedBlobDirectory().appending(path: metadata.relativePath)
    }

    private func encryptedBlobDirectory() throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base
            .appending(path: "Pines", directoryHint: .isDirectory)
            .appending(path: Self.directoryName, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try excludeFromBackup(directory)
        try fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
        return directory
    }

    private func excludeFromBackup(_ url: URL) throws {
        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutableURL.setResourceValues(values)
    }
}

enum EncryptedBlobStoreError: Error, LocalizedError {
    case sealFailed
    case checksumMismatch

    var errorDescription: String? {
        switch self {
        case .sealFailed:
            "Encrypted blob could not be sealed."
        case .checksumMismatch:
            "Encrypted blob checksum verification failed."
        }
    }
}
