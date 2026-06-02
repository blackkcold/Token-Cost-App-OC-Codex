# OpenCode Desktop Global Skills Manager v0.7.0 — Read-only Only Implementation Plan

> Status: scoped implementation plan, R1 audit complete
> Target: v0.7.0 / Unreleased
> Scope: OpenCode Desktop global Skills baseline panel only
> Mode: read-only only
> Supersedes for v0.7.0 implementation scope: writeback-heavy `skills-manager-v0.7.0.md` delivery plan
> Docs freshness: checked against official OpenCode config / skills / permissions docs on 2026-06-02
> Audit: R1 audit 2026-06-02 (20 issues, all resolved) + R2 final audit 2026-06-02 (10 new issues N1–N10, all resolved inline) + R3 audit 2026-06-02 (H1–H5 + M1/M3/M5/M6, 9 fixes applied — managed/MDM bundle IDs fixed, redaction upgraded to substring match, shell profile hints removed) + R4 final P0/P1 closure 2026-06-02 (unknown frontmatter values hidden, manifest validation aligned with official docs, JSONC parser requirement added, fixture-only tests required, scalar `permission.skill` clarified) + R5 cross-verification 2026-06-02 (top-level scalar `permission` handling and `skills.paths`/`skills.urls` config scanning added) + R6 final P0 closure 2026-06-02 (restored `config.json` config candidate per current OpenCode source, added `permission` object wildcard handling, corrected native agent matrix defaults, added agent-level scalar/object permission handling, added legacy top-level/agent `tools` handling, documented Desktop Application Support local-state exclusion)

## 1. Requirement Convergence

The v0.7.0 feature is limited to a read-only OpenCode Desktop global Skills baseline panel.

Important wording rule: do not call the result "final effective project availability". The panel only explains the global baseline plus any read-only override signals that can be detected safely. Project config, managed config, MDM, inline config, and runtime context can still change the final OpenCode behavior.

| Item | Decision |
|---|---|
| Product surface | New Skills tab/panel in this app |
| Managed target | OpenCode Desktop global skills baseline only |
| Data mode | Read-only discovery, parsing, validation, and explanation |
| Writeback | Not included in v0.7.0 |
| Future writeback exploration | Not included in v0.7.0. If explored later, every edit must run only against anonymized temp-folder copies and pass manual testing before any real writeback development begins. |
| Runtime mutation | Not included |
| Cleanup | Not included |
| Installation/removal | Not included |

The panel should help the user answer:

- Which global OpenCode skills are installed.
- Which built-in OpenCode skills are available but not disk-installed.
- Where each skill was discovered.
- Whether each `SKILL.md` manifest is valid or suspicious.
- How global `permission`, `permission.skill`, agent-level permission, and legacy `tools` signals currently affect baseline skill availability.
- Why a skill appears available, denied, overridden, duplicated, invalid, or read-only.
- Which higher-precedence or out-of-scope sources may make the final project runtime result different.

### 1.1 Pre-Implementation Risk & Issues Catalog

The following risks were identified during R1 cross-verification audit. Items marked **CRITICAL** block Phase 0 completion; items marked **HIGH** must be resolved before Phase 1 coding begins; items marked **MEDIUM** are implementation-phase decisions.

