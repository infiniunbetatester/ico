import Foundation
import AppKit

public struct GitHubReleaseAsset: Decodable, Sendable {
    public let name: String
    public let browserDownloadUrl: String
    
    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
    }
}

public struct GitHubRelease: Decodable, Sendable {
    public let tagName: String
    public let htmlUrl: String
    public let body: String?
    public let assets: [GitHubReleaseAsset]?
    
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
        case body
        case assets
    }
}

@MainActor
public final class UpdateChecker {
    public static let shared = UpdateChecker()
    
    // GitHub repository: "owner/repo" (e.g. "user/ico")
    public var repoSlug: String = "infiniunbetatester/ico"
    public var availableUpdateUrl: URL?
    public var availableDownloadUrl: URL?
    public var latestVersionString: String?
    public var hasAvailableUpdate: Bool = false
    public var onUpdateFound: ((String, URL) -> Void)?
    
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
                    
                    let dmgAsset = release.assets?.first(where: { $0.name.hasSuffix(".dmg") })
                    let directDownload = dmgAsset.flatMap { URL(string: $0.browserDownloadUrl) }
                    self.availableDownloadUrl = directDownload ?? self.availableUpdateUrl
                    self.hasAvailableUpdate = true
                    
                    IslandState.shared.showToast("Доступно \(release.tagName)! Нажмите для скачивания", icon: "arrow.down.circle.fill")
                    
                    if let targetUrl = self.availableDownloadUrl {
                        self.onUpdateFound?(release.tagName, targetUrl)
                    }
                    
                    // Если пользователь нажал проверку вручную и есть новая версия — сразу открываем скачивание DMG в браузере!
                    if notifyIfUpToDate, let downloadUrl = self.availableDownloadUrl {
                        NSWorkspace.shared.open(downloadUrl)
                    }
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
    
    public func openDownloadPage() {
        if let url = availableDownloadUrl ?? availableUpdateUrl ?? URL(string: "https://github.com/\(repoSlug)/releases/latest") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func isVersion(_ v1: String, greaterThan v2: String) -> Bool {
        return v1.compare(v2, options: .numeric) == .orderedDescending
    }
}
