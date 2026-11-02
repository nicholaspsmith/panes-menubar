// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import DisplayCore

/// Takes over from a Monitor Lizard that is still running when Panes starts
/// (parity installs Panes 1.0.0 while ML runs): quits it, turns its login item
/// off, then brings its settings over once. Runs on every launch, before the
/// displays feature starts; with no ML bundle installed it only checks the
/// one-time migration flag. `DisplayCore.MonitorLizardCutoverSequence` holds
/// the order; this supplies the system calls.
final class MonitorLizardCutover {
    static let bundleID = MonitorLizardMigration.oldDomain
    private var sequence: MonitorLizardCutoverSequence?

    func run(completion: @escaping () -> Void) {
        let steps = MonitorLizardCutoverSequence.Steps(
            isRunning: { !Self.runningApps().isEmpty },
            terminate: { Self.runningApps().forEach { $0.terminate() } },
            forceTerminate: { Self.runningApps().forEach { $0.forceTerminate() } },
            bundleURL: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) },
            loginOff: Self.loginOff,
            migrate: Self.migrate
        )
        let sequence = MonitorLizardCutoverSequence(steps: steps)
        self.sequence = sequence
        sequence.run { [weak self] in
            self?.sequence = nil
            completion()
        }
    }

    private static func runningApps() -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).filter { !$0.isTerminated }
    }

    /// `<bundle>/Contents/MacOS/<CFBundleExecutable> --login off`: StatusItemKit's
    /// LoginCLI, which unregisters ML's own SMAppService and exits headless.
    private static func loginOff(_ bundleURL: URL, done: @escaping (Int32?) -> Void) {
        guard let executable = Bundle(url: bundleURL)?.executableURL else {
            Log.migration.error("no executable in \(bundleURL.path, privacy: .public)")
            done(nil)
            return
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--login", "off"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { finished in
            let status = finished.terminationStatus
            DispatchQueue.main.async { done(status) }
        }
        do {
            try process.run()
        } catch {
            Log.migration.error("couldn't run \(executable.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            done(nil)
        }
    }

    /// The one-time copy of ML's settings into Panes's domain.
    private static func migrate() {
        guard let domain = Bundle.main.bundleIdentifier else {
            Log.migration.error("no bundle identifier (unbundled run): settings not migrated")
            return
        }
        let old = MonitorLizardMigration.readDomain(MonitorLizardMigration.oldDomain)
        guard let written = MonitorLizardMigration.applyOnce(old: old, to: .standard, domain: domain) else { return }
        Log.migration.info("settings migrated from Monitor Lizard: \(written.isEmpty ? "none" : written.joined(separator: ", "), privacy: .public)")
    }
}