| # | Severity | Issue | Location | Resolution |
|---|---|---|---|---|
| R1 | **CRITICAL** | Public docs (README, CHANGELOG, SECURITY) claim writeback exists but code is read-only | §10 Phase 0 | Execute Phase 0 doc reset immediately. See §10.1 for exact changes needed. |
| R2 | **CRITICAL** | `skills-manager-v0.7.0.md` (756 lines, R8 final) still claims authoritative status and contains full writeback plan | `.sisyphus/plans/` | Add SUPERSEDED header to that file pointing to this one |
| R3 | **CRITICAL** | `docs/开发手册.md` §8 and `docs/功能模块关联清单.md` §2.8 lack any mention of v0.7.0 Skills panel | `docs/` | Add read-only Skills panel entries. See §10.2. |
| R4 | HIGH | "OpenCode installed" criteria undefined — what triggers `notInstalled` state? | §2, §7.2 | Defined in §5.3: `~/.config/opencode/` directory exists. Binary presence is a separate informational signal, not a gate. |
| R5 | HIGH | Config file priority when both `opencode.json` and `opencode.jsonc` exist is not specified | §5.2 | Defined in §5.2: scan both independently, show both as separate config layers with `jsoncConfig` warning on `.jsonc` variant. Actual OpenCode priority is version-dependent; do not assert which "wins." |
| R6 | HIGH | Agent override signals in `oh-my-openagent.json` are completely invisible to the panel | §8.3 | Documented limitation: panel reads global config only. Show explicit warning "Agent-level overrides in oh-my-openagent.json not scanned in v0.7.0." |
| R7 | HIGH | Duplicate skill "winner" logic undefined — which copy is shown as primary? | §6.1, §7.2 | Primary display: first skill found in scan order (OpenCode plural → singular → Claude → Agents). All duplicates listed in detail view with source paths. No "winner" implied. |
| R8 | HIGH | `~/.config/opencode/skill/` (singular) semantic relationship to `skills/` (plural) undefined | §5.1 | Both scanned independently. Skills found in both are treated as duplicates. Singular directory is a legacy/alternative layout; no priority weighting. |
| R9 | HIGH | YAML frontmatter parsing failure modes not enumerated | §6.1, §11 | Defined in §6.3: malformed YAML → `yamlParseError` state (shown, not hidden); empty file → `skillInvalid`; non-UTF-8 → `skillInvalid` with "Unsupported encoding" note; multiple `---` blocks → parse first block only. |
| R10 | HIGH | symlink resolution "allowed root" not defined | §7.2 | Defined in §5.1: allowed roots are `~/.config/opencode/`, `~/.claude/`, `~/.agents/`. Symlinks resolving outside these trees → `outsideAllowedRoot`. Symlinks resolving within these trees but to different source trees → `symlinkDuplicate`. |
| R11 | MEDIUM | No performance budget for scanning 4 directories + YAML parsing | §6 | Implementation decision: scan is O(n) where n = number of SKILL.md files (typically < 50). No timeout needed for v0.7.0. Add 5-second timeout per directory scan as safety net. |
| R12 | MEDIUM | Unreadable SKILL.md (permission denied) has no defined state | §7.2 | Added: `inaccessiblePath` state. Show file path with "Permission denied" note, exclude from skill list, include in warning section. |
| R13 | MEDIUM | `OPENCODE_CONFIG_DIR` skills scan behavior was not verifiable in R1 | §5.1 | Resolved in R6: current OpenCode skill discovery scans config directories for `{skill,skills}/**/SKILL.md`; v0.7.0 scans the env custom directory read-only when present and labels it as runtime-context data. |
| R14 | MEDIUM | Managed/MDM config detection methodology missing | §5.2, §7.2 | Implementation decision: check `/Library/Application Support/opencode/` directory (file-based) and `/Library/Managed Preferences/ai.opencode.managed.plist` (MDM). If found → `managedScopeDetected` warning. Bundle IDs: `ai.opencode.desktop` (prod/beta/dev) per OpenCode Desktop source. This is a heuristic, not exhaustive. |
| R15 | MEDIUM | Localization key list not specified | §2 | Provided in §7.4 as a minimum key list. Exact count must be recalculated after R6 additions during implementation. |
| R16 | MEDIUM | Skills tab toolbar behavior undefined | §7.1 | Defined: Skills tab shows independent "Refresh Skills" button. Does not trigger token DB rescan. See §7.1 toolbar specification. |
| R17 | MEDIUM | Lazy load implementation strategy not specified | §10 Phase 2 | Defined: `OpenCodeSkillsModel` created as `@StateObject` at app init (matching existing 5-StateObject pattern) but scan is deferred to `onAppear` of Skills tab. Model holds a `nil` snapshot until first scan. |
| R18 | MEDIUM | Snapshot persistence vs re-scan tradeoff | §4, §10 Phase 2 | Decision: scan on every tab activation for v0.7.0. No persistence. Add explicit "Refresh" button. Rationale: read-only data is small (~50 files max), scan is fast, and avoids staleness from config changes between app launches. |
| R19 | LOW | 37 historical .bak files in `~/.config/opencode/` may confuse users | §3, §7.1 | Show informational warning in warning section: "N historical backup files detected in OpenCode config directory. These may contain sensitive data. Cleanup requires separate operation." No action button. |
| R20 | LOW | `mmx-cli` symlink case (`~/.claude/skills/mmx-cli → ../../.agents/skills/mmx-cli`) is a known real-world duplicate | §5.1, §11 | Add as explicit test case in discovery tests. Symlink canonicalization must handle relative symlinks correctly. |
| N1 | LOW | CHANGELOG L14 describes "Agent 可用性矩阵（Build/Plan/General/Explore）" — only 4 agents, but §8.2 defines 8 agents | §10 Phase 0.1 | Phase 0.1 CHANGELOG fix must also correct agent count from 4 to 8. |
| N2 | MEDIUM | Missing `noSkillsFound` state — what to show when OpenCode installed but 0 SKILL.md files discovered | §7.2 | Added: `noSkillsFound` state. Panel shows "No global skills found in scanned directories" with list of scanned paths. |
| N3 | MEDIUM | Missing localization keys for 7 §7.2 states: `yamlParseError`, `brokenSymlink`, `symlinkDuplicate`, `schemaUnknown`, `customConfigDirDetected`, `inlineConfigDetected`, `noSkillsFound` | §7.4 | Added 7 new local keys to §7.4. |
| N4 | MEDIUM | Directory scan failure (e.g., `FileManager.contentsOfDirectory` throws on unreadable directory) has no defined behavior | §5.1 | Defined: directory-level read failure → scanned directory excluded with warning. This is separate from per-file `inaccessiblePath`. All excluded directories listed in warning section. |
| N5 | MEDIUM | Invalid JSON / JSONC in config candidates parse failure behavior undefined | §5.2 | Defined: JSON/JSONC parse failure after the appropriate parser → `invalidConfigJson` state. File shown with parse error message; `permission`, legacy `tools`, `agent`, and `skills` sections are treated as absent for that layer. |
| N6 | **CRITICAL** | SKILL.md frontmatter unknown fields are displayed but OpenCode ignores them; displaying values can leak secrets under innocent-looking keys | §6.3, §9 | Final resolution: unknown frontmatter values are never displayed, logged, persisted, copied, or included in diagnostics. Show only unknown key names and count. Official display fields are redacted/truncated before display. |
| N7 | LOW | Duplicate detection is by skill `name` only, not content hash — intentionally distinct copies with same name would be grouped | §6.1 | Accepted as design choice. Detail view shows all source paths with warning "Skills share the same name but may have different content." |
| N8 | LOW | Within-directory scan order undefined — affects primary display since §6.1 uses "first occurrence in scan order" | §5.1 | Defined: within each directory, scan in alphabetical order of SKILL.md parent directory name (consistent, reproducible). |
| N9 | LOW | §10 Phase 3 says "Add fourth TabView item" — assumes exactly 3 existing tabs | §10 Phase 3 | Clarified: "Add Skills tab item to TabView (appends to existing tab count)." Implementation should read existing tab count from CodexDashboardPage enum, not hardcode "fourth." |
| N10 | LOW | `.sisyphus/plans/skills-manager-v0.7.0.backup-20260602-desktop-readonly.md` backup file not mentioned in Phase 0.3 | §10 Phase 0.3 | Phase 0.3 now mentions: "The `...backup-...` file is retained for historical audit trail. No action required." |
| F1 | **CRITICAL** | Unknown frontmatter values could leak secrets even with substring-key redaction | §6.3, §9 | Values for unknown/non-standard frontmatter fields are never rendered. This is stricter than OpenCode, which ignores unknown fields. |
| F2 | HIGH | Manifest validation was weaker than official OpenCode rules (`description` required, `name` regex/length/directory match, `description` length) | §6.3, §11 | Align validation with official Skills docs: non-compliant records are `skillInvalid` and excluded from permission matching. |
| F3 | HIGH | Unit tests were tied to real `~/.config/opencode`, `~/.claude`, and `~/.agents` paths via `swift test --disable-sandbox` | §11, §12 | Core tests must use injected temp fixture roots only. Real home scanning is app-runtime behavior and optional manual QA, never a unit-test prerequisite. |
| F4 | HIGH | JSONC support could be implemented as plain JSON parsing and incorrectly downgrade valid JSONC to invalid/absent | §5.2, §11 | Require a JSONC-capable parser for `.jsonc` and commented/trailing-comma `.json` files. Parse failure after JSONC parsing becomes `invalidConfigJson`. |
| F5 | MEDIUM | Local `permission.skill` can be scalar string; object-only readers would misrepresent baseline | §8.1, §11 | Scalar `"allow"`, `"ask"`, or `"deny"` means the same action applies to every skill in that layer. Object form remains ordered pattern rules. No migration/writeback exists in v0.7.0. |
| F6 | **CRITICAL** | Current OpenCode source still loads `~/.config/opencode/config.json` before `opencode.json` and `opencode.jsonc`; excluding it can miss the only configured skill permission layer | §5.2, §11 | Restore `config.json` as a read-only global config candidate. Parse it with the same JSON/JSONC-capable parser and show it as a separate compatibility layer. |
| F7 | **CRITICAL** | `permission` object-level wildcard rules are not covered; `permission: {"*": "deny"}` would be misread as absent `permission.skill` and shown as implicit allow | §8.1, §11 | Resolve skill permission through the full `permission` object: preserve top-level entry order, match permission-key patterns against `skill`, support scalar actions and nested `skill` object rules, and apply last-match-wins. |
| F8 | **CRITICAL** | Agent-level scalar/object permission rules are not covered; `agent.*.permission = "deny"` or `agent.*.permission: {"*": "deny"}` can disable skills for an agent | §8.2, §8.3, §11 | Agent matrix must merge native agent permission defaults, global `permission`, and `agent.*.permission` scalar/object overrides before reporting skill availability. |
| F9 | **CRITICAL** | Legacy `tools` config is still officially supported and can disable the skill tool; the plan only handled `agent.*.tools.skill=false` | §8.1, §8.3, §11 | Detect top-level and agent-level `tools.skill=false` / `tools.*=false` as legacy tool-disable signals. A matching false legacy tool rule marks the skill tool unavailable for the affected baseline/agent and shows a deprecation warning. |
| F10 | HIGH | Native agent matrix incorrectly treats every built-in agent as `skill` allow by default | §8.2, §11 | Correct native defaults from current OpenCode source: build/plan/general inherit skill allow unless overridden; explore/scout/compaction/title/summary contain `* deny` native rules, so skill is denied unless later user/global/agent permission rules explicitly allow it. |
| F11 | MEDIUM | `OPENCODE_CONFIG_DIR` skill scanning was left as presence-only even though current OpenCode skill discovery scans config directories for `{skill,skills}/**/SKILL.md` | §5.1, §11 | When `OPENCODE_CONFIG_DIR` is present, scan its `{skill,skills}/` subtrees read-only, label them as runtime custom-dir sources, and keep the global-baseline warning. |
| F12 | LOW | Desktop Application Support local state (`~/Library/Application Support/ai.opencode.desktop/skills/.skill-lock.json`, `opencode.global.dat`) is not explicitly excluded | §3, §5.1, §7.2 | Do not read Desktop local-state values for v0.7.0. Detect presence only, show an informational "Desktop local state ignored" note, and do not treat it as an installed skill source. |

## 2. In Scope

| Area | Read-only behavior |
|---|---|
| OpenCode detection | Detect whether OpenCode Desktop/OpenCode config exists; show not-installed or not-configured state |
| Global skill discovery | Scan known global skill locations, `OPENCODE_CONFIG_DIR` skill subtrees when present, and config `skills.paths` |
| Built-in skill signal | Show built-in OpenCode skills such as `customize-opencode` as non-disk, read-only, non-manageable signals |
| Manifest parsing | Parse `SKILL.md` frontmatter and show validation results |
| Duplicate detection | Canonicalize paths, resolve symlinks, and show duplicates without changing disk state |
| Config reading | Read global config candidates (`config.json`, `opencode.json`, `opencode.jsonc`) and selected higher-precedence signals without mutating them |
| Rule explanation | Show ordered global rule chain, wildcard matching, last-match-wins result, and implicit default |
| Agent matrix | Show Build / Plan / General / Explore / Scout / Compaction / Title / Summary baseline availability |
| Agent override signals | Read and explain global config `agent.*.permission` scalar/object rules and `agent.*.tools` legacy disable signals if present |
| Legacy tool signals | Detect top-level and agent-level legacy `tools.skill=false` / `tools.*=false` as read-only availability blockers |
| Environment signals | Detect `OPENCODE_CONFIG`, `OPENCODE_CONFIG_DIR`, and `OPENCODE_CONFIG_CONTENT` presence without rendering secrets |
| Warnings | Show JSONC, unknown schema, custom config, remote URLs, symlink, duplicate, project-scope, and managed-scope warnings |
| Localization | Add Chinese and English strings for the new panel |
| Documentation | Update README / CHANGELOG / SECURITY / docs to clearly state read-only-only scope |

### 2.1 Cross-Verification Findings (R1 Audit)

#### 2.1.1 Documentation Coherence

