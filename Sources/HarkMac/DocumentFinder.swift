import CoreServices
import Foundation
import HarkCore

/// Finds files through Spotlight by name, kind and when they were last used. It reads the index, never a file.
enum DocumentFinder {
    static func find(_ query: DocumentQuery, limit: Int = 8) -> [URL] {
        guard let search = MDQueryCreate(nil, query.spotlight as CFString, nil, nil) else { return [] }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        MDQuerySetSearchScope(search, [home] as CFArray, 0)
        MDQuerySetMaxCount(search, 60)
        guard MDQueryExecute(search, CFOptionFlags(kMDQuerySynchronous.rawValue)) else { return [] }
        var found: [(url: URL, used: Date)] = []
        for index in 0..<MDQueryGetResultCount(search) {
            guard let raw = MDQueryGetResultAtIndex(search, index) else { continue }
            let item = Unmanaged<MDItem>.fromOpaque(raw).takeUnretainedValue()
            guard let path = MDItemCopyAttribute(item, kMDItemPath) as? String, !path.contains("/Library/"),
                  !path.contains("/.") else { continue }
            let used = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date ?? .distantPast
            found.append((URL(fileURLWithPath: path), used))
        }
        return found.sorted { $0.used > $1.used }.prefix(limit).map(\.url)
    }
}
