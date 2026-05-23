import Foundation
import Combine
import OSLog

/// Unified registry for all skills — both chat-type and tool-type.
///
/// **Loading sources** (in priority order, later overrides earlier for same name):
/// 1. `Resources/skills/*.md`   → built-in chat skills
/// 2. `Resources/tools/*.md`    → built-in tool skills
/// 3. `LOCAL_TOOLS.json`        → legacy bundled tools (bridge to Skill)
/// 4. `Documents/skills/*.md`   → user chat skills
/// 5. `Documents/tools/*.md`    → user tool skills
/// 6. `Documents/user_skills.json` → legacy user chat skills (JSON-encoded)
///
/// This replaces the old chat-only `SkillRegistry` and works alongside
/// `ToolRegistry` via the backward-compat bridge in `ToolRegistryCompat`.
@MainActor
final class SkillRegistry: ObservableObject {
    static let shared = SkillRegistry()

    private static let logger = Logger(subsystem: "com.pelbagai", category: "SkillRegistry")

    @Published private(set) var builtInSkills: [Skill] = []
    @Published private(set) var userSkills: [Skill] = []
    @Published private(set) var recentSkillNames: [String] = []

    // MARK: - Computed Views

    var allSkills: [Skill] {
        builtInSkills + userSkills
    }

    var chatSkills: [Skill] {
        allSkills.filter { $0.type == .chat }
    }

    var toolSkills: [Skill] {
        allSkills.filter { $0.type == .tool }
    }

    var recentSkills: [Skill] {
        let all = allSkills
        return recentSkillNames.compactMap { name in
            all.first(where: { $0.name == name })
        }
    }

    // MARK: - Init

    private init() {
        loadAll()
    }

    /// Reload all skills from all sources.
    func loadAll() {
        var builtIns: [Skill] = []

        // 1. Bundle: Resources/skills/*.md → chat skills
        let bundledChat = loadBundledMarkdown(subdirectory: "skills", isBuiltIn: true)
        builtIns += bundledChat

        if bundledChat.isEmpty {
            Self.logger.info("SkillRegistry: Bundled chat skills empty, loading safety fallbacks")
            builtIns += loadFallbackChatSkills()
        }

        // 2. Bundle: Resources/tools/*.md → tool skills
        builtIns += loadBundledMarkdown(subdirectory: "tools", isBuiltIn: true)

        // 3. Legacy: LOCAL_TOOLS.json → bridge to Skill
        builtIns += loadLegacyToolDefinitions()

        // Deduplicate: prefer markdown versions over JSON legacy
        var seen = Set<String>()
        var deduped: [Skill] = []
        for skill in builtIns {
            if !seen.contains(skill.name) {
                seen.insert(skill.name)
                deduped.append(skill)
            }
        }
        self.builtInSkills = deduped

        // 4-6. User skills
        loadUserSkills()
        loadRecentSkills()

        Self.logger.info("SkillRegistry: Loaded \(self.builtInSkills.count) built-in, \(self.userSkills.count) user skills (\(self.chatSkills.count) chat, \(self.toolSkills.count) tool)")
    }

    // MARK: - CRUD

    func registerSkill(_ skill: Skill) {
        if let idx = userSkills.firstIndex(where: { $0.name == skill.name }) {
            userSkills[idx] = skill
        } else {
            userSkills.append(skill)
        }
        saveUserSkills()
    }

    /// Install a skill from a markdown string.
    @discardableResult
    func install(from markdown: String, isBuiltIn: Bool = false) throws -> Skill {
        guard var skill = SkillParser.parse(from: markdown, isBuiltIn: isBuiltIn) else {
            throw SkillRegistryError.parseFailed
        }
        skill.isBuiltIn = isBuiltIn
        if isBuiltIn {
            if let idx = builtInSkills.firstIndex(where: { $0.name == skill.name }) {
                builtInSkills[idx] = skill
            } else {
                builtInSkills.append(skill)
            }
        } else {
            registerSkill(skill)
        }
        return skill
    }

    /// Install a skill from a file URL.
    @discardableResult
    func install(from url: URL) throws -> Skill {
        let markdown = try String(contentsOf: url, encoding: .utf8)
        return try install(from: markdown)
    }

    func removeUserSkill(named name: String) {
        userSkills.removeAll { $0.name == name }
        recentSkillNames.removeAll { $0 == name }
        saveUserSkills()
        saveRecentSkills()
    }