| Document | Current Claim | vs Readonly Plan | Action |
|---|---|---|---|
| README.md L13 | "受限写入" | ❌ Conflict | Rewrite to read-only |
| README.md L15 | "受限写入" | ❌ Conflict | Rewrite to read-only |
| CHANGELOG.md L14 | "受限写入 permission.skill 子树" | ❌ Conflict | Remove writeback description |
| CHANGELOG.md L25-26 | "Product Security Posture Change" + 5 mechanisms | ❌ Conflict | Delete entire Security paragraph |
| SECURITY.md L7 | "新增 Skills 权限受限写入" | ❌ Conflict | Change to read-only |
| SECURITY.md L28-37 | 8 writeback security measures | ❌ Conflict | Delete, replace with read-only statement |
| docs/开发手册.md L360-361 | "只读…不修改任何源数据" | ✅ Consistent | Add Skills panel mention |
| docs/功能模块关联清单.md L97 | "所有源数据只读" | ✅ Consistent | Add Skills panel section |

#### 2.1.2 Plan Document Coherence

| Document | Status | Writeback | Relationship to this plan |
|---|---|---|---|
| `skills-manager-plan.md` | SUPERSEDED (v0.5.1) | Yes | Predecessor, ignore |
| `skills-manager-v0.6.0.md` | SUPERSEDED (v0.6.0) | Yes | Predecessor, ignore |
| `skills-manager-v0.7.0.md` | R8 Final Audit (756 lines) | **Yes — complete** | Conflicts. Must be marked SUPERSEDED. |
| `skills-manager-v0.7.0-readonly.md` | **This file** | **No** | **Authoritative** |

#### 2.1.3 Code-Plan Gap

| What | Expected | Actual |
|---|---|---|
| Skills source files (.swift) | 6 files per §6.2 | **0 files** |
| Skills test files | 8 test areas per §11 | **0 files, 0 test functions** |
| `CodexDashboardPage.skills` case | New enum case | **Not added** |
| Skills localization strings | 45 new keys | **0 keys** |
| Phase 0 doc reset | Completed | **Not started** |

**Conclusion**: The entire module is unimplemented. Phase 0 (documentation reset) must execute before any code is written.

## 3. Out of Scope

| Area | Reason |
|---|---|
| Writing `permission.skill` | Deferred until text patch, backup, redaction, and TOCTOU controls are proven separately |
| Creating `opencode.json` | Avoid changing OpenCode behavior or creating incomplete configs |
| Editing `oh-my-openagent.json` | Agent skill whitelist is separate from global skill permission |
| Editing MCP/provider/agent/plugin config | User requirement is skill panel only |
| Project-level skill management | v0.7.0 is global-only |
| Final project effective availability | Requires project root, runtime config merge, inline config, and managed/MDM context |
| Managed/MDM/custom config writeback | Higher-risk config layers |
| Skill install/delete/update | Avoid destructive and network-adjacent behavior |
| Remote `skills.urls` fetch | Show warning only; do not download |
| Desktop Application Support local state | `~/Library/Application Support/ai.opencode.desktop/` contains Desktop cache, lock, and UI state. v0.7.0 detects presence only and does not read values or treat it as a skill source. |
| `.bak` cleanup | Requires separate explicit user approval because it deletes user files |
| Keychain/browser/cookie access | Irrelevant to skills panel |
| Reading full `OPENCODE_CONFIG_CONTENT` | Can contain secrets and is runtime-specific; detect presence only |

## 4. Hard Safety Boundary

The implementation must not:

- Modify any file under `~/.config/opencode/`.
- Modify any file under `~/.agents/`, `~/.claude/`, or project directories.
- Create, delete, rename, move, or chmod skill/config files.
- Write backup files for OpenCode config.
- Print, log, render, or persist secrets from config files.
- Execute OpenCode, package managers, or shell commands from the app.
- Fetch remote skill indexes or remote skill content.
- Treat Codex skills as OpenCode Desktop skills.
- Claim that global baseline state equals final project runtime availability.
- Render raw `OPENCODE_CONFIG_CONTENT` or raw config snippets.

The only app writes allowed for this feature are app-local UI preferences such as search/filter state under this app's existing Application Support boundary. Do not persist parsed OpenCode config snapshots for v0.7.0 unless there is a separately approved UX requirement.

### 4.1 Safety Boundary Pre-Check (R1 Audit)

Running the §13 checklist against the **current pre-implementation state** (zero Skills code):

| §13 Check | Pre-Implementation Status | Notes |
|---|---|---|
| Writer type scan | ✅ Pass (no code exists) | No OpenCodeConfigEditor, text patcher, backup/rollback/config writers |
| Forbidden API scan | ✅ Pass (no Skills code) | Existing app code (SafeFileStore, UpdateChecker, BrowserCookieExtractor) writes only to app sandbox, never to ~/.config/opencode/ |
| Path mutation scan | ✅ Pass (no Skills code) | Confirmed by codebase-wide grep for OpenCode path mutations |
| UI action scan | ✅ Pass (no Skills UI) | No Apply/Save/Write/Toggle/Delete/Install/Update/Cleanup controls exist |
| Config display scan | ✅ Pass | No raw OpenCode config rendered (feature not implemented) |
| Secret scan | ✅ Pass | Existing app code has no secret leaks to logs/UI |
| Scope wording scan | ❌ **FAIL** | README/CHANGELOG/SECURITY still say "受限写入" instead of "read-only baseline" |
| Project scope scan | ❌ **FAIL** | No project scope excluded warning exists (feature not implemented) |
| Env signal scan | ✅ Pass | No OPENCODE_CONFIG_CONTENT parsing (feature not implemented) |
| Test scan | ❌ **FAIL** | 0 test files, 0 test functions for Skills |

**Pre-Check Verdict**: 3 documentation failures — all addressed by Phase 0 execution. Code-level checks are green because no Skills code exists yet. These checks must be re-run after each implementation phase.

## 5. Read Sources

### 5.1 Skill Directories

| Source | Path | v0.7.0 |
|---|---|---|
| OpenCode global plural | `~/.config/opencode/skills/` | Read |
| OpenCode global singular | `~/.config/opencode/skill/` | Read |
| Claude global skills | `~/.claude/skills/` | Read |
| Agents global skills | `~/.agents/skills/` | Read |
| `OPENCODE_CONFIG_DIR` skill subtrees | When `OPENCODE_CONFIG_DIR` is present, scan `{skill,skills}/**/SKILL.md` under that custom config directory read-only. Label these as `customConfigDirSkill` runtime-context sources and keep a warning that this is not a stable global baseline for every OpenCode launch. | Read + warning |
| Config `skills.paths` | Parse `skills.paths` array from `config.json`/`opencode.json`/`opencode.jsonc` (per `skills` top-level key in official JSON Schema/current source). Each path is canonicalized and scanned as long as it is a valid existing directory. Paths outside standard roots are allowed (user-configured) but shown with an informational note. Symlinks are followed with notation in detail view. | Read |
| Config `skills.urls` | Parse `skills.urls` array from `config.json`/`opencode.json`/`opencode.jsonc`. Show each URL in the warning section as "Remote skill index detected: [url] (not fetched)." No remote fetch in v0.7.0, even though OpenCode runtime may pull these sources. | Warning only |
| Built-in OpenCode skills | Current OpenCode source registers built-in `customize-opencode` before disk discovery. Show it as built-in/non-disk/non-manageable when the panel displays runtime availability signals; do not treat it as installed in any directory. | Signal only |
| Desktop Application Support skills lock | `~/Library/Application Support/ai.opencode.desktop/skills/.skill-lock.json` | Presence only — do not parse values, do not treat as a skill source |
| Project `.opencode` skills | `.opencode/{skill,skills}/` | Out of scope |
| Project `.claude` skills | `.claude/skills/` | Out of scope |
| Project `.agents` skills | `.agents/skills/` | Out of scope |

Symlink handling rules:
- All discovered skill directories must be canonicalized via `resolvingSymlinksInPath()`.
- **Allowed roots**: `~/.config/opencode/`, `~/.claude/`, `~/.agents/` (absolute, canonicalized). Applies to standard directories only.
- Symlinks resolving outside allowed roots → `outsideAllowedRoot` (warn + exclude).
- Symlinks resolving within allowed roots but to a different source tree → `symlinkDuplicate` (show both paths).
- **Runtime/custom entries (`OPENCODE_CONFIG_DIR` and config `skills.paths`)**: User-configured paths are NOT subject to allowed-root exclusion. They are canonicalized and scanned as long as they are valid existing directories. Paths outside standard roots show a mild informational note "Custom path outside standard OpenCode directories." Symlinks from these entries are followed with a note in the detail view.
- Known real-world case: `~/.claude/skills/mmx-cli → ../../.agents/skills/mmx-cli` (relative symlink across trees). Must be handled correctly by discovery and added as a test case.

OpenCode singular (`skill/`) vs plural (`skills/`) semantics:
- Both directories are scanned independently as separate source locations.
- A skill found in both is treated as a duplicate (same as any cross-directory duplicate).
- No priority weighting between singular and plural.

