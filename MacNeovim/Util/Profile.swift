import Foundation

struct Profile: Codable, Hashable, Sendable {
    let name: String
    var displayName: String

    static let `default` = Profile(name: "nvim", displayName: "Default")

    func hash(into hasher: inout Hasher) { hasher.combine(name) }
    static func == (lhs: Profile, rhs: Profile) -> Bool { lhs.name == rhs.name }
}
