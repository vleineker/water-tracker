import Foundation
import Testing

@Suite("Login item: LaunchAgent de reserva")
struct LaunchAgentFallbackTests {
    private let home = "/Users/exemplo"
    private let plist = "/Users/exemplo/Library/LaunchAgents/com.vleineker.gota.plist"

    @Test func plistLivesInUserLaunchAgents() {
        #expect(LaunchAgentFallback.plistPath(home: home) == plist)
        #expect(LaunchAgentFallback.plistPath(home: home + "/") == plist)
    }

    @Test func turningOffRemovesExistingPlist() {
        #expect(LaunchAgentFallback.pathToRemove(enabled: false, home: home) { $0 == plist } == plist)
    }

    @Test func turningOffWithoutPlistRemovesNothing() {
        #expect(LaunchAgentFallback.pathToRemove(enabled: false, home: home) { _ in false } == nil)
    }

    @Test func turningOnNeverRemoves() {
        #expect(LaunchAgentFallback.pathToRemove(enabled: true, home: home) { _ in true } == nil)
    }

    @Test func plistOpensTheAppAtLogin() {
        let contents = LaunchAgentFallback.contents(appPath: "/Applications/Gota.app")
        #expect(contents["Label"] as? String == "com.vleineker.gota")
        #expect(contents["ProgramArguments"] as? [String] == ["/usr/bin/open", "-a", "/Applications/Gota.app"])
        #expect(contents["RunAtLoad"] as? Bool == true)
    }
}