Within-directory scan order:
- Within each source directory, SKILL.md files are discovered by scanning subdirectories in alphabetical order (using `localizedStandardCompare`).
- This ensures reproducible "first occurrence" ordering for primary display per §6.1.

Directory-level error handling:
- If `FileManager.contentsOfDirectory` throws for a source directory (e.g., permission denied, sandbox restriction), that directory is excluded from the scan.
- A warning is added: "Skipped directory: [path] — [error localizedDescription]."
- The `OpenCodeSkillsScopeCoverage` record marks the directory as `excludedDueToError`.
- This is separate from per-file `inaccessiblePath` which covers individual unreadable SKILL.md files.

### 5.2 Config Candidates

Read config candidates only to determine display state and warnings. Do not write them.

OpenCode merges configuration layers. This panel must therefore avoid presenting a single global file as the final runtime truth.

| Candidate | Read behavior |
|---|---|
| `~/.config/opencode/config.json` | Read with the same JSON/JSONC-capable parser as other OpenCode config candidates. Show `configJsonDetected` compatibility warning because official docs prefer `opencode.json`/`opencode.jsonc`, but current OpenCode source still loads this file. Parse `permission`, legacy `tools`, `agent`, and `skills` sections. |
| `~/.config/opencode/opencode.jsonc` | Read with a JSONC-capable parser, show `jsoncConfig` warning (comments/trailing commas present). Mark as "writeback unavailable." |
| `~/.config/opencode/opencode.json` | Read with JSON parser; if comment markers or trailing commas are detected, fall back to the same JSONC-capable parser and show `jsoncConfig` warning. Parse `permission`, legacy `tools`, `agent`, and `skills` sections. |
| `OPENCODE_CONFIG` | Detect from `ProcessInfo.processEnvironment` only; warn that a custom config path may affect runtime context |
| `OPENCODE_CONFIG_DIR` | Detect from `ProcessInfo.processEnvironment`; scan its `{skill,skills}/` subtrees read-only per §5.1; warn that custom config directories may affect runtime context |
| `OPENCODE_CONFIG_CONTENT` | Detect presence only; do not display or parse raw value |
| Project config | Out of scope for v0.7.0; show warning when project context is not included |
| Managed / MDM config | Out of scope for detailed parsing. Show `managedScopeDetected` warning if detected via: (a) file-based: `/Library/Application Support/opencode/` directory exists; (b) MDM: `/Library/Managed Preferences/ai.opencode.managed.plist` or `/Library/Managed Preferences/<user>/ai.opencode.managed.plist` exists. Bundle IDs: `ai.opencode.desktop` (prod), `ai.opencode.desktop.beta` (beta), `ai.opencode.desktop.dev` (dev) per OpenCode Desktop source (`packages/desktop-electron/src/main/index.ts`). This is a heuristic — not exhaustive. |

Config file priority resolution for display:
- Scan `config.json`, `opencode.json`, and `opencode.jsonc` independently and show all present files as separate layers.
- For the global baseline explanation, use the current OpenCode source-derived merge order: `config.json` → `opencode.json` → `opencode.jsonc`.
- Label that merged result as "current-source global baseline", not final runtime availability. Project, inline, custom path, custom directory, remote, managed, and MDM layers can still change the result.
- If future source verification is not available during implementation, fall back to per-layer display only and show "merge order not asserted."

Config file JSON / JSONC parse error handling:
- Use a JSONC-capable parser for `.jsonc` files and for `.json` files that contain comments or trailing commas. Do not mark valid JSONC as invalid merely because strict JSON parsing fails.
- Any config file that fails after the appropriate JSON/JSONC parser → `invalidConfigJson` state.
- The file is shown in the config layers list with a parse error message (first 200 chars of the error).
- `permission`, legacy `tools`, `agent`, and `skills` sections are treated as **absent** for that layer. Do not let an invalid config layer imply allow or deny beyond its parse warning.
- Other layers that parse successfully are still processed normally.
- The warning section shows: "Config parse error in [filename]: [error]."

### 5.3 OpenCode Installation Detection

"OpenCode installed" for v0.7.0 is defined as: the directory `~/.config/opencode/` exists.

Additional signals (informational, not gating):
- opencode binary found at known paths → show "OpenCode binary detected" status
- opencode binary NOT found → show "OpenCode binary not found — may affect runtime behavior" warning
- `~/.config/opencode/` exists but is empty → `noConfig` state (`config.json`/`opencode.json`/`opencode.jsonc` not found)
- `~/.config/opencode/` does not exist → `notInstalled` state (panel shows installation guidance)

## 6. Data Model

### 6.1 Core Types

| Type | Responsibility |
|---|---|
| `OpenCodeSkillSourceKind` | Source directory category (opencodePlural, opencodeSingular, claude, agents, configSkillsPath) |
| `OpenCodeSkillRecord` | Skill identity, canonical path, display path, source kind, manifest summary |
| `OpenCodeSkillManifest` | Parsed frontmatter and validation issues |
| `OpenCodeSkillValidationIssue` | Error / warning / info classification |
| `OpenCodePermissionAction` | `allow`, `ask`, `deny`, `implicitDefault` |
| `OpenCodeSkillRule` | Ordered resolved skill-permission rule from top-level `permission`, nested `permission.skill`, agent permission, or legacy `tools` |
| `OpenCodeSkillBaselineState` | Global baseline permission and explanation |
| `OpenCodeAgentSkillAvailability` | Per-agent availability result |
| `OpenCodeAgentSkillOverrideSignal` | Read-only signal for `agent.*.permission` scalar/object rules and `agent.*.tools` legacy disable signals |
| `OpenCodeLegacyToolSignal` | Top-level or agent-level legacy `tools` boolean rule that affects `skill` or `*` |
| `OpenCodeBuiltinSkillSignal` | Built-in OpenCode skill such as `customize-opencode`; non-disk and non-manageable |
| `OpenCodeConfigLayerSignal` | Detected config/env/project/managed signal and scope warning |
| `OpenCodeSkillsScopeCoverage` | Explicitly records which global paths were scanned and which project/runtime paths were excluded |
| `OpenCodeSkillsReadOnlySnapshot` | Full read-only view model payload |

Duplicate resolution in display (R7 clarification):
- Primary display: first skill found in scan order (OpenCode plural → OpenCode singular → Claude → Agents → config `skills.paths`, alphabetical within each directory). This is a display ordering convention only — no semantic "winner" is asserted. The panel presents all copies and lets the user understand the duplication.
- All duplicate copies listed in detail panel with full source paths and source kind labels, with the warning "Skills share the same name but may have different content."
- If two discovered entries resolve to the same canonical `SKILL.md` file, show them as `symlinkDuplicate` / canonical-path duplicate, not as separate independently available skills. This covers `~/.claude/skills/mmx-cli -> ../../.agents/skills/mmx-cli`.
- Missing source directories, including the legacy singular `~/.config/opencode/skill/`, are normal "not present" inputs and must not produce errors or block the panel.

### 6.2 Suggested Files

| File | Purpose |
|---|---|
| `Sources/CodexTokenCostCore/OpenCodeSkillManifest.swift` | Manifest parser and validation |
| `Sources/CodexTokenCostCore/OpenCodeSkillDiscovery.swift` | Directory scanning, symlink canonicalization, duplicate grouping |
| `Sources/CodexTokenCostCore/OpenCodeSkillPermissions.swift` | Rule parser, wildcard matcher, global baseline calculation |
| `Sources/CodexTokenCostCore/OpenCodeSkillsReadOnlyStore.swift` | Config read and redacted snapshot assembly |
| `Sources/CodexTokenCostApp/Stores/OpenCodeSkillsModel.swift` | Lazy UI state model |
| `Sources/CodexTokenCostApp/Views/OpenCodeSkillsPageView.swift` | Skills panel |

No `OpenCodeConfigEditor`, text patcher, backup store, rollback store, or writer should be implemented for v0.7.0.

### 6.3 Manifest Parsing Edge Cases

| Input | Behavior |
|---|---|
| Valid frontmatter with official required fields and constraints | `skillValid`: `name` and `description` are present; `name` is 1–64 chars, matches `^[a-z0-9]+(-[a-z0-9]+)*$`, has no leading/trailing/consecutive hyphen, and matches the parent directory name; `description` is 1–1024 chars. |
| Missing `name` | `skillInvalid` (name is required for identification) |
| Missing `description` | `skillInvalid` (official OpenCode skill frontmatter requires description) |
| Invalid `name` format, length, or parent-directory mismatch | `skillInvalid`; shown with the specific validation issue; excluded from permission matching. |
| Invalid `description` length | `skillInvalid`; shown with the specific validation issue; excluded from permission matching. |
| Unknown/non-standard fields | Show only unknown field key names and unknown field count. Unknown field values are never displayed, logged, persisted, copied, included in diagnostics, or used for matching. |
| Official display fields (`name`, `description`) | May be shown after redaction and truncation. All displayed values are capped at 64 chars after redaction except where full description text is intentionally shown in the detail view; full description still passes through redaction first. |
| Malformed YAML (parse error) | `yamlParseError` state. Skill shown with error message, excluded from permission matching. |
| Empty file | `skillInvalid` — "Empty SKILL.md" |
| Non-UTF-8 encoding | `skillInvalid` — "Unsupported file encoding" |
| Multiple `---` blocks | Parse first block only as frontmatter. Remaining content treated as body text (not displayed in v0.7.0). |
| File > 1MB | `skillWarning` — "Large manifest file." Still parsed but with size warning. |
| File unreadable (permission denied) | `inaccessiblePath` state. File path shown with error. Excluded from skill list. Warning added. |

