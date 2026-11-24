import CryptoKit
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
    public let sha256: String?
    public let checksumAssetURL: URL?
    public let publishedAt: String?

    public init(
        tagName: String,
        version: AppVersion,
        title: String,
        notes: String,
        htmlURL: URL,
        zipAssetURL: URL?,
        sha256: String? = nil,
        checksumAssetURL: URL? = nil,
        publishedAt: String?
    ) {
        self.tagName = tagName
        self.version = version
        self.title = title
        self.notes = notes
        self.htmlURL = htmlURL
        self.zipAssetURL = zipAssetURL
        self.sha256 = sha256
        self.checksumAssetURL = checksumAssetURL
        self.publishedAt = publishedAt
    }
}

public enum UpdateCheckResult: Sendable, Equatable {
    case upToDate(current: AppVersion, latest: AppVersion)
    case updateAvailable(current: AppVersion, release: AppReleaseInfo)
    case notModified(current: AppVersion)
    case noReleasesPublished(current: AppVersion)
    case failed(String)
}

public enum AppUpdateError: LocalizedError, Sendable {
    case missingDownloadAsset
    case missingChecksum
    case checksumMismatch
    case invalidArchive
    case invalidBundle(String)
    case invalidSignature
    case nonBundleInstallTarget
    case directoryNotWritable(String)

    public var errorDescription: String? {
        switch self {
        case .missingDownloadAsset:
            return "This release has no trusted macOS .zip bundle attached."
        case .missingChecksum:
            return "This release has no SHA-256 checksum to verify the download."
        case .checksumMismatch:
            return "Downloaded update archive did not match its SHA-256 checksum."
        case .invalidArchive:
            return "Downloaded update archive did not contain a valid XYNTH-1.app bundle."
        case .invalidBundle(let reason):
            return reason
        case .invalidSignature:
            return "Downloaded XYNTH-1.app failed code signature verification."
        case .nonBundleInstallTarget:
            return "Auto-install requires running from a writable XYNTH-1.app bundle; opening GitHub release instead."
        case .directoryNotWritable(let path):
            return "Cannot write update into \(path). Move XYNTH-1.app to /Applications or download manually."
        }
    }

    /// Errors where falling back to opening the release page in the browser is helpful
    /// (as opposed to integrity/verification failures, which should stop and report clearly).
    public var shouldOpenReleasePage: Bool {
        switch self {
        case .nonBundleInstallTarget, .directoryNotWritable, .missingDownloadAsset:
            return true
        case .missingChecksum, .checksumMismatch, .invalidArchive, .invalidBundle, .invalidSignature:
            return false
        }
    }
}

/// Zero-dependency GitHub Releases auto-update client & atomic macOS bundle swapper.
public enum AppUpdateService {
    public static let defaultRepo = "mj0lken/xynth-1"
    public static let expectedBundleID = "com.xynth1.hapticsynth"
    public static let fallbackVersionString = "0.2.1"
    public static let checkInterval: TimeInterval = 30 * 60

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

    public static func isDue(lastCheck: Date?, now: Date = Date(), interval: TimeInterval = checkInterval) -> Bool {
        guard let lastCheck, lastCheck <= now else { return true }
        return now.timeIntervalSince(lastCheck) >= interval
    }

    public static func isTrustedPage(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "github.com"
    }

    /// Only downloads from this repository's GitHub Releases path, rejecting `..` path traversal.
    public static func isTrustedDownload(_ url: URL, repo: String = defaultRepo) -> Bool {
        let prefix = "/\(repo)/releases/download/"
        guard url.scheme == "https",
              url.host == "github.com",
              !url.pathComponents.contains(".."),
              url.path.hasPrefix(prefix),
              url.standardized.path.hasPrefix(prefix),
              url.path.count > prefix.count
        else { return false }
        return true
    }

