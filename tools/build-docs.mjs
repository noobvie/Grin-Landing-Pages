#!/usr/bin/env node
// build-docs.mjs — render the Grin Node Toolkit manual from Markdown to static HTML.
//
//   node tools/build-docs.mjs            build every page + sitemap.xml
//   node tools/build-docs.mjs --check    build to memory only, report problems, write nothing
//
// Zero dependencies on purpose: the landing-page repo has no package.json and the
// deploy script (site_manager.sh) rsyncs web/<site>/ as-is, so the rendered HTML is
// committed and nothing runs on the server. Sources live in docs-src/grinnode-org/,
// output goes to web/grinnode-org-2026/docs/. Only the subset of Markdown used by
// the manual is supported — see renderMarkdown() — which is why this file is small.
//
// Front matter (--- block at the top of every page):
//   title        page <h1> and <title>              (required)
//   description  lead paragraph + meta description  (required)
//   section      sidebar group, one of SECTIONS      (required)
//   order        sort key inside the section         (required, number)
//   covers       toolkit code date the page was written against (YYYY-MM-DD)
//   updated      date the page text last changed     (YYYY-MM-DD)
//   label        short kicker, e.g. "Script 01"      (optional)
//   short        page name in the symptom index      (optional, defaults to title)
//
// URLs are extension-less: pages are written as <slug>.html (the source Markdown links
// to "<slug>.html" too, which is what the dead-link check reads), but every relative
// href, the canonical, og:url, JSON-LD and the sitemap drop the ".html". nginx serves
// them with `try_files $uri $uri.html` and 301s the .html form — see the /docs/ location
// in site_manager.sh. Opening a page from disk still works; following a link from it
// does not, so preview through the real vhost (or read the pages one at a time).
//
// Troubleshooting: every row of a table under a heading named "Troubleshooting" (or
// "Common first-run problems") gets an anchor id "ts-<symptom words>", and a page that
// contains the line <div data-symptom-index></div> gets an A–Z table of all of them,
// generated at build time so the index can never drift from the pages it points into.

import { readFileSync, writeFileSync, readdirSync, mkdirSync, existsSync } from "node:fs";
import { join, basename, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { execSync } from "node:child_process";

const ROOT     = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const SRC_DIR  = join(ROOT, "docs-src", "grinnode-org");
const SITE_DIR = join(ROOT, "web", "grinnode-org-2026");
const OUT_DIR  = join(SITE_DIR, "docs");
const SITE_URL = "https://grinnode.org";
const DOCS_URL = `${SITE_URL}/docs/`;
const REPO_URL = "https://github.com/noobvie/Grin-Node-Toolkit";
const SECTIONS = ["Start here", "Scripts", "Reference"];
const CHECK    = process.argv.includes("--check");
const TS_HEADING = /^(troubleshooting|common first-run problems)$/i;

const problems = [];
const warn = (m) => problems.push(m);

// ---------------------------------------------------------------------------
// Front matter
// ---------------------------------------------------------------------------
function parseFrontMatter(raw, file) {
  const m = raw.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n?/);
  if (!m) throw new Error(`${file}: missing front matter`);
  const meta = {};
  for (const line of m[1].split(/\r?\n/)) {
    const kv = line.match(/^([a-z_]+):\s*(.*)$/);
    if (kv) meta[kv[1]] = kv[2].trim();
  }
  for (const k of ["title", "description", "section", "order"]) {
    if (!meta[k]) throw new Error(`${file}: front matter needs '${k}'`);
  }
  if (!SECTIONS.includes(meta.section)) throw new Error(`${file}: unknown section '${meta.section}'`);
  meta.order = Number(meta.order);
  for (const k of ["covers", "updated"]) {
    if (meta[k] && !/^\d{4}-\d{2}-\d{2}$/.test(meta[k])) throw new Error(`${file}: '${k}' must be YYYY-MM-DD`);
  }
  return { meta, body: raw.slice(m[0].length) };
}