## 7. UI Requirements

### 7.1 Page Structure

| Region | Content |
|---|---|
| Header | OpenCode Desktop Global Skills, read-only badge, refresh button |
| Status strip | OpenCode config status, global baseline source, custom env signals, global-only scope warning |
| Sidebar | Search, source filter, status filter, skill list |
| Detail | Manifest summary, validation issues, source paths, duplicates |
| Permission section | Configured global rule chain (key-path summaries only, per §9), baseline action, matched rule explanation |
| Agent matrix | Build / Plan / General / Explore / Scout / Compaction / Title / Summary with override/tool-disabled signals |
| Warning section | JSONC, schema, config.json compatibility, legacy tools, remote URLs, symlink, duplicate, custom config, custom config dir, skills paths, skills urls, project scope excluded, managed scope detected, Desktop local state ignored, not installed, historical .bak files |

Toolbar behavior for Skills tab:
- The Skills tab has an **independent "Refresh Skills" button** in the toolbar. This is separate from the existing "Refresh All" / "Rescan" / "Refresh Codex" buttons used by other tabs.
- Skills refresh does NOT trigger OpenCode token DB rescan or Codex session refresh.
- Skills refresh re-scans all standard skill directories, `OPENCODE_CONFIG_DIR` skill subtrees when present, config `skills.paths` directories, and re-reads config files. It is a full re-discovery, not incremental.
- When the user switches away from the Skills tab, the toolbar reverts to the appropriate button for the active tab (existing behavior unchanged).

### 7.2 Required States

| State | Meaning |
|:---|:---|
| `notInstalled` | `~/.config/opencode/` directory does not exist |
| `noConfig` | Config directory exists but no `config.json`/`opencode.json`/`opencode.jsonc` found |
| `noSkillsFound` | OpenCode installed and config exists, but 0 SKILL.md files discovered in any scanned directory. Panel shows list of scanned paths and message "No global skills found." |
| `invalidConfigJson` | A config file failed JSON/JSONC parsing. File shown with parse error; `permission`, legacy `tools`, `agent`, and `skills` sections are treated as absent for that layer. |
| `readOnlyConfig` | Config found and parsed for display |
| `configJsonDetected` | Compatibility config file `~/.config/opencode/config.json` found and parsed/read as a layer |
| `jsoncConfig` | JSONC/commented config detected (`.jsonc` extension OR `//`/`/* */` comments in `.json` file). Display only; writeback unavailable. |
| `schemaUnknown` | Unknown `$schema` version; display only |
| `skillValid` | Manifest passed required checks |
| `skillWarning` | Manifest loads but has non-blocking warnings (large file, unknown field keys hidden, optional display metadata omitted) |
| `skillInvalid` | Manifest has blocking errors (missing name, malformed YAML, empty file, unsupported encoding) |
| `yamlParseError` | YAML frontmatter failed to parse; skill shown with error message, excluded from permission matching |
| `inaccessiblePath` | File exists but cannot be read (permission denied); excluded from skill list, warning shown |
| `duplicate` | Same skill name appears in multiple places |
| `symlinkDuplicate` | Duplicate caused by symlink/canonical path resolving to same file across different source trees |
| `outsideAllowedRoot` | Symlink resolves outside allowed global roots (`~/.config/opencode/`, `~/.claude/`, `~/.agents/`); show warning and exclude |
| `brokenSymlink` | Symlink target does not exist; show warning and exclude |
| `projectScopeExcluded` | Project-level skills/config were intentionally not scanned |
| `customConfigDetected` | `OPENCODE_CONFIG` env var was detected in current process environment |
| `customConfigDirDetected` | `OPENCODE_CONFIG_DIR` env var was detected in current process environment |
| `inlineConfigDetected` | `OPENCODE_CONFIG_CONTENT` env var was detected; value is not displayed |
| `agentOverrideDetected` | Global config contains `agent.*.permission` scalar/object rules affecting `skill` |
| `skillToolDisabled` | Global config contains top-level or agent-level legacy `tools.skill=false` / `tools.*=false`, or a permission rule that resolves `skill` to `deny` |
| `legacyToolsDetected` | Deprecated but still supported top-level or agent-level `tools` config detected |
| `builtinSkillDetected` | Built-in OpenCode skill signal detected; shown as non-disk/non-manageable |
| `desktopLocalStateIgnored` | Desktop Application Support skill lock or local state detected but intentionally not parsed |
| `skillsPathsDetected` | Global config `skills.paths` contains additional skill directories; shown as separate source layers |
| `skillsUrlsDetected` | Global config `skills.urls` contains remote skill index URLs; shown as warning only, not fetched |
| `globalBaselineOnly` | Display result is not final project runtime availability |
| `historicalBakWarning` | Historical `.bak-*` files detected in `~/.config/opencode/`; informational warning only |

### 7.3 No Write UI

The UI must not show:

- Toggle switches that imply immediate permission changes.
- Apply / Save / Commit / Write buttons.
- Backup / Restore buttons.
- Delete / Install / Update skill buttons.
- "Fix", "Migrate", "Clean up", or "Restore" actions.

If future writeback is mentioned, it should be shown as "not available in v0.7.0" only.

### 7.4 Localization Key List

> **Minimum localization key list**. The exact count must be recalculated during implementation after all R6 additions are wired. 35 keys from R1 audit base set + 7 keys added via N1–N10 audit + R5/R6 additions (`skillsPathsDetected`, `skillsUrlsDetected`, `scalarPermission`, wildcard permission, legacy tools, built-in skill, config.json, Desktop local state). `directorySkipped` added via N4 audit trigger.

The following localization keys are needed for the Skills panel. All must have Chinese (`zh-Hans`) and English (`en`) variants.

**Tab & Navigation:**
- `tab.skills` — "Skills" / "Skills"
- `tab.skills.tooltip` — "管理 OpenCode Skills" / "Manage OpenCode Skills"

**Header & Status:**
- `skills.header.title` — "OpenCode Desktop Skills" / "OpenCode Desktop Skills"
- `skills.badge.readOnly` — "只读" / "Read-only"
- `skills.status.notInstalled` — "未检测到 OpenCode" / "OpenCode not detected"
- `skills.status.noConfig` — "未找到配置文件" / "No config found"
- `skills.status.noSkillsFound` — "未发现全局 Skills" / "No global skills found"
- `skills.status.invalidConfigJson` — "配置文件 JSON 解析失败" / "Config JSON parse error"
- `skills.status.globalBaselineOnly` — "仅显示全局基线，非最终运行时可用性" / "Global baseline only — not final runtime availability"
- `skills.status.builtinSkill` — "内置 Skill（非磁盘安装）" / "Built-in skill (not disk-installed)"

**Skill States:**
- `skills.state.valid` — "有效" / "Valid"
- `skills.state.warning` — "有警告" / "Warning"
- `skills.state.invalid` — "无效" / "Invalid"
- `skills.state.yamlParseError` — "YAML 解析错误" / "YAML parse error"
- `skills.state.duplicate` — "重复" / "Duplicate"
- `skills.state.symlinkDuplicate` — "符号链接重复" / "Symlink duplicate"
- `skills.state.outsideRoot` — "路径越界" / "Outside allowed root"
- `skills.state.brokenSymlink` — "符号链接损坏" / "Broken symlink"
- `skills.state.inaccessible` — "无法访问" / "Inaccessible"

**Permission:**
- `skills.permission.allow` — "允许" / "Allow"
- `skills.permission.deny` — "拒绝" / "Deny"
- `skills.permission.ask` — "询问" / "Ask"
- `skills.permission.implicitDefault` — "默认允许" / "Default allow"
- `skills.permission.scalarPermission` — "全局权限: [action]" / "Global permission: [action]"
- `skills.permission.wildcardPermission` — "通配权限: [pattern] = [action]" / "Wildcard permission: [pattern] = [action]"
- `skills.permission.mayBeOverridden` — "可能被更高优先级配置覆盖" / "May be overridden by higher-precedence config"
- `skills.permission.restartWarning` — "权限变更需重启 OpenCode 后生效" / "Changes take effect after OpenCode restart"

