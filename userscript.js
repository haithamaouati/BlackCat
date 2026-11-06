// ==UserScript==
// @name         BlackCat 🐈‍⬛
// @namespace    https://github.com/haithamaouati/BlackCat/
// @version      1.0
// @description  Shows the video creator's region and the viewer's region in an alert
// @author       Haitham Aouati
// @run-at       document-end
// @match        https://*/*
// @grant        none
// @license      WTFPL
// @downloadURL  https://github.com/haithamaouati/BlackCat/userscript.js
// @supportURL   https://github.com/haithamaouati/BlackCat/issues
// @updateURL    https://github.com/haithamaouati/BlackCat/userscript.js
// ==/UserScript==

(function () {
    'use strict';

    if (window.top !== window.self) return;
    if (!/(^|\.)tiktok\.com$/i.test(location.hostname)) return;

    const LOG = '[TikTok Region]';
    const MAX_TRIES = 10;
    const RETRY_MS = 1000;

    let initialId = getVideoId();
    let lastHandledUrl = '';
    let runToken = 0;

    function say(msg) {
        try { alert(msg); } catch (e) { console.log(LOG, msg); }
    }

    function fail(title, err) {
        const detail = err ? (err.message || String(err)) : '';
        console.error(LOG, title, err || '');
        say('⚠️ ' + title + (detail ? '\n' + detail : ''));
    }

    // ---------- Helpers ----------

    function getVideoId() {
        const m = location.pathname.match(/\/(?:video|photo|v)\/(\d+)/);
        return m ? m[1] : null;
    }

    function regionInfo(code) {
        code = String(code || '').toUpperCase();
        if (!/^[A-Z]{2}$/.test(code)) return { emoji: 'N/A', code: code || 'N/A', name: 'N/A' };
        let name = code;
        try {
            name = new Intl.DisplayNames(['en'], { type: 'region' }).of(code) || code;
        } catch (e) { /* older WebView: keep the code */ }
        const emoji = String.fromCodePoint(...[...code].map(c => 0x1F1E6 + c.charCodeAt(0) - 65));
        return { emoji, code, name };
    }

    function block(code) {
        const r = regionInfo(code);
        return `Emoji: ${r.emoji}\nCode: ${r.code}\nCountry: ${r.name}`;
    }

    // Walk a JSON tree: find locationCreated (matching the video ID) and the viewer region
    function walk(root, videoId) {
        const found = [];
        let viewer = null;
        const stack = [root];
        let guard = 0;
        while (stack.length && guard++ < 300000) {
            const o = stack.pop();
            if (!o || typeof o !== 'object') continue;
            if (typeof o.locationCreated === 'string' && o.locationCreated) {
                found.push({ id: String(o.id || o.itemId || ''), loc: o.locationCreated });
            }
            const ctx = o['webapp.app-context'];
            if (ctx && typeof ctx.region === 'string') viewer = ctx.region;
            for (const k in o) {
                const v = o[k];
                if (v && typeof v === 'object') stack.push(v);
            }
        }
        let loc = null;
        const exact = found.find(f => f.id && f.id === videoId);
        if (exact) loc = exact.loc;
        else if (found.length && !videoId) loc = found[0].loc;
        return { loc, viewer };
    }

    function fromDocument(doc, videoId, allowRegex) {
        let loc = null, viewer = null;

        const scripts = doc.querySelectorAll(
            'script#__UNIVERSAL_DATA_FOR_REHYDRATION__, script#SIGI_STATE, ' +
            'script#__NEXT_DATA__, script[type="application/json"]'
        );
        for (const s of scripts) {
            try {
                const r = walk(JSON.parse(s.textContent), videoId);
                if (r.loc && !loc) loc = r.loc;
                if (r.viewer && !viewer) viewer = r.viewer;
            } catch (e) { /* not valid JSON, skip */ }
        }

        if (allowRegex) {
            const reLoc = /"locationCreated"\s*:\s*"([A-Za-z]{2})"/;
            const reViewer = /"webapp\.app-context"\s*:\s*\{[^}]*?"region"\s*:\s*"([A-Za-z]{2})"/;
            for (const s of doc.querySelectorAll('script')) {
                const t = s.textContent || '';
                if (!loc) { const m = reLoc.exec(t); if (m) loc = m[1]; }
                if (!viewer) { const m = reViewer.exec(t); if (m) viewer = m[1]; }
            }
        }

        return loc ? { loc, viewer } : null;
    }

    async function fromFetch(videoId) {
        const res = await fetch(location.href, { credentials: 'include' });
        if (!res.ok) throw new Error('HTTP ' + res.status + ' while re-fetching the page');
        const html = await res.text();
        const doc = new DOMParser().parseFromString(html, 'text/html');
        const r = fromDocument(doc, videoId, false);
        if (r) return r;
        const m = /"locationCreated"\s*:\s*"([A-Za-z]{2})"/.exec(html);
        const v = /"webapp\.app-context"\s*:\s*\{[^}]*?"region"\s*:\s*"([A-Za-z]{2})"/.exec(html);
        return m ? { loc: m[1], viewer: v ? v[1] : null } : null;
    }

    // ---------- Main ----------

    async function run() {
        const url = location.href;
        const videoId = getVideoId();
        if (!videoId || url === lastHandledUrl) return;
        lastHandledUrl = url;

        const token = ++runToken;
        const allowRegex = videoId === initialId;

        try {
            let data = null;
            for (let i = 0; i < MAX_TRIES && token === runToken; i++) {
                data = fromDocument(document, videoId, allowRegex);
                if (data) break;
                await new Promise(r => setTimeout(r, RETRY_MS));
            }

            let fetchError = null;
            if (!data && token === runToken) {
                try {
                    data = await fromFetch(videoId);
                } catch (e) {
                    fetchError = e;
                }
            }
            if (token !== runToken) return;

            if (data) {
                console.log(LOG, data);
                say(
                    'Creator region:\n' + block(data.loc) +
                    '\n\nViewer region:\n' + block(data.viewer)
                );
            } else if (fetchError) {
                fail('Region not found.\nFallback request failed:', fetchError);
            } else {
                fail('Region not found.\n"locationCreated" is missing from the page data (login wall, captcha or app prompt?).');
            }
        } catch (e) {
            fail('Unexpected error in script:', e);
        }
    }

    function onNav() { run(); }

    try {
        ['pushState', 'replaceState'].forEach(fn => {
            const orig = history[fn];
            history[fn] = function () {
                const ret = orig.apply(this, arguments);
                setTimeout(onNav, 0);
                return ret;
            };
        });
        window.addEventListener('popstate', onNav);
        window.addEventListener('load', onNav);
        setInterval(() => { if (location.href !== lastHandledUrl) onNav(); }, 1500);
    } catch (e) {
        fail('Failed to set up navigation hooks:', e);
    }

    window.addEventListener('unhandledrejection', e => fail('Unhandled promise error:', e.reason));

    run();
})();