    func uninstall(id: String) {
        removeUserSkill(named: id)
    }

    // MARK: - Query

    func skill(byID id: String) -> Skill? {
        allSkills.first { $0.name == id }
    }

    func skill(byName name: String) -> Skill? {
        allSkills.first { $0.name == name }
    }

    func skills(withCapability cap: SkillCapability) -> [Skill] {
        allSkills.filter { $0.capabilities.contains(cap) }
    }

    func skills(matching keywords: [String]) -> [Skill] {
        let lowered = keywords.map { $0.lowercased() }
        return allSkills.filter { skill in
            guard let skillKeywords = skill.keywords else { return false }
            let skillLowered = skillKeywords.map { $0.lowercased() }
            return lowered.contains { kw in skillLowered.contains { $0.contains(kw) } }
        }
    }

    // MARK: - Usage Tracking

    func recordSkillUsed(_ skill: Skill) {
        recordUsed(id: skill.name)
    }

    func recordUsed(id: String) {
        recentSkillNames.removeAll { $0 == id }
        recentSkillNames.insert(id, at: 0)
        if recentSkillNames.count > 10 {
            recentSkillNames = Array(recentSkillNames.prefix(10))
        }
        saveRecentSkills()
    }

    // MARK: - Backward Compat Bridge

    /// Returns all tool-type skills as legacy LocalToolDefinition instances.
    /// Used by ToolRegistryCompat to keep existing code working.
    func allToolDefinitions() -> [LocalToolDefinition] {
        toolSkills.compactMap { $0.toToolDefinition() }
    }

    /// Look up a tool definition by toolID, using the skill registry.
    func toolDefinition(for toolID: String) -> LocalToolDefinition? {
        let normalized = LocalToolDefinition.normalizedToolID(toolID)
        return allSkills.first { $0.name == normalized }?.toToolDefinition()
    }

    // MARK: - Private: Loading

    private func loadBundledMarkdown(subdirectory: String, isBuiltIn: Bool) -> [Skill] {
        var skills: [Skill] = []
        guard let bundleURL = Bundle.main.url(forResource: subdirectory, withExtension: nil) else {
            Self.logger.info("SkillRegistry: No bundle directory '\(subdirectory)' found")
            return skills
        }

        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: bundleURL, includingPropertiesForKeys: nil) else {
            return skills
        }

        for fileURL in urls {
            if fileURL.pathExtension.lowercased() == "md",
               let md = try? String(contentsOf: fileURL, encoding: .utf8),
               var skill = SkillParser.parse(from: md, isBuiltIn: isBuiltIn,
                                              fallbackName: fileURL.deletingPathExtension().lastPathComponent) {
                skill.isBuiltIn = isBuiltIn
                skills.append(skill)
            }
        }

