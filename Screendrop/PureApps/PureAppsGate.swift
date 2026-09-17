import AppKit
import PureAppsLicense
import SwiftUI
import os

/// PureApps subscription check. One subscription unlocks every PureApps app, so there is
/// nothing app-specific here: read the signed licence the Hub wrote, and act on it.
///
/// This is the only PureApps code in the app. Everything else stays as upstream wrote it,
/// so merges from upstream keep working.
enum PureAppsGate {
    private static let log = Logger(subsystem: "apps.pure.pureshot", category: "license")

    static let upstreamURL = URL(string: "https://github.com/fayazara/screendrop")!
    static let websiteURL = URL(string: "https://pureapps.dev")!

    /// Called once at launch. Nothing is blocked here: the app opens, the library, editors
    /// and settings stay usable; only starting a new capture or recording asks for a licence.
    static func checkAtLaunch() {
        // Wakes the Hub in the background when the licence is within two days of going
        // stale, so someone who never opens the Hub is not locked out of what they paid for.
        PureAppsLicense.refreshIfNeeded()
        log.info("licence status: \(String(describing: PureAppsLicense.status()), privacy: .public)")
    }

    /// The gate. Call it where a capture or recording begins, never while one is running:
    /// a recording in progress always finishes and saves, even if the subscription lapses.
    @MainActor
    static func allowStartingCapture() -> Bool {
        let status = PureAppsLicense.status()
        guard !status.unlocksEverything else { return true }
        log.info("blocked capture: licence \(String(describing: status), privacy: .public)")
        presentSubscriptionNeeded()
        return false
    }

    /// Menu bar item.
    static func openSubscription() {
        guard PureAppsLicense.isHubInstalled else {
            NSWorkspace.shared.open(websiteURL)
            return
        }
        NSWorkspace.shared.open(PureAppsLicense.hubURL(action: .subscribe))
    }

    /// The app menu's About item (visible while an editor window is open) goes to the
    /// Settings About tab, which is where the house About content lives.
    static func showAbout() {
        SettingsWindowController.show(tab: .about)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @MainActor
    private static func presentSubscriptionNeeded() {
        let alert = NSAlert()
        if hadPaidSubscription {
            alert.messageText = String(localized: "Your PureApps subscription has ended")
            alert.informativeText = String(localized: "Renew it in PureApps Hub to take new screenshots and recordings. Your library and editors stay available. One subscription unlocks every PureApps app.")
        } else {
            alert.messageText = String(localized: "Your PureApps trial has ended")
            alert.informativeText = String(localized: "Subscribe in PureApps Hub to take new screenshots and recordings. Your library and editors stay available. One subscription unlocks every PureApps app.")
        }
        alert.addButton(withTitle: PureAppsLicense.isHubInstalled ? String(localized: "Open PureApps Hub") : String(localized: "Get PureApps Hub"))
        alert.addButton(withTitle: String(localized: "Later"))
        NSApplication.shared.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            openSubscription()
        }
    }

    /// `.expired` covers both a lapsed subscription and a finished trial. A genuine,
    /// non-trial token on disk means someone paid, so the wording says "subscription".
    private static var hadPaidSubscription: Bool {
        guard let data = try? Data(contentsOf: PureAppsLicense.licenseURL),
              let token = try? LicenseVerifier().token(from: data) else { return false }
        return token.plan != LicenseStatus.trialPlanName
    }
}

/// Settings > About. Replaces upstream's pane (and its Sparkle update controls): name,
/// version, the upstream credit and link, and the house footer with PureApps linked.
/// The credit lives here only; the rest of the app carries the PureApps brand alone.
struct SettingsAboutPane: View {
    private var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return String(localized: "Version \(version)")
    }

    var body: some View {
        Form {
            Section {
                HStack(alignment: .center, spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 72, height: 72)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("PureShot")
                            .font(.largeTitle.bold())

                        Text(versionText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text("A native screenshot and recording tool for macOS.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Credits") {
                Text("Based on Screendrop by Fayaz Ahmed, used under the CC0 1.0 licence.")
                    .foregroundStyle(.secondary)

                Link("github.com/fayazara/screendrop", destination: PureAppsGate.upstreamURL)
                    .pointerStyle(.link)
            }

            Section {
                HStack(spacing: 0) {
                    Text(verbatim: "© 2026 ")
                    Link("PureApps", destination: PureAppsGate.websiteURL)
                        .pointerStyle(.link)
                    Text(". Based on Screendrop by Fayaz Ahmed, CC0 1.0.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
    }
}
