import Foundation

struct VideoTrack: Equatable {
    let id: String
    let title: String

    var thumbnailURL: URL { URL(string: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg")! }

    init?(_ value: Any?) {
        guard let data = value as? [String: Any], let id = data["id"] as? String,
              id.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil else { return nil }
        self.id = id
        title = String((data["title"] as? String ?? "").prefix(512))
    }
}