**Agent Matrix:**
- `skills.agent.build` — "Build" / "Build"
- `skills.agent.plan` — "Plan" / "Plan"
- `skills.agent.general` — "General" / "General"
- `skills.agent.explore` — "Explore" / "Explore"
- `skills.agent.scout` — "Scout" / "Scout"
- `skills.agent.compaction` — "Compaction" / "Compaction"
- `skills.agent.title` — "Title" / "Title"
- `skills.agent.summary` — "Summary" / "Summary"
- `skills.agent.overrideDetected` — "检测到 Agent 级覆盖" / "Agent-level override detected"
- `skills.agent.skillToolDisabled` — "Skill 工具已禁用" / "Skill tool disabled"
- `skills.agent.nativeRestricted` — "原生 Agent 默认限制 Skill" / "Native agent restricts skill by default"

**Warnings:**
- `skills.warning.jsoncConfig` — "检测到 JSONC 配置（含注释），仅可读" / "JSONC config detected (contains comments) — read-only"
- `skills.warning.configJsonDetected` — "检测到兼容配置 config.json" / "Compatibility config.json detected"
- `skills.warning.schemaUnknown` — "未知 Schema 版本" / "Unknown schema version"
- `skills.warning.customConfig` — "检测到自定义配置文件路径" / "Custom config path detected"
- `skills.warning.customConfigDir` — "检测到自定义配置目录" / "Custom config directory detected"
- `skills.warning.inlineConfig` — "检测到内联配置（内容不显示）" / "Inline config detected (content hidden)"
- `skills.warning.legacyTools` — "检测到 legacy tools 配置" / "Legacy tools config detected"
- `skills.warning.desktopLocalStateIgnored` — "已忽略 Desktop 本地状态" / "Desktop local state ignored"
- `skills.warning.projectExcluded` — "项目级 Skills 未扫描" / "Project-level skills not scanned"
- `skills.warning.managedDetected` — "检测到托管配置，可能覆盖全局设置" / "Managed config detected — may override global settings"
- `skills.warning.historicalBak` — "检测到 N 个历史备份文件" / "N historical backup files detected"
- `skills.warning.directorySkipped` — "跳过目录：[path]" / "Skipped directory: [path]"
- `skills.warning.skillsPathsDetected` — "检测到自定义 skill 路径: [count] 个" / "Custom skill paths detected: [count]"
- `skills.warning.skillsUrlsDetected` — "检测到远程 skill 索引: [count] 个" / "Remote skill index URLs detected: [count]"

**Actions:**
- `skills.action.refresh` — "刷新 Skills" / "Refresh Skills"
- `skills.action.refresh.tooltip` — "重新扫描 skill 目录和配置文件" / "Rescan skill directories and config files"
- `skills.future.notAvailable` — "此功能在 v0.7.0 中不可用" / "Not available in v0.7.0"

## 8. Permission Semantics

### 8.1 Rule Matching

Implement display-only matching compatible with OpenCode behavior for the global baseline layer:

- `*` matches any sequence.
- `?` matches a single character.
- Last matching rule wins.
- If no rule is configured, show `Implicit default: allow`.
- If `permission` itself is a scalar string (`"allow"`, `"ask"`, or `"deny"`), it sets the default for ALL permissions including `skill`. The JSON Schema defines `PermissionConfig` as `anyOf [scalar, object]`.
- If `permission` is an object, preserve top-level entry order and match top-level keys as permission-name patterns against the permission name `skill`. This includes exact `skill`, `*`, and other wildcard patterns. A matching top-level scalar action updates the current skill action.
- If a matching top-level `permission` entry has an object value, evaluate that nested object against the skill name using the same wildcard matcher. A nested object updates the current action only when one of its nested patterns matches the skill name; otherwise the previous matched action remains.
- `permission.skill = "allow" | "ask" | "deny"` is therefore a specific top-level scalar entry that applies to every skill.
- `permission.skill = { pattern: action }` is a nested object entry that applies by skill name, preserving nested entry order and last-match-wins semantics.
- A top-level wildcard can deny skills even when `permission.skill` is absent. Example: `permission: {"*": "deny"}` resolves `skill` to `deny`, not implicit allow.
- If a layer contains unsupported permission value types, mark that layer with a schema/parse warning and skip only the unsupported entry for display matching.
- Legacy top-level `tools` is deprecated but still supported by OpenCode. If `tools.skill=false` or `tools.*=false` is present, show `legacyToolsDetected` and resolve the baseline skill tool as unavailable unless a source-verified implementation proves a later permission layer re-enables it. `tools.*=true` or `tools.skill=true` is shown as a legacy signal but does not remove explicit permission denies.
- If higher-precedence config layers are detected but not parsed, show `May be overridden outside this global baseline`.

### 8.2 Agent Matrix

| Agent | Native skill baseline before user config | Notes |
|---|---|---|
| build | Allow | Primary agent. In current source, native defaults allow most tools and then build adds specific allowances such as question/plan-enter. |
| plan | Allow | Primary agent. Edit is denied except plan files, but skill inherits allow unless global/user/agent permission or legacy tools disables it. |
| general | Allow | Subagent. `todowrite` is denied, but skill inherits allow unless overridden. |
| explore | Deny unless later allowed | Native source applies `* = deny` and then explicitly allows read/search/bash/web tools and readonly external directories. Skill is not in the explicit allow list. |
| scout | Deny unless later allowed / may be absent | Native source applies `* = deny` and then explicitly allows read/search/web/repo research tools. Scout may be behind an experimental runtime flag; show as absent/unknown if not listed by current source/runtime. |
| compaction | Deny unless later allowed | Hidden system agent with native `* = deny`. |
| title | Deny unless later allowed | Hidden system agent with native `* = deny`. |
| summary | Deny unless later allowed | Hidden system agent with native `* = deny`. |

**Important**: Do not infer every agent's skill availability from the generic "default allow" permission statement alone. Current OpenCode source builds each native agent by merging defaults with native agent-specific permission rules. `explore`, `scout`, `compaction`, `title`, and `summary` include native `* = deny` rules, so their skill availability is denied unless later global/user/agent rules explicitly allow `skill`.

Matrix calculation order for v0.7.0:
1. Start with current-source native agent defaults.
2. Apply merged global permission from `config.json` → `opencode.json` → `opencode.jsonc` using §8.1.
3. Apply `agent.<name>.permission` scalar/object rules from the same merged global layer.
4. Apply top-level legacy `tools` and `agent.<name>.tools` disable signals. Matching false legacy tool rules must be visible as `skillToolDisabled` / `legacyToolsDetected`.
5. If any higher-precedence config layers are detected but not parsed, show "may be overridden" instead of claiming final runtime availability.

The matrix is explanatory. It must not edit agent config or `oh-my-openagent.json`.

**Known limitation (v0.7.0)**: Agent skill availability may also be affected by `oh-my-openagent.json` agent definitions (e.g., per-agent `skills` whitelist arrays such as `oracle.skills: ["self-development-p", "skill-suggester"]`). v0.7.0 detects this file via `FileManager.default.fileExists(atPath:)` only — the file is NOT opened, read, or parsed. An explicit warning "Agent-level skill overrides in oh-my-openagent.json are not scanned in v0.7.0" is shown when the file exists at `~/.config/opencode/oh-my-openagent.json`.

### 8.3 Agent Override Signals

The panel should explain these separate causes:

| Cause | Display behavior |
|---|---|
| Native agent permission defaults | Show native allow/deny baseline per §8.2 before user config. |
| Global `permission` scalar/object | Baseline allow / ask / deny result, including top-level wildcard rules such as `permission.* = deny`. |
| Global legacy `tools` | Deprecated but supported disable signal; `tools.skill=false` / `tools.*=false` marks skill tool unavailable at the global baseline. |
| `agent.*.permission` scalar/object | Agent-specific override signal; explain that agent rules are applied after native/global rules. |
| `agent.*.tools` legacy booleans | Agent-specific legacy disable signal; `agent.*.tools.skill=false` / `agent.*.tools.*=false` marks skills unavailable for that agent. |
| `oh-my-openagent.json` | File existence warning only; not parsed in v0.7.0. |

Do not parse project custom agent frontmatter in v0.7.0. If project/custom agents are not scanned, show scope warning instead of guessing.

## 9. Secret Handling

Config reads must pass through redaction before any display, debug log, error message, or diagnostic string.

Minimum redaction targets:

- `mcp.*.environment`
- `mcp.*.headers`
- `provider.*.options.apiKey`
- Any key containing `token`, `secret`, `apiKey`, `api_key`, `authorization`, `cookie`, `password`, or `bearer` (case-insensitive substring match — covers variants like `MY_TOKEN`, `slack-bot-token`, `OAUTH_BEARER`)
- `OPENCODE_CONFIG_CONTENT` raw value

