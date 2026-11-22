// Prints the window id of the first on-screen window of a process name, for screencapture -l.
import CoreGraphics
import Foundation
let name = CommandLine.arguments.dropFirst().first ?? "Dyogène"
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for window in windows where (window[kCGWindowOwnerName as String] as? String) == name && (window[kCGWindowLayer as String] as? Int) == 0 {
    print(window[kCGWindowNumber as String] as? Int ?? 0)
    exit(0)
}
exit(1)