        Self.logger.info("SkillRegistry: Loaded \(skills.count) skills from bundle/\(subdirectory)")
        return skills
    }

    private func loadLegacyToolDefinitions() -> [Skill] {
        guard let url = Bundle.main.url(forResource: "LOCAL_TOOLS", withExtension: "json") else {
            return []
        }

        do {
            let data = try Data(contentsOf: url)
            let defs = try JSONDecoder().decode([LocalToolDefinition].self, from: data)
            let skills = defs.map { Skill.from(definition: $0, isBuiltIn: true) }
            Self.logger.info("SkillRegistry: Bridged \(skills.count) legacy tool definitions")
            return skills
        } catch {
            Self.logger.error("SkillRegistry: Failed to load LOCAL_TOOLS.json: \(error)")
            return []
        }
    }

    // MARK: - Private: User Skills Storage

    private var userSkillsStorageURL: URL {
        let fm = FileManager.default
        let docs = try! fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return docs.appendingPathComponent("user_skills.json")
    }

    private var userSkillsMDDirectory: URL {
        let fm = FileManager.default
        let docs = try! fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return docs.appendingPathComponent("skills")
    }

    private var userToolsMDDirectory: URL {
        let fm = FileManager.default
        let docs = try! fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return docs.appendingPathComponent("tools")
    }

    private func loadUserSkills() {
        var skills: [Skill] = []

        // Load from Documents/skills/*.md
        skills += loadUserMarkdown(from: userSkillsMDDirectory)

        // Load from Documents/tools/*.md
        skills += loadUserMarkdown(from: userToolsMDDirectory)

        // Load legacy JSON-encoded user skills
        let jsonURL = userSkillsStorageURL
        if FileManager.default.fileExists(atPath: jsonURL.path) {
            do {
                let data = try Data(contentsOf: jsonURL)
                let decoded = try JSONDecoder().decode([Skill].self, from: data)
                // Only add if not already loaded from MD
                let existingNames = Set(skills.map(\.name))
                for skill in decoded where !existingNames.contains(skill.name) {
                    skills.append(skill)
                }
                Self.logger.info("SkillRegistry: Loaded \(decoded.count) legacy JSON user skills")
            } catch {
                Self.logger.error("SkillRegistry: Failed to load user_skills.json: \(error)")
            }
        }

        // Load legacy user tool definitions
        let userToolDefsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("local_tool_definitions.json")
        if FileManager.default.fileExists(atPath: userToolDefsURL.path) {
            do {
                let data = try Data(contentsOf: userToolDefsURL)
                let defs = try JSONDecoder().decode([LocalToolDefinition].self, from: data)
                let existingNames = Set(skills.map(\.name))
                for def in defs {
                    let skill = Skill.from(definition: def, isBuiltIn: false)
                    if !existingNames.contains(skill.name) {
                        skills.append(skill)
                    }
                }
                Self.logger.info("SkillRegistry: Bridged \(defs.count) legacy user tool definitions")
            } catch {
                Self.logger.error("SkillRegistry: Failed to load legacy user tool definitions: \(error)")
            }
        }

        self.userSkills = skills
    }

    private func loadUserMarkdown(from directory: URL) -> [Skill] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return [] }

        var skills: [Skill] = []
        if let urls = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for fileURL in urls {
                if fileURL.pathExtension.lowercased() == "md",
                   let md = try? String(contentsOf: fileURL, encoding: .utf8),
                   var skill = SkillParser.parse(from: md, isBuiltIn: false,
                                                  fallbackName: fileURL.deletingPathExtension().lastPathComponent) {
                    skill.isBuiltIn = false
                    skills.append(skill)
                }
            }
        }
        return skills
    }

    private func saveUserSkills() {
        do {
            let data = try JSONEncoder().encode(userSkills)
            try data.write(to: userSkillsStorageURL)
            Self.logger.info("SkillRegistry: Saved \(self.userSkills.count) user skills")
        } catch {
            Self.logger.error("SkillRegistry: Failed to save user skills: \(error)")
        }
    }

    private func loadRecentSkills() {
        if let saved = UserDefaults.standard.stringArray(forKey: "recent_skills_cache") {
            recentSkillNames = saved
        }
    }

    private func saveRecentSkills() {
        UserDefaults.standard.set(recentSkillNames, forKey: "recent_skills_cache")
    }

    // MARK: - Hardcoded Fallback Skills

    /// Emergency fallback chat skills used when no .md files are found in the bundle.
    /// These match the original hardcoded skills from the previous SkillRegistry.
    func loadFallbackChatSkills() -> [Skill] {
        let wikiHTML = """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; margin: 0; padding: 12px; background: transparent; color: #1c1c1e; }
            .dark-mode { color: #f2f2f7; }
            .wiki-card { background: rgba(255, 255, 255, 0.7); backdrop-filter: blur(10px); border-radius: 12px; padding: 16px; border: 1px solid rgba(0,0,0,0.08); box-shadow: 0 4px 12px rgba(0,0,0,0.05); }
            .dark-mode .wiki-card { background: rgba(30, 30, 32, 0.7); border-color: rgba(255,255,255,0.08); }
            .title { font-weight: bold; font-size: 18px; margin-bottom: 6px; color: #007aff; }
            .dark-mode .title { color: #0a84ff; }
            .extract { font-size: 14px; line-height: 1.4; opacity: 0.85; }
            .loader { border: 2px solid #f3f3f3; border-top: 2px solid #3498db; border-radius: 50%; width: 20px; height: 20px; animation: spin 1s linear infinite; margin: 10px auto; }
            @keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }
          </style>
        </head>
        <body>
          <div class="wiki-card" id="card">
            <div id="loader" class="loader"></div>
            <div class="title" id="title">Searching Wikipedia...</div>
            <div class="extract" id="extract">Contacting Wikipedia servers for factual grounding details.</div>
          </div>
          <script>
            if (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) {
              document.body.classList.add('dark-mode');
            }
            async function searchWiki(query) {
              try {
                const response = await fetch(`https://en.wikipedia.org/api/rest_v1/page/summary/${encodeURIComponent(query)}`);
                if (!response.ok) throw new Error('Wiki page not found');
                const data = await response.json();
                document.getElementById('loader').style.display = 'none';
                document.getElementById('title').innerText = data.title;
                document.getElementById('extract').innerText = data.extract;
              } catch(e) {
                document.getElementById('loader').style.display = 'none';
                document.getElementById('title').innerText = 'Query Failed';
                document.getElementById('extract').innerText = 'Could not retrieve information for: ' + query;
              }
            }
            window.executeSkill = function(input) {
              const json = JSON.parse(input);
              const topic = json.topic || json.query || json.text || '';
              if (topic) {
                searchWiki(topic);
              }
            };
          </script>
        </body>
        </html>
        """

        let moodHTML = """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; margin: 0; padding: 12px; background: transparent; color: #1c1c1e; text-align: center; }
            .dark-mode { color: #f2f2f7; }
            .card { background: rgba(255, 255, 255, 0.7); backdrop-filter: blur(10px); border-radius: 16px; padding: 16px; border: 1px solid rgba(0,0,0,0.08); box-shadow: 0 4px 12px rgba(0,0,0,0.05); }
            .dark-mode .card { background: rgba(30, 30, 32, 0.7); border-color: rgba(255,255,255,0.08); }
            .title { font-weight: bold; font-size: 16px; margin-bottom: 12px; }
            .emoji-row { display: flex; justify-content: space-around; margin: 12px 0; }
            .emoji-btn { font-size: 28px; cursor: pointer; transition: transform 0.2s; border: none; background: none; }
            .emoji-btn:hover { transform: scale(1.25); }
            .status-text { font-size: 13px; opacity: 0.8; margin-top: 8px; font-weight: 500; }
          </style>
        </head>
        <body>
          <div class="card">
            <div class="title">How are you feeling today?</div>
            <div class="emoji-row">
              <button class="emoji-btn" onclick="selectMood('😃', 'Awesome')">😃</button>
              <button class="emoji-btn" onclick="selectMood('😊', 'Good')">😊</button>
              <button class="emoji-btn" onclick="selectMood('😐', 'Okay')">😐</button>
              <button class="emoji-btn" onclick="selectMood('😔', 'Sad')">😔</button>
              <button class="emoji-btn" onclick="selectMood('😠', 'Angry')">😠</button>
            </div>
            <div class="status-text" id="status">Select an emoji to log mood</div>
          </div>
          <script>
            if (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) {
              document.body.classList.add('dark-mode');
            }
            function selectMood(emoji, label) {
              document.getElementById('status').innerText = 'Logged: ' + emoji + ' ' + label;
              if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.pelbagaiBridge) {
                window.webkit.messageHandlers.pelbagaiBridge.postMessage({
                  type: 'moodLogged',
                  emoji: emoji,
                  label: label
                });
              }
            }
          </script>
        </body>
        </html>
        """

        let hashHTML = """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; margin: 0; padding: 12px; background: transparent; color: #1c1c1e; }
            .dark-mode { color: #f2f2f7; }
            .card { background: rgba(255, 255, 255, 0.7); backdrop-filter: blur(10px); border-radius: 16px; padding: 16px; border: 1px solid rgba(0,0,0,0.08); box-shadow: 0 4px 12px rgba(0,0,0,0.05); }
            .dark-mode .card { background: rgba(30, 30, 32, 0.7); border-color: rgba(255,255,255,0.08); }
            .hash-box { font-family: monospace; font-size: 12px; background: rgba(0,0,0,0.04); border-radius: 8px; padding: 10px; word-break: break-all; margin: 8px 0; }
            .dark-mode .hash-box { background: rgba(255,255,255,0.05); }
            .title { font-weight: bold; font-size: 14px; }
          </style>
        </head>
        <body>
          <div class="card">
            <div class="title">SHA-256 Secure Hash</div>
            <div class="hash-box" id="sha256">Hashing...</div>
          </div>
          <script>
            if (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) {
              document.body.classList.add('dark-mode');
            }
            async function sha256(message) {
              const msgBuffer = new TextEncoder().encode(message);
              const hashBuffer = await crypto.subtle.digest('SHA-256', msgBuffer);
              const hashArray = Array.from(new Uint8Array(hashBuffer));
              const hashHex = hashArray.map(b => b.toString(16).padStart(2, '0')).join('').toUpperCase();
              document.getElementById('sha256').innerText = hashHex;
              
              setTimeout(() => {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.pelbagaiBridge) {
                  window.webkit.messageHandlers.pelbagaiBridge.postMessage(document.documentElement.outerHTML);
                }
              }, 500);
            }
            window.executeSkill = function(input) {
              const json = JSON.parse(input);
              const text = json.text || '';
              if (text) {
                sha256(text);
              }
            };
          </script>
        </body>
        </html>
        """

        let qrHTML = """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700&display=swap" rel="stylesheet">
          <style>
            body {
              font-family: 'Plus Jakarta Sans', -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
              margin: 0;
              padding: 12px;
              background: transparent;
              color: #1c1c1e;
              text-align: center;
              display: flex;
              justify-content: center;
              align-items: center;
            }
            .dark-mode {
              color: #f2f2f7;
            }
            .card {
              background: rgba(255, 255, 255, 0.5);
              backdrop-filter: blur(20px);
              -webkit-backdrop-filter: blur(20px);
              border-radius: 24px;
              padding: 20px;
              border: 1px solid rgba(255, 255, 255, 0.5);
              box-shadow: 0 10px 30px rgba(0, 0, 0, 0.06);
              width: 100%;
              max-width: 280px;
              margin: 0 auto;
              box-sizing: border-box;
              transition: all 0.3s ease;
            }
            .dark-mode .card {
              background: rgba(28, 28, 30, 0.6);
              border-color: rgba(255, 255, 255, 0.08);
              box-shadow: 0 10px 30px rgba(0, 0, 0, 0.2);
            }
            .qr-container {
              position: relative;
              width: 150px;
              height: 150px;
              margin: 12px auto;
              background: linear-gradient(135deg, #007aff, #00c6ff);
              padding: 3px;
              border-radius: 20px;
              box-shadow: 0 8px 24px rgba(0, 122, 255, 0.15);
              transition: transform 0.2s ease, box-shadow 0.2s ease;
              cursor: pointer;
              -webkit-tap-highlight-color: transparent;
            }
            .dark-mode .qr-container {
              background: linear-gradient(135deg, #0a84ff, #30d158);
              box-shadow: 0 8px 24px rgba(10, 132, 255, 0.25);
            }
            .qr-container:hover {
              transform: scale(1.03);
              box-shadow: 0 12px 32px rgba(0, 122, 255, 0.25);
            }
            .qr-container:active {
              transform: scale(0.96);
            }
            .qr-img {
              width: 100%;
              height: 100%;
              display: block;
              border-radius: 17px;
              background: white;
              box-sizing: border-box;
              transition: transform 0.15s ease;
            }
            .label {
              font-size: 13px;
              font-weight: 500;
              word-break: break-all;
              opacity: 0.9;
              margin-bottom: 8px;
              color: #3a3a3c;
              line-height: 1.4;
            }
            .dark-mode .label {
              color: #e5e5ea;
            }
            .hint {
              font-size: 10px;
              font-weight: 500;
              color: #8e8e93;
              margin-bottom: 16px;
              display: flex;
              align-items: center;
              justify-content: center;
              gap: 4px;
            }
            .save-btn {
              background: linear-gradient(135deg, #007aff, #0056b3);
              color: white;
              border: none;
              padding: 10px 20px;
              border-radius: 12px;
              font-size: 13px;
              font-weight: 600;
              cursor: pointer;
              display: inline-flex;
              align-items: center;
              justify-content: center;
              gap: 8px;
              transition: all 0.2s ease;
              box-shadow: 0 4px 12px rgba(0, 122, 255, 0.3);
              width: 100%;
              box-sizing: border-box;
            }
            .save-btn:hover {
              transform: translateY(-1px);
              box-shadow: 0 6px 16px rgba(0, 122, 255, 0.4);
            }
            .save-btn:active {
              transform: translateY(1px) scale(0.98);
            }
            .dark-mode .save-btn {
              background: linear-gradient(135deg, #0a84ff, #0056b3);
              box-shadow: 0 4px 12px rgba(10, 132, 255, 0.3);
            }
            .svg-icon {
              width: 14px;
              height: 14px;
              fill: none;
              stroke: currentColor;
              stroke-width: 2.5;
              stroke-linecap: round;
              stroke-linejoin: round;
            }
          </style>
        </head>
        <body>
          <div class="card">
            <div class="qr-container" id="qrContainer">
              <img class="qr-img" id="qr" onload="onQrLoad()" alt="QR Code" />
            </div>
            <div class="label" id="label">Generating...</div>
            <button class="save-btn" id="saveBtn" onclick="saveQR()" style="display: none; margin-top: 8px;">
              <svg class="svg-icon" viewBox="0 0 24 24"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4M7 10l5 5 5-5M12 15V3"/></svg>
              Save QR Code
            </button>
          </div>
          <script>
            if (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) {
              document.body.classList.add('dark-mode');
            }
            
            function onQrLoad() {
              const qrSrc = document.getElementById('qr').src;
              if (!qrSrc || qrSrc === "" || qrSrc === window.location.href) {
                return;
              }
              document.getElementById('saveBtn').style.display = 'inline-flex';
            }
            
            function saveQR() {
              const qrSrc = document.getElementById('qr').src;
              if (!qrSrc || qrSrc === "" || qrSrc === window.location.href) {
                return;
              }
              if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.pelbagaiBridge) {
                window.webkit.messageHandlers.pelbagaiBridge.postMessage({
                  type: 'saveImage',
                  url: qrSrc
                });
              }
            }
            
            window.executeSkill = function(input) {
              const json = JSON.parse(input);
              const text = json.text || json.url || 'Hello';
              document.getElementById('qr').src = `https://api.qrserver.com/v1/create-qr-code/?size=1080x1080&data=${encodeURIComponent(text)}`;
              document.getElementById('label').innerText = text;
              
              setTimeout(() => {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.pelbagaiBridge) {
                  window.webkit.messageHandlers.pelbagaiBridge.postMessage(document.documentElement.outerHTML);
                }
              }, 500);
            };
          </script>
        </body>
        </html>
        """

        return [
            Skill(
                name: "query-wikipedia",
                displayName: "Wikipedia Query",
                description: "Query summary extracts from Wikipedia for any given topic to ground factual chat.",
                instructions: """
                You are a Wikipedia Search assistant.
                When the user asks about a topic, identify the single most appropriate canonical Wikipedia article title.
                You MUST output a JSON block containing ONLY this exact canonical topic name, formatted as:
                ```json
                {
                  "topic": "Exact Topic Name"
                }
                ```
                For example:
                - "What is quantum computing?" -> {"topic": "Quantum computing"}
                - "Tell me about cats" -> {"topic": "Cat"}
                - "Who was Albert Einstein?" -> {"topic": "Albert Einstein"}

                Do NOT include natural language questions, punctuation, conversational phrases, or extra words in the JSON topic field.
                Keep your response concise, using only 2-3 informative sentences.
                Ensure your response is helpful and ends on a complete sentence in the same language as the user's prompt.
                """,
                isBuiltIn: true,
                icon: "globe.americas.fill",
                color: "cyan",
                htmlContent: wikiHTML
            ),
            Skill(
                name: "personal-finance-coach",
                displayName: "Personal Finance Coach",
                description: "Provides practical, research-grounded guidance on budgeting, savings, and debt payoff.",
                instructions: """
                You are a Personal Finance Coach.
                Provide structured, practical, and highly actionable advice on budgeting, emergency fund planning, and debt repayment (using the avalanche or snowball method).
                Do not offer direct licensed investment advice or replace fiduciary professionals.
                Format your responses in clear bullet points or numbered lists.
                """,
                isBuiltIn: true,
                icon: "dollarsign.circle.fill",
                color: "green"
            ),
            Skill(
                name: "fire-service-advisor",
                displayName: "Fire Service Advisor",
                description: "Provides emergency triage, safety guidance, and incident response advice.",
                instructions: """
                You are a Fire Service Advisor.
                Provide clear, calm, and structured safety guidance, triage advice, and emergency response instructions.
                Always prioritize human safety, evacuation protocols, containment steps, and contacting official emergency services (911/999/112).
                Bold key safety actions so they stand out immediately.
                """,
                isBuiltIn: true,
                icon: "flame.fill",
                color: "orange"
            ),
            Skill(
                name: "mood-tracker",
                displayName: "Mood Tracker",
                description: "Interactive mood logging and supportive emotional reflection guidance.",
                instructions: """
                You are a Mood Tracker assistant.
                Help the user log their feelings, mood, and reflections.
                Be highly empathetic, supportive, and non-judgmental.
                Ask clarifying questions about their feelings when they offer vague statements, and guide them in positive mental wellness exercises.
                """,
                isBuiltIn: true,
                icon: "heart.text.square.fill",
                color: "pink",
                htmlContent: moodHTML
            ),
            Skill(
                name: "calculate-hash",
                displayName: "Hash Calculator",
                description: "Calculates standard cryptographic hashes (MD5, SHA-1, SHA-256) of input sequences.",
                instructions: """
                You are a Cryptographic Hash Calculator assistant.
                Provide the user with standard, detailed cryptographic hashes (like MD5, SHA-1, or SHA-256) for any text input they provide.
                Explain the theoretical difference between collision resistance and speed in secure hashing algorithms.
                Always present the final hashes in clear, mono-spaced uppercase blocks.
                """,
                isBuiltIn: true,
                icon: "lock.shield.fill",
                color: "purple",
                htmlContent: hashHTML
            ),
            Skill(
                name: "qr-code",
                displayName: "QR Generator",
                description: "Generates QR codes for target URLs, Contact Cards, or custom texts.",
                instructions: """
                You are a QR Code Generator assistant.
                Help the user formulate custom payload structures (URLs, Contact Cards, Wi-Fi configuration details) to embed in QR codes.
                Instruct the user on how the dense matrix barcode format handles error correction levels (L, M, Q, H).
                """,
                isBuiltIn: true,
                icon: "qrcode",
                color: "blue",
                htmlContent: qrHTML
            ),
            Skill(
                name: "send-email",
                displayName: "Email Builder",
                description: "Drafts and structures formal or casual emails with standard headers.",
                instructions: """
                You are an Email Drafting assistant.
                Help the user compose high-quality professional, formal, or casual emails.
                Suggest optimized and catchy subject lines, structure standard greeting sections, and draft cohesive, clear, and action-oriented message bodies.
                Always separate the final draft components clearly (Subject:, Body:) with horizontal dividers.
                """,
                isBuiltIn: true,
                icon: "envelope.fill",
                color: "cyan"
            ),
            Skill(
                name: "text-spinner",
                displayName: "Text Paraphraser",
                description: "Spins and reformulates input texts into multiple stylistic variations.",
                instructions: """
                You are a Text Spinner and Paraphraser assistant.
                Rewrite, spin, and rephrase input sentences or paragraphs into several highly distinct variations (e.g. Formal, Creative, Professional, Direct, and Persuasive).
                Provide a side-by-side comparison matrix of the spun options, explaining the distinct tone and sentiment of each.
                """,
                isBuiltIn: true,
                icon: "arrow.triangle.2.circlepath",
                color: "orange"
            ),
            Skill(
                name: "kitchen-adventure",
                displayName: "Kitchen Chef",
                description: "Plans recipes, suggests ingredient substitutions, and guides prep timelines.",
                instructions: """
                You are a Kitchen Adventure chef assistant.
                Help the user construct customized recipes based strictly on the ingredients they have available.
                Offer smart ingredient substitutions, step-by-step culinary preparation techniques, and approximate cooking/prep timelines.
                Ensure safety and food hygiene warnings are clearly highlighted.
                """,
                isBuiltIn: true,
                icon: "fork.knife",
                color: "pink"
            ),
            Skill(
                name: "interactive-map",
                displayName: "Route Planner",
                description: "Assists in route optimization, geospatial travel planning, and landmarks.",
                instructions: """
                You are an Interactive Map and Route Optimizer assistant.
                Analyze starting points, destinations, and intermediate waypoints to propose optimized navigation pathways.
                Provide the user with approximate transit durations, local terrain considerations, and key historical landmarks along the way.
                """,
                isBuiltIn: true,
                icon: "map.fill",
                color: "green"
            ),
        ]
    }
}

// MARK: - Errors

enum SkillRegistryError: LocalizedError {
    case parseFailed
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .parseFailed:
            return "Failed to parse skill from markdown"
        case .notFound(let id):
            return "Skill not found: \(id)"
        }
    }
}
