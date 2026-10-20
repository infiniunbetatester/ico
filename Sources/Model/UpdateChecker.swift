import Foundation
import AppKit

public struct GitHubRelease: Decodable, Sendable {
    public let tagName: String
    public let htmlUrl: String
    public let body: String?
    
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
        case body
    }
}

@MainActor
public final class UpdateChecker {
    public static let shared = UpdateChecker()
    
    // GitHub repository: "owner/repo" (e.g. "user/ico")
    public var repoSlug: String = "infiniunbetatester/ico"
    public var availableUpdateUrl: URL?
    public var latestVersionString: String?
    
    public var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    
    public init() {}
    
    public func checkForUpdates(notifyIfUpToDate: Bool = false) {
        guard !repoSlug.isEmpty else { return }
        guard let url = URL(string: "https://api.github.com/repos/\(repoSlug)/releases/latest") else { return }
        
        Task {
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            request.setValue("ICO-UpdateChecker", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 8
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    if notifyIfUpToDate {
                        IslandState.shared.showToast("Релизов пока нет", icon: "sparkles")
                    }
                    return
                }
                
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                let latestVer = release.tagName.replacingOccurrences(of: "v", with: "").trimmingCharacters(in: .whitespaces)
                let currentVer = self.currentVersion.replacingOccurrences(of: "v", with: "").trimmingCharacters(in: .whitespaces)
                
                if self.isVersion(latestVer, greaterThan: currentVer) {
                    self.latestVersionString = release.tagName
                    self.availableUpdateUrl = URL(string: release.htmlUrl)
                    
                    IslandState.shared.showToast("Доступно ICO \(release.tagName)!", icon: "arrow.down.circle.fill")
                } else if notifyIfUpToDate {
                    IslandState.shared.showToast("У вас последняя версия ICO", icon: "checkmark.circle.fill")
                }
            } catch {
                if notifyIfUpToDate {
                    IslandState.shared.showToast("Ошибка проверки обновления", icon: "exclamationmark.triangle")
                }
            }
        }
    }
    
    public func openReleasePage() {
        if let url = availableUpdateUrl ?? URL(string: "https://github.com/\(repoSlug)/releases") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func isVersion(_ v1: String, greaterThan v2: String) -> Bool {
        return v1.compare(v2, options: .numeric) == .orderedDescending
    }
}
