import SwiftUI
import WebKit

// Compile the content rule list once so it's ready before any WKWebView loads.
actor ContentRuleListCache {
    static let shared = ContentRuleListCache()
    private var cached: WKContentRuleList?

    func get() async -> WKContentRuleList? {
        if let cached { return cached }
        let result = await withCheckedContinuation { cont in
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "TroveBlock-v5",
                encodedContentRuleList: WebView.urlBlockRules
            ) { list, _ in cont.resume(returning: list) }
        }
        cached = result
        return result
    }
}

struct WebView: NSViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    @Binding var currentURL: URL
    var state: WebViewState
    let isDark: Bool
    var initialProgress: Double = 0
    var onProgress: ((Double) -> Void)? = nil

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.addUserScript(adBlockScript)
        config.userContentController.addUserScript(scrollScript)
        config.userContentController.add(context.coordinator, name: "scroll")

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        wv.allowsBackForwardNavigationGestures = true
        wv.appearance = isDark ? NSAppearance(named: .darkAqua) : nil
        state.webView = wv

        Task {
            if let list = await ContentRuleListCache.shared.get() {
                wv.configuration.userContentController.add(list)
            }
            wv.load(URLRequest(url: url))
        }

        return wv
    }

    func updateNSView(_ wv: WKWebView, context: Context) {
        state.webView = wv
        wv.appearance = isDark ? NSAppearance(named: .darkAqua) : nil
        context.coordinator.isDark = isDark
        context.coordinator.onProgress = onProgress
        context.coordinator.initialProgress = initialProgress
        context.coordinator.applyDarkMode(to: wv)

        guard wv.url != url, !context.coordinator.isNavigating else { return }
        wv.load(URLRequest(url: url))
    }

    func makeCoordinator() -> Coordinator {
        let c = Coordinator(isLoading: $isLoading, currentURL: $currentURL, isDark: isDark)
        c.onProgress = onProgress
        c.initialProgress = initialProgress
        return c
    }

    private var scrollScript: WKUserScript {
        WKUserScript(source: Self.scrollJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }

    static let scrollJS = #"""
    (function() {
        let last = 0, t = null;
        function send() {
            const max = Math.max(1, document.documentElement.scrollHeight - window.innerHeight);
            const p = Math.min(1, Math.max(0, window.scrollY / max));
            if (Math.abs(p - last) < 0.005) return;
            last = p;
            try { window.webkit.messageHandlers.scroll.postMessage(p); } catch(_) {}
        }
        window.addEventListener('scroll', () => {
            if (t) clearTimeout(t);
            t = setTimeout(send, 400);
        }, { passive: true });
    })();
    """#

    // MARK: - Ad block user script

    private var adBlockScript: WKUserScript {
        WKUserScript(source: Self.adBlockJS, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }

    static let adBlockJS = #"""
    (function() {
        const CSS = `
            ins.adsbygoogle, .adsbygoogle,
            [data-ad-client], [data-ad-slot], [data-google-query-id],
            #google_ads_iframe_0,
            iframe[src*="doubleclick"], iframe[src*="googlesyndication"],
            iframe[src*="google_ads"], iframe[id*="google_ads"],
            .ad, .ads, .advert, .advertisement, .ad-container, .ad-wrapper,
            .ad-block, .ad-unit, .ad-slot, .ad-placement, .ad-banner,
            .ad-area, .ad-section, .ad-box, .ad-label,
            [class*="AdSlot"], [class*="adSlot"], [class*="adUnit"], [class*="adBlock"],
            [class*="GoogleAd"], [class*="google-ad"], [id*="google_ads"],
            [id^="ad-"], [id^="ad_"], [id*="dfp"], [class*="dfp-ad"],
            [class*="outbrain"], [id*="outbrain"],
            [class*="taboola"], [id*="taboola"],
            [class*="carbon-ads"], [id*="carbonads"],
            [class*="mediavine"], [id*="mediavine"],
            [class*="gpt-ad"], [id*="gpt-ad"],
            .sponsored, .sponsored-content, .sponsor-content,
            .native-ad, .native-advertising, .promoted, .promoted-content,
            .promo-ad, [class*="Sponsored"], [data-sponsored],
            [class*="sticky-ad"], [class*="floating-ad"], [class*="fixed-ad"],
            [class*="interstitial"], [class*="overlay-ad"], [class*="popup-ad"],
            .sidebar-ad, #sidebar-ad, .widget-ad, [data-ad-label],
            iframe[width="728"][height="90"],
            iframe[width="300"][height="250"],
            iframe[width="320"][height="50"],
            iframe[width="160"][height="600"],
            iframe[width="970"][height="250"] {
                display: none !important;
                visibility: hidden !important;
                max-height: 0 !important;
                overflow: hidden !important;
            }
        `;

        const style = document.createElement('style');
        style.id = '__trove_adblock__';
        style.textContent = CSS;
        document.documentElement.insertBefore(style, document.documentElement.firstChild);

        const JS_SELECTORS = [
            'ins.adsbygoogle','[data-ad-client]','[data-ad-slot]',
            '#google_ads_iframe_0','iframe[src*="doubleclick"]',
            'iframe[src*="googlesyndication"]','.adsbygoogle',
            '[class*="outbrain"]','[id*="outbrain"]',
            '[class*="taboola"]','[id*="taboola"]',
            '.sponsored','.sponsored-content','.native-ad','.promoted',
            '[class*="sticky-ad"]','[class*="floating-ad"]',
        ];

        function removeAds() {
            for (const sel of JS_SELECTORS) {
                try { document.querySelectorAll(sel).forEach(el => el.remove()); } catch(_) {}
            }
        }

        document.addEventListener('DOMContentLoaded', removeAds);
        window.addEventListener('load', removeAds);

        const observer = new MutationObserver(() => removeAds());
        const watch = () => {
            if (document.body) {
                observer.observe(document.body, { childList: true, subtree: true });
            } else {
                setTimeout(watch, 50);
            }
        };
        watch();
    })();
    """#

    // MARK: - URL-level block rules

    static let urlBlockRules = #"""
    [
      {"trigger":{"url-filter":".*\\.doubleclick\\.net"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*googlesyndication\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*googleadservices\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*google-analytics\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*amazon-adsystem\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*adnxs\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*advertising\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*outbrain\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*taboola\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*pubmatic\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*rubiconproject\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*openx\\.net"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*moatads\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*criteo\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*adsrvr\\.org"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*media\\.net"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*bidswitch\\.net"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*smartadserver\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*casalemedia\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*sovrn\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*33across\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*sharethrough\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*triplelift\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*indexexchange\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*contextweb\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*yieldmo\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*buysellads\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*carbonads\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*propellerads\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*scorecardresearch\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*quantserve\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*adsafeprotected\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*hotjar\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*mixpanel\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*segment\\.io"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*segment\\.com\\/analytics"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*facebook\\.net\\/en_US\\/fbevents"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*connect\\.facebook\\.net\\/.*\\/sdk\\/xfbml"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*platform\\.twitter\\.com\\/widgets"},"action":{"type":"block"}}
    ]
    """#

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        @Binding var isLoading: Bool
        @Binding var currentURL: URL
        var isNavigating = false
        var isDark: Bool
        var onProgress: ((Double) -> Void)?
        var initialProgress: Double = 0

        init(isLoading: Binding<Bool>, currentURL: Binding<URL>, isDark: Bool) {
            _isLoading = isLoading
            _currentURL = currentURL
            self.isDark = isDark
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "scroll", let p = message.body as? Double else { return }
            onProgress?(p)
        }

        func webView(_ wv: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
            isLoading = true; isNavigating = true
        }

        func webView(_ wv: WKWebView, didFinish _: WKNavigation!) {
            isLoading = false; isNavigating = false
            if let url = wv.url { currentURL = url }
            applyDarkMode(to: wv)
            restoreScroll(to: wv)
        }

        private func restoreScroll(to wv: WKWebView) {
            guard initialProgress > 0.01 else { return }
            let p = initialProgress
            // Wait briefly for layout to settle, then scroll proportionally.
            wv.evaluateJavaScript("""
            setTimeout(function(){
                const max = Math.max(1, document.documentElement.scrollHeight - window.innerHeight);
                window.scrollTo(0, max * \(p));
            }, 250);
            """, completionHandler: nil)
        }

        func webView(_ wv: WKWebView, didFail _: WKNavigation!, withError _: Error) {
            isLoading = false; isNavigating = false
        }

        func webView(_ wv: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError _: Error) {
            isLoading = false; isNavigating = false
        }

        // Color-override dark mode: we override backgrounds and text colors via CSS
        // rules. We never apply CSS filters anywhere, so images, videos, photos,
        // logos, and CSS background-images all keep their original colors.
        // wv.appearance = .darkAqua handles sites that natively support dark mode.
        func applyDarkMode(to wv: WKWebView) {
            let js: String
            if isDark {
                js = #"""
                (function() {
                    const css = `
                        :root { color-scheme: dark !important; }

                        html, body {
                            background-color: #1a1a1a !important;
                            color: #e8e8e8 !important;
                        }

                        /* Force transparent backgrounds on common containers so the
                           dark body color shows through. Don't touch elements likely
                           to wrap images (figure, picture). */
                        body, body div, body section, body article, body main,
                        body header, body footer, body aside, body nav,
                        body ul, body ol, body li, body dl, body dd, body dt,
                        body p, body span, body small, body em, body strong,
                        body h1, body h2, body h3, body h4, body h5, body h6,
                        body blockquote, body figure, body figcaption,
                        body table, body thead, body tbody, body tr, body td, body th,
                        body label, body fieldset, body form {
                            background-color: transparent !important;
                            border-color: #3a3a3a !important;
                        }

                        body { background-color: #1a1a1a !important; }

                        /* Text colors */
                        body, body p, body span, body div, body li, body td, body th,
                        body h1, body h2, body h3, body h4, body h5, body h6,
                        body small, body em, body strong, body blockquote,
                        body label, body figcaption, body article, body section {
                            color: #e8e8e8 !important;
                        }

                        /* Links */
                        body a, body a:link { color: #6cb0ff !important; }
                        body a:visited { color: #c084fc !important; }

                        /* Form controls */
                        body input, body textarea, body select, body button {
                            background-color: #2a2a2a !important;
                            color: #e8e8e8 !important;
                            border-color: #444 !important;
                        }

                        /* Code */
                        body pre, body code, body kbd, body samp {
                            background-color: #2a2a2a !important;
                            color: #e8e8e8 !important;
                        }

                        /* Common explicit-light utility classes */
                        body [class*="white" i], body [class*="light-bg" i],
                        body [class*="bg-white" i], body [class*="paper" i] {
                            background-color: #1a1a1a !important;
                            color: #e8e8e8 !important;
                        }

                        /* Never alter media — leave images and videos with their
                           true colors. */
                        body img, body video, body picture, body canvas, body iframe {
                            background-color: transparent !important;
                            filter: none !important;
                        }
                    `;

                    let s = document.getElementById('__trove_dark__');
                    if (!s) {
                        s = document.createElement('style');
                        s.id = '__trove_dark__';
                        document.documentElement.appendChild(s);
                    }
                    s.textContent = css;
                })();
                """#
            } else {
                js = """
                (function() {
                    document.getElementById('__trove_dark__')?.remove();
                })();
                """
            }
            wv.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}
