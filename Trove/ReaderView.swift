import SwiftUI
import WebKit

@MainActor
class ReaderState: ObservableObject {
    var webView: WKWebView?

    func captureSelection() {
        // Calls into the in-page handler so the selection (which still lives in
        // the webview's DOM) is captured atomically without crossing focus.
        webView?.evaluateJavaScript(
            "if (window.__trovePostHighlight) window.__trovePostHighlight();",
            completionHandler: nil
        )
    }
}

struct ReaderView: NSViewRepresentable {
    let title: String
    let html: String
    let isDark: Bool
    let fontSize: Double
    let useSerif: Bool
    var state: ReaderState
    var initialProgress: Double = 0
    var savedHighlights: [String] = []
    var onProgress: ((Double) -> Void)? = nil
    var onHighlight: ((String) -> Void)? = nil
    var onWordCount: ((Int) -> Void)? = nil

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(context.coordinator, name: "scroll")
        cfg.userContentController.add(context.coordinator, name: "highlight")
        cfg.userContentController.add(context.coordinator, name: "wordCount")
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = context.coordinator
        wv.appearance = isDark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
        context.coordinator.onProgress = onProgress
        context.coordinator.onHighlight = onHighlight
        context.coordinator.onWordCount = onWordCount
        context.coordinator.initialProgress = initialProgress
        context.coordinator.contentKey = stableKey()
        wv.loadHTMLString(makeHTML(), baseURL: nil)
        state.webView = wv
        return wv
    }

    func updateNSView(_ wv: WKWebView, context: Context) {
        wv.appearance = isDark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
        context.coordinator.onProgress = onProgress
        context.coordinator.onHighlight = onHighlight
        context.coordinator.onWordCount = onWordCount
        state.webView = wv

        // Only reload HTML when stable inputs change (article, font, dark).
        // Reading-progress updates must NOT trigger reloads, or the view flickers.
        let key = stableKey()
        if key != context.coordinator.contentKey {
            context.coordinator.contentKey = key
            context.coordinator.initialProgress = initialProgress
            wv.loadHTMLString(makeHTML(), baseURL: nil)
        }
    }

    private func stableKey() -> String {
        "\(title.hashValue)|\(html.hashValue)|\(isDark)|\(Int(fontSize))|\(useSerif)"
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private func makeHTML() -> String {
        let escapedTitle = title
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
        let fontStack = useSerif
            ? "Georgia, 'Palatino Linotype', Palatino, serif"
            : "-apple-system, 'SF Pro Text', 'Helvetica Neue', sans-serif"
        let highlightsJSON: String = {
            guard let data = try? JSONSerialization.data(withJSONObject: savedHighlights),
                  let s = String(data: data, encoding: .utf8) else { return "[]" }
            return s
        }()
        return """
        <!DOCTYPE html>
        <html data-mode="\(isDark ? "dark" : "light")">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        :root {
            --bg:         \(isDark ? "#18181b" : "#FAFAF8");
            --fg:         \(isDark ? "#e4e4e7" : "#18181b");
            --muted:      \(isDark ? "#a1a1aa" : "#52525b");
            --link:       \(isDark ? "#60a5fa" : "#2563eb");
            --code-bg:    \(isDark ? "#27272a" : "#f4f4f5");
            --border:     \(isDark ? "#3f3f46" : "#e4e4e7");
            --quote-fg:   \(isDark ? "#a1a1aa" : "#71717a");
            --hl-bg:      \(isDark ? "rgba(250, 204, 21, 0.25)" : "rgba(250, 204, 21, 0.45)");
        }
        *, *::before, *::after { box-sizing: border-box; }
        html { background: var(--bg); }
        body {
            font-family: \(fontStack);
            font-size: \(Int(fontSize))px;
            line-height: 1.78;
            color: var(--fg);
            background: var(--bg);
            max-width: 680px;
            margin: 0 auto;
            padding: 52px 28px 100px;
        }
        h1.reader-title {
            font-size: \(Int(fontSize * 1.42))px;
            font-weight: 700;
            line-height: 1.28;
            margin-bottom: 36px;
            padding-bottom: 28px;
            border-bottom: 1px solid var(--border);
        }
        h1,h2,h3,h4,h5,h6 { color: var(--fg); line-height: 1.3; margin: 32px 0 14px; }
        h2 { font-size: \(Int(fontSize * 1.21))px; }
        h3 { font-size: \(Int(fontSize * 1.05))px; }
        h4 { font-size: \(Int(fontSize * 0.95))px; }
        p  { margin-bottom: 22px; }
        a  { color: var(--link); text-decoration-thickness: 1px; text-underline-offset: 3px; }
        strong, b { color: var(--fg); }
        img, video {
            max-width: 100%; height: auto; border-radius: 8px;
            margin: 20px auto; display: block;
        }
        figure { margin: 28px 0; }
        figcaption {
            font-size: 14px; color: var(--muted); text-align: center;
            margin-top: 10px; font-style: italic;
        }
        blockquote {
            border-left: 3px solid var(--border);
            margin: 28px 0; padding: 6px 0 6px 22px;
            color: var(--quote-fg); font-style: italic;
        }
        blockquote p:last-child { margin-bottom: 0; }
        pre {
            background: var(--code-bg); border-radius: 8px;
            padding: 18px 20px; overflow-x: auto;
            margin: 24px 0; line-height: 1.5;
        }
        code {
            font-family: 'SF Mono', ui-monospace, monospace;
            font-size: 0.86em; background: var(--code-bg);
            padding: 2px 6px; border-radius: 4px;
        }
        pre code { background: none; padding: 0; font-size: 0.88em; }
        hr { border: none; border-top: 1px solid var(--border); margin: 36px 0; }
        ul, ol { padding-left: 26px; margin-bottom: 22px; }
        li { margin-bottom: 7px; }
        table { width: 100%; border-collapse: collapse; margin: 24px 0; font-size: 0.93em; }
        th, td { padding: 9px 14px; border: 1px solid var(--border); text-align: left; }
        th { background: var(--code-bg); font-weight: 700; }
        ::selection { background: var(--hl-bg); }
        mark.__trove_hl__ {
            background-color: var(--hl-bg) !important;
            color: inherit !important;
            padding: 1px 2px;
            border-radius: 2px;
        }
        * { color: unset; background-color: unset; font-size: unset; font-family: unset; line-height: unset; }
        body { color: var(--fg); background: var(--bg); font-size: \(Int(fontSize))px; line-height: 1.78; font-family: \(fontStack); }
        h1.reader-title { color: var(--fg); }
        a { color: var(--link); }
        code, pre { font-family: 'SF Mono', ui-monospace, monospace; }
        script, style, noscript, iframe,
        [class*="ad-"],[class*="-ad"],[id*="google_ad"],
        [class*="social"],[class*="share"],[class*="comment"],
        [class*="related"],[class*="recommend"],[class*="newsletter"],
        [class*="subscribe"],[class*="popup"],[class*="cookie"] { display: none !important; }
        </style>
        </head>
        <body>
        <h1 class="reader-title">\(escapedTitle)</h1>
        \(html)
        <script>
        (function(){
            try {
                const txt = document.body.innerText || '';
                const words = txt.split(/\\s+/).filter(Boolean).length;
                window.webkit.messageHandlers.wordCount.postMessage(words);
            } catch(_) {}

            setTimeout(function(){
                const max = Math.max(1, document.documentElement.scrollHeight - window.innerHeight);
                window.scrollTo(0, max * \(initialProgress));
            }, 80);

            let last = 0, t = null;
            window.addEventListener('scroll', function(){
                if (t) clearTimeout(t);
                t = setTimeout(function(){
                    const max = Math.max(1, document.documentElement.scrollHeight - window.innerHeight);
                    const p = Math.min(1, Math.max(0, window.scrollY / max));
                    if (Math.abs(p - last) < 0.005) return;
                    last = p;
                    try { window.webkit.messageHandlers.scroll.postMessage(p); } catch(_){}
                }, 350);
            }, { passive: true });

            // ---- Highlight: floating button + ⇧⌘H + global hook for toolbar
            const SAVED_HIGHLIGHTS = \(highlightsJSON);

            function highlightInDOM(searchText) {
                if (!searchText || searchText.length < 2) return;
                const walker = document.createTreeWalker(
                    document.body, NodeFilter.SHOW_TEXT,
                    {
                        acceptNode: function(node) {
                            if (!node.parentElement) return NodeFilter.FILTER_REJECT;
                            const tag = node.parentElement.tagName;
                            if (['SCRIPT','STYLE','MARK','BUTTON','NOSCRIPT'].includes(tag))
                                return NodeFilter.FILTER_REJECT;
                            return node.nodeValue.indexOf(searchText) !== -1
                                ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP;
                        }
                    }
                );
                const node = walker.nextNode();
                if (!node) return;
                const idx = node.nodeValue.indexOf(searchText);
                if (idx === -1) return;
                const middle = node.splitText(idx);
                middle.splitText(searchText.length);
                const m = document.createElement('mark');
                m.className = '__trove_hl__';
                m.textContent = middle.nodeValue;
                middle.parentNode.replaceChild(m, middle);
            }

            // Apply saved highlights once on load
            try {
                SAVED_HIGHLIGHTS.forEach(function(h){ highlightInDOM(h); });
            } catch(_) {}

            function wrapSelection(sel, text) {
                if (!sel || sel.rangeCount === 0) return;
                const range = sel.getRangeAt(0);
                const m = document.createElement('mark');
                m.className = '__trove_hl__';
                try {
                    range.surroundContents(m);
                } catch(_) {
                    // surroundContents fails when the range crosses element boundaries.
                    // Fallback: extract & reinsert wrapped in <mark>.
                    try {
                        const frag = range.extractContents();
                        m.appendChild(frag);
                        range.insertNode(m);
                    } catch(_) {}
                }
            }

            function postHighlight() {
                const sel = window.getSelection ? window.getSelection() : null;
                const text = sel ? sel.toString().trim() : '';
                if (text.length === 0) return false;
                wrapSelection(sel, text);
                try { window.webkit.messageHandlers.highlight.postMessage(text); } catch(_){}
                showToast('Highlighted');
                if (sel) sel.removeAllRanges();
                fbtn.style.display = 'none';
                return true;
            }
            window.__trovePostHighlight = postHighlight;

            function showToast(msg) {
                let toast = document.getElementById('__trove_toast__');
                if (!toast) {
                    toast = document.createElement('div');
                    toast.id = '__trove_toast__';
                    toast.style.cssText = 'position:fixed;bottom:36px;left:50%;transform:translateX(-50%);background:rgba(0,0,0,0.85);color:#fff;padding:8px 18px;border-radius:6px;font:600 13px -apple-system,sans-serif;z-index:99999;opacity:0;transition:opacity .2s;pointer-events:none;';
                    document.body.appendChild(toast);
                }
                toast.textContent = msg;
                toast.style.opacity = '1';
                clearTimeout(toast.__t);
                toast.__t = setTimeout(function(){ toast.style.opacity = '0'; }, 1100);
            }

            const fbtn = document.createElement('button');
            fbtn.innerHTML = '<span style="font-size:11px">✦</span> Highlight';
            fbtn.style.cssText = 'position:fixed;display:none;background:#facc15;color:#0a0a0a;padding:7px 14px;border:none;border-radius:7px;font:600 12px -apple-system,sans-serif;cursor:pointer;z-index:99999;box-shadow:0 4px 14px rgba(0,0,0,0.35);';
            fbtn.addEventListener('mousedown', function(e){ e.preventDefault(); });
            fbtn.addEventListener('click', function(e){ e.preventDefault(); postHighlight(); });
            document.body.appendChild(fbtn);

            function showFloater() {
                const sel = window.getSelection ? window.getSelection() : null;
                const text = sel ? sel.toString().trim() : '';
                if (!sel || !sel.rangeCount || text.length === 0) {
                    fbtn.style.display = 'none';
                    return;
                }
                const r = sel.getRangeAt(0).getBoundingClientRect();
                if (r.width === 0 && r.height === 0) { fbtn.style.display = 'none'; return; }
                fbtn.style.display = 'block';
                const above = r.top - fbtn.offsetHeight - 8;
                fbtn.style.top = (above < 8 ? r.bottom + 8 : above) + 'px';
                let left = r.left + (r.width - fbtn.offsetWidth) / 2;
                left = Math.max(8, Math.min(left, window.innerWidth - fbtn.offsetWidth - 8));
                fbtn.style.left = left + 'px';
            }

            document.addEventListener('mouseup', function(){ setTimeout(showFloater, 0); });
            document.addEventListener('selectionchange', function(){
                const sel = window.getSelection();
                if (!sel || sel.toString().trim().length === 0) fbtn.style.display = 'none';
            });
            document.addEventListener('mousedown', function(e){
                if (e.target !== fbtn && !fbtn.contains(e.target)) fbtn.style.display = 'none';
            });
            document.addEventListener('keydown', function(e){
                if ((e.metaKey || e.ctrlKey) && e.shiftKey && (e.key === 'h' || e.key === 'H')) {
                    if (postHighlight()) { e.preventDefault(); e.stopPropagation(); }
                }
            });
        })();
        </script>
        </body>
        </html>
        """
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var onProgress: ((Double) -> Void)?
        var onHighlight: ((String) -> Void)?
        var onWordCount: ((Int) -> Void)?
        var initialProgress: Double = 0
        var contentKey: String = ""

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "scroll":
                if let p = message.body as? Double { onProgress?(p) }
            case "highlight":
                if let s = message.body as? String { onHighlight?(s) }
            case "wordCount":
                if let n = message.body as? Int { onWordCount?(n) }
            default: break
            }
        }
    }
}