The Skills UI should normally avoid rendering raw config snippets at all. Prefer key-path summaries such as:

- `permission.skill.* = allow`
- `permission.skill.some-skill = deny`

For env vars, show only the env var name and a redacted path/presence state where appropriate. Do not render inline config contents.

**SKILL.md frontmatter display**: Values from unknown/non-standard frontmatter fields are never shown, logged, copied, persisted, or included in diagnostics (§6.3). Show only unknown field key names and count. Official display fields (`name`, `description`) pass through the same redaction patterns before display: field keys containing `token`, `secret`, `apiKey`, `api_key`, `authorization`, `cookie`, `password`, or `bearer` (case-insensitive substring match) have their values replaced with `[REDACTED]`; non-redacted values are truncated to 64 characters in compact lists, and full description text may appear only in the detail view after redaction.

## 10. Implementation Phases

### Phase 0 — Documentation Scope Reset [STATUS: NOT STARTED — BLOCKING]

This phase fixes the current documentation mismatch where README/CHANGELOG/SECURITY claim writeback that does not exist. **Must complete before any code is written.**

#### Phase 0.1 — Public Documents

> **Note**: Line numbers are based on current file state as of 2026-06-02 (R2 audit). Verify target content matches before editing — do not rely solely on line numbers.

| File | Target Content (current) | Rewrite To |
|---|---|---|
| `README.md` L13 | `"只读安全 — …OpenCode skill permission 为可选功能，需用户手动确认后方可受限写入"` | Replace entire Skills clause: `"OpenCode skill 权限为只读分析功能，仅展示全局基线配置，不修改任何 OpenCode 文件"` |
| `README.md` L15 | `"OpenCode Skills 管理与权限控制 — 全局 skill 发现、manifest 校验、permission 权限可视化与受限写入"` | Rewrite entire line: `"OpenCode Skills 只读面板 — 全局 skill 发现、manifest 校验、permission 权限可视化（当前阶段为只读）"` |
| `CHANGELOG.md` L14 | `"…可视化规则链与 Agent 可用性矩阵（Build/Plan/General/Explore）；支持用户确认后受限写入…"` | Rewrite without writeback + fix agent count: `"…可视化规则链与 Agent 可用性矩阵（8 agent：Build/Plan/General/Explore/Scout/Compaction/Title/Summary）；当前阶段为只读分析"` |
| `CHANGELOG.md` L24-26 | `### Security` paragraph with "Product Security Posture Change" + 5 writeback mechanisms | Delete entire `### Security` paragraph. No replacement — v0.7.0 has no security posture change (read-only). |
| `SECURITY.md` L7 | `"新增 Skills 权限受限写入"` | Change to: `"新增 Skills 只读管理面板"` |
| `SECURITY.md` L28-37 | 8 writeback security measures (hash guard, batch tx, backup, rollback, JSONC read-only, file-not-exist guard, secret redaction, diff guard) | Delete all 10 lines. Replace with: `"- **OpenCode Skills 只读面板（v0.7.0）**：仅读取 skill 目录和配置进行分析展示，不做任何写入操作。权限可视化基于全局配置文件只读解析，不修改 `permission.skill` 规则。"` |

#### Phase 0.2 — Project Docs

| File | Action |
|---|---|
| `docs/开发手册.md` §8 | Add entry: "Skills 管理面板（v0.7.0）只读分析 skill 权限配置，不修改 OpenCode 任何文件" |
| `docs/功能模块关联清单.md` | Add §2.12: Skills 只读面板 module entry with key files |
| `docs/功能模块关联清单.md` §2.8 | Add mention of v0.7.0 Skills panel read-only posture |

#### Phase 0.3 — Plan Document Housekeeping

| File | Action |
|---|---|
| `.sisyphus/plans/skills-manager-v0.7.0.md` | Add header: `⚠️ SUPERSEDED by skills-manager-v0.7.0-readonly.md. See readonly plan for current v0.7.0 scope. This document retained as writeback reference only.` |
| `.sisyphus/plans/skills-manager-v0.7.0.backup-20260602-desktop-readonly.md` | No action required. This file is a historical backup retained for audit trail. Its timestamp and naming convention do not conflict with the authoritative plan. |

Exit criteria:

- No v0.7.0 documentation claims `permission.skill` writeback.
- No v0.7.0 documentation claims backup / rollback / diff guard for Skills.
- README / CHANGELOG / SECURITY all use the same read-only-only posture.
- Project docs (开发手册, 功能模块关联清单) include Skills panel as read-only entry.
- v0.7.0.md writeback plan is clearly marked SUPERSEDED.

### Phase 1 — Read-only Core

- Add manifest parser (with all edge cases from §6.3).
- Add global skill discovery (with symlink canonicalization and allowed-root validation per §5.1).
- Add duplicate grouping (with primary display order per §6.1).
- Add permission rule parsing and matching (with `*`/`?` wildcard, top-level permission-name matching, nested skill-name matching, last-match-wins).
- Add `permission` object-level wildcard handling, including `permission: {"*": "deny"}`.
- Add `config.json` / `opencode.json` / `opencode.jsonc` layer parsing and source-derived merge order.
- Add scalar `permission.skill` handling (`"allow"`, `"ask"`, `"deny"`) as a valid layer-wide baseline, separate from object pattern rules.
- Add agent-level `permission` scalar/object handling for all matrix agents.
- Add legacy top-level and agent-level `tools` detection (`tools.skill=false`, `tools.*=false`, `agent.*.tools.skill=false`, `agent.*.tools.*=false`).
- Add config layer signal detection for `OPENCODE_CONFIG`, `OPENCODE_CONFIG_DIR`, and `OPENCODE_CONFIG_CONTENT`.
- Add `OPENCODE_CONFIG_DIR` `{skill,skills}/` read-only scanning when the env var is present.
- Add `skills.paths` discovery and `skills.urls` detection from `config.json`/`opencode.json`/`opencode.jsonc` config (per §5.1 and §5.2).
- Add built-in OpenCode skill signal handling for `customize-opencode` as non-disk/non-manageable.
- Add Desktop Application Support local-state presence detection and explicit ignore note.
- Add JSONC-capable config parsing for `.jsonc` and commented/trailing-comma `.json` files.
- Add agent override signal parsing for global config only.
- Add agent matrix calculation (8 possible agents, native defaults per §8.2; `scout` may be absent if not enabled by current source/runtime).
- Add redaction pass for all config reads (per §9).
- Add frontmatter value suppression for unknown fields; unknown values must never enter UI/debug/diagnostic strings.
- Add `mmx-cli` symlink test case as specific known scenario (§5.1).

Exit criteria:

- No writer types exist.
- Unit tests pass for parser, matching, duplicates, env signals, agent override signals, invalid manifests, and redaction.
- `mmx-cli` relative symlink case handled correctly.
- All §6.3 manifest edge cases tested.
- Tests use injected temporary fixture roots only; no unit test reads the user's real `~/.config/opencode`, `~/.claude`, or `~/.agents` directories.

### Phase 2 — Read-only App Model

- Add `OpenCodeSkillsModel` as `@StateObject` in `TokenCostApp.swift` (matching existing 5-StateObject pattern).
- Defer actual scanning to `onAppear` of Skills tab. Model holds `nil` snapshot until first scan.
- Scan on every tab activation (no snapshot persistence for v0.7.0 — see R18 rationale).
- Keep refresh independent from OpenCode token database scanning.
- Keep app startup unchanged except for creating lightweight model state.

Exit criteria:

- App startup does not scan skills until Skills panel is opened.
- No config mutation path exists.
- OpenCode DB rescan and Skills refresh are separate actions.
- Switching to Skills tab triggers scan; switching away preserves last snapshot in memory.

### Phase 3 — UI

- Add `.skills` case to `CodexDashboardPage` enum (no `.allCases` usage exists — safe to add).
- Add Skills tab item to `TabView` in `ContentView.swift` (appends to existing tab count — do not hardcode "fourth"; read existing cases from the enum).
- Add `OpenCodeSkillsPageView` with all regions per §7.1.
- Add toolbar case for `.skills` in `ContentView.toolbarRefreshButton` per §7.1 toolbar specification.
- Add read-only badges and warnings.
- Add all localization keys from §7.4 (Chinese + English `.strings` files); recalculate exact key count after R6 additions.
- Add "global baseline only" and "project scope excluded" warnings.
- Add custom env signal badges.
- Add agent override and skill-tool-disabled explanations.
- Add `oh-my-openagent.json` detection warning per §8.2 known limitation.
- Add historical .bak files informational warning (§3).

Exit criteria:

- No write controls are visible.
- Empty/not-installed/no-config states are clear.
- Users can tell baseline/global state from final project runtime state.
- All localization keys render correctly in both languages.
- Toolbar button behavior is correct for each tab.

### Phase 4 — Safety Review

