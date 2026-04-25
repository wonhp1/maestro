import Foundation
@testable import MaestroCore
import XCTest

final class DiagnosticsBundleTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = try TestSupport.makeTempDirectory(named: "diag-bundle")
    }

    override func tearDown() {
        TestSupport.removeTempDirectory(tempDir)
        super.tearDown()
    }

    func testCreateProducesZipWithManifestAndCopies() async throws {
        // 테스트 source: 작은 텍스트 파일 + 작은 디렉토리.
        let file1 = tempDir.appending(path: "registry.json")
        try "{\"agents\":{}}".write(to: file1, atomically: true, encoding: .utf8)

        let subdir = tempDir.appending(path: "logs", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        try "log line\n".write(
            to: subdir.appending(path: "yesterday.log"),
            atomically: true,
            encoding: .utf8
        )

        let outputZip = tempDir.appending(path: "bundle.zip")
        let bundle = DiagnosticsBundle()  // 실제 /usr/bin/zip 사용
        let manifest = try await bundle.create(
            outputZipURL: outputZip,
            sourcePaths: [file1, subdir],
            now: Date(timeIntervalSince1970: 1_714_500_000)
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputZip.path))
        XCTAssertGreaterThan(
            try FileManager.default.attributesOfItem(atPath: outputZip.path)[.size] as? Int ?? 0,
            0
        )
        XCTAssertEqual(manifest.appName, MaestroConfig.appName)
        XCTAssertEqual(manifest.appVersion, MaestroConfig.appVersion)
        XCTAssertEqual(manifest.bundleIdentifier, MaestroConfig.bundleIdentifier)
        XCTAssertEqual(manifest.includedRelativePaths.sorted(), [
            "paths/logs",
            "paths/registry.json",
        ])
        XCTAssertEqual(manifest.createdAt, Date(timeIntervalSince1970: 1_714_500_000))
        XCTAssertFalse(manifest.macOSVersionString.isEmpty)
    }

    func testCreateIgnoresMissingSourcePaths() async throws {
        let real = tempDir.appending(path: "real.txt")
        try "x".write(to: real, atomically: true, encoding: .utf8)
        let missing = tempDir.appending(path: "ghost.txt")  // does not exist

        let outputZip = tempDir.appending(path: "bundle.zip")
        let bundle = DiagnosticsBundle()
        let manifest = try await bundle.create(
            outputZipURL: outputZip,
            sourcePaths: [real, missing]
        )

        XCTAssertEqual(manifest.includedRelativePaths, ["paths/real.txt"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputZip.path))
    }

    /// 미존재 zip 경로는 must-fix preflight 로 missingZipExecutable 로 변환됨.
    func testMissingZipBinaryYieldsPreflightError() async throws {
        let bundle = DiagnosticsBundle(zipExecutable: URL(fileURLWithPath: "/no/such/zip"))
        let real = tempDir.appending(path: "x.txt")
        try "x".write(to: real, atomically: true, encoding: .utf8)
        let outputZip = tempDir.appending(path: "out.zip")
        do {
            _ = try await bundle.create(outputZipURL: outputZip, sourcePaths: [real])
            XCTFail("expected missingZipExecutable")
        } catch let err as DiagnosticsBundleError {
            if case .missingZipExecutable = err { /* OK */ } else {
                XCTFail("unexpected: \(err)")
            }
        }
    }

    /// Phase 5 must-fix: ZIP 의 실제 내용 검증 (manifest + paths/* 모두 존재).
    func testZipContentsContainManifestAndCopiedPaths() async throws {
        let file1 = tempDir.appending(path: "registry.json")
        try "{\"x\":1}".write(to: file1, atomically: true, encoding: .utf8)
        let logsDir = tempDir.appending(path: "logs", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        try "log\n".write(
            to: logsDir.appending(path: "today.log"),
            atomically: true, encoding: .utf8
        )

        let outputZip = tempDir.appending(path: "verify.zip")
        let bundle = DiagnosticsBundle()
        // 고정 epoch 으로 ms-truncation drift 방지 (Phase 2 의 JSON 정밀도 패턴과 동일).
        let manifest = try await bundle.create(
            outputZipURL: outputZip,
            sourcePaths: [file1, logsDir],
            now: Date(timeIntervalSince1970: 1_714_500_000)
        )

        // unzip -l 로 entry 목록 추출.
        let listing = try await runUnzipListing(zipPath: outputZip.path)
        XCTAssertTrue(listing.contains("manifest.json"), "manifest.json 누락: \(listing)")
        XCTAssertTrue(listing.contains("paths/registry.json"), "registry.json 누락: \(listing)")
        XCTAssertTrue(listing.contains("paths/logs/today.log"), "today.log 누락: \(listing)")

        // ZIP 안의 manifest.json 을 추출하여 반환된 manifest 와 일치 확인.
        let extracted = try await runUnzipExtractManifest(zipPath: outputZip.path)
        let decoded = try JSONDecoder.maestro.decode(DiagnosticsBundle.Manifest.self, from: extracted)
        XCTAssertEqual(decoded, manifest)
    }

    /// Phase 5 must-fix: 같은 lastPathComponent 의 두 source 가 충돌 없이 모두 포함.
    func testDuplicateLastPathComponentsArePreservedWithIndexPrefix() async throws {
        let dirA = tempDir.appending(path: "a", directoryHint: .isDirectory)
        let dirB = tempDir.appending(path: "b", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)
        let fileA = dirA.appending(path: "config.json")
        let fileB = dirB.appending(path: "config.json")
        try "A".write(to: fileA, atomically: true, encoding: .utf8)
        try "B".write(to: fileB, atomically: true, encoding: .utf8)

        let outputZip = tempDir.appending(path: "dup.zip")
        let bundle = DiagnosticsBundle()
        let manifest = try await bundle.create(
            outputZipURL: outputZip,
            sourcePaths: [fileA, fileB]
        )

        XCTAssertEqual(manifest.includedRelativePaths, [
            "paths/config.json",
            "paths/1-config.json",
        ])
    }

    /// Phase 5 must-fix: outputZipURL 이 source 안에 있으면 거부.
    func testOutputInsideSourceThrows() async throws {
        let bundleDir = tempDir.appending(path: "data", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: bundleDir, withIntermediateDirectories: true)
        let outputZip = bundleDir.appending(path: "self.zip")  // source 내부

        let bundle = DiagnosticsBundle()
        do {
            _ = try await bundle.create(outputZipURL: outputZip, sourcePaths: [bundleDir])
            XCTFail("expected outputInsideSource")
        } catch let err as DiagnosticsBundleError {
            if case .outputInsideSource = err { /* OK */ } else {
                XCTFail("wrong: \(err)")
            }
        }
    }

    /// Phase 5 must-fix: zip 실행파일 누락은 missingZipExecutable.
    func testMissingZipExecutablePreflighted() async throws {
        let bundle = DiagnosticsBundle(zipExecutable: URL(fileURLWithPath: "/no/such/zip"))
        let real = tempDir.appending(path: "x.txt")
        try "x".write(to: real, atomically: true, encoding: .utf8)
        do {
            _ = try await bundle.create(
                outputZipURL: tempDir.appending(path: "out.zip"),
                sourcePaths: [real]
            )
            XCTFail("expected missingZipExecutable")
        } catch let err as DiagnosticsBundleError {
            if case .missingZipExecutable = err { /* OK */ } else {
                XCTFail("wrong: \(err)")
            }
        }
    }

    // MARK: - Helpers

    private func runUnzipListing(zipPath: String) async throws -> String {
        let exec = DefaultProcessExecutor(timeout: 5)
        let output = try await exec.run(
            executable: URL(fileURLWithPath: "/usr/bin/unzip"),
            arguments: ["-l", zipPath]
        )
        return output.stdout
    }

    private func runUnzipExtractManifest(zipPath: String) async throws -> Data {
        let exec = DefaultProcessExecutor(timeout: 5)
        let output = try await exec.run(
            executable: URL(fileURLWithPath: "/usr/bin/unzip"),
            arguments: ["-p", zipPath, "manifest.json"]
        )
        return output.stdout.data(using: .utf8) ?? Data()
    }

    func testManifestRoundtripsJSON() throws {
        let manifest = DiagnosticsBundle.Manifest(
            appName: "Maestro",
            appVersion: "0.1.0",
            bundleIdentifier: "com.test",
            macOSVersionString: "Version 14.0",
            createdAt: Date(timeIntervalSince1970: 1_714_500_000),
            includedRelativePaths: ["paths/a", "paths/b"]
        )
        let data = try JSONEncoder.maestro.encode(manifest)
        let decoded = try JSONDecoder.maestro.decode(DiagnosticsBundle.Manifest.self, from: data)
        XCTAssertEqual(decoded, manifest)
    }
}
