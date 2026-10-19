import Sparkle

enum AppUpdateChannel: String, CaseIterable {
    case stable
    case beta

    var feedURL: URL {
        switch self {
        case .stable:
            URL(string: "https://github.com/oh-my-brew/miniTools/releases/latest/download/appcast.xml")!
        case .beta:
            URL(string: "https://github.com/oh-my-brew/miniTools/releases/download/beta/appcast-beta.xml")!
        }
    }
}

@MainActor
final class AppUpdateController: NSObject, SPUUpdaterDelegate {
    private var selectedChannel = AppUpdateChannel.stable
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    override init() {
        super.init()
        _ = updaterController
    }

    func checkForUpdates(channel: AppUpdateChannel = .stable) {
        selectedChannel = channel
        updaterController.checkForUpdates(nil)
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        selectedChannel.feedURL.absoluteString
    }
}
