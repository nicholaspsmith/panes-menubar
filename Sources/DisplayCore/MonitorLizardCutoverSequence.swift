// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

/// The order of the cut-over from a running Monitor Lizard, with the system
/// calls injected (Panes's `MonitorLizardCutover` supplies the real ones):
///
/// 1. If ML is running, ask it to quit; poll for `quitTimeout`, then force it.
///    Its own `applicationWillTerminate` clears its XDR table and dim overlay.
/// 2. If its bundle is installed, run `<bundle> --login off`, so it doesn't
///    come back at login. Waits at most `loginOffTimeout` for the answer.
/// 3. Migrate its settings (the snapshot is final now it has quit).
/// 4. `completion`, exactly once.
///
/// Every step is logged under the `migration` category.
public final class MonitorLizardCutoverSequence {
    public struct Steps {
        public var isRunning: () -> Bool
        public var terminate: () -> Void
        public var forceTerminate: () -> Void
        public var bundleURL: () -> URL?
        /// Runs the bundle's `--login off`; calls back with the exit status,
        /// or nil when it couldn't be started. Called back on the main queue.
        public var loginOff: (URL, @escaping (Int32?) -> Void) -> Void
        public var migrate: () -> Void

        public init(isRunning: @escaping () -> Bool, terminate: @escaping () -> Void,
                    forceTerminate: @escaping () -> Void, bundleURL: @escaping () -> URL?,
                    loginOff: @escaping (URL, @escaping (Int32?) -> Void) -> Void,
                    migrate: @escaping () -> Void) {
            self.isRunning = isRunning
            self.terminate = terminate
            self.forceTerminate = forceTerminate
            self.bundleURL = bundleURL
            self.loginOff = loginOff
            self.migrate = migrate
        }
    }

    public static let quitTimeout: TimeInterval = 5
    public static let pollInterval: TimeInterval = 0.1
    /// After a force quit, how long to wait for the process to go.
    public static let forceGrace: TimeInterval = 1
    public static let loginOffTimeout: TimeInterval = 5

    private let steps: Steps
    private let after: (TimeInterval, @escaping () -> Void) -> Void

    /// - Parameter after: runs a closure after a delay, on the main queue.
    public init(steps: Steps,
                after: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, run in
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: run)
                }) {
        self.steps = steps
        self.after = after
    }

    public func run(completion: @escaping () -> Void) {
        quit { [self] in
            loginOff { [self] in
                steps.migrate()
                Log.migration.info("cut-over done")
                completion()
            }
        }
    }

    // MARK: - Steps

    private func quit(then next: @escaping () -> Void) {
        guard steps.isRunning() else { next(); return }
        Log.migration.info("Monitor Lizard is running: asking it to quit")
        steps.terminate()
        let polls = Int((Self.quitTimeout / Self.pollInterval).rounded())
        let graces = Int((Self.forceGrace / Self.pollInterval).rounded())
        waitForQuit(pollsLeft: polls, forced: false, graces: graces, then: next)
    }

    private func waitForQuit(pollsLeft: Int, forced: Bool, graces: Int, then next: @escaping () -> Void) {
        if !steps.isRunning() {
            Log.migration.info("Monitor Lizard quit\(forced ? " (forced)" : "", privacy: .public)")
            next()
            return
        }
        if pollsLeft <= 0 {
            guard !forced else {
                Log.migration.error("Monitor Lizard still running after a force quit; going on")
                next()
                return
            }
            Log.migration.notice("Monitor Lizard didn't quit in \(Self.quitTimeout)s: forcing it")
            steps.forceTerminate()
            waitForQuit(pollsLeft: graces, forced: true, graces: graces, then: next)
            return
        }
        after(Self.pollInterval) { [self] in
            waitForQuit(pollsLeft: pollsLeft - 1, forced: forced, graces: graces, then: next)
        }
    }

    private func loginOff(then next: @escaping () -> Void) {
        guard let url = steps.bundleURL() else {
            Log.migration.info("no Monitor Lizard bundle installed")
            next()
            return
        }
        var finished = false
        let finish: (String) -> Void = { outcome in
            guard !finished else { return }
            finished = true
            Log.migration.info("Monitor Lizard --login off: \(outcome, privacy: .public)")
            next()
        }
        Log.migration.info("turning Monitor Lizard's login item off (\(url.path, privacy: .public))")
        steps.loginOff(url) { status in
            finish(status.map { "exit \($0)" } ?? "couldn't run")
        }
        after(Self.loginOffTimeout) { finish("no answer in \(Self.loginOffTimeout)s") }
    }
}
