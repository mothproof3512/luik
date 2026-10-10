import Foundation

/// Compares the running version with the latest GitHub release of the repository.
enum UpdateCheck {
    struct Release {
        let latest: String
        let url: String
        var isNewer: Bool { UpdateCheck.isVersion(latest, newerThan: AppInfo.version) }
    }

    static var releasesURL: URL {
        URL(string: "https://api.github.com/repos/\(AppInfo.repository)/releases/latest")!
    }

    static var releasesPage: String {
        "https://github.com/\(AppInfo.repository)/releases"
    }

    /// Fetches the latest release; `completion` runs on the main thread.
    static func check(completion: @escaping (Result<Release, Error>) -> Void) {
        var request = URLRequest(url: releasesURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Luik/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, error in
            let outcome: Result<Release, Error>
            if let error {
                outcome = .failure(error)
            } else if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                outcome = .failure(NSError(domain: "Luik", code: 404, userInfo: [NSLocalizedDescriptionKey: "No releases published yet."]))
            } else if let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = json["tag_name"] as? String {
                let url = json["html_url"] as? String ?? releasesPage
                outcome = .success(Release(latest: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, url: url))
            } else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                outcome = .failure(NSError(domain: "Luik", code: code, userInfo: [NSLocalizedDescriptionKey: "Unexpected answer from GitHub (HTTP \(code))."]))
            }
            DispatchQueue.main.async { completion(outcome) }
        }.resume()
    }

    /// Runs the check at launch when enabled and the last check is more than a day old.
    static func checkAtLaunchIfDue() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: SettingsKey.checkForUpdates) else { return }
        let last = defaults.double(forKey: SettingsKey.lastUpdateCheck)
        guard Date().timeIntervalSince1970 - last > 24 * 3600 else { return }
        check { outcome in
            defaults.set(Date().timeIntervalSince1970, forKey: SettingsKey.lastUpdateCheck)
            if case .success(let result) = outcome, result.isNewer {
                UIState.shared.updateAvailable = (result.latest, result.url)
            }
        }
    }

    /// "0.13.0" vs "0.12.1": numeric part-by-part comparison.
    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
