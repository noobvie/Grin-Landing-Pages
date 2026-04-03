/* ═══════════════════════════════════════════════════════════════════════════
   Grin Landing Page — main.js
   Features: Matrix rain, typewriter, scroll reveal, nav toggle
   Zero dependencies — vanilla JS only
   ═══════════════════════════════════════════════════════════════════════════ */

'use strict';

// ── Matrix rain ───────────────────────────────────────────────────────────────
(function initMatrix() {
  const canvas = document.getElementById('matrix-canvas');
  if (!canvas) return;

  const ctx = canvas.getContext('2d');
  const CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789$><|[]{}#@!%^&*+=GRIN';
  const FONT_SIZE = 14;
  let columns, drops;

  function resize() {
    canvas.width  = window.innerWidth;
    canvas.height = window.innerHeight;
    columns = Math.floor(canvas.width / FONT_SIZE);
    drops   = Array.from({ length: columns }, () => Math.floor(Math.random() * -50));
  }

  function draw() {
    ctx.fillStyle = 'rgba(10, 10, 10, 0.05)';
    ctx.fillRect(0, 0, canvas.width, canvas.height);

    ctx.fillStyle = '#00ff41';
    ctx.font = `${FONT_SIZE}px 'JetBrains Mono', monospace`;

    for (let i = 0; i < drops.length; i++) {
      const char = CHARS[Math.floor(Math.random() * CHARS.length)];
      ctx.fillText(char, i * FONT_SIZE, drops[i] * FONT_SIZE);

      if (drops[i] * FONT_SIZE > canvas.height && Math.random() > 0.975) {
        drops[i] = 0;
      }
      drops[i]++;
    }
  }

  resize();
  window.addEventListener('resize', resize);
  setInterval(draw, 50);
})();

// ── Typewriter effect (hero terminal) ─────────────────────────────────────────
(function initTypewriter() {
  const lines = [
    { id: 'hero-line-1', text: 'name:     Grin',                    color: 'text-bright', delay: 400  },
    { id: 'hero-line-2', text: 'protocol: Mimblewimble',            color: 'cyan',        delay: 900  },
    { id: 'hero-line-3', text: 'status:   active since 2019-01-15', color: 'green',       delay: 1400 },
    { id: 'hero-line-4', text: 'icu:      no_premine | no_ico | fair', color: 'text',     delay: 1900 },
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
      }, 22);
    }, delay);
  });
})();

// ── Scroll reveal (IntersectionObserver) ──────────────────────────────────────
(function initScrollReveal() {
  const targets = document.querySelectorAll('.fade-in');
  if (!targets.length) return;

  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add('visible');
          observer.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.12, rootMargin: '0px 0px -40px 0px' }
  );

  targets.forEach((el) => observer.observe(el));
})();

// ── Stagger fade-in for grids ─────────────────────────────────────────────────
(function initStagger() {
  const grids = [
    '.feature-cards .feature-card',
    '.toolkit-grid .toolkit-card',
    '.community-grid .community-card',
    '.started-grid .started-card',
    '.process-grid .process-step',
    '.git-entries .git-entry',
  ];

  grids.forEach((selector) => {
    const items = document.querySelectorAll(selector);
    items.forEach((el, i) => {
      el.style.transitionDelay = `${i * 80}ms`;
      el.classList.add('fade-in');
    });
  });

  // Re-init observer for newly added .fade-in elements
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

// ── Nav: highlight active section on scroll ────────────────────────────────────
(function initNavHighlight() {
  const links   = document.querySelectorAll('.nav-links a');
  const sections = Array.from(links)
    .map((a) => a.getAttribute('href'))
    .filter((h) => h && h.startsWith('#'))
    .map((h) => document.querySelector(h))
    .filter(Boolean);

  function update() {
    const scrollY = window.scrollY + 80;
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
  update();
})();

// ── Nav: mobile toggle ────────────────────────────────────────────────────────
(function initNavToggle() {
  const btn   = document.getElementById('nav-toggle');
  const links = document.getElementById('nav-links');
  if (!btn || !links) return;

  btn.addEventListener('click', () => {
    links.classList.toggle('open');
    btn.textContent = links.classList.contains('open') ? '✕' : '☰';
  });

  // Close on link click
  links.querySelectorAll('a').forEach((a) => {
    a.addEventListener('click', () => {
      links.classList.remove('open');
      btn.textContent = '☰';
    });
  });
})();

// ── Nav: add shadow on scroll ─────────────────────────────────────────────────
(function initNavScroll() {
  const nav = document.getElementById('nav');
  if (!nav) return;
  window.addEventListener('scroll', () => {
    nav.style.boxShadow = window.scrollY > 20
      ? '0 2px 20px rgba(0,0,0,0.5)'
      : 'none';
  }, { passive: true });
})();

// ── Footer: live "block" counter (decorative) ─────────────────────────────────
(function initFooterBlock() {
  const el = document.getElementById('footer-block');
  if (!el) return;

  // Grin started Jan 15 2019. 60 grin/min = 1 block/min
  const genesis = new Date('2019-01-15T00:00:00Z').getTime();
  function update() {
    const elapsed = Date.now() - genesis;
    const block = Math.floor(elapsed / 60000);
    el.textContent = block.toLocaleString();
  }
  update();
  setInterval(update, 60000);
})();

// ── Glitch effect on logo hover ───────────────────────────────────────────────
(function initGlitch() {
  const logo = document.querySelector('.nav-logo');
  if (!logo) return;

  logo.addEventListener('mouseenter', () => {
    logo.style.textShadow = '2px 0 var(--cyan), -2px 0 var(--magenta)';
    setTimeout(() => {
      logo.style.textShadow = '1px 0 var(--cyan), -1px 0 var(--magenta)';
    }, 80);
    setTimeout(() => {
      logo.style.textShadow = 'none';
    }, 160);
  });
})();
