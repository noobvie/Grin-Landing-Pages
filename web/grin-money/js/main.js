/* ═══════════════════════════════════════════════════════════════════════════
   Grin Landing Page — main.js
   Zero external dependencies — vanilla JS only.

   Sections:
     1. Matrix rain          — animated background canvas
     2. Typewriter           — hero terminal text animation
     3. Scroll reveal        — IntersectionObserver fade-in
     4. Stagger fade-in      — grid card staggered entrance
     5. Nav highlight        — active section tracking on scroll
     6. Nav mobile toggle    — hamburger menu for small screens
     7. Nav shadow on scroll — subtle depth effect
     8. Block counter        — live chain height from API
     9. Logo glitch          — hover effect on nav brand
    10. Clock cursor         — canvas-drawn clock replaces OS cursor
    11. Global stats         — live network stats from world.grin.money API

   Security notes:
     - All user-visible dynamic text is written via .textContent (not
       .innerHTML), so there is no XSS surface from API data.
     - External fetch targets are read-only public APIs (no auth tokens).
     - The custom cursor is gated on a .js-cursor class added to <html>
       so the native cursor is preserved if this script fails to load.
   ═══════════════════════════════════════════════════════════════════════════ */

'use strict';

/* ── 1. Matrix rain ───────────────────────────────────────────────────────────
   Draws falling green characters on a fixed canvas behind all page content.
   Uses setInterval at 50 ms (20 fps) for a deliberate, retro feel.
   The low opacity (0.07) keeps it subtle so it never obscures text.
*/
(function initMatrix() {
  const canvas = document.getElementById('matrix-canvas');
  if (!canvas) return;

  const ctx      = canvas.getContext('2d');
  const CHARS    = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789$><|[]{}#@!%^&*+=GRIN';
  const FONT_SZ  = 14;
  let columns, drops;

  function resize() {
    canvas.width  = window.innerWidth;
    canvas.height = window.innerHeight;
    columns = Math.floor(canvas.width / FONT_SZ);
    // Randomise starting positions so columns don't all begin at the top
    drops = Array.from({ length: columns }, () => Math.floor(Math.random() * -50));
  }

  function draw() {
    // Semi-transparent fill creates the fading trail effect
    ctx.fillStyle = 'rgba(10, 10, 10, 0.04)';
    ctx.fillRect(0, 0, canvas.width, canvas.height);

    ctx.fillStyle = '#00ff41';
    ctx.font = `${FONT_SZ}px 'JetBrains Mono', monospace`;

    for (let i = 0; i < drops.length; i++) {
      const char = CHARS[Math.floor(Math.random() * CHARS.length)];
      ctx.fillText(char, i * FONT_SZ, drops[i] * FONT_SZ);

      // Reset column to top with low probability once it passes the bottom
      if (drops[i] * FONT_SZ > canvas.height && Math.random() > 0.975) {
        drops[i] = 0;
      }
      drops[i]++;
    }
  }

  resize();
  window.addEventListener('resize', resize);
  setInterval(draw, 50);
})();


/* ── 2. Typewriter effect (hero terminal) ─────────────────────────────────────
   Types out four lines of "command output" with staggered delays.
   Text is written via textContent — no HTML injection possible.
*/
(function initTypewriter() {
  const lines = [
    { id: 'hero-line-1', text: 'name:     Grin',                               color: 'text-bright', delay: 400  },
    { id: 'hero-line-2', text: 'protocol: Mimblewimble',                       color: 'cyan',        delay: 900  },
    { id: 'hero-line-3', text: 'status:   active since 2019-01-15',            color: 'green',       delay: 1400 },
    { id: 'hero-line-4', text: 'emission: 60_grin/min | time_backed | forever', color: 'text',       delay: 1900 },
  ];

  lines.forEach(({ id, text, color, delay }) => {
    const el = document.getElementById(id);
    if (!el) return;

    el.style.color = 'var(--' + color + ')';

    setTimeout(() => {
      let i = 0;
      const interval = setInterval(() => {
        el.textContent = text.slice(0, i + 1);
        i++;
        if (i >= text.length) clearInterval(interval);
      }, 22); // ~22 ms per character ≈ typing speed
    }, delay);
  });
})();


