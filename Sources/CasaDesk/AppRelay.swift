import Foundation

// ⭐ ITS OWN APP IDENTITY (2026-10-03). macOS privacy (TCC) charges every request to the "responsible" app — the one
// that started the process tree. Run from Grok Bot, that is Grok Bot's helper, which can't show the permission prompt,
// so Calendar/Reminders/Contacts stayed "not asked yet" and a grant to Terminal didn't carry over.
//
// The fix: install.sh also builds ~/Applications/Casa Desk.app (this same binary, its own bundle id, signed). When that
// app exists, the `casa-desk` command doesn't do the work itself — it asks LaunchServices (`open`) to run the app with
// the same arguments. A LaunchServices launch is its OWN responsible process, so every prompt and every grant
// (Calendar, Reminders, Contacts, Automation, Full Disk Access) belongs to "Casa Desk", granted once, whatever app
// called it. Output and the exit code come back through files.
//
// ⛔ Arguments go to `open --args` as an argv — never through a shell. CASA_DESK_DIRECT=1 skips the relay (debugging).

enum Relay {
    static let env = ProcessInfo.processInfo.environment
    static var inApp: Bool { env["CASA_DESK_IN_APP"] == "1" }
    /// Who the person grants permissions to, in doctor's wording.
    static var grantee: String { inApp ? "Casa Desk (~/Applications/Casa Desk.app)" : "the app running casa-desk" }

    static var appPath: String? {
        let p = env["CASA_DESK_APP"] ?? (NSHomeDirectory() + "/Applications/Casa Desk.app")
        return FileManager.default.fileExists(atPath: p + "/Contents/MacOS/casa-desk") ? p : nil
    }

    /// Every way the program ends goes through here, so the caller outside the app learns the exit code.
    static func finish(_ code: Int32) -> Never {
        fflush(stdout); fflush(stderr)                              // all output is on disk before the result appears
        if inApp, let f = env["CASA_DESK_EXIT_FILE"] { try? "\(code)".write(toFile: f, atomically: true, encoding: .utf8) }
        exit(code)
    }

    /// Outside the app with the app installed: run this command inside it, pass its output through, and exit.
    static func runThroughAppIfNeeded() {
        guard !inApp, env["CASA_DESK_DIRECT"] != "1", let app = appPath else { return }
        let dir = NSTemporaryDirectory() + "casa-desk-relay-\(UUID().uuidString)"
        let fm = FileManager.default
        guard (try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])) != nil else { return }
        let out = dir + "/out", err = dir + "/err", code = dir + "/code"
        // -n new instance (calls can overlap) · -W wait for it · -g stay in the background.
        let argv = ["-n", "-W", "-g", "-a", app, "--stdout", out, "--stderr", err,
                    "--env", "CASA_DESK_IN_APP=1", "--env", "CASA_DESK_EXIT_FILE=\(code)",
                    "--env", "CASA_DESK_CWD=\(fm.currentDirectoryPath)",          // the app starts in "/"; --file paths are the caller's
                    "--args"] + Array(CommandLine.arguments.dropFirst())
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = argv
        let openErr = Pipe(); p.standardError = openErr                // `open`'s own chatter, shown only if it failed
        do { try p.run() } catch { return }                       // couldn't even start `open`: do the work here instead
        p.waitUntilExit()
        // `open -W` can return early when the app finishes before it gets the pid; the exit file is the real signal.
        let deadline = Date().addingTimeInterval(p.terminationStatus == 0 ? 300 : 2)
        while !fm.fileExists(atPath: code) && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        let result = (try? String(contentsOfFile: code, encoding: .utf8)).flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        if let d = fm.contents(atPath: out) { FileHandle.standardOutput.write(d) }
        if let d = fm.contents(atPath: err) { FileHandle.standardError.write(d) }
        try? fm.removeItem(atPath: dir)                             // exit() skips defer
        if let result { exit(result) }
        let why = String(data: openErr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if p.terminationStatus != 0 {
            FileHandle.standardError.write(Data("casa-desk: couldn't start Casa Desk.app (open exited \(p.terminationStatus)\(why.isEmpty ? "" : ": " + why)). Re-run scripts/install.sh, or set CASA_DESK_DIRECT=1.\n".utf8))
            exit(5)
        }
        FileHandle.standardError.write(Data("casa-desk: Casa Desk.app ended without reporting a result.\n".utf8))
        exit(5)
    }
}
