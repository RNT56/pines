import ActivityKit
import Foundation

struct ModelDownloadActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var status: String
        var bytesReceived: Int64
        var totalBytes: Int64?
        var currentFile: String?
        var errorMessage: String?
        var updatedAt: Date

        var fractionCompleted: Double {
            guard let totalBytes, totalBytes > 0 else { return 0 }
            return min(1, max(0, Double(bytesReceived) / Double(totalBytes)))
        }

        var progressLabel: String {
            let received = ByteCountFormatter.string(fromByteCount: bytesReceived, countStyle: .file)
            guard let totalBytes else { return received }
            let total = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
            return "\(received) of \(total)"
        }
    }

    var repository: String
    var displayName: String
}
