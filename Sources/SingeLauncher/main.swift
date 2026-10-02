import Foundation

// Singe's launcher. macOS ties the Accessibility permission to this executable, so it
// is kept tiny and unchanged across updates; it loads the app from libSingeCore.dylib,
// which the installer replaces freely. Change this file only when you must: every change
// means granting Accessibility again.

let fm = FileManager.default
let exeDir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
var candidates: [String] = []
if let override = ProcessInfo.processInfo.environment["SINGE_CORE"] { candidates.append(override) }
candidates.append(fm.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/Singe/libSingeCore.dylib").path)
candidates.append(exeDir.appendingPathComponent("libSingeCore.dylib").path)

for path in candidates where fm.fileExists(atPath: path) {
    guard let handle = dlopen(path, RTLD_NOW) else {
        FileHandle.standardError.write("Singe: cannot load \(path): \(String(cString: dlerror()))\n".data(using: .utf8)!)
        continue
    }
    guard let sym = dlsym(handle, "singe_main") else { continue }
    typealias Main = @convention(c) () -> Int32
    exit(unsafeBitCast(sym, to: Main.self)())
}

let message = "Singe could not find its app library. Run the installer again." as CFString
CFUserNotificationDisplayAlert(0, kCFUserNotificationStopAlertLevel, nil, nil, nil,
                               "Singe" as CFString, message, nil, nil, nil, nil)
exit(1)
