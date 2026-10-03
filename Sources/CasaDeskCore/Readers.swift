import Foundation

// Pure, testable pieces of the file readers (Spotlight scope rules, Safari bookmarks, Focus).

public enum Paths {
    /// Is `path` inside `root` after resolving `..` and symlinks? (Blocks ../../ escapes.)
    public static func isInside(_ path: String, root: String) -> Bool {
        let p = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
        let r = URL(fileURLWithPath: root).standardizedFileURL.resolvingSymlinksInPath().path
        return p == r || p.hasPrefix(r.hasSuffix("/") ? r : r + "/")
    }

    /// Places Spotlight results must never come from: secrets, message/mail stores, browser cookies.
    public static func isRefused(_ path: String, home: String) -> Bool {
        let p = path.lowercased(), h = home.lowercased()
        let blocked = ["\(h)/library/keychains", "/library/keychains", "/system/library/keychains",
                       "\(h)/library/messages", "\(h)/library/mail", "\(h)/library/containers/com.apple.mail",
                       "\(h)/library/cookies", "\(h)/library/group containers/group.com.apple.notes"]
        if blocked.contains(where: { p == $0 || p.hasPrefix($0 + "/") }) { return true }
        let name = (p as NSString).lastPathComponent
        return p.contains("/cookies") || name.hasSuffix(".keychain") || name.hasSuffix(".keychain-db") || name == "chat.db"
    }
}

/// Safari's Bookmarks.plist → flat bookmarks and Reading List.
public enum SafariBookmarks {
    public struct Item { public let title: String; public let url: String; public let folder: String; public let added: Date?; public let preview: String? }

    public static func parse(_ root: [String: Any]) -> (bookmarks: [Item], readingList: [Item]) {
        var bookmarks: [Item] = [], reading: [Item] = []
        func walk(_ node: [String: Any], folder: String, inReading: Bool) {
            let type = node["WebBookmarkType"] as? String
            if type == "WebBookmarkTypeLeaf", let url = node["URLString"] as? String {
                let title = (node["URIDictionary"] as? [String: Any])?["title"] as? String ?? url
                let rl = node["ReadingList"] as? [String: Any]
                let item = Item(title: title, url: url, folder: folder, added: rl?["DateAdded"] as? Date, preview: rl?["PreviewText"] as? String)
                if inReading { reading.append(item) } else { bookmarks.append(item) }
                return
            }
            let title = node["Title"] as? String ?? ""
            if title == "History" { return }
            let isReading = inReading || title == "com.apple.ReadingList"
            let name = title == "BookmarksBar" ? "Favorites" : title == "BookmarksMenu" ? "Bookmarks Menu" : title
            let path = folder.isEmpty ? name : (name.isEmpty ? folder : folder + "/" + name)
            for child in node["Children"] as? [[String: Any]] ?? [] { walk(child, folder: isReading ? "Reading List" : path, inReading: isReading) }
        }
        for child in root["Children"] as? [[String: Any]] ?? [] { walk(child, folder: "", inReading: false) }
        return (bookmarks, reading)
    }
}

/// Focus status from ~/Library/DoNotDisturb/DB (Assertions.json + ModeConfigurations.json).
public enum FocusStatus {
    public static func active(assertions: [String: Any], modes: [String: Any]?) -> [String] {
        let records = ((assertions["data"] as? [[String: Any]])?.first?["storeAssertionRecords"] as? [[String: Any]]) ?? []
        let configs = ((modes?["data"] as? [[String: Any]])?.first?["modeConfigurations"] as? [String: Any]) ?? [:]
        return records.compactMap { r in
            guard let id = (r["assertionDetails"] as? [String: Any])?["assertionDetailsModeIdentifier"] as? String else { return nil }
            let name = ((configs[id] as? [String: Any])?["mode"] as? [String: Any])?["name"] as? String
            return name ?? id.components(separatedBy: ".").last ?? id
        }
    }
}
