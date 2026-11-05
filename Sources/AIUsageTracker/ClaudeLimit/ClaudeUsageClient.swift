import Foundation
import WebKit

/// Reads your plan usage from claude.ai the same way claude.ai's own Usage page does.
///
/// There is no official API for this. The requests run inside a hidden copy of
/// Safari's web engine so claude.ai's bot protection sees an ordinary browser.
@MainActor
final class ClaudeUsageClient {
    enum FetchError: LocalizedError {
        case signedOut
        case blocked
        case noOrganization
        case unexpected(status: Int)

        var errorDescription: String? {
            switch self {
            case .signedOut: "Your claude.ai sign-in has expired."
            case .blocked: "claude.ai's bot check didn't let the app through."
            case .noOrganization: "Couldn't find your Claude account."
            case .unexpected(let status): "claude.ai answered with an unexpected error (\(status))."
            }
        }
    }

    struct Result {
        let snapshot: UsageSnapshot
        /// "Pro", "Max", ... when claude.ai's account details say so; nil if unclear.
        let plan: String?
    }

    private var webView: WKWebView?
    private var organizationID: String?
    private var plan: String?

    func fetch() async throws -> Result {
        try await loadClaudeOrigin(force: false)
        let orgID = try await resolveOrganization()

        var response = try await get("/api/organizations/\(orgID)/usage")
        if response.isBotCheck {
            Log.write("usage: bot check on usage request, reloading and retrying once")
            try await loadClaudeOrigin(force: true)
            response = try await get("/api/organizations/\(orgID)/usage")
        }

        if response.isBotCheck { throw FetchError.blocked }

        switch response.status {
        case 200:
            let snapshot = try UsageSnapshot.parse(Data(response.body.utf8))
            let five = snapshot.fiveHour.map { "\($0.utilization)" } ?? "none"
            let week = snapshot.weekly.map { "\($0.utilization)" } ?? "none"
            Log.write("usage: ok 5h=\(five) weekly=\(week)")
            return Result(snapshot: snapshot, plan: plan)
        case 401, 403:
            Log.write("usage: signed out (\(response.status))")
            organizationID = nil
            throw FetchError.signedOut
        default:
            Log.write("usage: unexpected \(response.status) \(response.body.prefix(300))")
            throw FetchError.unexpected(status: response.status)
        }
    }

    /// A chat touched recently, and whether Claude is still writing its reply.
    struct ChatActivity: Sendable {
        let id: String
        let name: String
        let updatedAt: Date
        let isReplying: Bool
        /// When the newest message in the chat was sent.
        let lastMessageAt: Date?
    }

    /// Checks your most recent chats for one that's still being answered.
    ///
    /// claude.ai saves Claude's reply only once it's finished, so while Claude is writing,
    /// the newest message in the chat is still yours. (Verified live: a reply that took two
    /// minutes appeared in the chat at the moment it finished.) Each chat lists its newest
    /// message's ID, so the full chat is downloaded only when that ID changes, about twice
    /// per question. A reply that failed shows up through `completion_status`'s `is_error`.
    func fetchChatActivity(recentWithin: TimeInterval) async throws -> [ChatActivity] {
        try await loadClaudeOrigin(force: false)
        let orgID = try await resolveOrganization()
        guard let webView else { throw FetchError.blocked }

        let script = """
        const opts = { credentials: 'include', headers: { 'accept': 'application/json' } };
        const base = `/api/organizations/${org}/chat_conversations`;
        const known = (window.__aiUsageNewest = window.__aiUsageNewest || {});
        const list = await fetch(`${base}_v2?limit=5&consistency=eventual`, opts);
        if (!list.ok) return { status: list.status };
        const recent = ((await list.json()).data || [])
            .filter(c => Date.now() - Date.parse(c.updated_at) <= recentMs);
        const chats = await Promise.all(recent.map(async c => {
            const newestID = c.current_leaf_message_uuid;
            let newest = newestID && known[newestID];
            if (!newest) {
                const r = await fetch(`${base}/${c.uuid}?tree=True&rendering_mode=messages&consistency=strong`, opts);
                if (!r.ok) return null;
                const t = await r.json();
                const msgs = t.chat_messages || [];
                const id = newestID || t.current_leaf_message_uuid;
                const m = msgs.find(x => x.uuid === id) || msgs[msgs.length - 1];
                newest = m ? { sender: m.sender, at: Date.parse(m.created_at) / 1000 } : { sender: 'none', at: 0 };
                if (id) known[id] = newest;
            }
            let replying = newest.sender === 'human';
            if (replying) {
                const s = await fetch(`${base}/${c.uuid}/completion_status?poll=false`, opts);
                if (s.ok && (await s.json()).is_error === true) replying = false;
            }
            return { id: c.uuid, name: c.name || '', updatedAt: Date.parse(c.updated_at) / 1000, replying, sentAt: newest.at };
        }));
        return { status: 200, chats: chats.filter(Boolean) };
        """
        let result = try await webView.callAsyncJavaScript(
            script,
            arguments: ["org": orgID, "recentMs": recentWithin * 1000],
            contentWorld: .defaultClient
        )
        guard let dict = result as? [String: Any], let status = (dict["status"] as? NSNumber)?.intValue else {
            throw FetchError.unexpected(status: -1)
        }
        switch status {
        case 200: break
        case 401, 403: throw FetchError.signedOut
        default: throw FetchError.unexpected(status: status)
        }
        let rows = dict["chats"] as? [[String: Any]] ?? []
        return rows.compactMap { row in
            guard let id = row["id"] as? String, let updated = (row["updatedAt"] as? NSNumber)?.doubleValue else { return nil }
            let sent = (row["sentAt"] as? NSNumber)?.doubleValue ?? 0
            return ChatActivity(
                id: id,
                name: row["name"] as? String ?? "",
                updatedAt: Date(timeIntervalSince1970: updated),
                isReplying: (row["replying"] as? NSNumber)?.boolValue ?? false,
                lastMessageAt: sent > 0 ? Date(timeIntervalSince1970: sent) : nil
            )
        }
    }

