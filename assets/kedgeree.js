/* Kedgeree: a modern theme for Haddock. Vanilla, dependency-free, defensive.
 * CSS handles theming. This file does the rest: theme toggle, sticky sidebar
 * with scroll-spy, search overlay, source-page niceties.
 */
(function () {
  "use strict";

  var STORE_KEY = "kedgeree-theme";
  var root = document.documentElement;
  var $ = function (sel, ctx) { return (ctx || document).querySelector(sel); };
  var $$ = function (sel, ctx) {
    return Array.prototype.slice.call((ctx || document).querySelectorAll(sel));
  };
  var el = function (tag, attrs, html) {
    var n = document.createElement(tag);
    if (attrs) for (var k in attrs) n.setAttribute(k, attrs[k]);
    if (html != null) n.innerHTML = html;
    return n;
  };

  /* Brand mark. */
  var LAMBDA = '<span class="kg-lambda" aria-hidden="true">&#955;</span>';

  /* Theme toggle */
  var mql = window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)");

  function currentTheme() {
    var t = null;
    try { t = localStorage.getItem(STORE_KEY); } catch (e) {}
    return t === "light" || t === "dark" || t === "auto"
      ? t
      : root.getAttribute("data-theme") || "auto";
  }

  function applyTheme(t) {
    var dark = t === "dark" || (t === "auto" && mql && mql.matches);
    root.setAttribute("data-theme", t);
    root.setAttribute("data-resolved", dark ? "dark" : "light");
    try { localStorage.setItem(STORE_KEY, t); } catch (e) {}
  }

  // Cycle the theme on click. The icon is a CSS mask keyed on html[data-theme]
  // (see kedgeree.css), so there is no icon to set here.
  function wireTheme(btn) {
    var order = ["auto", "light", "dark"];
    btn.addEventListener("click", function () {
      var t = currentTheme();
      applyTheme(order[(order.indexOf(t) + 1) % order.length]);
    });
    if (mql && mql.addEventListener) {
      mql.addEventListener("change", function () {
        if (currentTheme() === "auto") applyTheme("auto");
      });
    }
    return btn;
  }
  function themeButton() {
    return wireTheme(el("button", {
      type: "button",
      class: "kg-iconbtn kg-theme",
      title: "Toggle color theme",
      "aria-label": "Toggle color theme",
    }));
  }

  /* Header: brand, search trigger, menu button, theme toggle */
  function enhanceHeader() {
    var header = $("#package-header");
    if (!header) return;

    // Chrome is rendered server-side (see headerChrome in Rewrite.hs), present
    // at first paint. Just wire it up.
    var mt = $(".kg-menu-toggle", header);
    if (mt) mt.addEventListener("click", function () {
      document.body.classList.toggle("kg-nav-open");
    });
    var srch = $(".kg-search", header);
    if (srch) srch.addEventListener("click", openSearch);
    var theme = $(".kg-theme", header);
    if (theme) wireTheme(theme);
    // Our server-rendered Instances dropdown (see instancesControl in Rewrite.hs):
    // wire its two actions, and close it on an outside click.
    var inst = $(".kg-instances", header);
    if (inst) {
      $$("[data-inst]", inst).forEach(function (b) {
        b.addEventListener("click", function () {
          setAllInstances(b.dataset.inst === "open");
          inst.open = false;
        });
      });
      document.addEventListener("click", function (e) {
        if (inst.open && !e.target.closest(".kg-instances")) inst.open = false;
      });
    }

    var menu = $("#page-menu", header);
    if (menu) {
      // The bundle injects JS-only controls into #page-menu after load (Quick
      // Jump and its own "Instances" menu) with fragment (#) hrefs. They pop in
      // late and duplicate what we provide (search, our Instances control). Drop
      // them as they arrive so they never paint. Leave our control (a button,
      // not a fragment link). Real cross-page links have non-fragment hrefs.
      var dropInjected = function () {
        $$("li", menu).forEach(function (li) {
          if (li.querySelector(".kg-instances")) return;
          var a = li.querySelector("a[href]");
          if (a && (a.getAttribute("href") || "").charAt(0) === "#") li.remove();
        });
      };
      dropInjected();
      if (window.MutationObserver) {
        new MutationObserver(dropInjected).observe(menu, { childList: true });
      }
    }
  }


  /* Sidebar + scroll-spy */
  function buildSidebar() {
    // Rendered server-side (Kedgeree.Sidebar), present at first paint. Just wire
    // the drawer-close and scroll-spy, don't rebuild it.
    var nav = $("#kg-sidebar");
    if (!nav) return;
    nav.addEventListener("click", function (e) {
      if (e.target.closest("a")) document.body.classList.remove("kg-nav-open");
    });
    scrollSpy($$("a[href^='#']", nav));
  }

  function scrollSpy(links) {
    var targets = [];
    links.forEach(function (a) {
      var id = decodeURIComponent((a.getAttribute("href") || "").slice(1));
      if (!id) return;
      var node = document.getElementById(id) ||
        document.querySelector("[name='" + cssEscape(id) + "']");
      if (node) targets.push({ link: a, node: node });
    });
    if (!targets.length) return;
    // Sort into document order so "last heading scrolled past" is well-defined.
    targets.sort(function (a, b) {
      return a.node.compareDocumentPosition(b.node) & Node.DOCUMENT_POSITION_FOLLOWING ? -1 : 1;
    });

    var ticking = false;
    var active = null;
    function update() {
      ticking = false;
      var line = 150; // activation line just below the sticky header
      // Active = the last heading scrolled past the line.
      var current = targets[0].link;
      for (var i = 0; i < targets.length; i++) {
        if (targets[i].node.getBoundingClientRect().top <= line) current = targets[i].link;
        else break;
      }
      // Pin the last section at the bottom of the page.
      var atBottom = window.innerHeight + window.scrollY >=
        document.documentElement.scrollHeight - 2;
      if (atBottom) current = targets[targets.length - 1].link;

      // Touch the DOM only when the active link changes.
      if (current !== active) {
        if (active) active.classList.remove("kg-active");
        if (current) current.classList.add("kg-active");
        active = current;
      }
    }
    function onScroll() {
      if (!ticking) { ticking = true; requestAnimationFrame(update); }
    }
    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", onScroll);
    // Defer the first pass a frame so it does not force a layout during init.
    requestAnimationFrame(update);
  }

  /* Search overlay (over Haddock's doc-index.json from --quickjump) */
  var searchState = { loaded: false, items: [], overlay: null, input: null, list: null, sel: 0 };

  function baseHref() {
    // Source pages live under src/. The index sits one level up.
    return /(^|\/)src\/[^/]*$/.test(location.pathname) ? "../" : "";
  }

  function loadIndex(cb) {
    if (searchState.loaded) return cb();
    var url = baseHref() + "doc-index.json";
    fetch(url).then(function (r) { return r.ok ? r.json() : []; })
      .then(function (data) {
        searchState.items = normalizeIndex(data);
        searchState.loaded = true;
        cb();
      })
      .catch(function () { searchState.loaded = true; cb(); });
  }

  function normalizeIndex(data) {
    if (!Array.isArray(data)) return [];
    return data.map(function (e) {
      var mod = typeof e.module === "string" ? e.module
        : (e.module && e.module.name) || "";
      // Haddock packs a class's members into one space-separated `name`. Match
      // the whole string, display the first token.
      var full = e.name || "";
      return {
        name: full.split(/\s+/)[0],
        search: full.toLowerCase(),
        module: mod,
        link: baseHref() + (e.link || ""),
      };
    }).filter(function (e) { return e.name && e.link; });
  }

  function buildSearchOverlay() {
    var ov = el("div", { class: "kg-overlay kg-search-overlay", role: "dialog", "aria-modal": "true" });
    var card = el("div", { class: "kg-help-card" });
    var input = el("input", {
      type: "text", class: "kg-search-input", placeholder: "Search identifiers…",
      "aria-label": "Search", autocomplete: "off", spellcheck: "false",
    });
    var list = el("ul", { class: "kg-search-list" });
    card.appendChild(input);
    card.appendChild(list);
    ov.appendChild(card);
    document.body.appendChild(ov);

    ov.addEventListener("click", function (e) { if (e.target === ov) closeSearch(); });
    input.addEventListener("input", function () { runSearch(input.value); });
    input.addEventListener("keydown", function (e) {
      if (e.key === "ArrowDown") { e.preventDefault(); moveSel(1); }
      else if (e.key === "ArrowUp") { e.preventDefault(); moveSel(-1); }
      else if (e.key === "Enter") { e.preventDefault(); gotoSel(); }
      else if (e.key === "Escape") { e.preventDefault(); closeSearch(); }
    });

    searchState.overlay = ov;
    searchState.input = input;
    searchState.list = list;
    return ov;
  }

  function openSearch() {
    loadIndex(function () {
      if (!searchState.items.length) { location.href = baseHref() + "doc-index.html"; return; }
      var ov = searchState.overlay || buildSearchOverlay();
      ov.classList.add("kg-open");
      searchState.input.value = "";
      runSearch("");
      searchState.input.focus();
    });
  }

  function closeSearch() {
    if (searchState.overlay) searchState.overlay.classList.remove("kg-open");
  }

  function runSearch(q) {
    q = q.trim().toLowerCase();
    // Empty query shows a hint, not a dump of entries.
    if (!q) {
      searchState.results = [];
      searchState.list.innerHTML =
        '<li class="kg-sr-hint">Type to search ' + searchState.items.length +
        ' identifiers · <kbd>↑</kbd><kbd>↓</kbd> to navigate · <kbd>↵</kbd> to open</li>';
      return;
    }
    var items = searchState.items, out = [];
    for (var i = 0; i < items.length && out.length < 50; i++) {
      var it = items[i];
      if (it.search.indexOf(q) !== -1) out.push(it);
    }
    // Prefix matches on the display name first, then shorter names.
    out.sort(function (a, b) {
      var ap = a.name.toLowerCase().indexOf(q) === 0 ? 0 : 1;
      var bp = b.name.toLowerCase().indexOf(q) === 0 ? 0 : 1;
      return ap - bp || a.name.length - b.name.length;
    });
    searchState.sel = 0;
    searchState.results = out;
    searchState.list.innerHTML = out.map(function (it, i) {
      return '<li class="kg-sr' + (i === 0 ? " kg-sr-sel" : "") + '" data-i="' + i + '">' +
        '<a href="' + esc(it.link) + '">' +
        '<span class="kg-sr-name">' + esc(it.name) + '</span>' +
        '<span class="kg-sr-mod">' + esc(it.module) + '</span></a></li>';
    }).join("") || '<li class="kg-sr-empty">No matches</li>';
    $$(".kg-sr", searchState.list).forEach(function (li) {
      li.addEventListener("mousemove", function () { setSel(+li.dataset.i); });
      li.addEventListener("click", function () { setSel(+li.dataset.i); gotoSel(); });
    });
  }

  function setSel(i) {
    var lis = $$(".kg-sr", searchState.list);
    if (!lis.length) return;
    searchState.sel = Math.max(0, Math.min(i, lis.length - 1));
    lis.forEach(function (li, j) { li.classList.toggle("kg-sr-sel", j === searchState.sel); });
    var cur = lis[searchState.sel];
    if (cur) cur.scrollIntoView({ block: "nearest" });
  }
  function moveSel(d) { setSel(searchState.sel + d); }
  function gotoSel() {
    var r = searchState.results || [];
    var it = r[searchState.sel];
    if (!it) return;
    // Close first: a same-page result only changes the hash, so the overlay lingers.
    closeSearch();
    location.href = it.link;
  }

  /* Help overlay */
  var helpOverlay = null;
  function toggleHelp() {
    if (!helpOverlay) {
      helpOverlay = el("div", { class: "kg-overlay", role: "dialog", "aria-modal": "true" },
        '<div class="kg-help-card"><h2>Keyboard shortcuts</h2><dl>' +
        "<dt><kbd>/</kbd> or <kbd>s</kbd></dt><dd>Focus search</dd>" +
        "<dt><kbd>↑</kbd> <kbd>↓</kbd></dt><dd>Move through results</dd>" +
        "<dt><kbd>↵</kbd></dt><dd>Open the selected result</dd>" +
        "<dt><kbd>?</kbd></dt><dd>Toggle this help</dd>" +
        "<dt><kbd>Esc</kbd></dt><dd>Close overlays</dd>" +
        "</dl></div>");
      helpOverlay.addEventListener("click", function (e) {
        if (e.target === helpOverlay) helpOverlay.classList.remove("kg-open");
      });
      document.body.appendChild(helpOverlay);
    }
    helpOverlay.classList.toggle("kg-open");
  }

  /* Global keyboard shortcuts */
  function typingInField(e) {
    var t = e.target;
    return t && (t.tagName === "INPUT" || t.tagName === "TEXTAREA" || t.isContentEditable);
  }
  document.addEventListener("keydown", function (e) {
    if (e.metaKey || e.ctrlKey || e.altKey) return;
    if (e.key === "Escape") {
      closeSearch();
      if (helpOverlay) helpOverlay.classList.remove("kg-open");
      return;
    }
    if (typingInField(e)) return;
    if (e.key === "/" || e.key === "s" || e.key === "S") { e.preventDefault(); openSearch(); }
    else if (e.key === "?") { e.preventDefault(); toggleHelp(); }
  });

  // Expand or collapse all instance lists (the "i:<Class>" sections, not the
  // per-instance method panes "i:ic:..."). Syncs each toggle's chevron.
  function setAllInstances(open) {
    $$("details[id^='i:']").forEach(function (d) {
      if (d.id.indexOf("i:ic:") === 0) return;
      d.open = open;
      $$("[data-details-id='" + d.id + "']").forEach(function (ctrl) {
        ctrl.classList.toggle("collapser", open);
        ctrl.classList.toggle("expander", !open);
      });
    });
  }

  // Make the whole instance-card header toggle its <details>. Forwarding a click
  // to Haddock's control was unreliable. No-JS falls back to the native summary.
  function enlargeInstanceToggles() {
    $$("#interface .instance.details-toggle-control[data-details-id]").forEach(function (ctrl) {
      var det = document.getElementById(ctrl.getAttribute("data-details-id"));
      var row = ctrl.closest("tr");
      // Drop Haddock's literal space after the chevron span, so spacing to the
      // name matches every other toggle.
      var after = ctrl.nextSibling;
      if (after && after.nodeType === 3) after.textContent = after.textContent.replace(/^\s+/, "");
      if (!det || !row || row.dataset.kgToggle) return;
      row.dataset.kgToggle = "1";
      row.addEventListener("click", function (e) {
        if (e.target.closest("a")) return; // Source / # / type links
        if (e.target.closest(".details-toggle-control")) return; // chevron to Haddock
        det.open = !det.open;
        ctrl.classList.toggle("collapser", det.open);
        ctrl.classList.toggle("expander", !det.open);
      });
    });
  }

  /* Source pages: line numbers + target-line highlight */
  function enhanceSource() {
    var pre = $("pre");
    if (!pre || !$(".hs-keyword, .hs-identifier", pre)) return;
    document.body.classList.add("kg-source");

    // Source pages have no header, so float a minimal toolbar.
    if (!$("#package-header")) {
      var bar = el("div", { class: "kg-src-toolbar" });
      var back = el("a", {
        class: "kg-iconbtn", href: "../index.html", title: "Back to docs", "aria-label": "Back to docs",
      }, LAMBDA);
      bar.appendChild(back);
      bar.appendChild(themeButton());
      document.body.appendChild(bar);
    }

    // Turn each line marker into a clickable line-number anchor in the gutter.
    $$("span[id^='line-']", pre).forEach(function (s) {
      var n = s.id.slice(5);
      if (!/^\d+$/.test(n)) return;
      var a = el("a", { class: "kg-lineno", href: "#" + s.id, "aria-label": "Line " + n });
      a.textContent = n;
      s.insertBefore(a, s.firstChild);
    });

    function highlightHash() {
      var old = pre.querySelector(".kg-line-hl-overlay");
      if (old) old.remove();
      $$(".kg-line-target", pre).forEach(function (s) { s.classList.remove("kg-line-target"); });
      var m = /^#line-(\d+)$/.exec(location.hash);
      if (!m) return;
      var s = document.getElementById("line-" + m[1]);
      if (!s) return;
      s.classList.add("kg-line-target");
      // Full-row highlight: an overlay spanning the pre's width at the line's y.
      var ov = el("div", { class: "kg-line-hl-overlay" });
      ov.style.top = s.offsetTop + "px";
      pre.appendChild(ov);
    }
    window.addEventListener("hashchange", highlightHash);
    highlightHash();
  }

  /* ---- tiny helpers ---------------------------------------------------- */
  function esc(s) {
    return String(s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }
  function cssEscape(s) {
    return window.CSS && CSS.escape ? CSS.escape(s) : String(s).replace(/[^\w-]/g, "\\$&");
  }

  /* Footer credit */
  function enhanceFooter() {
    var footer = $("#footer p") || $("#footer");
    if (!footer || footer.querySelector(".kg-credit")) return;
    var span = el("span", { class: "kg-credit" },
      " · rendered with <a href=\"https://github.com/velveteer/kedgeree\">Kedgeree</a> 🍛");
    footer.appendChild(span);
  }

  /* Each declaration box doubles as its own anchor. A click anywhere that is not
     a real hyperlink jumps to its #id, replacing the old # selflink (hidden via
     CSS once JS is live). Type links and the Source link keep working, and a
     drag to select text never navigates. Instances are skipped, their anchor
     points at the class, not themselves. */
  function wireSelfAnchors() {
    $$(".src").forEach(function (box) {
      if (box.closest(".instances")) return;
      if (box.closest('[id="section.orphans"]')) return;
      var sl = box.querySelector(".kg-srclinks a.selflink");
      var def = box.querySelector(".def[id]");
      var hash = (sl && sl.getAttribute("href")) ||
        (def && def.id ? "#" + def.id : "");
      if (!hash || hash === "#") return;
      box.classList.add("kg-anchorable");
      box.addEventListener("click", function (e) {
        if (e.target.closest("a[href]")) return;
        if (window.getSelection && String(window.getSelection())) return;
        location.hash = hash;
      });
    });
  }

  // Landing page (kedgeree --landing): just add the theme toggle. The Haddock
  // passes above all no-op on it.
  function enhanceLanding() {
    if (!document.body.classList.contains("kg-landing")) return;
    var header = $(".kg-landing-header");
    if (!header) return;
    var actions = el("div", { class: "kg-actions" });
    actions.appendChild(themeButton());
    header.appendChild(actions);
  }

  /* Boot */
  function init() {
    applyTheme(currentTheme());
    enhanceHeader();
    enhanceLanding();
    buildSidebar();
    enlargeInstanceToggles();
    enhanceSource();
    wireSelfAnchors();
    enhanceFooter();

    // Dismiss the mobile drawer when tapping outside it.
    document.addEventListener("click", function (e) {
      if (!document.body.classList.contains("kg-nav-open")) return;
      if (e.target.closest("#kg-sidebar") || e.target.closest(".kg-menu-toggle")) return;
      document.body.classList.remove("kg-nav-open");
    });

    // Haddock's preferences dropdown uses a bare <span> not a <label>. Delegate.
    document.addEventListener("click", function (e) {
      var span = e.target.closest(".dropdown-menu span");
      if (!span || span.closest("label")) return;
      var row = span.parentElement;
      var cb = row && row.querySelector('input[type="checkbox"]');
      if (cb) cb.click();
    });
    // No sidebar here, so hide the hamburger.
    if (!document.body.classList.contains("kg-has-sidebar")) {
      var mt = $(".kg-menu-toggle");
      if (mt) mt.style.display = "none";
    }
  }
  if (document.readyState === "loading")
    document.addEventListener("DOMContentLoaded", init);
  else init();
})();