/* ── 3. Scroll reveal (IntersectionObserver) ──────────────────────────────────
   Watches all .fade-in elements and adds .visible when they enter the viewport.
   Uses unobserve() after triggering so each animation fires only once.
*/
(function initScrollReveal() {
  const targets = document.querySelectorAll('.fade-in');
  if (!targets.length) return;

  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add('visible');
          observer.unobserve(entry.target); // fire once, then stop watching
        }
      });
    },
    { threshold: 0.12, rootMargin: '0px 0px -40px 0px' }
  );

  targets.forEach((el) => observer.observe(el));
})();


/* ── 4. Stagger fade-in for grid cards ───────────────────────────────────────
   Adds .fade-in + a CSS transition-delay to each card in a grid so they
   animate in one by one rather than all at once.
   Runs a second IntersectionObserver pass to catch the newly added .fade-in
   elements that weren't present when initScrollReveal ran.
*/
(function initStagger() {
  const grids = [
    '.feature-cards .feature-card',
    '.eco-grid .eco-card',
    '.why-grid .why-card',
    '.community-grid .community-card',
    '.started-grid .started-card',
    '.process-grid .process-step',
    '.git-entries .git-entry',
  ];

  grids.forEach((selector) => {
    document.querySelectorAll(selector).forEach((el, i) => {
      el.style.transitionDelay = `${i * 80}ms`;
      el.classList.add('fade-in');
    });
  });

  // Second observer pass for the elements just marked .fade-in above
  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add('visible');
          observer.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.08 }
  );

  document.querySelectorAll('.fade-in:not(.visible)').forEach((el) => observer.observe(el));
})();


/* ── 5. Nav: highlight active section on scroll ───────────────────────────────
   Reads each nav link's href, finds the matching section, and highlights
   the link whose section is currently at or above the scroll position.
*/
(function initNavHighlight() {
  const links    = document.querySelectorAll('.nav-links a');
  const sections = Array.from(links)
    .map((a) => a.getAttribute('href'))
    .filter((h) => h && h.startsWith('#'))
    .map((h) => document.querySelector(h))
    .filter(Boolean);

  function update() {
    const scrollY = window.scrollY + 80; // offset for fixed nav height
    let current = null;
    sections.forEach((sec) => {
      if (sec.offsetTop <= scrollY) current = sec.id;
    });
    links.forEach((a) => {
      a.style.color = a.getAttribute('href') === '#' + current
        ? 'var(--green)'
        : '';
    });
  }

  window.addEventListener('scroll', update, { passive: true });
  update(); // run once on load
})();


/* ── 6. Nav: mobile hamburger toggle ─────────────────────────────────────────
   Shows/hides the nav-links list on small screens via the .open class.
   Also closes the menu when any nav link is tapped.
*/
(function initNavToggle() {
  const btn   = document.getElementById('nav-toggle');
  const links = document.getElementById('nav-links');
  if (!btn || !links) return;

  btn.addEventListener('click', () => {
    links.classList.toggle('open');
    btn.textContent = links.classList.contains('open') ? '✕' : '☰';
  });

  links.querySelectorAll('a').forEach((a) => {
    a.addEventListener('click', () => {
      links.classList.remove('open');
      btn.textContent = '☰';
    });
  });
})();


/* ── 7. Nav: drop shadow on scroll ───────────────────────────────────────────
   Adds a subtle box-shadow to the fixed nav once the user scrolls past 20px,
   creating visual separation from the page content below.
*/
(function initNavScroll() {
  const nav = document.getElementById('nav');
  if (!nav) return;
  window.addEventListener('scroll', () => {
    nav.style.boxShadow = window.scrollY > 20
      ? '0 2px 20px rgba(0,0,0,0.5)'
      : 'none';
  }, { passive: true });
})();


