import Foundation

/// Semantic version (`major.minor.patch`) supporting optional `"v"` prefix.
public struct AppVersion: Comparable, Equatable, Hashable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = max(0, major)
        self.minor = max(0, minor)
        self.patch = max(0, patch)
    }

    public init?(parsing raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrefix = trimmed.hasPrefix("v") || trimmed.hasPrefix("V")
            ? String(trimmed.dropFirst())
            : trimmed
        let core = withoutPrefix.split(separator: "-", maxSplits: 1).first.map(String.init) ?? withoutPrefix
        let parts = core.split(separator: ".").compactMap { Int($0) }
        guard !parts.isEmpty, parts.count <= 3 else { return nil }
        self.major = parts[0]
        self.minor = parts.count > 1 ? parts[1] : 0
        self.patch = parts.count > 2 ? parts[2] : 0
    }

    public var description: String {
        "\(major).\(minor).\(patch)"
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

public struct AppReleaseInfo: Sendable, Equatable {
    public let tagName: String
    public let version: AppVersion
    public let title: String
    public let notes: String
    public let htmlURL: URL
    public let zipAssetURL: URL?
    public let publishedAt: String?

    public init(
        tagName: String,
        version: AppVersion,
        title: String,
        notes: String,
        htmlURL: URL,
        zipAssetURL: URL?,
        publishedAt: String?
    ) {
        self.tagName = tagName
        self.version = version
        self.title = title
        self.notes = notes
        self.htmlURL = htmlURL
        self.zipAssetURL = zipAssetURL
        self.publishedAt = publishedAt
    }
}

public enum UpdateCheckResult: Sendable, Equatable {
    case upToDate(current: AppVersion, latest: AppVersion)
    case updateAvailable(current: AppVersion, release: AppReleaseInfo)
    case noReleasesPublished(current: AppVersion)
    case failed(String)
}

public enum AppUpdateError: LocalizedError, Sendable {
    case missingDownloadAsset
    case invalidArchive
    case nonBundleInstallTarget
    case directoryNotWritable(String)

    public var errorDescription: String? {
        switch self {
        case .missingDownloadAsset:
            return "This release has no macOS .zip bundle attached."
        case .invalidArchive:
            return "Downloaded update archive did not contain a valid XYNTH-1.app bundle."
        case .nonBundleInstallTarget:
            return "Auto-install requires running from XYNTH-1.app; opening GitHub release instead."
        case .directoryNotWritable(let path):
            return "Cannot write update into \(path). Move XYNTH-1.app to /Applications or download manually."
        }
    }
}

/// Zero-dependency GitHub Releases auto-update client & atomic macOS bundle swapper.
public enum AppUpdateService {
    public static let defaultRepo = "mj0lken/xynth-1"
    public static let fallbackVersionString = "0.2.1"

    public static var repoURL: URL {
        URL(string: "https://github.com/\(defaultRepo)")!
    }

    public static var landingPageURL: URL {
        URL(string: "https://mj0lken.github.io/xynth-1/")!
    }

    public static var releasesURL: URL {
        URL(string: "https://github.com/\(defaultRepo)/releases")!
    }

    public static var currentAppVersion: AppVersion {
        let raw = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? fallbackVersionString
        return AppVersion(parsing: raw) ?? AppVersion(major: 0, minor: 2, patch: 0)
    }

    /// Parses GitHub's `/releases/latest` JSON payload into `AppReleaseInfo`.
    public static func parseGitHubReleaseJSON(_ data: Data) -> AppReleaseInfo? {
        struct AssetPayload: Decodable {
            let name: String
            let browser_download_url: String
        }
        struct ReleasePayload: Decodable {
            let tag_name: String
            let name: String?
            let body: String?
            let html_url: String
            let published_at: String?
            let assets: [AssetPayload]?
        }

        guard let payload = try? JSONDecoder().decode(ReleasePayload.self, from: data),
              let version = AppVersion(parsing: payload.tag_name),
              let htmlURL = URL(string: payload.html_url) else {
            return nil
        }

        let assets = payload.assets ?? []
        let preferredAsset = assets.first(where: {
            let lower = $0.name.lowercased()
            return lower.hasSuffix(".zip") && (lower.contains("arm64") || lower.contains("xynth") || lower.contains("macos"))
        }) ?? assets.first(where: { $0.name.lowercased().hasSuffix(".zip") })

        let zipURL = preferredAsset.flatMap { URL(string: $0.browser_download_url) }
        return AppReleaseInfo(
            tagName: payload.tag_name,
            version: version,
            title: (payload.name?.isEmpty == false ? payload.name! : payload.tag_name),
            notes: (payload.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            htmlURL: htmlURL,
            zipAssetURL: zipURL,
            publishedAt: payload.published_at
        )
    }

    public static func checkLatestRelease(
        repo: String = defaultRepo,
        currentVersion: AppVersion = currentAppVersion
    ) async -> UpdateCheckResult {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            return .failed("Invalid update repository URL.")
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("XYNTH-1/\(currentVersion.description)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 404 {
                    return .noReleasesPublished(current: currentVersion)
                }
                guard (200...299).contains(http.statusCode) else {
                    return .failed("GitHub API returned HTTP \(http.statusCode).")
                }
            }
            guard let release = parseGitHubReleaseJSON(data) else {
                return .failed("Could not parse latest release metadata.")
            }
            if release.version > currentVersion {
                return .updateAvailable(current: currentVersion, release: release)
            } else {
                return .upToDate(current: currentVersion, latest: release.version)
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Downloads the release `.zip`, extracts `XYNTH-1.app`, verifies executable presence,
    /// and stages an atomic post-exit swap + relaunch script.
    public static func downloadAndStageInstall(
        release: AppReleaseInfo,
        currentBundleURL: URL = Bundle.main.bundleURL
    ) async throws -> URL {
        guard currentBundleURL.pathExtension.lowercased() == "app" else {
            throw AppUpdateError.nonBundleInstallTarget
        }
        guard let zipURL = release.zipAssetURL else {
            throw AppUpdateError.missingDownloadAsset
        }

        let parentDir = currentBundleURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parentDir.path) else {
            throw AppUpdateError.directoryNotWritable(parentDir.path)
        }

        let (tempZipURL, _) = try await URLSession.shared.download(from: zipURL)
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("xynth1-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-xk", tempZipURL.path, workDir.path]
        try unzip.run()
        unzip.waitUntilExit()
        try? FileManager.default.removeItem(at: tempZipURL)

        guard unzip.terminationStatus == 0 else {
            throw AppUpdateError.invalidArchive
        }

        // Locate extracted .app bundle
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: workDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        guard let newAppURL = contents.first(where: { $0.pathExtension.lowercased() == "app" }),
              FileManager.default.fileExists(atPath: newAppURL.appendingPathComponent("Contents/MacOS/XYNTH-1").path) else {
            throw AppUpdateError.invalidArchive
        }

        return newAppURL
    }

    /// Spawns a detached shell helper that waits for this process to terminate, swaps in `stagedAppURL`,
    /// and relaunches `XYNTH-1.app`.
    public static func launchSwapHelperAndExit(
        stagedAppURL: URL,
        targetAppURL: URL = Bundle.main.bundleURL
    ) throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        #!/bin/sh
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        rm -rf "$1"
        mv "$2" "$1"
        xattr -dr com.apple.quarantine "$1" 2>/dev/null || true
        open "$1"
        rm -rf "$(dirname "$2")"
        """

        let helperURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("xynth1-swap-\(UUID().uuidString).sh")
        try script.write(to: helperURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperURL.path)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = [helperURL.path, targetAppURL.path, stagedAppURL.path]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try proc.run()
    }
}