    /// Forget cached account details (after sign-out or a new sign-in).
    func reset() {
        organizationID = nil
        plan = nil
        webView = nil
    }

    // MARK: - Steps

    /// Opens a claude.ai address in the hidden web view so later requests come
    /// from claude.ai itself. Waits out claude.ai's brief "checking your browser" step if shown.
    private func loadClaudeOrigin(force: Bool) async throws {
        if !force, let webView, webView.url?.host == "claude.ai", !webView.isLoading { return }

        let view = webView ?? WKWebView(frame: .zero, configuration: ClaudeWebSession.shared.makeConfiguration())
        webView = view
        view.load(URLRequest(url: URL(string: "https://claude.ai/api/organizations")!))

        for _ in 0..<30 {
            try await Task.sleep(for: .seconds(1))
            guard !view.isLoading, view.url?.host == "claude.ai" else { continue }
            let text = (try? await view.evaluateJavaScript("document.body ? document.body.innerText : ''")) as? String ?? ""
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("[") || trimmed.hasPrefix("{") { return }
        }
        Log.write("usage: claude.ai never returned data while loading (likely bot check)")
        throw FetchError.blocked
    }

    /// Finds which Claude account to read (people can belong to several, e.g. personal + API).
    private func resolveOrganization() async throws -> String {
        if let organizationID { return organizationID }

        let response = try await get("/api/organizations")
        if response.status == 401 || response.status == 403 { throw response.isBotCheck ? FetchError.blocked : FetchError.signedOut }
        guard response.status == 200,
              let orgs = try? JSONSerialization.jsonObject(with: Data(response.body.utf8)) as? [[String: Any]]
        else { throw FetchError.unexpected(status: response.status) }

        // Prefer the account you last used on claude.ai, then any chat account.
        let lastActive = await ClaudeWebSession.shared.cookieValue(named: "lastActiveOrg")
        let org = orgs.first { ($0["uuid"] as? String) == lastActive }
            ?? orgs.first { ($0["capabilities"] as? [String])?.contains("chat") == true }
            ?? orgs.first
        guard let org, let id = org["uuid"] as? String else { throw FetchError.noOrganization }

        let capabilities = org["capabilities"] as? [String] ?? []
        plan = Self.planName(from: capabilities)
        Log.write("usage: \(orgs.count) organization(s); capabilities=\(capabilities) rate_limit_tier=\(org["rate_limit_tier"] ?? "none") → plan=\(plan ?? "unknown")")
        organizationID = id
        return id
    }

    /// claude.ai lists what an account can do, e.g. ["chat", "claude_pro"].
    static func planName(from capabilities: [String]) -> String? {
        if capabilities.contains(where: { $0.contains("max") }) { return "Max" }
        if capabilities.contains("claude_pro") { return "Pro" }
        return nil
    }

    // MARK: - Requests

    private struct Response {
        let status: Int
        let body: String
        /// claude.ai's bot protection answers with an HTML page instead of data.
        var isBotCheck: Bool {
            let start = body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)
            return status == 403 && start != "{" && start != "["
        }
    }

    private func get(_ path: String) async throws -> Response {
        guard let webView else { throw FetchError.blocked }
        let script = """
        const response = await fetch(path, { credentials: 'include', headers: { 'accept': 'application/json' } });
        return { status: response.status, body: await response.text() };
        """
        let result = try await webView.callAsyncJavaScript(
            script,
            arguments: ["path": path],
            contentWorld: .defaultClient
        )
        guard let dict = result as? [String: Any],
              let status = (dict["status"] as? NSNumber)?.intValue,
              let body = dict["body"] as? String
        else { throw FetchError.unexpected(status: -1) }
        return Response(status: status, body: body)
    }
}