/* ── 8. Block counter — live chain height from world.grin.money API ───────────
   Fetches /api/summary which returns { tip_height, current_hashrate, ... }.
   Shows "connecting..." until the first response arrives.
   On any network or parse error, shows "connecting..." (never a stale number).
   Refreshes every 5 minutes.

   Security: response is a plain JSON object; only a numeric field is read
   and formatted via toLocaleString() before being written as textContent.
*/
(function initBlockCounters() {
  const footer = document.getElementById('footer-block');
  const nav    = document.getElementById('nav-block');

  function set(text) {
    if (footer) footer.textContent = text;
    if (nav)    nav.textContent    = text;
  }

  async function fetchHeight() {
    try {
      const res  = await fetch('https://world.grin.money/api/summary', { cache: 'no-store' });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();
      if (data && data.tip_height) {
        set(Number(data.tip_height).toLocaleString());
        return;
      }
      throw new Error('tip_height missing in response');
    } catch (err) {
      console.error('[Grin] Block counter fetch failed:', err.message);
      set('connecting...');
    }
  }

  set('connecting...');
  fetchHeight();
  setInterval(fetchHeight, 5 * 60 * 1000); // refresh every 5 min
})();


/* ── 9. Logo glitch on hover ──────────────────────────────────────────────────
   Fires a quick three-step text-shadow glitch animation when the nav logo
   is hovered, reinforcing the cyberpunk aesthetic.
*/
(function initGlitch() {
  const logo = document.querySelector('.nav-logo');
  if (!logo) return;

  logo.addEventListener('mouseenter', () => {
    logo.style.textShadow = '2px 0 var(--cyan), -2px 0 var(--magenta)';
    setTimeout(() => { logo.style.textShadow = '1px 0 var(--cyan), -1px 0 var(--magenta)'; }, 80);
    setTimeout(() => { logo.style.textShadow = 'none'; }, 160);
  });
})();