// ---------------------------------------------------------------------------
// Markdown → HTML (the subset the manual uses)
// ---------------------------------------------------------------------------
const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
const slug = (s) => s.toLowerCase().replace(/<[^>]+>/g, "").replace(/&[a-z]+;/g, "").replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");

function inline(text) {
  // Protect code spans first so nothing inside them is touched.
  const codes = [];
  let s = text.replace(/`([^`]+)`/g, (_, c) => { codes.push(`<code>${esc(c)}</code>`); return `\u0000${codes.length - 1}\u0000`; });
  s = esc(s);
  s = s.replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, (_, t, u) => {
    const ext = /^https?:\/\//.test(u);
    return `<a href="${u}"${ext ? ' target="_blank" rel="noopener"' : ""}>${t}</a>`;
  });
  s = s.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
  s = s.replace(/(^|[\s(])\*([^*\s][^*]*?)\*(?=[\s.,;:)!?]|$)/g, "$1<em>$2</em>");
  s = s.replace(/(^|[\s(])_([^_\s][^_]*?)_(?=[\s.,;:)!?]|$)/g, "$1<em>$2</em>");
  return s.replace(/\u0000(\d+)\u0000/g, (_, i) => codes[i]);
}

const CALLOUTS = { note: "Note", tip: "Tip", warning: "Warning", danger: "Danger" };

// First free id of the form base, base-2, base-3 … on this page.
function uniqueId(ctx, base) {
  if (!ctx.ids.has(base)) return base;
  let n = 2;
  while (ctx.ids.has(`${base}-${n}`)) n++;
  return `${base}-${n}`;
}

// Extension-less URLs: "slug.html#x" → "slug#x", "index.html" → "./". Relative hrefs only.
const cleanHrefs = (html) => html.replace(/href="([a-z0-9][a-z0-9.-]*?)\.html(#[^"]*)?"/g, (_, s, h = "") => `href="${s === "index" ? "./" : s}${h}"`);
const pageUrl = (s) => (s === "index" ? DOCS_URL : `${DOCS_URL}${s}`);

function renderMarkdown(md, ctx) {
  const lines = md.replace(/\r\n/g, "\n").split("\n");
  const out = [];
  const headings = [];
  let i = 0;
  const peek = () => lines[i] ?? null;

  const renderList = (indentBase) => {
    // Returns HTML for a list whose items sit at indentBase columns.
    const first = lines[i].match(/^(\s*)([-*]|\d+\.)\s+/);
    const ordered = /\d/.test(first[2]);
    let html = ordered ? "<ol>" : "<ul>";
    while (i < lines.length) {
      const m = lines[i].match(/^(\s*)([-*]|\d+\.)\s+(.*)$/);
      if (!m || m[1].length !== indentBase) break;
      i++;
      let item = m[3];
      // Continuation lines (indented more, not a new bullet) join the item.
      let sub = "";
      while (i < lines.length) {
        const n = lines[i];
        const nm = n.match(/^(\s*)([-*]|\d+\.)\s+/);
        if (nm && nm[1].length > indentBase) { sub += renderList(nm[1].length); continue; }
        if (nm || n.trim() === "" || n.match(/^\s*/)[0].length <= indentBase) break;
        item += " " + n.trim(); i++;
      }
      html += `<li>${inline(item)}${sub}</li>`;
    }
    return html + (ordered ? "</ol>" : "</ul>");
  };

  while (i < lines.length) {
    const line = lines[i];
    if (line.trim() === "") { i++; continue; }

    // Fenced code
    let m = line.match(/^```(\w*)\s*$/);
    if (m) {
      const lang = m[1] || "text";
      const buf = [];
      i++;
      while (i < lines.length && !/^```\s*$/.test(lines[i])) buf.push(lines[i++]);
      i++;
      out.push(`<div class="code" data-lang="${lang}"><button type="button" class="copy" aria-label="Copy to clipboard">Copy</button><pre><code class="lang-${lang}">${esc(buf.join("\n"))}</code></pre></div>`);
      continue;
    }
    // Heading
    m = line.match(/^(#{1,4})\s+(.+?)\s*#*$/);
    if (m) {
      const level = Math.max(2, m[1].length); // the front-matter title owns h1, so '#' and '##' both render as h2
      const text = inline(m[2]);
      let id = slug(m[2]);
      if (ctx.ids.has(id)) {
        warn(`${ctx.file}: duplicate heading id '${id}' — give the heading a unique text (rendered as '${uniqueId(ctx, id)}')`);
        id = uniqueId(ctx, id);
      }
      ctx.ids.add(id);
      if (level <= 3) ctx.ts = TS_HEADING.test(m[2].trim());
      if (level === 2) headings.push({ id, text });
      out.push(`<h${level} id="${id}">${text}<a class="anchor" href="#${id}" aria-label="Link to this section">#</a></h${level}>`);
      i++; continue;
    }
    // Horizontal rule
    if (/^-{3,}\s*$/.test(line)) { out.push("<hr>"); i++; continue; }
    // Blockquote / callout
    if (/^>/.test(line)) {
      const buf = [];
      while (i < lines.length && /^>/.test(lines[i])) buf.push(lines[i++].replace(/^>\s?/, ""));
      const text = buf.join("\n");
      const cm = text.match(/^\*\*(Note|Tip|Warning|Danger):\*\*\s*/i);
      if (cm) {
        const kind = cm[1].toLowerCase();
        const body = renderMarkdown(text.slice(cm[0].length), ctx).html;
        out.push(`<aside class="callout callout-${kind}"><span class="callout-label">${CALLOUTS[kind]}</span><div>${body}</div></aside>`);
      } else {
        out.push(`<blockquote>${renderMarkdown(text, ctx).html}</blockquote>`);
      }
      continue;
    }
    // Table
    if (/^\|/.test(line) && i + 1 < lines.length && /^\|?\s*:?-{2,}/.test(lines[i + 1])) {
      const cells = (l) => l.replace(/^\||\|$/g, "").split("|").map((c) => c.trim());
      const head = cells(line);
      const align = cells(lines[i + 1]).map((c) => (/^:-+:$/.test(c) ? "center" : /-+:$/.test(c) ? "right" : ""));
      i += 2;
      const rows = [];
      while (i < lines.length && /^\|/.test(lines[i])) rows.push(cells(lines[i++]));
      const td = (c, j, tag) => `<${tag}${align[j] ? ` style="text-align:${align[j]}"` : ""}>${inline(c)}</${tag}>`;
      const tr = (r) => {
        if (!ctx.ts) return "<tr>";
        const id = uniqueId(ctx, "ts-" + slug(r[0]).split("-").slice(0, 8).join("-").slice(0, 60).replace(/-+$/, ""));
        ctx.ids.add(id);
        ctx.tsRows.push({ md: r[0], id });
        return `<tr id="${id}">`;
      };
      out.push(`<div class="table-wrap"><table><thead><tr>${head.map((c, j) => td(c, j, "th")).join("")}</tr></thead><tbody>${rows.map((r) => `${tr(r)}${r.map((c, j) => td(c, j, "td")).join("")}</tr>`).join("")}</tbody></table></div>`);
      continue;
    }
    // List
    m = line.match(/^(\s*)([-*]|\d+\.)\s+/);
    if (m) { out.push(renderList(m[1].length)); continue; }
    // Raw block HTML passthrough (a line starting with a tag, up to the next blank line)
    if (/^<(div|aside|details|section|figure|p|table|ul|ol|nav)\b/.test(line)) {
      const buf = [];
      while (i < lines.length && lines[i].trim() !== "") buf.push(lines[i++]);
      out.push(buf.join("\n"));
      continue;
    }
    // Paragraph
    const buf = [];
    while (i < lines.length && lines[i].trim() !== "" && !/^(#{1,4}\s|```|>|\||-{3,}\s*$|\s*([-*]|\d+\.)\s)/.test(lines[i])) buf.push(lines[i++]);
    out.push(`<p>${inline(buf.join(" "))}</p>`);
  }
  return { html: out.join("\n"), headings };
}

// ---------------------------------------------------------------------------
// Page template
// ---------------------------------------------------------------------------
function gitDate(relPath) {
  try {
    const d = execSync(`git log -1 --format=%cs -- "${relPath}"`, { cwd: ROOT, stdio: ["ignore", "pipe", "ignore"] }).toString().trim();
    return /^\d{4}-\d{2}-\d{2}$/.test(d) ? d : null;
  } catch { return null; }
}
const today = new Date().toISOString().slice(0, 10);
const fmtDate = (d) => new Date(d + "T00:00:00Z").toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric", timeZone: "UTC" });

function sidebar(pages, current) {
  return SECTIONS.map((sec) => {
    const items = pages.filter((p) => p.meta.section === sec);
    if (!items.length) return "";
    return `<div class="nav-group"><div class="nav-title">${sec}</div>${items.map((p) =>
      `<a href="${p.slug}.html"${p === current ? ' aria-current="page"' : ""}>${p.meta.label ? `<span class="nav-label">${esc(p.meta.label)}</span>` : ""}${esc(p.meta.title)}</a>`
    ).join("")}</div>`;
  }).join("");
}

function page(p, pages, idx) {
  const { meta, html, headings, slug: s } = p;
  const url = pageUrl(s);
  const fullTitle = s === "index" ? `${meta.title} — GrinNode.org` : `${meta.title} — Grin Node Toolkit Manual`;
  const prev = pages[idx - 1], next = pages[idx + 1];
  const crumbs = [{ n: "GrinNode.org", u: `${SITE_URL}/` }, { n: "Manual", u: DOCS_URL }];
  if (s !== "index") crumbs.push({ n: meta.title, u: url });
  const ld = [
    { "@context": "https://schema.org", "@type": "TechArticle", headline: meta.title, description: meta.description, url,
      dateModified: meta.updated || today, inLanguage: "en", isPartOf: { "@type": "WebSite", name: "GrinNode.org", url: `${SITE_URL}/` },
      about: { "@type": "SoftwareApplication", name: "Grin Node Toolkit", operatingSystem: "Linux", applicationCategory: "DeveloperApplication", url: REPO_URL },
      author: { "@type": "Organization", name: "GrinNode.org", url: `${SITE_URL}/` } },
    { "@context": "https://schema.org", "@type": "BreadcrumbList",
      itemListElement: crumbs.map((c, n) => ({ "@type": "ListItem", position: n + 1, name: c.n, item: c.u })) },
  ];
  const toc = headings.length > 1 ? `<aside class="toc" aria-label="On this page"><div class="toc-title">On this page</div><nav>${headings.map((h) => `<a href="#${h.id}">${h.text}</a>`).join("")}</nav></aside>` : "";
  const stamp = (meta.covers || meta.updated)
    ? `<div class="stamp">${meta.covers ? `<span>Covers the toolkit as of <time datetime="${meta.covers}">${fmtDate(meta.covers)}</time></span>` : ""}${meta.updated ? `<span>Page updated <time datetime="${meta.updated}">${fmtDate(meta.updated)}</time></span>` : ""}<a href="${REPO_URL}" target="_blank" rel="noopener">Toolkit on GitHub</a></div>`
    : "";
  const pager = `<nav class="pager" aria-label="Previous and next page">${prev ? `<a class="pager-prev" href="${prev.slug}.html"><span>Previous</span><strong>${esc(prev.meta.title)}</strong></a>` : "<span></span>"}${next ? `<a class="pager-next" href="${next.slug}.html"><span>Next</span><strong>${esc(next.meta.title)}</strong></a>` : ""}</nav>`;

  return cleanHrefs(`<!doctype html>
<html lang="en" data-theme="dark">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${esc(fullTitle)}</title>
  <meta name="description" content="${esc(meta.description)}">
  <meta name="robots" content="index, follow">
  <meta name="author" content="GrinNode.org">
  <meta name="theme-color" content="#3dffa0">
  <link rel="canonical" href="${url}">
  <link rel="icon" href="../favicon.svg" type="image/svg+xml">
  <meta property="og:type" content="article">
  <meta property="og:site_name" content="GrinNode.org">
  <meta property="og:title" content="${esc(fullTitle)}">
  <meta property="og:description" content="${esc(meta.description)}">
  <meta property="og:url" content="${url}">
  <meta property="og:image" content="${SITE_URL}/og-image.svg">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${esc(fullTitle)}">
  <meta name="twitter:description" content="${esc(meta.description)}">
  <meta name="twitter:image" content="${SITE_URL}/og-image.svg">
  <link rel="stylesheet" href="docs.css">
  <script>(function(){try{var t=localStorage.getItem("grinnode-theme");if(t==="light"||t==="dark")document.documentElement.dataset.theme=t;else if(matchMedia("(prefers-color-scheme: light)").matches)document.documentElement.dataset.theme="light";}catch(e){}})();</script>
  <script type="application/ld+json">${JSON.stringify(ld)}</script>
</head>
<body>
  <a class="skip" href="#main">Skip to content</a>
  <header class="header">
    <nav class="nav" aria-label="Primary navigation">
      <div class="brand"><a href="../" aria-label="GrinNode.org home"><img src="../favicon.svg" width="32" height="32" alt="" aria-hidden="true" class="brand-logo"><span>GrinNode.org</span></a><span class="brand-sep" aria-hidden="true">/</span><a href="./" class="brand-manual">Manual</a></div>
      <div class="links">
        <a href="../#run">Run a node</a><a href="../#grim">Wallets</a><a href="../#why-grin">Why Grin</a>
      </div>
      <div class="actions">
        <button class="theme" id="themeToggle" type="button" aria-label="Toggle light and dark theme"><span class="sun" aria-hidden="true"></span></button>
        <a class="btn ghost" href="${REPO_URL}" target="_blank" rel="noopener">GitHub</a>
        <button class="btn ghost menu-btn" id="menuToggle" type="button" aria-expanded="false" aria-controls="sidebar">Contents</button>
      </div>
    </nav>
  </header>

  <div class="layout">
    <aside class="sidebar" id="sidebar" aria-label="Manual contents">
      <nav>${sidebar(pages, p)}</nav>
    </aside>

    <main id="main">
      <nav class="crumbs" aria-label="Breadcrumb">${crumbs.map((c, n) => n === crumbs.length - 1 ? `<span aria-current="page">${esc(c.n)}</span>` : `<a href="${c.u}">${esc(c.n)}</a>`).join('<span class="crumb-sep" aria-hidden="true">›</span>')}</nav>
      <article>
        <div class="kicker">${esc(meta.section)}${meta.label ? ` · ${esc(meta.label)}` : ""}</div>
        <h1>${esc(meta.title)}</h1>
        <p class="lead">${esc(meta.description)}</p>
        ${stamp}
${html}
      </article>
      ${pager}
    </main>

    ${toc}
  </div>

  <footer class="footer">
    <div class="footerInner">
      <span>From Saigon with ❤️ <svg viewBox="0 0 27 18" width="21" height="14" role="img" aria-label="Yellow flag with three red stripes" style="vertical-align:-2px;border-radius:2px"><rect width="27" height="18" fill="#FFCD00"/><rect y="4" width="27" height="2" fill="#DA251D"/><rect y="8" width="27" height="2" fill="#DA251D"/><rect y="12" width="27" height="2" fill="#DA251D"/></svg></span>
      <span><a href="${REPO_URL}" target="_blank" rel="noopener">Grin Node Toolkit</a> &nbsp;/&nbsp; <a href="${REPO_URL}/issues" target="_blank" rel="noopener">Report an issue</a> &nbsp;/&nbsp; <a href="https://grin.mw" target="_blank" rel="noopener">Grin</a></span>
    </div>
  </footer>

  <script>
    (function () {
      var root = document.documentElement;
      document.getElementById("themeToggle").addEventListener("click", function () {
        root.dataset.theme = root.dataset.theme === "dark" ? "light" : "dark";
        try { localStorage.setItem("grinnode-theme", root.dataset.theme); } catch (e) {}
      });
      var side = document.getElementById("sidebar"), btn = document.getElementById("menuToggle");
      btn.addEventListener("click", function () {
        var open = side.classList.toggle("open");
        btn.setAttribute("aria-expanded", open ? "true" : "false");
      });
      document.querySelectorAll(".copy").forEach(function (b) {
        b.addEventListener("click", function () {
          var code = b.parentNode.querySelector("code").textContent;
          var done = function () { b.textContent = "Copied"; setTimeout(function () { b.textContent = "Copy"; }, 1600); };
          if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(code).then(done, function () {});
          else { var r = document.createRange(); r.selectNodeContents(b.parentNode.querySelector("code")); var s = getSelection(); s.removeAllRanges(); s.addRange(r); try { document.execCommand("copy"); done(); } catch (e) {} s.removeAllRanges(); }
        });
      });
      var filter = document.getElementById("symptomFilter");
      if (filter) {
        var trs = Array.prototype.slice.call(document.querySelectorAll(".symptom-index tbody tr")), count = document.getElementById("symptomCount");
        var run = function () {
          var q = filter.value.trim().toLowerCase(), n = 0;
          trs.forEach(function (r) { var hit = !q || r.textContent.toLowerCase().indexOf(q) > -1; r.hidden = !hit; if (hit) n++; });
          count.textContent = q ? n + " of " + trs.length + " match" : trs.length + " symptoms";
        };
        filter.parentNode.hidden = false;
        filter.addEventListener("input", run); run();
      }
      var links = Array.prototype.slice.call(document.querySelectorAll(".toc a"));
      if (links.length && "IntersectionObserver" in window) {
        var map = {};
        links.forEach(function (a) { map[a.getAttribute("href").slice(1)] = a; });
        var io = new IntersectionObserver(function (entries) {
          entries.forEach(function (en) {
            if (en.isIntersecting) { links.forEach(function (a) { a.classList.remove("active"); }); var a = map[en.target.id]; if (a) a.classList.add("active"); }
          });
        }, { rootMargin: "-80px 0px -70% 0px" });
        Object.keys(map).forEach(function (id) { var el = document.getElementById(id); if (el) io.observe(el); });
      }
    })();
  </script>
</body>
</html>
`);
}

// ---------------------------------------------------------------------------
// Build
// ---------------------------------------------------------------------------
const files = readdirSync(SRC_DIR).filter((f) => f.endsWith(".md")).sort();
const pages = files.map((f) => {
  const raw = readFileSync(join(SRC_DIR, f), "utf8");
  const { meta, body } = parseFrontMatter(raw, f);
  const s = basename(f, ".md");
  const ctx = { file: f, ids: new Set(), ts: false, tsRows: [] };
  const { html, headings } = renderMarkdown(body, ctx);
  return { file: f, slug: s, meta, html, headings, tsRows: ctx.tsRows };
});
pages.sort((a, b) => SECTIONS.indexOf(a.meta.section) - SECTIONS.indexOf(b.meta.section) || a.meta.order - b.meta.order || a.slug.localeCompare(b.slug));
if (!pages.some((p) => p.slug === "index")) throw new Error("docs-src needs an index.md");

// Symptom index: every troubleshooting row of every page, A–Z, linking to the row itself.
const SYMPTOM_SLOT = "<div data-symptom-index></div>";
const sortKey = (md) => md.replace(/[`*_"“”'…]/g, "").replace(/^(the|a|an)\s+/i, "").trim().toLowerCase();
for (const p of pages.filter((q) => q.html.includes(SYMPTOM_SLOT))) {
  const rows = pages.filter((q) => q !== p).flatMap((q) => q.tsRows.map((r) => ({ ...r, page: q })))
    .sort((a, b) => sortKey(a.md).localeCompare(sortKey(b.md), "en"));
  const from = new Set(rows.map((r) => r.page.slug)).size;
  p.html = p.html.replace(SYMPTOM_SLOT,
    `<div class="symptom-filter" hidden><label for="symptomFilter">Filter</label><input id="symptomFilter" type="search" placeholder="Type part of the message, e.g. certbot" autocomplete="off" spellcheck="false"><span id="symptomCount" class="symptom-count" aria-live="polite"></span></div>
` +
    `<p class="symptom-total">${rows.length} symptoms from ${from} pages.</p>
` +
    `<div class="table-wrap symptom-index"><table><thead><tr><th>Symptom</th><th>Page</th></tr></thead><tbody>${rows.map((r) =>
      `<tr><td>${inline(r.md)}</td><td><a href="${r.page.slug}.html#${r.id}">${esc(r.page.meta.short || r.page.meta.title)}</a></td></tr>`).join("")}</tbody></table></div>`);
}

// Dead-link check across the set (relative .html links and #anchors inside a page).
const slugs = new Set(pages.map((p) => p.slug));
for (const p of pages) {
  const ids = new Set([...p.html.matchAll(/ id="([^"]+)"/g)].map((m) => m[1]));
  for (const m of p.html.matchAll(/href="([^"#:]+\.html)(#[^"]*)?"/g)) {
    const target = m[1].replace(/^\.\//, "").replace(/\.html$/, "");
    if (!slugs.has(target)) warn(`${p.file}: link to missing page '${m[1]}'`);
    else if (m[2]) {
      const tp = pages.find((q) => q.slug === target);
      if (!tp.html.includes(` id="${m[2].slice(1)}"`)) warn(`${p.file}: anchor '${m[1]}${m[2]}' not found`);
    }
  }
  for (const m of p.html.matchAll(/href="#([^"]+)"/g)) {
    if (!ids.has(m[1])) warn(`${p.file}: in-page anchor '#${m[1]}' not found`);
  }
  if (p.meta.description.length > 160) warn(`${p.file}: description is ${p.meta.description.length} chars (aim for ≤160 for search snippets)`);
}

const rendered = pages.map((p, i) => ({ path: join(OUT_DIR, `${p.slug}.html`), html: page(p, pages, i) }));
const sitemap = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>${SITE_URL}/</loc><lastmod>${gitDate("web/grinnode-org-2026/index.html") || today}</lastmod><changefreq>weekly</changefreq><priority>1.0</priority></url>
${pages.map((p) => `  <url><loc>${pageUrl(p.slug)}</loc><lastmod>${p.meta.updated || today}</lastmod><changefreq>monthly</changefreq><priority>${p.slug === "index" ? "0.9" : "0.8"}</priority></url>`).join("\n")}
</urlset>
`;
const robots = `User-agent: *
Allow: /

Sitemap: ${SITE_URL}/sitemap.xml
`;

if (problems.length) {
  console.error(`\n${problems.length} problem(s):`);
  for (const m of problems) console.error("  - " + m);
}
if (CHECK) {
  console.log(`check: ${pages.length} page(s) render cleanly${problems.length ? " (with warnings above)" : ""}`);
  process.exit(problems.length ? 1 : 0);
}
if (!existsSync(OUT_DIR)) mkdirSync(OUT_DIR, { recursive: true });
for (const r of rendered) writeFileSync(r.path, r.html);
writeFileSync(join(SITE_DIR, "sitemap.xml"), sitemap);
writeFileSync(join(SITE_DIR, "robots.txt"), robots);
console.log(`built ${rendered.length} page(s) → ${OUT_DIR}\n  + sitemap.xml, robots.txt`);
for (const p of pages) console.log(`  ${p.slug}.html  [${p.meta.section}] ${p.meta.title}`);
process.exit(problems.length ? 1 : 0);
