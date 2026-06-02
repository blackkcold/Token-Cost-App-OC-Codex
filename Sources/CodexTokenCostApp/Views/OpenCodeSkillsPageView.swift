import SwiftUI
import CodexTokenCostCore

struct OpenCodeSkillsPageView: View {
    @ObservedObject var model: OpenCodeSkillsModel
    let palette: TokenCostPalette

    @State private var searchText = ""
    @State private var selectedSkillID: String?
    @State private var filterSourceKind: OpenCodeSkillSourceKind? = nil
    @State private var filterState: OpenCodeSkillManifestState? = nil
    @State private var filterOnlyIssues = false
    @State private var bodyExpanded = false
    @State private var sectionsExpanded: Set<String> = ["opencodePlural", "claude", "agents", "custom", "builtin"]

    var body: some View {
        if model.snapshot == nil && !model.isLoading {
            loadingPlaceholder
        } else if model.isLoading && model.snapshot == nil {
            scanningView
        } else if let snapshot = model.snapshot {
            mainContent(snapshot)
        }
    }

    private var loadingPlaceholder: some View {
        ProgressView()
            .onAppear { model.refreshIfNeeded() }
    }

    private var scanningView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(verbatim: "Scanning OpenCode skills...")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func mainContent(_ snapshot: OpenCodeSkillsReadOnlySnapshot) -> some View {
        if !snapshot.openCodeInstalled {
            notInstalledView
        } else {
            HSplitView {
                sidebarView(snapshot)
                    .frame(minWidth: 240, idealWidth: 280)
                detailView(snapshot)
                    .frame(minWidth: 420)
            }
            .background(.ultraThinMaterial)
        }
    }