/* ── 10. Clock cursor ─────────────────────────────────────────────────────────
   Replaces the OS cursor with a canvas-drawn analogue clock that shows the
   current local time — reinforcing Grin's "time-backed" theme.

   The .js-cursor class is added to <html> before the canvas is initialised
   so that cursor: none only applies when this code has actually run.
   On hover over links/buttons the clock ring shifts to cyan.

   Canvas is sized at 34×34 logical px, scaled for HiDPI (max 2×).
*/
(function initClockCursor() {
  const canvas = document.getElementById('clock-cursor');
  if (!canvas) return;

  // Signal to CSS that JS is active — enables cursor: none safely
  document.documentElement.classList.add('js-cursor');

  // HiDPI: render at device pixel ratio (capped at 2×) for crisp lines
  const SIZE = 34;
  const DPR  = Math.min(window.devicePixelRatio || 1, 2);
  canvas.width  = SIZE * DPR;
  canvas.height = SIZE * DPR;
  canvas.style.width  = SIZE + 'px';
  canvas.style.height = SIZE + 'px';

  const ctx = canvas.getContext('2d');
  ctx.scale(DPR, DPR);

  const CX = SIZE / 2; // centre x
  const CY = SIZE / 2; // centre y
  const R  = SIZE / 2 - 2; // radius, leaving 2px margin

  let mx = 0, my = 0;
  let hover = false;

  // Track mouse position to move the canvas
  document.addEventListener('mousemove', (e) => {
    mx = e.clientX;
    my = e.clientY;
    canvas.style.left = mx + 'px';
    canvas.style.top  = my + 'px';
  });

  // Change ring colour when hovering interactive elements
  document.querySelectorAll('a, button').forEach((el) => {
    el.addEventListener('mouseenter', () => { hover = true;  canvas.classList.add('hover'); });
    el.addEventListener('mouseleave', () => { hover = false; canvas.classList.remove('hover'); });
  });

  function drawClock() {
    ctx.clearRect(0, 0, SIZE, SIZE);

    const now = new Date();
    const h  = now.getHours() % 12;
    const m  = now.getMinutes();
    const s  = now.getSeconds();
    const ms = now.getMilliseconds();

    // Dark face background
    ctx.beginPath();
    ctx.arc(CX, CY, R, 0, Math.PI * 2);
    ctx.fillStyle = 'rgba(6, 6, 6, 0.88)';
    ctx.fill();

    // Outer ring — cyan on hover, green otherwise
    ctx.beginPath();
    ctx.arc(CX, CY, R, 0, Math.PI * 2);
    ctx.strokeStyle = hover ? '#00e5ff' : '#00ff41';
    ctx.lineWidth = 1.4;
    ctx.stroke();

    // 12 tick marks (major at 12/3/6/9, minor elsewhere)
    for (let i = 0; i < 12; i++) {
      const a       = (i / 12) * Math.PI * 2 - Math.PI / 2;
      const isMajor = i % 3 === 0;
      const inner   = R - (isMajor ? 3.5 : 2);
      ctx.beginPath();
      ctx.moveTo(CX + Math.cos(a) * inner,       CY + Math.sin(a) * inner);
      ctx.lineTo(CX + Math.cos(a) * (R - 0.5),   CY + Math.sin(a) * (R - 0.5));
      ctx.strokeStyle = isMajor ? 'rgba(0,255,65,0.6)' : 'rgba(0,255,65,0.25)';
      ctx.lineWidth   = isMajor ? 1.2 : 0.8;
      ctx.stroke();
    }

    // Hour hand (short, light grey)
    const hAngle = ((h + m / 60) / 12) * Math.PI * 2 - Math.PI / 2;
    ctx.beginPath();
    ctx.moveTo(CX, CY);
    ctx.lineTo(CX + Math.cos(hAngle) * R * 0.48, CY + Math.sin(hAngle) * R * 0.48);
    ctx.strokeStyle = '#cccccc';
    ctx.lineWidth   = 1.8;
    ctx.lineCap     = 'round';
    ctx.stroke();

    // Minute hand (medium, shifts to cyan on hover)
    const mAngle = ((m + s / 60) / 60) * Math.PI * 2 - Math.PI / 2;
    ctx.beginPath();
    ctx.moveTo(CX, CY);
    ctx.lineTo(CX + Math.cos(mAngle) * R * 0.72, CY + Math.sin(mAngle) * R * 0.72);
    ctx.strokeStyle = hover ? '#00e5ff' : '#88cccc';
    ctx.lineWidth   = 1.2;
    ctx.lineCap     = 'round';
    ctx.stroke();

    // Second hand — uses ms for smooth continuous sweep (no tick jitter)
    const sAngle = ((s + ms / 1000) / 60) * Math.PI * 2 - Math.PI / 2;
    ctx.beginPath();
    ctx.moveTo(CX, CY);
    ctx.lineTo(CX + Math.cos(sAngle) * R * 0.88, CY + Math.sin(sAngle) * R * 0.88);
    ctx.strokeStyle = '#00ff41';
    ctx.lineWidth   = 0.9;
    ctx.lineCap     = 'round';
    ctx.stroke();

    // Counter-weight nub behind the pivot
    ctx.beginPath();
    ctx.moveTo(CX, CY);
    ctx.lineTo(CX - Math.cos(sAngle) * R * 0.22, CY - Math.sin(sAngle) * R * 0.22);
    ctx.strokeStyle = '#00ff41';
    ctx.lineWidth   = 0.9;
    ctx.stroke();

    // Centre pivot dot
    ctx.beginPath();
    ctx.arc(CX, CY, 1.8, 0, Math.PI * 2);
    ctx.fillStyle = '#00ff41';
    ctx.fill();

    requestAnimationFrame(drawClock);
  }

  drawClock();
})();


