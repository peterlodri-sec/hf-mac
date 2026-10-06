/* ============================================================
   hf.app — interaction layer
   ternary field · spotlight · reveal · tilt · live MoE router
   vanilla, no deps, reduced-motion aware
   ============================================================ */
(() => {
  'use strict';
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));
  const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
  const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* ---------- scroll progress + navbar ---------- */
  const progress = $('#scrollProgress');
  const navbar = $('#navbar');
  const onScroll = () => {
    const h = document.documentElement;
    const max = h.scrollHeight - h.clientHeight;
    if (progress) progress.style.width = (max > 0 ? (h.scrollTop / max) * 100 : 0) + '%';
    if (navbar) navbar.classList.toggle('scrolled', h.scrollTop > 24);
  };
  addEventListener('scroll', onScroll, { passive: true });
  onScroll();

  /* ---------- cursor spotlight ---------- */
  const spotlight = $('#spotlight');
  if (spotlight && !reduced && matchMedia('(pointer:fine)').matches) {
    addEventListener('pointermove', (e) => {
      document.body.classList.add('has-pointer');
      spotlight.style.setProperty('--mx', e.clientX + 'px');
      spotlight.style.setProperty('--my', e.clientY + 'px');
    }, { passive: true });
  }

  /* ---------- reveal on scroll ---------- */
  const revealEls = $$('.reveal');
  if ('IntersectionObserver' in window && !reduced) {
    const io = new IntersectionObserver((entries) => {
      entries.forEach((entry, i) => {
        if (entry.isIntersecting) {
          entry.target.style.transitionDelay = (Math.min(i, 6) * 60) + 'ms';
          entry.target.classList.add('in');
          io.unobserve(entry.target);
        }
      });
    }, { threshold: 0.12, rootMargin: '0px 0px -8% 0px' });
    revealEls.forEach((el) => io.observe(el));
  } else {
    revealEls.forEach((el) => el.classList.add('in'));
  }

  /* ---------- animated counters ---------- */
  const runCounter = (el) => {
    const target = parseFloat(el.dataset.count || '0');
    const decimals = parseInt(el.dataset.decimals || '0', 10);
    const prefix = el.dataset.prefix || '';
    const suffix = el.dataset.suffix || '';
    if (reduced) { el.textContent = prefix + target.toFixed(decimals) + suffix; return; }
    const dur = 1400; const start = performance.now();
    const tick = (now) => {
      const p = clamp((now - start) / dur, 0, 1);
      const eased = 1 - Math.pow(1 - p, 3);
      el.textContent = prefix + (target * eased).toFixed(decimals) + suffix;
      if (p < 1) requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  };
  const counters = $$('.stat-num');
  if (counters.length) {
    if ('IntersectionObserver' in window) {
      const cio = new IntersectionObserver((entries) => {
        entries.forEach((e) => { if (e.isIntersecting) { runCounter(e.target); cio.unobserve(e.target); } });
      }, { threshold: 0.4 });
      counters.forEach((c) => cio.observe(c));
    } else counters.forEach(runCounter);
  }

  /* ---------- marquee: duplicate for a seamless loop ---------- */
  const track = $('#marqueeTrack');
  if (track) track.innerHTML += track.innerHTML;

  /* ---------- tilt cards ---------- */
  if (!reduced && matchMedia('(pointer:fine)').matches) {
    $$('.tilt').forEach((card) => {
      card.addEventListener('pointermove', (e) => {
        const r = card.getBoundingClientRect();
        const px = (e.clientX - r.left) / r.width - 0.5;
        const py = (e.clientY - r.top) / r.height - 0.5;
        card.style.transform = `translateY(-8px) perspective(900px) rotateY(${px * 7}deg) rotateX(${-py * 7}deg)`;
      });
      card.addEventListener('pointerleave', () => { card.style.transform = ''; });
    });
  }

  /* ---------- magnetic buttons ---------- */
  if (!reduced && matchMedia('(pointer:fine)').matches) {
    $$('.btn-magnetic').forEach((btn) => {
      btn.addEventListener('pointermove', (e) => {
        const r = btn.getBoundingClientRect();
        const px = (e.clientX - r.left) / r.width - 0.5;
        const py = (e.clientY - r.top) / r.height - 0.5;
        btn.style.transform = `translate(${px * 10}px, ${py * 8 - 2}px)`;
      });
      btn.addEventListener('pointerleave', () => { btn.style.transform = ''; });
    });
  }

  /* ---------- pipeline ---------- */
  const flowDetail = $('#flowDetail');
  const flowDefault = flowDetail ? flowDetail.textContent : '';
  const flow = $('#flow');
  $$('.flow-node').forEach((node) => {
    const show = () => {
      $$('.flow-node').forEach((n) => n.classList.remove('active'));
      node.classList.add('active');
      if (flowDetail) {
        flowDetail.textContent = node.dataset.detail || '';
        flowDetail.classList.remove('flash');
        void flowDetail.offsetWidth;
        flowDetail.classList.add('flash');
      }
    };
    node.addEventListener('pointerenter', show);
    node.addEventListener('focus', show);
    node.addEventListener('click', show);
  });
  if (flow && flowDetail) flow.addEventListener('pointerleave', () => {
    $$('.flow-node').forEach((n) => n.classList.remove('active'));
    flowDetail.textContent = flowDefault;
  });

  /* ---------- live MoE router (mirrors MoEOptimizer.swift) ---------- */
  const DOMAINS = {
    code: { ico: '⚡', name: 'Code Expert', model: 'coder / qwen-coder', frame: 'software engineering — precise, compilable, idiomatic' },
    math: { ico: '📐', name: 'Reasoning & Math Expert', model: 'reasoning / deepseek-r1', frame: 'step-by-step logic — show the work, no hand-waving' },
    summary: { ico: '📝', name: 'Summarization Expert', model: 'summarizer / any chat model', frame: 'actionable bullet extraction — terse, structured' },
    creative: { ico: '🎨', name: 'Creative Writing Expert', model: 'creative / qwen-instruct', frame: 'expansive, evocative drafting — voice over brevity' },
    general: { ico: '🧠', name: 'General Expert', model: 'any active Osaurus model', frame: 'concise, high-throughput general assistant' },
  };
  const KEYWORDS = {
    code: ['code', 'function', 'refactor', 'bug', 'error', 'rust', 'swift', 'python', 'javascript', 'compile', 'api', 'regex', 'sql', 'docker', 'git', 'typescript', 'class', 'lifetime', 'borrow', 'async'],
    math: ['solve', 'equation', 'math', 'calculate', 'proof', 'derive', 'integral', 'probability', 'theorem', 'step by step', 'x =', 'sum', 'matrix', 'algorithm', 'reason', 'logic'],
    summary: ['summarize', 'summarise', 'tl;dr', 'shorten', 'condense', 'bullet', 'key points', 'changelog', 'abstract', 'recap', 'digest', 'extract'],
    creative: ['write', 'novel', 'poem', 'story', 'creative', 'character', 'lyrics', 'screenplay', 'narrative', 'opening paragraph', 'metaphor', 'describe'],
  };
  const classify = (text) => {
    const t = (text || '').toLowerCase();
    const scores = { code: 0, math: 0, summary: 0, creative: 0 };
    for (const [domain, words] of Object.entries(KEYWORDS)) {
      for (const w of words) if (t.includes(w)) scores[domain] += w.includes(' ') ? 2 : 1;
    }
    let best = 'general'; let bestScore = 0;
    for (const [d, s] of Object.entries(scores)) if (s > bestScore) { bestScore = s; best = d; }
    const total = Object.values(scores).reduce((a, b) => a + b, 0) || 1;
    const conf = bestScore === 0 ? 0.42 : clamp(0.55 + (bestScore / total) * 0.44, 0.55, 0.98);
    return { domain: best, conf };
  };

  const moeInput = $('#moeInput');
  const renderRoute = () => {
    if (!moeInput) return;
    const { domain, conf } = classify(moeInput.value);
    const d = DOMAINS[domain];
    const set = (id, val) => { const el = $(id); if (el) el.textContent = val; };
    set('#domainIco', d.ico);
    set('#domainName', d.name);
    set('#recModel', d.model);
    set('#sysFrame', d.frame);
    const confEl = $('#domainConf');
    if (confEl) confEl.textContent = Math.round(conf * 100) + '% match';
    const meter = $('#meterFill');
    if (meter) meter.style.width = Math.round(conf * 100) + '%';
  };
  if (moeInput) {
    let t = null;
    moeInput.addEventListener('input', () => { clearTimeout(t); t = setTimeout(renderRoute, 140); });
    $$('#moeExamples button').forEach((b) => b.addEventListener('click', () => {
      moeInput.value = b.dataset.example || b.textContent;
      renderRoute();
      moeInput.focus();
    }));
    renderRoute();
  }

  /* ---------- tabs ---------- */
  const tabButtons = $$('.tab-btn');
  const tabContents = $$('.tab-content');
  tabButtons.forEach((button) => {
    button.addEventListener('click', () => {
      const target = button.getAttribute('data-tab');
      tabButtons.forEach((b) => b.classList.remove('active'));
      tabContents.forEach((c) => c.classList.remove('active'));
      button.classList.add('active');
      const el = document.getElementById('tab-' + target);
      if (el) el.classList.add('active');
    });
  });

  /* ---------- copy code ---------- */
  $$('.copy-btn').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const codeBlock = btn.closest('.code-block');
      const code = codeBlock && codeBlock.querySelector('code');
      if (!code) return;
      try {
        await navigator.clipboard.writeText(code.innerText);
        const original = btn.innerText;
        btn.innerText = 'Copied!';
        btn.style.background = 'var(--hf-yellow)';
        btn.style.color = '#000';
        setTimeout(() => { btn.innerText = original; btn.style.background = ''; btn.style.color = ''; }, 1800);
      } catch (err) { /* clipboard unavailable */ }
    });
  });

  /* ---------- smooth scroll (offset for the fixed nav) ---------- */
  $$('a[href^="#"]').forEach((a) => {
    a.addEventListener('click', (e) => {
      const id = a.getAttribute('href');
      if (!id || id === '#') return;
      const el = document.querySelector(id);
      if (!el) return;
      e.preventDefault();
      const y = el.getBoundingClientRect().top + window.scrollY - 84;
      window.scrollTo({ top: y, behavior: reduced ? 'auto' : 'smooth' });
    });
  });

  /* ---------- ternary field (hero canvas) ---------- */
  const canvas = $('#ternaryField');
  if (canvas && !reduced) {
    const ctx = canvas.getContext('2d');
    let W = 0, H = 0, dpr = 1, spacing = 44, cols = 0, rows = 0, t = 0, raf = 0;
    let pointer = { x: -9999, y: -9999, active: false };

    const resize = () => {
      const r = canvas.getBoundingClientRect();
      dpr = Math.min(window.devicePixelRatio || 1, 2);
      W = r.width; H = r.height;
      canvas.width = W * dpr; canvas.height = H * dpr;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      spacing = W < 700 ? 34 : 44;
      cols = Math.ceil(W / spacing) + 1;
      rows = Math.ceil(H / spacing) + 1;
    };

    const draw = () => {
      t += 0.006;
      ctx.clearRect(0, 0, W, H);
      for (let gy = 0; gy < rows; gy++) {
        for (let gx = 0; gx < cols; gx++) {
          const x = gx * spacing;
          const y = gy * spacing;
          const nx = x / spacing, ny = y / spacing;
          // two crossing wave systems (mind + anchor), plus a living source
          let v = Math.sin(nx * 0.5 + t * 2) + Math.sin(ny * 0.6 - t * 1.4) + Math.sin((nx + ny) * 0.35 + t);
          if (pointer.active) {
            const d = Math.hypot(x - pointer.x, y - pointer.y);
            v += Math.sin(d * 0.045 - t * 6) * (1.6 * Math.exp(-d / 260));
          }
          const state = v > 0.55 ? 1 : v < -0.55 ? -1 : 0;
          let color, alpha, r;
          if (state === 1) { color = '34,211,238'; alpha = 0.62; r = 1.9; }
          else if (state === -1) { color = '167,139,250'; alpha = 0.55; r = 1.7; }
          else { color = '100,116,139'; alpha = 0.3; r = 1.1; }
          if (pointer.active) {
            const d = Math.hypot(x - pointer.x, y - pointer.y);
            alpha += Math.exp(-d / 200) * 0.5;
          }
          ctx.fillStyle = `rgba(${color},${alpha.toFixed(3)})`;
          ctx.beginPath();
          ctx.arc(x, y, r, 0, Math.PI * 2);
          ctx.fill();
        }
      }
      raf = requestAnimationFrame(draw);
    };

    const start = () => { if (!raf) raf = requestAnimationFrame(draw); };
    const stop = () => { if (raf) { cancelAnimationFrame(raf); raf = 0; } };

    const hero = $('.hero');
    hero.addEventListener('pointermove', (e) => {
      const r = canvas.getBoundingClientRect();
      pointer = { x: e.clientX - r.left, y: e.clientY - r.top, active: true };
    }, { passive: true });
    hero.addEventListener('pointerleave', () => { pointer.active = false; });

    addEventListener('resize', resize, { passive: true });
    resize();
    if ('IntersectionObserver' in window) {
      new IntersectionObserver((entries) => {
        entries.forEach((en) => (en.isIntersecting ? start() : stop()));
      }, { threshold: 0.02 }).observe(hero);
    } else start();
  }
})();