    private var notInstalledView: some View {
        VStack(spacing: 20) {
            Image(systemName: "gearshape.2")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(verbatim: "OpenCode not detected")
                .font(.title2)
            Text(verbatim: "The ~/.config/opencode/ directory was not found.")
                .foregroundStyle(.secondary)
            Text(verbatim: "Install OpenCode Desktop to use this panel.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sidebarView(_ snapshot: OpenCodeSkillsReadOnlySnapshot) -> some View {
        VStack(spacing: 0) {
            headerView(snapshot)
            filterBar
            Divider().opacity(0.3)
            skillSectionsView(snapshot)
        }
        .background(.regularMaterial)
    }

    private func headerView(_ snapshot: OpenCodeSkillsReadOnlySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(verbatim: "Skills")
                    .font(.headline)
                Spacer()
                Text(verbatim: "Read-only")
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(palette.accent.opacity(0.15)))
                    .foregroundStyle(palette.accent)
            }
            Text(verbatim: "\(snapshot.discoveredSkills.count) global · \(snapshot.builtinSkills.count) built-in")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    private var filterBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary).font(.caption)
                TextField("Filter...", text: $searchText)
                    .textFieldStyle(.plain).font(.caption)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(.secondary.opacity(0.08)))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    filterChip("All", isActive: filterSourceKind == nil && filterState == nil && !filterOnlyIssues) {
                        filterSourceKind = nil; filterState = nil; filterOnlyIssues = false
                    }
                    ForEach(OpenCodeSkillSourceKind.allCases, id: \.self) { kind in
                        filterChip(kind.shortLabel, isActive: filterSourceKind == kind) {
                            if filterSourceKind == kind { filterSourceKind = nil }
                            else { filterSourceKind = kind }
                        }
                    }
                    Menu {
                        Button("Any state") { filterState = nil }
                        Button("Valid only") { filterState = .valid }
                        Button("Warning") { filterState = .warning }
                        Button("Invalid / Error") { filterState = .invalid }
                    } label: {
                        filterChip(filterState?.rawValue ?? "State", isActive: filterState != nil, isMenu: true) {}
                    }
                    filterChip("Issues", isActive: filterOnlyIssues) {
                        filterOnlyIssues.toggle()
                    }
                }
                .padding(.horizontal, 8)
            }
        }
        .padding(.vertical, 6)
    }

    private func filterChip(_ label: String, isActive: Bool, isMenu: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 2) {
                Text(verbatim: label).font(.caption2)
                if isMenu { Image(systemName: "chevron.down").font(.system(size: 7)) }
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(isActive ? palette.accent.opacity(0.2) : .secondary.opacity(0.08)))
            .foregroundStyle(isActive ? palette.accent : .secondary)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func skillSectionsView(_ snapshot: OpenCodeSkillsReadOnlySnapshot) -> some View {
        let grouped = groupSkills(snapshot)

        if grouped.isEmpty {
            VStack(spacing: 8) {
                Text(verbatim: "No skills match filter").foregroundStyle(.secondary)
            }.frame(maxHeight: .infinity)
        } else {
            List {
                ForEach(grouped, id: \.kind) { group in
                    Section(isExpanded: Binding(
                        get: { sectionsExpanded.contains(group.kind) },
                        set: { if $0 { sectionsExpanded.insert(group.kind) } else { sectionsExpanded.remove(group.kind) } }
                    )) {
                        ForEach(group.skills) { skill in
                            skillRow(skill)
                                .tag(skill.id)
                                .listRowBackground(Color.clear)
                        }
                    } header: {
                        sectionHeader(icon: group.icon, title: group.title, count: group.skills.count, kind: group.kind)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
    }

    private func sectionHeader(icon: String, title: String, count: Int, kind: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption2).foregroundStyle(.secondary)
            Text(verbatim: title).font(.caption.weight(.medium))
            Text(verbatim: "\(count)").font(.caption2).foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func skillRow(_ skill: OpenCodeSkillRecord) -> some View {
        Button {
            selectedSkillID = skill.id
            bodyExpanded = false
        } label: {
            HStack(spacing: 8) {
                statusDot(skill.manifest.state)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: skill.name).font(.callout).lineLimit(1)
                    if let desc = skill.manifest.description, !desc.isEmpty {
                        Text(verbatim: String(desc.prefix(50)))
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                HStack(spacing: 3) {
                    if skill.isSymlink {
                        Image(systemName: "link").font(.system(size: 8)).foregroundStyle(.secondary)
                    }
                    if !skill.manifest.extraFields.isEmpty {
                        ForEach(Array(skill.manifest.extraFields.keys.prefix(2)), id: \.self) { key in
                            Text(verbatim: key).font(.system(size: 7))
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Capsule().fill(.secondary.opacity(0.1)))
                                .foregroundStyle(.secondary)
                        }
                    }
                    sourceChip(skill.sourceKind)
                }
            }
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
    }

    private func sourceChip(_ kind: OpenCodeSkillSourceKind) -> some View {
        Text(verbatim: kind.shortLabel)
            .font(.system(size: 7))
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(Capsule().fill(kind.color.opacity(0.15)))
            .foregroundStyle(kind.color)
    }

    private func statusDot(_ state: OpenCodeSkillManifestState) -> some View {
        Circle()
            .fill(state == .valid ? .green : state == .warning ? .yellow : .red)
            .frame(width: 7, height: 7)
    }

    @ViewBuilder
    private func detailView(_ snapshot: OpenCodeSkillsReadOnlySnapshot) -> some View {
        if let selectedID = selectedSkillID,
           let skill = (snapshot.discoveredSkills + snapshot.builtinSkills).first(where: { $0.id == selectedID }) {
            skillDetailView(skill, snapshot: snapshot)
        } else {
            overviewView(snapshot)
        }
    }

    private func overviewView(_ snapshot: OpenCodeSkillsReadOnlySnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(verbatim: "Global Skills Baseline")
                    .font(.title2).padding(.bottom, 4)

                configSummarySection(snapshot)
                agentMatrixSection(snapshot)
                warningsSection(snapshot)
            }
            .padding(24)
        }
    }

    private func skillDetailView(_ skill: OpenCodeSkillRecord, snapshot: OpenCodeSkillsReadOnlySnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    statusDot(skill.manifest.state)
                    Text(verbatim: skill.name).font(.title3.weight(.semibold))
                    Spacer()
                    sourceChip(skill.sourceKind)
                }

                if let desc = skill.manifest.description {
                    detailCard(icon: "doc.text", title: "Description") {
                        Text(verbatim: desc).font(.callout)
                    }
                }

                if !skill.manifest.extraFields.isEmpty {
                    detailCard(icon: "tag", title: "Metadata") {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                            ForEach(Array(skill.manifest.extraFields.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: key).font(.caption2).foregroundStyle(.secondary)
                                    Text(verbatim: String(value.prefix(80))).font(.caption).lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(6)
                                .background(RoundedRectangle(cornerRadius: 6).fill(.secondary.opacity(0.06)))
                            }
                        }
                    }
                }

                if let body = skill.manifest.bodyContent {
                    detailCard(icon: "book.pages", title: "Skill Content") {
                        let preview = bodyExpanded ? body : String(body.prefix(300))
                        let needsToggle = body.count > 300
                        Text(verbatim: preview)
                            .font(.caption)
                            .monospaced()
                            .foregroundStyle(.secondary)
                        if needsToggle {
                            Button { withAnimation { bodyExpanded.toggle() } } label: {
                                Text(verbatim: bodyExpanded ? "Collapse" : "Expand all (\(body.count) chars)")
                                    .font(.caption2)
                                    .foregroundStyle(palette.accent)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                    }
                }

                if let license = skill.manifest.license {
                    infoLine("License", license)
                }
                if let compat = skill.manifest.compatibility {
                    infoLine("Compatibility", compat)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "Source").font(.caption2).foregroundStyle(.tertiary)
                    Text(verbatim: skill.displayPath).font(.caption2).monospaced().foregroundStyle(.tertiary)
                }

                if skill.isSymlink, let target = skill.targetCanonicalPath {
                    Text(verbatim: "→ \(target)").font(.caption2).foregroundStyle(.tertiary)
                }

                if !skill.duplicatePaths.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: "Duplicates").font(.caption).foregroundStyle(.orange)
                        ForEach(skill.duplicatePaths, id: \.self) { Text(verbatim: $0).font(.caption2).monospaced().foregroundStyle(.secondary) }
                    }
                }

                if !skill.manifest.issues.isEmpty {
                    detailCard(icon: "exclamationmark.triangle", title: "Issues") {
                        ForEach(skill.manifest.issues) { issue in
                            HStack(spacing: 6) {
                                Circle().fill(issue.severity == .error ? .red : issue.severity == .warning ? .yellow : .blue).frame(width: 6, height: 6)
                                Text(verbatim: issue.message).font(.caption)
                            }
                        }
                    }
                }

                if !skill.manifest.unknownFieldKeys.isEmpty {
                    Text(verbatim: "Unknown fields: \(skill.manifest.unknownFieldKeys.joined(separator: ", ")) (\(skill.manifest.unknownFieldKeys.count))")
                        .font(.caption2).foregroundStyle(.tertiary)
                }

                let baseline = OpenCodeSkillPermissionResolver.resolveSkillPermission(
                    skillName: skill.name,
                    permissionConfig: extractPermissionFromLayers(snapshot.configLayers)
                )
                permissionCard(baseline)
            }
            .padding(24)
        }
    }

    private func detailCard<Content: View>(icon: String, title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.caption).foregroundStyle(palette.accent)
                Text(verbatim: title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.secondary.opacity(0.06)))
    }

    private func infoLine(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: label).font(.caption).foregroundStyle(.secondary)
            Text(verbatim: value).font(.callout)
        }
    }

    private func permissionCard(_ baseline: OpenCodeSkillBaselineState) -> some View {
        detailCard(icon: "lock.shield", title: "Permission") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(verbatim: "Resolved:").font(.caption)
                    Text(verbatim: baseline.resolvedAction.rawValue).font(.caption.weight(.medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(
                            baseline.resolvedAction == .allow ? .green.opacity(0.15) :
                            baseline.resolvedAction == .deny ? .red.opacity(0.15) :
                            baseline.resolvedAction == .ask ? .orange.opacity(0.15) : .gray.opacity(0.15)
                        ))
                }
                Text(verbatim: baseline.explainMessage).font(.caption2).foregroundStyle(.tertiary)
                if !baseline.ruleChain.isEmpty {
                    ForEach(baseline.ruleChain.sorted(by: { $0.order < $1.order })) { rule in
                        HStack(spacing: 4) {
                            Text(verbatim: "[\(rule.order)]").font(.caption2).monospaced()
                            Text(verbatim: "\(rule.pattern) = \(rule.action.rawValue)").font(.caption2)
                            if rule.isLegacy { Text(verbatim: "(legacy)").font(.caption2).foregroundStyle(.orange) }
                        }
                    }
                }
            }
        }
    }

    private func configSummarySection(_ snapshot: OpenCodeSkillsReadOnlySnapshot) -> some View {
        detailCard(icon: "gearshape.2", title: "Config Layers") {
            ForEach(snapshot.configLayers, id: \.name) { layer in
                HStack(spacing: 6) {
                    Circle()
                        .fill(layer.isPresent ? (layer.parseError != nil ? .red : .green) : .gray)
                        .frame(width: 8, height: 8)
                    Text(verbatim: layer.name).font(.caption)
                    if layer.isJSONC { Text(verbatim: "JSONC").font(.caption2).foregroundStyle(.orange) }
                    if layer.isCompatibilityLayer { Text(verbatim: "compat").font(.caption2).foregroundStyle(.secondary) }
                    if let err = layer.parseError {
                        Text(verbatim: err).font(.caption2).foregroundStyle(.red).lineLimit(1)
                    }
                }
            }
        }
    }

    private func agentMatrixSection(_ snapshot: OpenCodeSkillsReadOnlySnapshot) -> some View {
        detailCard(icon: "cpu", title: "Agent Matrix") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(snapshot.agentMatrix) { agent in
                    HStack(spacing: 6) {
                        Circle().fill(agent.skillToolAvailable ? .green : .red).frame(width: 7, height: 7)
                        Text(verbatim: agent.agent.rawValue).font(.caption)
                        if let note = agent.note {
                            Text(verbatim: note).font(.caption2).foregroundStyle(.orange).lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.secondary.opacity(0.05)))
                }
            }
        }
    }

    private func warningsSection(_ snapshot: OpenCodeSkillsReadOnlySnapshot) -> some View {
        if snapshot.scopeWarnings.isEmpty { return AnyView(EmptyView()) }
        return AnyView(
            detailCard(icon: "exclamationmark.triangle", title: "Warnings") {
                ForEach(Array(snapshot.scopeWarnings.enumerated()), id: \.offset) { _, w in
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle").font(.caption2).foregroundStyle(.yellow)
                        Text(verbatim: w).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        )
    }

    private func extractPermissionFromLayers(_ layers: [OpenCodeConfigLayerSignal]) -> Any? {
        for layer in layers.reversed() {
            if layer.isPresent, layer.parseError == nil, let dict = layer.rawJSON {
                if let perm = dict["permission"] { return perm }
            }
        }
        return nil
    }

    private struct SkillGroup {
        let kind: String
        let icon: String
        let title: String
        let skills: [OpenCodeSkillRecord]
    }

    private func groupSkills(_ snapshot: OpenCodeSkillsReadOnlySnapshot) -> [SkillGroup] {
        let filtered = snapshot.discoveredSkills.filter { matchesFilter($0) }
        var groups: [SkillGroup] = []
        var seenKinds: Set<OpenCodeSkillSourceKind> = []

        let kindOrder: [(OpenCodeSkillSourceKind, String, String)] = [
            (.opencodePlural, "folder", "OpenCode Skills"),
            (.opencodeSingular, "folder", "OpenCode Skill (Singular)"),
            (.claude, "link", "Claude Skills"),
            (.agents, "person.2", "Agents Skills"),
            (.configSkillsPath, "tray", "Custom Path Skills"),
            (.customConfigDir, "externaldrive", "Custom Config Dir"),
            (.builtin, "cube", "Built-in Skills"),
        ]

        for (kind, icon, title) in kindOrder {
            let skills = filtered.filter { $0.sourceKind == kind }
            if !skills.isEmpty {
                groups.append(SkillGroup(kind: kind.rawValue, icon: icon, title: title, skills: skills))
                seenKinds.insert(kind)
            }
        }

        for skill in filtered where !seenKinds.contains(skill.sourceKind) {
            groups.append(SkillGroup(kind: skill.sourceKind.rawValue, icon: "questionmark", title: "Other", skills: [skill]))
            seenKinds.insert(skill.sourceKind)
        }

        if !snapshot.builtinSkills.isEmpty {
            let buFiltered = snapshot.builtinSkills.filter { b in
                if searchText.isEmpty { return true }
                return b.name.lowercased().contains(searchText.lowercased())
            }
            if !buFiltered.isEmpty {
                groups.append(SkillGroup(kind: "builtin", icon: "cube", title: "Built-in Skills", skills: buFiltered))
            }
        }

        return groups
    }

    private func matchesFilter(_ skill: OpenCodeSkillRecord) -> Bool {
        if let kind = filterSourceKind, skill.sourceKind != kind { return false }
        if let state = filterState, skill.manifest.state != state { return false }
        if filterOnlyIssues && skill.manifest.issues.isEmpty { return false }
        if !searchText.isEmpty {
            let lower = searchText.lowercased()
            if !skill.name.lowercased().contains(lower)
                && !(skill.manifest.description?.lowercased().contains(lower) ?? false) {
                return false
            }
        }
        return true
    }
}

extension OpenCodeSkillSourceKind {
    static var allCases: [OpenCodeSkillSourceKind] {
        [.opencodePlural, .opencodeSingular, .claude, .agents, .configSkillsPath, .customConfigDir, .builtin]
    }

    var shortLabel: String {
        switch self {
        case .opencodePlural: "opencode"
        case .opencodeSingular: "legacy"
        case .claude: "claude"
        case .agents: "agents"
        case .configSkillsPath: "path"
        case .customConfigDir: "custom"
        case .builtin: "built-in"
        }
    }

    var color: Color {
        switch self {
        case .opencodePlural: .blue
        case .opencodeSingular: .blue.opacity(0.6)
        case .claude: .orange
        case .agents: .purple
        case .configSkillsPath: .teal
        case .customConfigDir: .mint
        case .builtin: .gray
        }
    }
}