/* ── 11. Grin Network Live — API stat cards ───────────────────────────────────
   Fetches three endpoints from world.grin.money in parallel and populates
   six stat cards with live network data. Refreshes every 5 minutes.

   Endpoints used:
     /api/summary      → tip_height, current_hashrate, current_difficulty
     /api/price        → GRIN_USDT.last, GRIN_USDT.change_pct, GRIN_BTC.last
     /api/active_peers → mainnet.recent (array of [timestamp, count] pairs)

   Security:
     - API is CORS-enabled and read-only (no credentials sent).
     - All values written via .textContent — no HTML injection possible.
     - An in-flight guard prevents overlapping fetches on slow connections.
*/
(function initGlobalStats() {
  function el(id) { return document.getElementById(id); }

  // Format a number with optional decimal places; returns '—' for null/undefined
  function fmt(n, decimals) {
    if (n == null) return '—';
    return Number(n).toLocaleString(undefined, {
      minimumFractionDigits: decimals || 0,
      maximumFractionDigits: decimals || 0,
    });
  }

  // Show the API data timestamp in the footer of the stats section
  function setUpdated(ts) {
    const upd = el('ls-updated');
    if (!upd || !ts) return;
    const d = new Date(ts * 1000);
    upd.textContent = 'updated ' + d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  }

  let fetching = false; // in-flight guard — prevents overlapping requests

  async function fetchStats() {
    if (fetching) return;
    fetching = true;

    try {
      // All three requests fire in parallel
      const [summary, price, peers] = await Promise.all([
        fetch('https://world.grin.money/api/summary',      { cache: 'no-store' }).then(r => r.json()),
        fetch('https://world.grin.money/api/price',        { cache: 'no-store' }).then(r => r.json()),
        fetch('https://world.grin.money/api/active_peers', { cache: 'no-store' }).then(r => r.json()),
      ]);

      // Block height
      if (el('ls-height') && summary.tip_height)
        el('ls-height').textContent = fmt(summary.tip_height);

      // Hashrate in GPS (graph-per-second), 2 decimal places
      if (el('ls-hashrate') && summary.current_hashrate != null)
        el('ls-hashrate').textContent = fmt(summary.current_hashrate, 2);

      // Difficulty — compact suffix (G/M) for large numbers
      if (el('ls-diff') && summary.current_difficulty != null) {
        const d = Number(summary.current_difficulty);
        el('ls-diff').textContent =
          d >= 1e9 ? (d / 1e9).toFixed(2) + 'G' :
          d >= 1e6 ? (d / 1e6).toFixed(2) + 'M' :
          fmt(d);
      }

      // Price USD — field is .last (not .price), change is .change_pct (not _24h)
      const usd = price?.GRIN_USDT;
      if (el('ls-price-usd') && usd?.last != null) {
        el('ls-price-usd').textContent = '$' + Number(usd.last).toFixed(4);
        const chg = el('ls-price-change');
        if (chg && usd.change_pct != null) {
          const pct = Number(usd.change_pct);
          chg.textContent = (pct >= 0 ? '▲ +' : '▼ ') + pct.toFixed(2) + '% 24h';
          chg.className   = 'ls-change ' + (pct >= 0 ? 'up' : 'down');
        }
      }

      // Price BTC — convert decimal BTC to satoshis (× 10⁸)
      const btc = price?.GRIN_BTC;
      if (el('ls-price-btc') && btc?.last != null) {
        const sats = Math.round(Number(btc.last) * 1e8);
        el('ls-price-btc').textContent = sats.toLocaleString() + ' sat';
      }

      // Active mainnet peers — last entry in the recent time-series array
      if (el('ls-peers') && peers?.mainnet?.recent?.length) {
        const last = peers.mainnet.recent[peers.mainnet.recent.length - 1];
        el('ls-peers').textContent = fmt(last[1]);
      }

      // Timestamp from summary (falls back to price timestamp)
      setUpdated(summary?.updated || price?.updated);

    } catch (err) {
      console.error('[Grin] Stats fetch failed:', err.message);
      // Only mark as unavailable if still showing the initial placeholder
      ['ls-height', 'ls-hashrate', 'ls-diff', 'ls-price-usd', 'ls-price-btc', 'ls-peers']
        .forEach(id => { if (el(id) && el(id).textContent === '—') el(id).textContent = 'n/a'; });
    } finally {
      fetching = false; // release guard whether fetch succeeded or failed
    }
  }

  fetchStats();
  setInterval(fetchStats, 5 * 60 * 1000); // refresh every 5 minutes
})();
