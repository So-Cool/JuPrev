import Foundation
import WebKit

/// WKWebView settings for showing a static notebook page safely.
///
/// The page's CSP alone isn't enough: Quick Look's data-based HTML previews ignore it.
/// So static pages are shown with JavaScript switched off and every URL load blocked —
/// everything a rendered notebook needs is already inlined as `data:` URIs.
public enum StaticWebView {
    /// Content blocker rules: block all URL loads. (WebKit's url-filter regex has no `|`.)
    static let blockNetworkRulesJSON = """
    [
      {"trigger": {"url-filter": "^https?:"}, "action": {"type": "block"}},
      {"trigger": {"url-filter": "^wss?:"}, "action": {"type": "block"}},
      {"trigger": {"url-filter": "^ftp:"}, "action": {"type": "block"}},
      {"trigger": {"url-filter": "^file:"}, "action": {"type": "block"}}
    ]
    """

    @MainActor private static var cachedRules: WKContentRuleList?

    @MainActor
    public static func blockNetworkRules() async throws -> WKContentRuleList {
        if let cachedRules { return cachedRules }
        guard let store = WKContentRuleListStore.default() else {
            throw CocoaError(.featureUnsupported)
        }
        let rules = try await store.compileContentRuleList(
            forIdentifier: "ch.usi.kacper.juprev.block-network",
            encodedContentRuleList: blockNetworkRulesJSON
        )
        guard let rules else { throw CocoaError(.featureUnsupported) }
        cachedRules = rules
        return rules
    }

    /// JavaScript off, no persistent website data, all network loads blocked.
    @MainActor
    public static func makeConfiguration() async throws -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(try await blockNetworkRules())
        return configuration
    }
}
