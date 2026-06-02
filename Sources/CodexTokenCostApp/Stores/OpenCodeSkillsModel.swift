import SwiftUI
import CodexTokenCostCore

@MainActor
final class OpenCodeSkillsModel: ObservableObject {
    @Published var snapshot: OpenCodeSkillsReadOnlySnapshot?
    @Published var isLoading = false
    @Published var errorMessage: String?

    var isRefreshing: Bool { isLoading }

    func refreshIfNeeded() {
        if snapshot == nil {
            refresh()
        }
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = OpenCodeSkillsReadOnlyStore.buildReadOnlySnapshot()
            DispatchQueue.main.async {
                self?.snapshot = result
                self?.isLoading = false
            }
        }
    }
}
