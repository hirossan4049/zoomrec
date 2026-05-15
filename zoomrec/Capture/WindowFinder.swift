import Foundation
import AppKit
import ScreenCaptureKit

struct CaptureProbe {
    var chosen: SCWindow?
    var zoomTotal: Int
    var zoomVisible: Int
    var thirdPartyVisible: Int
    var zoomRunning: Bool
}

enum WindowFinder {
    static func probe(in content: SCShareableContent) -> CaptureProbe {
        let zoomAll = content.windows.filter {
            ($0.owningApplication?.bundleIdentifier ?? "").hasPrefix("us.zoom.")
        }
        let zoomVisible = zoomAll.filter {
            $0.isOnScreen && $0.frame.width >= 100 && $0.frame.height >= 100
        }

        let ownBundle = Bundle.main.bundleIdentifier ?? "io.lh.zoomrec"
        let thirdPartyVisible = content.windows.filter { w in
            let bid = w.owningApplication?.bundleIdentifier ?? ""
            return w.isOnScreen
                && !bid.isEmpty
                && bid != ownBundle
                && !bid.hasPrefix("com.apple.")
        }.count

        let zoomRunning = !NSRunningApplication
            .runningApplications(withBundleIdentifier: "us.zoom.xos")
            .isEmpty

        let chosen = pick(from: zoomVisible)
        return CaptureProbe(
            chosen: chosen,
            zoomTotal: zoomAll.count,
            zoomVisible: zoomVisible.count,
            thirdPartyVisible: thirdPartyVisible,
            zoomRunning: zoomRunning
        )
    }

    private static func pick(from windows: [SCWindow]) -> SCWindow? {
        let titledMeeting = windows.filter { w in
            let t = w.title ?? ""
            return t.localizedCaseInsensitiveContains("meeting")
                || t.contains("ミーティング")
                || t.localizedCaseInsensitiveContains("zoom")
        }
        let byArea: (SCWindow, SCWindow) -> Bool = { a, b in
            (a.frame.width * a.frame.height) < (b.frame.width * b.frame.height)
        }
        return titledMeeting.max(by: byArea) ?? windows.max(by: byArea)
    }
}
