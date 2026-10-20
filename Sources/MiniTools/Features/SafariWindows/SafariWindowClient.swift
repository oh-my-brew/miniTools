struct SafariWindowClient: Sendable {
    let fetchWindows: @Sendable () throws -> [SafariWindowItem]
    let activateWindow: @Sendable (String) throws -> Void
    let activateWindows: @Sendable ([String]) throws -> Void
    let createWindow: @Sendable () throws -> Void

    var processIdentity: @Sendable () -> String? = { nil }

    static let live = SafariWindowClient(
        fetchWindows: SafariWindowService.fetchWindows,
        activateWindow: SafariWindowService.activateWindow,
        activateWindows: SafariWindowService.activateWindows,
        createWindow: SafariWindowService.createWindow,
        processIdentity: SafariWindowService.currentProcessIdentity
    )
}
