import Foundation

enum DefaultApplicationMessageKind: Equatable, Sendable {
    case success
    case error
}

struct DefaultApplicationMessage: Equatable, Sendable {
    let kind: DefaultApplicationMessageKind
    let text: String
}

struct DefaultApplicationRowState: Identifiable, Equatable, Sendable {
    let fileType: DefaultApplicationFileType
    var currentApplication: DefaultApplicationIdentity?
    var isUpdating = false
    var message: DefaultApplicationMessage?

    var id: String { fileType.id }
}

@MainActor
final class DefaultApplicationSettingsModel: ObservableObject {
    @Published private(set) var rows: [DefaultApplicationRowState]
    @Published private(set) var sublimeTextApplication: DefaultApplicationIdentity?

    private let client: any DefaultApplicationClient

    var isUpdating: Bool {
        rows.contains(where: \.isUpdating)
    }

    init(
        client: any DefaultApplicationClient = NSWorkspaceDefaultApplicationClient(),
        fileTypes: [DefaultApplicationFileType] = DefaultApplicationFileTypeCatalog.supported
    ) {
        self.client = client
        rows = fileTypes.map { DefaultApplicationRowState(fileType: $0) }
    }

    func refresh() {
        sublimeTextApplication = client.sublimeTextApplication()
        for index in rows.indices {
            rows[index].isUpdating = false
            rows[index].message = nil
            refreshApplication(at: index)
        }
    }

    func setSublimeText(for id: String) async {
        guard !isUpdating else { return }
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        guard let contentType = rows[index].fileType.resolvedContentType else {
            rows[index].message = DefaultApplicationMessage(
                kind: .error,
                text: "无法将扩展名解析为预期的 UTType"
            )
            return
        }
        guard let sublimeTextApplication else {
            rows[index].message = DefaultApplicationMessage(
                kind: .error,
                text: "未找到 Sublime Text，请先安装后刷新"
            )
            return
        }

        rows[index].isUpdating = true
        rows[index].message = nil
        do {
            try await client.setDefaultApplication(
                sublimeTextApplication,
                for: contentType
            )
            let actualApplication = client.defaultApplication(for: contentType)
            rows[index].currentApplication = actualApplication
            if actualApplication?.matches(sublimeTextApplication) == true {
                rows[index].message = DefaultApplicationMessage(
                    kind: .success,
                    text: "已验证默认应用为 Sublime Text"
                )
            } else {
                rows[index].message = DefaultApplicationMessage(
                    kind: .error,
                    text: "macOS 未采用此更改；当前仍为 \(actualApplication?.name ?? "未知应用")"
                )
            }
        } catch {
            rows[index].currentApplication = client.defaultApplication(for: contentType)
            rows[index].message = DefaultApplicationMessage(
                kind: .error,
                text: "设置失败：\(error.localizedDescription)"
            )
        }
        rows[index].isUpdating = false
    }

    func isSublimeTextDefault(for row: DefaultApplicationRowState) -> Bool {
        guard let sublimeTextApplication, let currentApplication = row.currentApplication else {
            return false
        }
        return currentApplication.matches(sublimeTextApplication)
    }

    private func refreshApplication(at index: Int) {
        guard let contentType = rows[index].fileType.resolvedContentType else {
            rows[index].currentApplication = nil
            rows[index].message = DefaultApplicationMessage(
                kind: .error,
                text: "无法将扩展名解析为预期的 UTType"
            )
            return
        }
        rows[index].currentApplication = client.defaultApplication(for: contentType)
    }
}
