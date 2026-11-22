import Foundation
import WebKit

/// WKWebView settings for showing rendered notebooks.
///
/// The page's CSP alone isn't enough: Quick Look's data-based HTML previews ignore it.
/// So static pages are shown with JavaScript switched off and URL loads blocked by a
/// content rule list — everything a rendered notebook needs is inlined as `data:` URIs.
public enum NotebookWebView {
    public enum Mode: Equatable, Sendable {
        /// JavaScript off, every load blocked except (optionally) `https:` images.
        case `static`(remoteImages: Bool)
        /// The user chose "Allow Scripts": JavaScript on and network allowed, so
        /// interactive outputs can fetch their libraries from CDNs.
        case scriptsAllowed
    }

    @MainActor
    public static func makeConfiguration(_ mode: Mode) async throws -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        if case .static(let remoteImages) = mode {
            configuration.defaultWebpagePreferences.allowsContentJavaScript = false
            configuration.userContentController.add(try await contentRules(remoteImages: remoteImages))
        }
        return configuration
    }

    // MARK: Content rules

    // WebKit's url-filter regex has no `|`, hence one rule per scheme.
    static let blockAllRulesJSON = """
    [
      {"trigger": {"url-filter": "^https?:"}, "action": {"type": "block"}},
      {"trigger": {"url-filter": "^wss?:"}, "action": {"type": "block"}},
      {"trigger": {"url-filter": "^ftp:"}, "action": {"type": "block"}},
      {"trigger": {"url-filter": "^file:"}, "action": {"type": "block"}}
    ]
    """

    /// Same, but `https:` images may load (the app's "Load remote images" setting).
    static let blockAllButHTTPSImagesRulesJSON = """
    [
      {"trigger": {"url-filter": "^http:"}, "action": {"type": "block"}},
      {"trigger": {"url-filter": "^https:", "resource-type": ["document", "style-sheet", "script", "font", "raw", "svg-document", "media", "popup", "ping", "fetch", "websocket", "other"]}, "action": {"type": "block"}},
      {"trigger": {"url-filter": "^wss?:"}, "action": {"type": "block"}},
      {"trigger": {"url-filter": "^ftp:"}, "action": {"type": "block"}},
      {"trigger": {"url-filter": "^file:"}, "action": {"type": "block"}}
    ]
    """

    @MainActor private static var cachedRules: [Bool: WKContentRuleList] = [:]

    @MainActor
    static func contentRules(remoteImages: Bool) async throws -> WKContentRuleList {
        if let rules = cachedRules[remoteImages] { return rules }
        guard let store = WKContentRuleListStore.default() else { throw CocoaError(.featureUnsupported) }
        let rules = try await store.compileContentRuleList(
            forIdentifier: remoteImages ? "me.kcpr.juprev.block-network-but-images" : "me.kcpr.juprev.block-network",
            encodedContentRuleList: remoteImages ? blockAllButHTTPSImagesRulesJSON : blockAllRulesJSON
        )
        guard let rules else { throw CocoaError(.featureUnsupported) }
        cachedRules[remoteImages] = rules
        return rules
    }

    // MARK: Navigation

    public enum NavigationDecision: Equatable {
        case allow
        case cancel
        /// A clicked web or mail link: cancel in the view, open in the default app.
        case openExternally(URL)
    }

    /// Only the page itself (loaded with `loadHTMLString(_:baseURL: nil)`) and in-page anchors
    /// may load in the view; clicked web links go to the browser, everything else is cancelled.
    public static func decision(for action: WKNavigationAction) -> NavigationDecision {
        let url = action.request.url
        if action.navigationType == .linkActivated {
            if let url, ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                return .openExternally(url)
            }
            return url?.scheme == "about" && url?.fragment != nil ? .allow : .cancel
        }
        guard action.targetFrame?.isMainFrame == true else {
            // Subframes (iframes) only exist in interactive outputs; the static CSP blocks them anyway.
            return .allow
        }
        return url?.scheme == "about" ? .allow : .cancel
    }
}
