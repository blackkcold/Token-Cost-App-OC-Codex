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
            Text(AppLocalization.text("skills.scanning"))
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
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(palette.surfaceFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(palette.surfaceStroke, lineWidth: 0.8)
                    )
                    .shadow(color: palette.surfaceShadow, radius: 10, x: 0, y: 6)
            )
        }
    }

    private var notInstalledView: some View {
        VStack(spacing: 20) {
            Image(systemName: "gearshape.2")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(AppLocalization.text("skills.notInstalled.title"))
                .font(.title2)
            Text(AppLocalization.text("skills.notInstalled.body"))
                .foregroundStyle(.secondary)
            Text(AppLocalization.text("skills.notInstalled.hint"))
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
        .settingsInsetSurface(
            in: Rectangle(),
            palette: palette
        )
    }

    private func headerView(_ snapshot: OpenCodeSkillsReadOnlySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(AppLocalization.text("skills.header.title"))
                    .font(.headline)
                Spacer()
                Text(AppLocalization.text("skills.header.readOnly"))
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(palette.accent.opacity(0.15)))
                    .foregroundStyle(palette.accent)
            }
            Text(AppLocalization.format("skills.header.summary", snapshot.discoveredSkills.count, snapshot.builtinSkills.count))
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
                TextField(AppLocalization.text("skills.filter.placeholder"), text: $searchText)
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
                    filterChip(AppLocalization.text("skills.filter.all"), isActive: filterSourceKind == nil && filterState == nil && !filterOnlyIssues) {
                        filterSourceKind = nil; filterState = nil; filterOnlyIssues = false
                    }
                    ForEach(OpenCodeSkillSourceKind.allCases, id: \.self) { kind in
                        filterChip(kind.shortLabel, isActive: filterSourceKind == kind) {
                            if filterSourceKind == kind { filterSourceKind = nil }
                            else { filterSourceKind = kind }
                        }
                    }
                    Menu {
                        Button(AppLocalization.text("skills.filter.anyState")) { filterState = nil }
                        Button(AppLocalization.text("skills.filter.validOnly")) { filterState = .valid }
                        Button(AppLocalization.text("skills.filter.warning")) { filterState = .warning }
                        Button(AppLocalization.text("skills.filter.invalid")) { filterState = .invalid }
                    } label: {
                        filterChip(filterState?.rawValue ?? AppLocalization.text("skills.filter.state"), isActive: filterState != nil, isMenu: true) {}
                    }
                    filterChip(AppLocalization.text("skills.filter.issues"), isActive: filterOnlyIssues) {
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
                Text(AppLocalization.text("skills.filter.empty")).foregroundStyle(.secondary)
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
                Text(AppLocalization.text("skills.overview.title"))
                    .font(.title2).padding(.bottom, 4)

                configSummarySection(snapshot)
                agentMatrixSection(snapshot)
                desktopSkillLockSection(snapshot)
                ohMyOpenAgentSection(snapshot)
                diagnosticsSection(snapshot)
            }
            .padding(24)
        }
    }

    private func skillDetailView(_ skill: OpenCodeSkillRecord, snapshot: OpenCodeSkillsReadOnlySnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Button {
                        selectedSkillID = nil
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text(AppLocalization.text("skills.detail.backToOverview"))
                        }
                        .font(.subheadline)
                        .foregroundStyle(palette.accent)
                    }
                    .buttonStyle(.plain)
                    .help("Back to skills overview")
                    statusDot(skill.manifest.state)
                    Text(verbatim: skill.name).font(.title3.weight(.semibold))
                    Spacer()
                    sourceChip(skill.sourceKind)
                }

                if let desc = skill.manifest.description {
                    detailCard(icon: "doc.text", title: AppLocalization.text("skills.detail.description")) {
                        Text(verbatim: desc).font(.callout)
                    }
                }

                if !skill.manifest.extraFields.isEmpty {
                    detailCard(icon: "tag", title: AppLocalization.text("skills.detail.metadata")) {
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
                    detailCard(icon: "book.pages", title: AppLocalization.text("skills.detail.skillContent")) {
                        let preview = bodyExpanded ? body : String(body.prefix(300))
                        let needsToggle = body.count > 300
                        Text(verbatim: preview)
                            .font(.caption)
                            .monospaced()
                            .foregroundStyle(.secondary)
                        if needsToggle {
                            Button { withAnimation { bodyExpanded.toggle() } } label: {
                                Text(verbatim: bodyExpanded ? AppLocalization.text("common.collapse") : AppLocalization.format("skills.detail.expandAll", body.count))
                                    .font(.caption2)
                                    .foregroundStyle(palette.accent)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                    }
                }

                if let license = skill.manifest.license {
                    infoLine(AppLocalization.text("skills.detail.license"), license)
                }
                if let compat = skill.manifest.compatibility {
                    infoLine(AppLocalization.text("skills.detail.compatibility"), compat)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(AppLocalization.text("skills.detail.source")).font(.caption2).foregroundStyle(.tertiary)
                    Text(verbatim: skill.displayPath).font(.caption2).monospaced().foregroundStyle(.tertiary)
                }

                if skill.isSymlink, let target = skill.targetCanonicalPath {
                    Text(verbatim: "→ \(target)").font(.caption2).foregroundStyle(.tertiary)
                }

                if let lockEntry = snapshot.desktopSkillLock.entries.first(where: { $0.name == skill.name }) {
                    desktopSkillInstallCard(lockEntry)
                }

                if !skill.duplicatePaths.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(AppLocalization.text("skills.detail.duplicates")).font(.caption).foregroundStyle(.orange)
                        ForEach(skill.duplicatePaths, id: \.self) { Text(verbatim: $0).font(.caption2).monospaced().foregroundStyle(.secondary) }
                    }
                }

                if !skill.manifest.issues.isEmpty {
                    detailCard(icon: "exclamationmark.triangle", title: AppLocalization.text("skills.detail.issues")) {
                        ForEach(skill.manifest.issues) { issue in
                            HStack(spacing: 6) {
                                Circle().fill(issue.severity == .error ? .red : issue.severity == .warning ? .yellow : .blue).frame(width: 6, height: 6)
                                Text(verbatim: issue.message).font(.caption)
                            }
                        }
                    }
                }

                if !skill.manifest.unknownFieldKeys.isEmpty {
                    Text(AppLocalization.format("skills.detail.unknownFields", skill.manifest.unknownFieldKeys.joined(separator: ", "), skill.manifest.unknownFieldKeys.count))
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
        .settingsInsetSurface(
            in: RoundedRectangle(cornerRadius: 14, style: .continuous),
            palette: palette
        )
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
                    Text(AppLocalization.text("skills.permission.resolved")).font(.caption)
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
        detailCard(icon: "gearshape.2", title: AppLocalization.text("skills.overview.configLayers")) {
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
            if !snapshot.skillsPathsEntries.isEmpty || !snapshot.skillsUrlsEntries.isEmpty {
                Divider().opacity(0.3)
                if !snapshot.skillsPathsEntries.isEmpty {
                    Text(AppLocalization.format("skills.config.pathsEntries", snapshot.skillsPathsEntries.count)).font(.caption2).foregroundStyle(.secondary)
                }
                if !snapshot.skillsUrlsEntries.isEmpty {
                    Text(AppLocalization.format("skills.config.urlsEntries", snapshot.skillsUrlsEntries.count)).font(.caption2).foregroundStyle(.orange)
                }
            }
        }
    }

    private var agentCardColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 200), spacing: 6, alignment: .top)]
    }

    private func agentMatrixSection(_ snapshot: OpenCodeSkillsReadOnlySnapshot) -> some View {
        detailCard(icon: "cpu", title: AppLocalization.text("skills.overview.agentMatrix")) {
            LazyVGrid(columns: agentCardColumns, alignment: .leading, spacing: 6) {
                ForEach(snapshot.agentMatrix) { agent in
                    HStack(spacing: 6) {
                        Circle().fill(agent.skillToolAvailable ? .green : .red).frame(width: 7, height: 7)
                        Text(verbatim: agent.agent.rawValue).font(.caption)
                        if let note = agent.note {
                            Text(verbatim: note).font(.caption2).foregroundStyle(.orange).lineLimit(1)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.secondary.opacity(0.05)))
                }
            }
        }
    }

    @ViewBuilder
    private func desktopSkillLockSection(_ snapshot: OpenCodeSkillsReadOnlySnapshot) -> some View {
        if snapshot.desktopSkillLock.detected {
            detailCard(icon: "shippingbox", title: AppLocalization.text("skills.overview.desktopSkillLock")) {
                HStack(spacing: 8) {
                    Circle().fill(snapshot.desktopSkillLock.parseError == nil ? .green : .red).frame(width: 8, height: 8)
                    Text(AppLocalization.format("skills.desktopSkillLock.version", snapshot.desktopSkillLock.version.map(String.init) ?? "unknown"))
                        .font(.caption)
                    Text(AppLocalization.format("skills.desktopSkillLock.installedRecords", snapshot.desktopSkillLock.entries.count))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let error = snapshot.desktopSkillLock.parseError {
                    Text(verbatim: error).font(.caption2).foregroundStyle(.red)
                }
                ForEach(snapshot.desktopSkillLock.entries.prefix(6)) { entry in
                    desktopSkillLockRow(entry)
                }
            }
        }
    }

    private func desktopSkillInstallCard(_ entry: OpenCodeDesktopSkillLockEntry) -> some View {
        detailCard(icon: "shippingbox", title: AppLocalization.text("skills.detail.installedSource")) {
            VStack(alignment: .leading, spacing: 4) {
                infoLine(AppLocalization.text("skills.detail.source"), entry.source ?? "unknown")
                if let sourceType = entry.sourceType { infoLine(AppLocalization.text("skills.detail.sourceType"), sourceType) }
                if let pluginName = entry.pluginName { infoLine(AppLocalization.text("skills.detail.plugin"), pluginName) }
                if let updatedAt = entry.updatedAt {
                    HStack(spacing: 6) {
                        Text(AppLocalization.text("skills.detail.updated")).font(.caption).foregroundStyle(.secondary)
                        Text(updatedAt, style: .date).font(.caption)
                    }
                }
            }
        }
    }

    private func desktopSkillLockRow(_ entry: OpenCodeDesktopSkillLockEntry) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: entry.name).font(.caption.weight(.medium))
            if let sourceType = entry.sourceType {
                Text(verbatim: sourceType).font(.caption2).foregroundStyle(.secondary)
            }
            if let source = entry.source {
                Text(verbatim: source).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func ohMyOpenAgentSection(_ snapshot: OpenCodeSkillsReadOnlySnapshot) -> some View {
        if snapshot.ohMyOpenAgent.detected {
            detailCard(icon: "point.3.connected.trianglepath.dotted", title: AppLocalization.text("skills.overview.omo")) {
                if let error = snapshot.ohMyOpenAgent.parseError {
                    Text(verbatim: error).font(.caption2).foregroundStyle(.red)
                } else {
                    Text(AppLocalization.format("skills.omo.agentsCategories", snapshot.ohMyOpenAgent.agentOverrides.count, snapshot.ohMyOpenAgent.categoryOverrides.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: agentCardColumns, alignment: .leading, spacing: 6) {
                        ForEach(snapshot.ohMyOpenAgent.agentOverrides.prefix(12)) { agent in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Circle().fill(agent.disabled ? .red : .green).frame(width: 6, height: 6)
                                    Text(verbatim: agent.name).font(.caption.weight(.medium)).lineLimit(1)
                                }
                                if let model = agent.model {
                                    Text(verbatim: model).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                                if !agent.skillNames.isEmpty {
                                    Text(verbatim: "skills: \(agent.skillNames.joined(separator: ", "))").font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(.secondary.opacity(0.05)))
                        }
                    }
                    if !snapshot.ohMyOpenAgent.categoryOverrides.isEmpty {
                        Text(verbatim: "Categories: \(snapshot.ohMyOpenAgent.categoryOverrides.map(\.name).joined(separator: ", "))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func backupManagerSection(_ snapshot: OpenCodeSkillsReadOnlySnapshot) -> some View {
        if !snapshot.backupFiles.isEmpty {
            detailCard(icon: "clock.arrow.circlepath", title: AppLocalization.text("skills.overview.backupManager")) {
                Text(AppLocalization.format("skills.backup.readOnlyComparison", snapshot.backupFiles.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(snapshot.backupFiles.prefix(8)) { file in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(verbatim: file.fileName).font(.caption.weight(.medium)).lineLimit(1)
                            Text(verbatim: file.parseStatus).font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            if let modifiedAt = file.modifiedAt {
                                Text(modifiedAt, style: .date).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        Text(verbatim: "→ \(file.targetName): \(file.diffSummary)").font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        if !file.changedKeySamples.isEmpty {
                            Text(verbatim: file.changedKeySamples.joined(separator: ", "))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.secondary.opacity(0.05)))
                }
            }
        }
    }

    @ViewBuilder
    private func diagnosticsSection(_ snapshot: OpenCodeSkillsReadOnlySnapshot) -> some View {
        if !snapshot.diagnostics.isEmpty {
            detailCard(icon: "exclamationmark.triangle", title: AppLocalization.text("skills.overview.diagnostics")) {
                ForEach(snapshot.diagnostics) { diagnostic in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: diagnosticIcon(diagnostic.severity)).font(.caption2).foregroundStyle(diagnosticColor(diagnostic.severity))
                            Text(verbatim: diagnostic.title).font(.caption.weight(.medium))
                            Text(verbatim: diagnostic.severity.rawValue).font(.caption2).foregroundStyle(diagnosticColor(diagnostic.severity))
                            Spacer()
                        }
                        Text(verbatim: diagnostic.message).font(.caption2).foregroundStyle(.secondary)
                        Text(verbatim: "Impact: \(diagnostic.impact)").font(.caption2).foregroundStyle(.tertiary)
                        Text(verbatim: "Suggestion: \(diagnostic.recommendation)").font(.caption2).foregroundStyle(.tertiary)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.secondary.opacity(0.05)))
                }
            }
        }
    }

    private func diagnosticIcon(_ severity: OpenCodeSkillDiagnosticSeverity) -> String {
        switch severity {
        case .info: "info.circle"
        case .warning: "exclamationmark.triangle"
        case .error: "xmark.octagon"
        }
    }

    private func diagnosticColor(_ severity: OpenCodeSkillDiagnosticSeverity) -> Color {
        switch severity {
        case .info: .blue
        case .warning: .yellow
        case .error: .red
        }
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
            (.opencodePlural, "folder", AppLocalization.text("skills.section.opencodePlural")),
            (.opencodeSingular, "folder", AppLocalization.text("skills.section.opencodeSingular")),
            (.claude, "link", AppLocalization.text("skills.section.claude")),
            (.agents, "person.2", AppLocalization.text("skills.section.agents")),
            (.configSkillsPath, "tray", AppLocalization.text("skills.section.configSkillsPath")),
            (.customConfigDir, "externaldrive", AppLocalization.text("skills.section.customConfigDir")),
            (.builtin, "cube", AppLocalization.text("skills.section.builtin")),
        ]

        for (kind, icon, title) in kindOrder {
            let skills = filtered.filter { $0.sourceKind == kind }
            if !skills.isEmpty {
                groups.append(SkillGroup(kind: kind.rawValue, icon: icon, title: title, skills: skills))
                seenKinds.insert(kind)
            }
        }

        for skill in filtered where !seenKinds.contains(skill.sourceKind) {
            groups.append(SkillGroup(kind: skill.sourceKind.rawValue, icon: "questionmark", title: AppLocalization.text("skills.section.other"), skills: [skill]))
            seenKinds.insert(skill.sourceKind)
        }

        if !snapshot.builtinSkills.isEmpty {
            let buFiltered = snapshot.builtinSkills.filter { b in
                if searchText.isEmpty { return true }
                return b.name.lowercased().contains(searchText.lowercased())
            }
            if !buFiltered.isEmpty {
                groups.append(SkillGroup(kind: "builtin", icon: "cube", title: AppLocalization.text("skills.section.builtin"), skills: buFiltered))
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
