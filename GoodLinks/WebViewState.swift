import WebKit

@MainActor
class WebViewState: ObservableObject {
    // Strong reference — weak caused nil during SwiftUI re-renders
    var webView: WKWebView?

    func extractArticle(completion: @escaping (String, String) -> Void) {
        guard let webView else {
            completion("", "")
            return
        }
        webView.evaluateJavaScript(Self.extractionJS) { result, _ in
            let title: String
            let html: String
            if let raw = result as? String,
               let data = raw.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                title = json["title"] ?? ""
                html  = json["html"]  ?? ""
            } else {
                title = ""
                html  = "<p>Could not extract article content.</p>"
            }
            DispatchQueue.main.async { completion(title, html) }
        }
    }

    static let extractionJS = #"""
    (function() {
        try {
            const title = document.title;
            const body  = document.body.cloneNode(true);

            ['script','style','noscript','iframe','object','embed',
             'nav','header','footer','aside','form','button'].forEach(t =>
                body.querySelectorAll(t).forEach(e => e.remove()));

            const noiseRE = /\b(ad|ads|advert|banner|cookie|popup|modal|overlay|sidebar|nav|menu|footer|header|related|share|social|comment|subscribe|newsletter|promo|sponsor|outbrain|taboola|widget|sticky|breadcrumb|pagination)\b/i;
            body.querySelectorAll('[class],[id]').forEach(el => {
                const s = (el.getAttribute('class')||'') + ' ' + (el.getAttribute('id')||'');
                if (noiseRE.test(s)) el.remove();
            });

            const selectors = [
                'article','[role="main"]','main',
                '.post-content','.article-body','.entry-content',
                '.story-body','.article-content','.page-content',
                '[itemprop="articleBody"]','.content-body','.post-body'
            ];
            for (const sel of selectors) {
                const el = body.querySelector(sel);
                if (el && el.querySelectorAll('p').length >= 2)
                    return JSON.stringify({ title, html: el.innerHTML });
            }

            const scores = new Map();
            body.querySelectorAll('p').forEach(p => {
                if (p.textContent.trim().length < 80) return;
                let el = p.parentElement;
                while (el && el !== body) {
                    scores.set(el, (scores.get(el)||0) + p.textContent.length);
                    el = el.parentElement;
                }
            });

            let best = null, bestScore = 0;
            scores.forEach((score, el) => { if (score > bestScore) { bestScore = score; best = el; } });

            return JSON.stringify({ title, html: (best || body).innerHTML });
        } catch(e) {
            return JSON.stringify({ title: document.title, html: document.body.innerHTML });
        }
    })();
    """#
}