- Search Skills-related code for forbidden write APIs.
- Search UI for forbidden write action labels.
- Verify redaction coverage.
- Verify docs and UI do not imply project-level final effectiveness.
- Re-run §13 Safety Boundary Checklist against completed implementation.

Exit criteria:

- Safety boundary checklist passes with all 10 checks green.
- No OpenCode config or skill path is mutated by the feature.

## 11. Tests

| Area | Required tests |
|---|---|
| Manifest parser | Valid frontmatter with official constraints; missing name (invalid); missing description (invalid); invalid name regex/length/directory mismatch (invalid); invalid description length (invalid); unknown field keys shown without values; official display fields redacted/truncated; malformed YAML (yamlParseError); empty file; non-UTF-8; multiple `---` blocks; file >1MB; unreadable file |
| Discovery | Missing directories (no crash, including absent `~/.config/opencode/skill/`); plural/singular dirs independently scanned when present; config `skills.paths` directories canonicalized and scanned (not subject to allowed-root exclusion); `skills.paths` nonexistent/inaccessible path → warning and excluded; symlink duplicate by canonical path (absolute path); symlink duplicate by canonical path (relative path — `mmx-cli` case); outside-root symlink exclusion (standard dirs only); broken symlink |
| Permission parser | Absent `permission` and `permission.skill` (implicit default); scalar `permission` string (sets all permissions including `skill`); top-level `permission` object wildcard such as `{"*": "deny"}`; ordered top-level permission-name matching for `*` and `skill`; scalar string forms `"allow"`, `"ask"`, `"deny"` for `permission.skill`; nested `permission.skill` object rules by skill name; mixed allow/deny/ask; ordered rule preservation; unsupported type produces schema warning |
| Wildcard matcher | Exact match; `*` prefix/suffix/full wildcard; `?` single-char; last-match-wins for both top-level permission-name matching and nested skill-name matching; no match → implicit default or previous matched parent action |
| Legacy tools | Top-level `tools.skill=false`; top-level `tools.*=false`; agent-level `agent.<name>.tools.skill=false`; agent-level `agent.<name>.tools.*=false`; legacy `true` values do not erase explicit permission deny; deprecation warning shown |
| Config parsing/signals | Strict JSON config; JSONC `.jsonc`; commented/trailing-comma `.json` parsed with JSONC parser; `config.json` parsed as compatibility candidate; invalid JSON/JSONC produces `invalidConfigJson`; `OPENCODE_CONFIG` env var detected; `OPENCODE_CONFIG_DIR` env var detected and custom-dir skills scanned with fixtures; `OPENCODE_CONFIG_CONTENT` detected but NOT parsed; multiple config files coexisting (`config.json` + `opencode.json` + `opencode.jsonc`); `skills.paths` parsed and added to discovery; `skills.urls` parsed and shown as warning |
| Agent matrix | 8 possible agent columns (Build/Plan/General/Explore/Scout/Compaction/Title/Summary); build/plan/general native skill allow; explore/scout/compaction/title/summary native skill deny unless later allowed; agent permission scalar/object override detected and explained; legacy `tools.skill=false` / `tools.*=false` → "Skill tool disabled"; `oh-my-openagent.json` file existence detection → warning shown |
| Built-in/Desktop signals | Built-in `customize-opencode` shown as non-disk/non-manageable; Desktop Application Support `.skill-lock.json` / local state presence shown as ignored without parsing values |
| Redaction | Secret keys (token, apiKey, authorization, cookie, password) never appear in diagnostics or UI strings; unknown frontmatter values never appear at all; `OPENCODE_CONFIG_CONTENT` value never rendered; MCP environment/headers redacted |
| UI model | Lazy load (scan deferred until tab activation); refresh re-scans; global baseline warning shown; no write action label found in UI code; tab switch preserves last snapshot |
| Documentation | README / CHANGELOG / SECURITY contain zero v0.7.0 writeback claims; wording uses "global baseline" / "read-only baseline" not unqualified "effective" |

Test isolation requirements:
- Unit tests must inject temporary fixture roots for OpenCode, Claude, Agents, custom config, and managed-signal paths. They must not read, list, print, or depend on the user's real home-directory OpenCode/Claude/Agents configuration.
- `swift test` should run without `--disable-sandbox` for these core tests. If a future manual integration check needs real home paths, keep it outside the unit-test suite and document it as opt-in QA only.
- Test fixtures must use synthetic non-secret values only.

## 12. Acceptance Criteria

- The app can show a new OpenCode Skills panel appended to the existing TabView tabs.
- The panel only reads global OpenCode skill/config data.
- No app code path writes to OpenCode config or skill directories.
- The panel clearly labels itself as read-only.
- The panel does not manage MCP, provider, agent, plugin, Codex skills, or project skills.
- The panel explains global baseline permission state without changing it.
- The panel warns that project/runtime/managed layers can change final availability.
- The panel detects `OPENCODE_CONFIG_DIR` as a runtime-context signal.
- The panel scans `OPENCODE_CONFIG_DIR` `{skill,skills}/` subtrees read-only when the env var is present and labels them as runtime custom-dir sources.
- The panel explains top-level and agent-level legacy `tools.skill=false` / `tools.*=false` when present in global config.
- The panel handles all edge cases: malformed YAML, unreadable files, broken symlinks, outside-root symlinks, duplicate skills, missing config, JSONC config.
- The panel treats scalar `permission.skill` as a valid layer-wide baseline and object `permission.skill` as ordered pattern rules.
- The panel treats scalar `permission` (top-level) as a global override that applies to all permissions including `skill`.
- The panel treats object `permission` top-level wildcard rules as applicable to `skill`, including `permission.* = deny`.
- The panel treats agent-level scalar/object `permission` rules as part of the agent matrix calculation.
- The panel reads `config.json` as a compatibility global config layer alongside `opencode.json` and `opencode.jsonc`.
- The panel reads config `skills.paths` entries and scans them for additional skill discovery.
- The panel detects config `skills.urls` entries and shows remote-skill-index warnings.
- The panel shows built-in OpenCode skills as non-disk/non-manageable and does not count them as installed directory skills.
- The panel detects Desktop Application Support local-state presence only and does not parse its values.
- The panel validates SKILL.md manifests using official OpenCode required fields, name rules, and length rules.
- The panel never displays unknown frontmatter values.
- The panel warns about `oh-my-openagent.json` agent-level overrides in scope.
- The panel shows informational warning about historical .bak files (without offering cleanup).
- Documentation matches the read-only implementation.
- `swift test` passes with fixture-only Skills tests. Any unrelated pre-existing environment-dependent failures must be documented separately (list of expected-failing tests + reason, in a `docs/skills-test-baseline.md` or equivalent).

> **Test framework prerequisite**: The `swift test` command assumes Swift Package Manager as the test runner on macOS. Skills tests must use injected temporary fixture roots and synthetic config/skill files, so they should not require `--disable-sandbox` and should not touch real `~/.config/opencode/`, `~/.claude/`, or `~/.agents/` directories. If the platform or sandbox policy changes, keep the same fixture-only principle and adjust the harness accordingly.

## 13. Safety Boundary Checklist

Run this checklist before implementation review and before release.

| Check | Required result |
|---|---|
| Writer type scan | No `OpenCodeConfigEditor`, text patcher, backup writer, rollback writer, or config writer exists for Skills |
| Forbidden API scan | Skills-related files do not call `Data.write`, `FileHandle.write`, `removeItem`, `moveItem`, `replaceItemAt`, `chmod`, or shell execution for OpenCode paths |
| Path mutation scan | No mutation under `~/.config/opencode`, `~/.agents`, `~/.claude`, `.opencode`, `.agents`, or `.claude` |
| UI action scan | No Apply / Save / Write / Toggle / Delete / Install / Update / Cleanup controls |
| Config display scan | No raw OpenCode config snippets are rendered. Permission section must only show key-path summaries (e.g., `"permission.skill.* = allow"`), not raw JSON config trees. See §7.1 and §9. |
| Secret scan | Diagnostics and UI never contain token/apiKey/cookie/password/authorization values |
| Scope wording scan | UI and docs say "global baseline" or "read-only baseline", not unqualified "effective" |
| Project scope scan | UI explicitly warns that project and managed layers are out of scope |
| Env signal scan | `OPENCODE_CONFIG_CONTENT` is detected only by presence, never parsed or displayed |
| Test scan | Unit tests cover parser, discovery, permissions, env signals, agent signals, redaction, and lazy loading |

## 14. Future Writeback Gate

Writeback may be reconsidered only in a later version after a separate approval and proof plan.

Minimum future gates:

- Text patch prototype passes real-shape tests.
- Redaction tests prove no secrets leak.
- Backup path is app-local, not config-directory-local.
- TOCTOU checks are implemented and tested.
- JSONC/commented config remains read-only.
- User explicitly approves the product posture change.

Until those gates pass, v0.7.0 remains read-only only.
