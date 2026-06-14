/* Kedgeree — a modern theme for Haddock.
 *
 * Vanilla, dependency-free, and defensive: every feature degrades gracefully
 * if the page Haddock produced doesn't have what it expects. Visual theming is
 * all CSS. This file only does what CSS can't:
 *   - the light/dark/auto toggle (+ persistence),
 *   - building a sticky sidebar from the existing DOM, with scroll-spy,
 *   - a keyboard-driven search overlay over Haddock's doc-index.json,
 *   - line numbers / line highlighting on hyperlinked-source pages.
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

  /* Brand mark (TODO: real icon). */
  var LAMBDA = '<span class="kg-lambda" aria-hidden="true">&#955;</span>';

  /* Inline SVG icons (inherit currentColor). */
  var ICON = {
    auto:
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="9"/><path d="M12 3a9 9 0 0 0 0 18z" fill="currentColor" stroke="none"/></svg>',
    sun:
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="4.2"/><path d="M12 2v2M12 20v2M2 12h2M20 12h2M5 5l1.4 1.4M17.6 17.6 19 19M19 5l-1.4 1.4M6.4 17.6 5 19"/></svg>',
    moon:
      '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M20 14.5A8 8 0 0 1 9.5 4 8 8 0 1 0 20 14.5z"/></svg>',
    menu:
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M4 7h16M4 12h16M4 17h16"/></svg>',
    search:
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/></svg>',
  };

  /* ====================================================================== */
  /* Theme toggle                                                            */
  /* ====================================================================== */
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

  function themeButton() {
    var order = ["auto", "light", "dark"];
    var btn = el("button", {
      type: "button",
      class: "kg-iconbtn kg-theme",
      title: "Toggle color theme",
      "aria-label": "Toggle color theme",
    });
    function render() {
      var t = currentTheme();
      btn.innerHTML = ICON[t === "auto" ? "auto" : t === "light" ? "sun" : "moon"];
      btn.dataset.theme = t;
    }
    btn.addEventListener("click", function () {
      var t = currentTheme();
      applyTheme(order[(order.indexOf(t) + 1) % order.length]);
      render();
    });
    if (mql && mql.addEventListener) {
      mql.addEventListener("change", function () {
        if (currentTheme() === "auto") applyTheme("auto");
      });
    }
    render();
    return btn;
  }

  /* ====================================================================== */
  /* Header: brand, search trigger, menu button, theme toggle               */
  /* ====================================================================== */
  function enhanceHeader() {
    var header = $("#package-header");
    if (!header) return;

    var menuBtn = el("button", {
      type: "button",
      class: "kg-iconbtn kg-menu-toggle",
      title: "Toggle navigation",
      "aria-label": "Toggle navigation",
    }, ICON.menu);
    menuBtn.addEventListener("click", function () {
      document.body.classList.toggle("kg-nav-open");
    });

    // Navbar shows the package, sidebar shows the module.
    var brand = el("a", { class: "kg-brand", href: "index.html" },
      LAMBDA + "<span>" + esc(pkgName() || moduleName() || "Documentation") + "</span>");

    var search = el("button", { type: "button", class: "kg-search", title: "Search (press / )" },
      ICON.search +
      '<span class="kg-search-label">Search…</span>' +
      '<kbd>/</kbd>');
    search.addEventListener("click", openSearch);

    header.insertBefore(menuBtn, header.firstChild);
    header.insertBefore(brand, menuBtn.nextSibling);

    // Right-aligned cluster: search + theme toggle, before the page menu.
    var menu = $("#page-menu", header);
    var cluster = el("div", { class: "kg-actions" });
    cluster.appendChild(search);
    cluster.appendChild(themeButton());
    if (menu) {
      // Remove Haddock's native Quick Jump link (we provide our own search).
      // It is injected asynchronously, so keep watching for it.
      var dropQuickJump = function () {
        $$("li", menu).forEach(function (li) {
          if (/quick\s*jump/i.test(li.textContent || "")) li.remove();
        });
      };
      dropQuickJump();
      if (window.MutationObserver) {
        new MutationObserver(dropQuickJump).observe(menu, { childList: true });
      }
      menu.style.marginLeft = "0.5rem";
      header.insertBefore(cluster, menu);
    } else header.appendChild(cluster);
  }

  // The current module name (Haddock's module-header caption).
  function moduleName() {
    var cap = $("#module-header .caption") || $("#content .caption");
    if (cap && cap.textContent.trim()) return cap.textContent.trim();
    return (document.title || "").trim();
  }

  // What the sidebar heading says, derived from the page itself so new page
  // kinds need no special-casing. A module page uses its module name. Every
  // other Haddock page titles itself "<package> (Qualifier)" — so the
  // alphabetical index reads "Index" — and the package contents page (no such
  // qualifier) falls back to "Contents".
  function sidebarHeading() {
    var cap = $("#module-header .caption");
    if (cap && cap.textContent.trim()) return cap.textContent.trim();
    var qualifier = /\(([^)]+)\)\s*$/.exec(document.title || "");
    return qualifier ? qualifier[1].trim() : "Contents";
  }

  // The package name, injected as a meta by the kedgeree post-processor.
  function pkgName() {
    var m = document.querySelector('meta[name="kg-package"]');
    return ((m && m.getAttribute("content")) || "").trim();
  }

  /* ====================================================================== */
  /* Sidebar + scroll-spy                                                    */
  /* ====================================================================== */
  function buildSidebar() {
    var contents = $("#contents-list");
    var defs = $$("#interface .top > .src a.def[id], #interface .top > .src a.def[name]");
    var pageMenu = $("#page-menu");
    // Mirror only real cross-page links (Source / Contents / Index). Haddock's
    // bundle injects JS-only controls into #page-menu at runtime — Quick Jump and
    // the "Instances" expand/collapse menu — which carry fragment (#) hrefs, do
    // nothing when cloned, and appear or not depending on whether the bundle has
    // run yet. Excluding fragment hrefs drops them and kills that race.
    var pageLinks = (pageMenu ? $$("a[href]", pageMenu) : []).filter(function (a) {
      var href = a.getAttribute("href") || "";
      return href && href.charAt(0) !== "#";
    });
    // Pages with real navigation get a full sidebar — the rest (contents, index)
    // still get a minimal drawer so the mobile hamburger works.
    var rich = !!contents || defs.length > 0;
    if (!rich && !pageLinks.length) return;

    var nav = el("nav", { id: "kg-sidebar", "aria-label": "Documentation navigation" });

    // The module name is the top-level nav entry. On a module page it links to
    // the top, so the description / synopsis area (which Haddock's contents list
    // omits) is reachable and lights up the scroll-spy while you're up there —
    // elsewhere it falls back to a link to the package index.
    var header = $("#module-header");
    var home = el("a", { class: "kg-sb-home", href: header ? "#module-header" : "index.html" },
      LAMBDA + " <strong>" + esc(sidebarHeading()) + "</strong>");
    nav.appendChild(home);

    var spyTargets = [];
    if (header) spyTargets.push(home);
    function pushSpy(root) {
      $$("a[href^='#']", root).forEach(function (a) { spyTargets.push(a); });
    }

    // A <ul> of declaration links. The href is a URL fragment, not a CSS
    // selector — the id (e.g. "t:Config") goes in verbatim, as Haddock's own
    // selflinks do.
    function declList(decls) {
      var ul = el("ul", { class: "kg-sb-sub" });
      decls.forEach(function (d) {
        var id = d.id || d.getAttribute("name");
        if (!id) return;
        var a = el("a", { href: "#" + id }, esc(d.textContent.trim()));
        ul.appendChild(el("li", null, a.outerHTML));
      });
      return ul;
    }

    // Group each declaration under the id of the nearest section heading above
    // it (headings come back in document order, so the last one that precedes
    // the declaration wins). Declarations before any heading land under "".
    function declsBySection() {
      var headings = $$("#interface [id^='g:']");
      var groups = {};
      defs.forEach(function (d) {
        var sec = "";
        for (var i = 0; i < headings.length; i++) {
          if (d.compareDocumentPosition(headings[i]) & Node.DOCUMENT_POSITION_PRECEDING)
            sec = headings[i].id;
          else break;
        }
        (groups[sec] = groups[sec] || []).push(d);
      });
      return groups;
    }

    if (contents) {
      nav.appendChild(el("div", { class: "kg-sb-title" }, "Contents"));
      var groups = declsBySection();
      // Declarations exported before the first section have no contents entry.
      if (groups[""]) {
        var orphans = declList(groups[""]);
        nav.appendChild(orphans);
        pushSpy(orphans);
      }
      var ul = contents.querySelector("ul");
      if (ul) {
        var clone = ul.cloneNode(true);
        clone.classList.add("kg-sb-contents");
        // Nest each section's declarations beneath its contents entry, so the
        // sidebar is one tree rather than a separate "Declarations" list — the
        // split made the scroll-spy highlight jump between the two blocks.
        $$("a[href^='#']", clone).forEach(function (a) {
          var sec = decodeURIComponent((a.getAttribute("href") || "").slice(1));
          if (groups[sec]) a.parentNode.appendChild(declList(groups[sec]));
        });
        nav.appendChild(clone);
        pushSpy(clone);
      }
    } else if (defs.length) {
      // No sections on this page: a single flat list of declarations.
      nav.appendChild(el("div", { class: "kg-sb-title" }, "Declarations"));
      var dl = declList(defs);
      nav.appendChild(dl);
      pushSpy(dl);
    }

    // Mirror the header page links into the drawer (header nav is hidden on mobile).
    if (pageLinks.length) {
      nav.appendChild(el("div", { class: "kg-sb-title" }, "Page"));
      var pl = el("ul", { class: "kg-sb-sub" });
      pageLinks.forEach(function (a) {
        var li = el("li");
        li.appendChild(el("a", { href: a.getAttribute("href") }, esc(a.textContent.trim())));
        pl.appendChild(li);
      });
      nav.appendChild(pl);
    }

    document.body.appendChild(nav);
    document.body.classList.add("kg-has-sidebar");
    if (!rich) document.body.classList.add("kg-sidebar-min");

    // Close the mobile drawer after following a link.
    nav.addEventListener("click", function (e) {
      if (e.target.closest("a")) document.body.classList.remove("kg-nav-open");
    });

    scrollSpy(spyTargets);
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

      links.forEach(function (a) { a.classList.toggle("kg-active", a === current); });
    }
    function onScroll() {
      if (!ticking) { ticking = true; requestAnimationFrame(update); }
    }
    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", onScroll);
    update();
  }

  /* ====================================================================== */
  /* Search overlay (over Haddock's doc-index.json from --quickjump)         */
  /* ====================================================================== */
  var searchState = { loaded: false, items: [], overlay: null, input: null, list: null, sel: 0 };

  function baseHref() {
    // Source pages live under src/ — the index sits one level up.
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
      // Haddock folds a class/data's members into one entry, so `name` is a
      // space-separated list ("Container empty insert Elem size $dmsize") meant
      // for matching. Match on the whole string, but only show the first token.
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
    // Entries whose displayed (primary) name prefix-matches rank first, then
    // shorter names.
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
    // Close first: a same-page result only changes the hash, so the page never
    // unloads and the overlay would otherwise stay open over the target.
    closeSearch();
    location.href = it.link;
  }

  /* ====================================================================== */
  /* Help overlay                                                            */
  /* ====================================================================== */
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

  /* ====================================================================== */
  /* Global keyboard shortcuts                                               */
  /* ====================================================================== */
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

  // Functions that document their arguments individually render as just a name
  // plus an "Arguments" table, with no inline type signature. Rebuild the
  // signature from the argument bars (":: Int", "-> String", ...) and show it
  // next to the name, keeping the table below for the per-argument docs.
  function inlineArgSignatures() {
    $$("#interface .top").forEach(function (top) {
      var table = $(".subs.arguments table", top);
      if (!table) return;
      var src = $(".src", top);
      if (!src || $(".kg-argsig", src)) return;
      var def = $("a.def", src);
      if (!def) return;
      var bars = $$("td.src", table);
      if (!bars.length) return;
      var sig = el("span", { class: "kg-argsig" });
      bars.forEach(function (bar, i) {
        if (i) sig.appendChild(document.createTextNode(" "));
        // Clone the bar's nodes so links and styling carry over.
        Array.prototype.slice.call(bar.childNodes).forEach(function (n) {
          sig.appendChild(n.cloneNode(true));
        });
      });
      // Drop it in right after the defined name, with a leading space.
      def.parentNode.insertBefore(sig, def.nextSibling);
      def.parentNode.insertBefore(document.createTextNode(" "), sig);
    });
  }

  // Re-flow over-long type signatures into the canonical multi-line shape: break
  // before each top-level :: => and -> (never inside parens or brackets), each
  // continuation indented two columns so the operators line up. Done only when
  // the single-line form doesn't fit, so short sigs are left alone — and it is
  // width-aware and re-runnable, so a sig that fits on a wide screen but not a
  // narrow/mobile one gets broken (and un-broken again if the screen widens).
  // Runs after enhanceSourceLinks: we measure the .kg-sig, whose width already
  // excludes the Source/# links, so the fit test is accurate.
  function reflowSignatures() {
    $$("#interface .src").forEach(function (src) {
      var sig = $(".kg-sig", src) || src; // the signature, minus the source links
      collapseBreaks(sig); // start from the single-line form every time
      src.classList.remove("kg-multiline");
      if (sigNeedsBreak(sig) && breakTypeSig(sig)) {
        src.classList.add("kg-multiline");
      }
    });
  }

  // True when the single-line signature is wider than the space it has.
  function sigNeedsBreak(sig) {
    var avail = sig.clientWidth;
    if (!avail) {
      // Unmeasurable (inline, or inside a collapsed details): length heuristic.
      return sig.textContent.replace(/\s+/g, " ").trim().length > 64;
    }
    var prev = sig.style.whiteSpace;
    sig.style.whiteSpace = "nowrap";
    var over = sig.scrollWidth - avail > 6;
    sig.style.whiteSpace = prev;
    return over;
  }

  // Undo a previous break pass: collapse each inserted "\n  " back to one space.
  function collapseBreaks(root) {
    var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null);
    for (var n = walker.nextNode(); n; n = walker.nextNode()) {
      if (n.textContent.indexOf("\n") >= 0) {
        n.textContent = n.textContent.replace(/\n[ \t]*/g, " ");
      }
    }
  }

  function breakTypeSig(root) {
    var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null);
    var nodes = [];
    for (var n = walker.nextNode(); n; n = walker.nextNode()) nodes.push(n);
    var depth = 0;
    var seen = false; // any non-space content emitted, so we never lead with a break
    var broke = false;
    nodes.forEach(function (node) {
      var t = node.textContent;
      var out = "";
      var i = 0;
      while (i < t.length) {
        var c = t.charAt(i);
        if (c === "(" || c === "[") { depth++; seen = true; out += c; i++; continue; }
        if (c === ")" || c === "]") { if (depth > 0) depth--; seen = true; out += c; i++; continue; }
        if (depth === 0 && seen) {
          var two = t.substr(i, 2);
          if (two === "::" || two === "=>" || two === "->") {
            out = out.replace(/[ \t]+$/, "");
            out += "\n  " + two;
            i += 2;
            broke = true;
            continue;
          }
        }
        if (c !== " " && c !== "\t" && c !== "\n") seen = true;
        out += c;
        i++;
      }
      node.textContent = out;
    });
    return broke;
  }

  // The chevron is only an indicator — make the whole instance card header
  // toggle. We toggle the linked <details> directly (forwarding a click to
  // Haddock's control proved unreliable) and keep the chevron class in sync.
  // The chevron itself is left to Haddock's own handler. No-JS users fall back
  // to the native <summary> toggle (see the body.js-enabled CSS gating).
  function enlargeInstanceToggles() {
    $$("#interface .instance.details-toggle-control[data-details-id]").forEach(function (ctrl) {
      var det = document.getElementById(ctrl.getAttribute("data-details-id"));
      var row = ctrl.closest("tr");
      // Haddock emits a literal space after the (empty) chevron span. Drop it so
      // the gap to the instance name comes only from the chevron's margin, the
      // same as every other toggle.
      var after = ctrl.nextSibling;
      if (after && after.nodeType === 3) after.textContent = after.textContent.replace(/^\s+/, "");
      if (!det || !row || row.dataset.kgToggle) return;
      row.dataset.kgToggle = "1";
      row.addEventListener("click", function (e) {
        if (e.target.closest("a")) return; // Source / # / type links
        if (e.target.closest(".details-toggle-control")) return; // chevron → Haddock
        det.open = !det.open;
        ctrl.classList.toggle("collapser", det.open);
        ctrl.classList.toggle("expander", !det.open);
      });
    });
  }

  // Split each signature row into a scrollable signature and a pinned links box,
  // so Source / # sit consistently at the right (flex, no overlap).
  function enhanceSourceLinks() {
    $$(".src").forEach(function (src) {
      var links = $$("a.link, a.selflink", src).filter(function (a) {
        return a.parentNode === src;
      });
      if (!links.length) return;
      var sig = el("span", { class: "kg-sig" });
      var box = el("span", { class: "kg-srclinks" });
      Array.prototype.slice.call(src.childNodes).forEach(function (node) {
        if (node.nodeType === 1 && node.matches && node.matches("a.link, a.selflink")) {
          box.appendChild(node);
        } else {
          sig.appendChild(node);
        }
      });
      src.appendChild(sig);
      src.appendChild(box);
      src.classList.add("kg-srcrow");
    });
  }

  /* ====================================================================== */
  /* Source pages: line numbers + target-line highlight                      */
  /* ====================================================================== */
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

  /* ====================================================================== */
  /* Footer credit                                                           */
  /* ====================================================================== */
  function enhanceFooter() {
    var footer = $("#footer p") || $("#footer");
    if (!footer || footer.querySelector(".kg-credit")) return;
    var span = el("span", { class: "kg-credit" },
      " · rendered with <a href=\"https://github.com/velveteer/kedgeree\">Kedgeree</a> 🍛");
    footer.appendChild(span);
  }

  // Multi-package landing page (generated by kedgeree --landing): give it the
  // same theme toggle as a doc page. The Haddock-specific passes above all no-op
  // on it (it has no #package-header, #interface, #footer, source spans…).
  function enhanceLanding() {
    if (!document.body.classList.contains("kg-landing")) return;
    var header = $(".kg-landing-header");
    if (!header) return;
    var actions = el("div", { class: "kg-actions" });
    actions.appendChild(themeButton());
    header.appendChild(actions);
  }

  /* ====================================================================== */
  /* Boot                                                                    */
  /* ====================================================================== */
  function init() {
    applyTheme(currentTheme());
    enhanceHeader();
    enhanceLanding();
    buildSidebar();
    inlineArgSignatures();
    enlargeInstanceToggles();
    enhanceSourceLinks();
    reflowSignatures();
    enhanceSource();
    enhanceFooter();

    // Re-flow signatures when the viewport changes (resize / rotate), so the
    // multi-line breaks track whether the single-line form still fits.
    var reflowTimer;
    window.addEventListener("resize", function () {
      clearTimeout(reflowTimer);
      reflowTimer = setTimeout(reflowSignatures, 150);
    });

    // Dismiss the mobile drawer when tapping outside it.
    document.addEventListener("click", function (e) {
      if (!document.body.classList.contains("kg-nav-open")) return;
      if (e.target.closest("#kg-sidebar") || e.target.closest(".kg-menu-toggle")) return;
      document.body.classList.remove("kg-nav-open");
    });

    // One checkbox in Haddock's preferences dropdown uses a bare <span>, not a
    // <label>, so delegate clicks on its text to the checkbox.
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