    public static func isValidSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isASCII && $0.isHexDigit }
    }

    /// Validates a GitHub asset digest of the form `"sha256:<64 hex chars>"`.
    public static func parseDigest(_ digest: String?) -> String? {
        guard let digest, digest.hasPrefix("sha256:") else { return nil }
        let hex = String(digest.dropFirst("sha256:".count))
        guard isValidSHA256(hex) else { return nil }
        return hex.lowercased()
    }

    /// Extracts the leading 64-character hex digest from `shasum -a 256` output.
    public static func parseChecksumFile(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.split(whereSeparator: \.isWhitespace).first else { return nil }
        let hex = String(first)
        guard isValidSHA256(hex) else { return nil }
        return hex.lowercased()
    }

    /// Any writable, non-translocated `.app` bundle with the expected bundle ID can self-update.
    public static func canSelfUpdate(
        bundlePath: String,
        bundleIdentifier: String?,
        expectedBundleID: String = expectedBundleID,
        isParentWritable: Bool,
        isBundleWritable: Bool
    ) -> Bool {
        guard bundlePath.hasSuffix(".app"),
              bundleIdentifier == expectedBundleID,
              !bundlePath.contains("/AppTranslocation/"),
              isParentWritable,
              isBundleWritable
        else { return false }
        return true
    }

    /// Streams a file in 1 MiB chunks through CryptoKit SHA-256 and returns the lowercase hex digest.
    public static func sha256(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        let chunkSize = 1024 * 1024
        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Detached swap-and-relaunch script: ignores HUP, waits up to 30s for PID exit, swaps with
    /// guarded rollback on failure, relaunches, and cleans up the staging directory.
    public static func installScript() -> String {
        """
        #!/usr/bin/env bash
        set -euo pipefail
        trap '' HUP

        PID="$1"
        NEW_APP="$2"
        TARGET_APP="${3%/}"
        WORK_DIR="$(cd "$(dirname "$0")" && pwd)"
        BACKUP="${TARGET_APP}.backup-$$"

        # Wait up to 30 seconds for XYNTH-1 to exit cleanly.
        for _ in $(seq 1 300); do
          kill -0 "$PID" 2>/dev/null || break
          sleep 0.1
        done

        # Don't swap under a live process.
        if kill -0 "$PID" 2>/dev/null; then
          rm -rf "$WORK_DIR"
          exit 1
        fi

        rollback() {
          if [[ -e "$BACKUP" ]]; then
            rm -rf "$TARGET_APP"
            mv "$BACKUP" "$TARGET_APP" || true
          fi
          rm -rf "$WORK_DIR"
        }
        trap rollback ERR

        if [[ -e "$TARGET_APP" ]]; then
          mv "$TARGET_APP" "$BACKUP"
        fi
        /usr/bin/ditto "$NEW_APP" "$TARGET_APP"
        rm -rf "$BACKUP"
        /usr/bin/open "$TARGET_APP"
        rm -rf "$WORK_DIR"
        """
    }

    /// Parses GitHub's `/releases/latest` JSON payload into `AppReleaseInfo`.
    public static func parseGitHubReleaseJSON(_ data: Data, repo: String = defaultRepo) -> AppReleaseInfo? {
        struct AssetPayload: Decodable {
            let name: String
            let browser_download_url: String
            let digest: String?
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
              let htmlURL = URL(string: payload.html_url),
              isTrustedPage(htmlURL) else {
            return nil
        }

        let assets = payload.assets ?? []
        let trustedZips = assets.filter { asset in
            let lower = asset.name.lowercased()
            guard lower.hasSuffix(".zip"),
                  let url = URL(string: asset.browser_download_url),
                  isTrustedDownload(url, repo: repo)
            else { return false }
            return true
        }
        let preferredAsset = trustedZips.first(where: {
            let lower = $0.name.lowercased()
            return lower.contains("arm64") || lower.contains("xynth") || lower.contains("macos")
        }) ?? trustedZips.first

        let zipURL = preferredAsset.flatMap { URL(string: $0.browser_download_url) }
        let sha256 = preferredAsset.flatMap { parseDigest($0.digest) }
        let checksumURL: URL? = preferredAsset.flatMap { zip in
            let expectedName = "\(zip.name).sha256"
            guard let checksumAsset = assets.first(where: { $0.name == expectedName }),
                  let url = URL(string: checksumAsset.browser_download_url),
                  isTrustedDownload(url, repo: repo)
            else { return nil }
            return url
        }

        return AppReleaseInfo(
            tagName: payload.tag_name,
            version: version,
            title: (payload.name?.isEmpty == false ? payload.name! : payload.tag_name),
            notes: (payload.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            htmlURL: htmlURL,
            zipAssetURL: zipURL,
            sha256: sha256,
            checksumAssetURL: checksumURL,
            publishedAt: payload.published_at
        )
    }

    public static func checkLatestRelease(
        repo: String = defaultRepo,
        currentVersion: AppVersion = currentAppVersion,
        etag: String? = nil,
        onETag: (@Sendable (String) -> Void)? = nil
    ) async -> UpdateCheckResult {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            return .failed("Invalid update repository URL.")
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("XYNTH-1/\(currentVersion.description)", forHTTPHeaderField: "User-Agent")
        if let etag, !etag.isEmpty {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 304 {
                    return .notModified(current: currentVersion)
                }
                if http.statusCode == 404 {
                    return .noReleasesPublished(current: currentVersion)
                }
                guard (200...299).contains(http.statusCode) else {
                    return .failed("GitHub API returned HTTP \(http.statusCode).")
                }
                if let newETag = http.value(forHTTPHeaderField: "ETag"), !newETag.isEmpty {
                    onETag?(newETag)
                }
            }
            guard let release = parseGitHubReleaseJSON(data, repo: repo) else {
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

    /// Downloads the release `.zip`, verifies SHA-256, unpacks `XYNTH-1.app`, verifies bundle ID,
    /// version, executable, and `codesign --verify --deep --strict`, and strips quarantine.
    public static func downloadAndStageInstall(
        release: AppReleaseInfo,
        currentBundleURL: URL = Bundle.main.bundleURL,
        currentBundleID: String? = Bundle.main.bundleIdentifier
    ) async throws -> URL {
        let fm = FileManager.default
        let parentDir = currentBundleURL.deletingLastPathComponent()
        guard currentBundleURL.pathExtension.lowercased() == "app",
              !currentBundleURL.path.contains("/AppTranslocation/"),
              currentBundleID == expectedBundleID else {
            throw AppUpdateError.nonBundleInstallTarget
        }
        guard fm.isWritableFile(atPath: parentDir.path),
              fm.isWritableFile(atPath: currentBundleURL.path) else {
            throw AppUpdateError.directoryNotWritable(parentDir.path)
        }
        guard let zipURL = release.zipAssetURL, isTrustedDownload(zipURL) else {
            throw AppUpdateError.missingDownloadAsset
        }

        let expectedSHA = try await resolveExpectedSHA256(for: release)

        let workDir = fm.temporaryDirectory
            .appendingPathComponent("xynth1-update-\(UUID().uuidString)", isDirectory: true)
        var succeeded = false
        defer {
            if !succeeded {
                try? fm.removeItem(at: workDir)
            }
        }
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)

        var request = URLRequest(url: zipURL, timeoutInterval: 300)
        request.setValue("XYNTH-1/\(currentAppVersion.description)", forHTTPHeaderField: "User-Agent")
        let (tempZipURL, response) = try await URLSession.shared.download(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200...299).contains(status) else {
            try? fm.removeItem(at: tempZipURL)
            throw AppUpdateError.invalidArchive
        }

        let localZipURL = workDir.appendingPathComponent("update.zip")
        try fm.moveItem(at: tempZipURL, to: localZipURL)

        let actualSHA = try sha256(of: localZipURL)
        guard actualSHA == expectedSHA else {
            throw AppUpdateError.checksumMismatch
        }

        let unpackDir = workDir.appendingPathComponent("unpacked", isDirectory: true)
        try fm.createDirectory(at: unpackDir, withIntermediateDirectories: true)
        guard try runTool("/usr/bin/ditto", ["-x", "-k", localZipURL.path, unpackDir.path]) == 0 else {
            throw AppUpdateError.invalidArchive
        }

        let newAppURL = unpackDir.appendingPathComponent("XYNTH-1.app", isDirectory: true)
        guard fm.fileExists(atPath: newAppURL.path), let bundle = Bundle(url: newAppURL) else {
            throw AppUpdateError.invalidArchive
        }
        guard bundle.bundleIdentifier == expectedBundleID else {
            throw AppUpdateError.invalidBundle("Downloaded app has an unexpected bundle identifier.")
        }
        let versionText = bundle.infoDictionary?["CFBundleShortVersionString"] as? String
        guard let unpackedVersion = versionText.flatMap(AppVersion.init(parsing:)),
              unpackedVersion == release.version else {
            throw AppUpdateError.invalidBundle("Downloaded app version did not match \(release.version.description).")
        }
        guard fm.isExecutableFile(atPath: newAppURL.appendingPathComponent("Contents/MacOS/XYNTH-1").path) else {
            throw AppUpdateError.invalidBundle("Downloaded app is missing its XYNTH-1 executable.")
        }
        guard try runTool("/usr/bin/codesign", ["--verify", "--deep", "--strict", newAppURL.path]) == 0 else {
            throw AppUpdateError.invalidSignature
        }

        // Best-effort: clears Gatekeeper quarantine so the ad-hoc signed relaunch opens smoothly.
        _ = try? runTool("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newAppURL.path])

        succeeded = true
        return newAppURL
    }

    /// Spawns a detached `nohup /bin/bash` helper that waits for this process to exit, swaps in
    /// `stagedAppURL` with guarded rollback, cleans up, and relaunches `XYNTH-1.app`.
    public static func launchSwapHelperAndExit(
        stagedAppURL: URL,
        targetAppURL: URL = Bundle.main.bundleURL
    ) throws {
        let workDir = stagedAppURL.deletingLastPathComponent().deletingLastPathComponent()
        let helperURL = workDir.appendingPathComponent("install.sh")
        try installScript().write(to: helperURL, atomically: true, encoding: .utf8)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
        proc.arguments = [
            "/bin/bash",
            helperURL.path,
            String(ProcessInfo.processInfo.processIdentifier),
            stagedAppURL.path,
            targetAppURL.path,
        ]
        proc.standardInput = FileHandle.nullDevice
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try proc.run()
    }

    private static func resolveExpectedSHA256(for release: AppReleaseInfo) async throws -> String {
        if let sha = release.sha256 {
            return sha
        }
        guard let checksumURL = release.checksumAssetURL, isTrustedDownload(checksumURL) else {
            throw AppUpdateError.missingChecksum
        }
        var request = URLRequest(url: checksumURL, timeoutInterval: 30)
        request.setValue("XYNTH-1/\(currentAppVersion.description)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200...299).contains(status),
              let text = String(data: data, encoding: .utf8),
              let sha = parseChecksumFile(text) else {
            throw AppUpdateError.missingChecksum
        }
        return sha
    }

    private static func runTool(_ executable: String, _ arguments: [String]) throws -> Int32 {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = arguments
        proc.standardInput = FileHandle.nullDevice
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try proc.run()
        proc.waitUntilExit()
        return proc.terminationStatus
    }
}
