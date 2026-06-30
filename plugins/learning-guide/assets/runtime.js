(function () {
  'use strict';
  var i18n = JSON.parse(document.getElementById('lg-i18n').textContent || '{}');
  var meta = JSON.parse(document.getElementById('lg-tour-meta').textContent || '{}');
  var tourId = meta.tourId || 'lg-default';
  var sections = meta.sections || [];

  var STORAGE_KEYS = {
    progress: 'lg.' + tourId + '.progress',
    active: 'lg.' + tourId + '.active'
  };

  function t(key, fallback) {
    return (i18n[key] != null) ? i18n[key] : (fallback || key);
  }

  // Slug for embedded-source heading ids — must match scripts/markdown.cjs slugify
  // (R9: Unicode-aware so Cyrillic etc. survive). Falls back to a Latin/Cyrillic range
  // on the rare engine without Unicode property escapes.
  var slugify = (function () {
    try {
      new RegExp('[\\p{L}\\p{N}]', 'u');
      return function (s) {
        return String(s).toLowerCase().replace(/[^\p{L}\p{N}]+/gu, '-').replace(/^-+|-+$/g, '');
      };
    } catch (e) {
      return function (s) {
        return String(s).toLowerCase()
          .replace(/[^0-9a-zß-öø-ÿĀ-ſа-яё]+/g, '-')
          .replace(/^-+|-+$/g, '');
      };
    }
  })();

  function cssEsc(s) {
    if (window.CSS && CSS.escape) return CSS.escape(String(s));
    return String(s).replace(/["\\\][]/g, '\\$&');
  }

  function loadProgress() {
    try { return JSON.parse(localStorage.getItem(STORAGE_KEYS.progress) || '{}') || {}; }
    catch (e) { return {}; }
  }
  function saveProgress(p) {
    try { localStorage.setItem(STORAGE_KEYS.progress, JSON.stringify(p)); }
    catch (e) {}
  }

  function activate(id) {
    document.querySelectorAll('.section').forEach(function (s) { s.classList.remove('active'); });
    document.querySelectorAll('aside nav a').forEach(function (a) { a.classList.remove('active'); });
    var sec = document.getElementById(id);
    if (sec) sec.classList.add('active');
    var link = document.querySelector('aside nav a[data-id="' + cssEsc(id) + '"]');
    if (link) link.classList.add('active');
    try { localStorage.setItem(STORAGE_KEYS.active, id); } catch (e) {}
    window.scrollTo(0, 0);
  }

  function updateProgressDisplay() {
    var progress = loadProgress();
    var done = 0;
    sections.forEach(function (id) { if (progress[id]) done++; });
    var bar = document.getElementById('progress-bar');
    var txt = document.getElementById('progress-text');
    if (bar) bar.style.width = (sections.length ? (done / sections.length * 100) : 0) + '%';
    if (txt) txt.textContent = done + ' / ' + sections.length;
    document.querySelectorAll('aside nav a').forEach(function (a) {
      var id = a.getAttribute('data-id');
      var dot = a.querySelector('.dot');
      if (dot) dot.classList.toggle('done', !!progress[id]);
    });
    document.querySelectorAll('.mark-read').forEach(function (b) {
      var id = b.getAttribute('data-section');
      b.setAttribute('aria-pressed', progress[id] ? 'true' : 'false');
      b.textContent = progress[id] ? t('alreadyRead', '✓ Read') : t('markRead', 'Mark as read');
    });
  }

  function bindNav() {
    document.querySelectorAll('aside nav a').forEach(function (a) {
      a.addEventListener('click', function (ev) {
        ev.preventDefault();
        var id = a.getAttribute('data-id');
        if (id) activate(id);
      });
    });
    document.querySelectorAll('.mark-read').forEach(function (b) {
      b.addEventListener('click', function () {
        var id = b.getAttribute('data-section');
        var p = loadProgress();
        p[id] = true;
        saveProgress(p);
        updateProgressDisplay();
      });
    });
    var reset = document.getElementById('reset-progress');
    if (reset) reset.addEventListener('click', function () {
      try { localStorage.removeItem(STORAGE_KEYS.progress); } catch (e) {}
      updateProgressDisplay();
    });
    // R13: pager prev/next are <button data-target> (keyboard-operable).
    document.querySelectorAll('.pager [data-target]').forEach(function (el) {
      el.addEventListener('click', function (ev) {
        var target = el.getAttribute('data-target');
        if (target) { ev.preventDefault(); activate(target); }
      });
    });
  }

  function bindFilepathButtons() {
    document.querySelectorAll('.filepath').forEach(function (b) {
      b.addEventListener('click', function () {
        var p = b.getAttribute('data-path') || '';
        copyToClipboard(p, function (ok) {
          showToast(ok ? t('copied', 'Copied') + ': ' + p : t('copyFailed', 'Copy failed'));
        });
      });
    });
  }

  function copyToClipboard(text, cb) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(function () { cb(true); }, function () { execCopy(text, cb); });
      return;
    }
    execCopy(text, cb);
  }
  function execCopy(text, cb) {
    try {
      var ta = document.createElement('textarea');
      ta.value = text; ta.style.position = 'fixed'; ta.style.opacity = '0';
      document.body.appendChild(ta); ta.select();
      var ok = document.execCommand && document.execCommand('copy');
      document.body.removeChild(ta);
      cb(!!ok);
    } catch (e) { cb(false); }
  }
  function showToast(msg) {
    var el = document.getElementById('toast');
    if (!el) return;
    el.textContent = msg;
    el.classList.add('show');
    clearTimeout(el._t);
    el._t = setTimeout(function () { el.classList.remove('show'); }, 1800);
  }

  function bindQuizzes() {
    document.querySelectorAll('.quiz').forEach(function (q) {
      var answer = parseInt(q.getAttribute('data-answer') || '-1', 10);
      var inputs = q.querySelectorAll('input[type="radio"]');
      var labels = q.querySelectorAll('.options label');
      var status = q.querySelector('.quiz-status');
      inputs.forEach(function (inp, idx) {
        inp.addEventListener('change', function () {
          q.classList.add('answered');
          labels.forEach(function (lab, j) {
            lab.classList.toggle('correct', j === answer);
            lab.classList.toggle('wrong', j === idx && idx !== answer);
          });
          // R13: announce result to assistive tech (don't rely on colour alone).
          if (status) {
            if (idx === answer) {
              status.textContent = t('correct', 'Correct');
            } else {
              var correctText = labels[answer] ? labels[answer].textContent.trim() : '';
              status.textContent = t('incorrect', 'Incorrect') + (correctText ? ': ' + correctText : '');
            }
          }
        });
      });
    });
  }

  // ---- Side panel: render embedded markdown sources on demand. ----
  var renderedCache = {};
  var lastTrigger = null;
  function panelEl() { return document.getElementById('md-viewer'); }
  function backdropEl() { return document.getElementById('md-viewer-backdrop'); }
  function openSource(name, anchor, trigger) {
    var src = document.querySelector('script[type="text/markdown"][data-name="' + cssEsc(name) + '"]');
    if (!src) return;
    var panel = panelEl();
    if (!panel) return;
    var content = panel.querySelector('.md-viewer-content');
    if (!Object.prototype.hasOwnProperty.call(renderedCache, name))
      renderedCache[name] = renderEmbeddedMarkdown(unescapeScriptTag(src.textContent || ''));
    content.innerHTML = renderedCache[name]; // always (re)set — fixes stale content when switching sources
    panel.classList.add('open');
    panel.setAttribute('aria-hidden', 'false'); // R12: reachable by assistive tech while open
    var bd = backdropEl();
    if (bd) bd.classList.add('open');
    lastTrigger = trigger || (document.activeElement && document.activeElement.focus ? document.activeElement : null);
    if (anchor) {
      var target = content.querySelector('[id="' + cssEsc(anchor) + '"]');
      if (target) {
        target.scrollIntoView({ behavior: 'smooth', block: 'start' });
        target.classList.remove('anchor-flash'); void target.offsetWidth;
        target.classList.add('anchor-flash');
      } else {
        content.scrollTop = 0;
      }
    } else {
      content.scrollTop = 0;
    }
    var closeBtn = document.getElementById('md-viewer-close');
    if (closeBtn && closeBtn.focus) closeBtn.focus(); // R12: move focus into the panel
  }
  function closeSource() {
    var panel = panelEl();
    if (!panel) return;
    panel.classList.remove('open');
    panel.setAttribute('aria-hidden', 'true');
    var bd = backdropEl();
    if (bd) bd.classList.remove('open');
    if (lastTrigger && lastTrigger.focus) { try { lastTrigger.focus(); } catch (e) {} }
    lastTrigger = null;
  }
  function bindXrefs() {
    document.body.addEventListener('click', function (ev) {
      var el = ev.target;
      while (el && el !== document.body) {
        if (el.classList && el.classList.contains('xref')) {
          ev.preventDefault();
          openSource(el.getAttribute('data-source'), el.getAttribute('data-anchor'), el);
          return;
        }
        el = el.parentNode;
      }
    });
    var close = document.getElementById('md-viewer-close');
    if (close) close.addEventListener('click', closeSource);
    var bd = backdropEl();
    if (bd) bd.addEventListener('click', closeSource);
    // R11: guard against a missing panel (tours with no embedded sources).
    document.addEventListener('keydown', function (ev) {
      var p = panelEl();
      if (ev.key === 'Escape' && p && p.classList.contains('open')) closeSource();
    });
  }

  // Reverse render.cjs escapeForScriptTag's transport-only escaping so the side panel shows
  // the original comment-open and script open/close markers (esc() then makes them safe).
  function unescapeScriptTag(s) {
    // Remove only the backslash render.cjs inserted right after '<' (case-preserving).
    // A source that literally contained '<\!--' / '<\script' (very rare) would also lose
    // that backslash — an accepted cosmetic limitation of the backslash transport.
    return String(s).replace(/<\\(\/?script|!--)/gi, '<$1');
  }

  // Tiny CommonMark-ish renderer for embedded sources.
  // Supports: headings, paragraphs, fenced code, lists, blockquotes, inline code, bold, italic, links.
  function renderEmbeddedMarkdown(src) {
    src = src.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
    var html = [];
    var lines = src.split('\n');
    var i = 0;
    var usedIds = {};
    function uniqueId(slug) {
      var id = slug || 'section';
      if (usedIds[id]) { var n = 2; while (usedIds[id + '-' + n]) n++; id = id + '-' + n; }
      usedIds[id] = true;
      return id;
    }
    while (i < lines.length) {
      var ln = lines[i];
      var hm = ln.match(/^(#{1,6})\s+(.*)$/);
      if (hm) {
        var lvl = hm[1].length;
        var text = inline(hm[2]);
        // R1/R9: heading id = bare Unicode slug (no `section-` prefix), matching cross-ref anchors.
        var id = uniqueId(slugify(hm[2] || ''));
        html.push('<h' + lvl + ' id="' + id + '">' + text + '</h' + lvl + '>');
        i++; continue;
      }
      if (/^```/.test(ln)) {
        var lang = ln.slice(3).trim();
        var code = []; i++;
        while (i < lines.length && !/^```/.test(lines[i])) { code.push(lines[i]); i++; }
        i++;
        var content = code.join('\n').replace(/[&<>]/g, function (c) { return ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]); });
        html.push('<pre><code' + (lang ? ' class="lang-' + lang.replace(/[^a-z0-9-]/gi, '') + '"' : '') + '>' + content + '</code></pre>');
        continue;
      }
      if (/^\s*$/.test(ln)) { i++; continue; }
      if (/^[*-]\s+/.test(ln)) {
        html.push('<ul>');
        while (i < lines.length && /^[*-]\s+/.test(lines[i])) {
          html.push('<li>' + inline(lines[i].replace(/^[*-]\s+/, '')) + '</li>');
          i++;
        }
        html.push('</ul>');
        continue;
      }
      if (/^>\s?/.test(ln)) {
        var bq = [];
        while (i < lines.length && /^>\s?/.test(lines[i])) {
          bq.push(lines[i].replace(/^>\s?/, ''));
          i++;
        }
        html.push('<blockquote>' + inline(bq.join(' ')) + '</blockquote>');
        continue;
      }
      var para = [ln]; i++;
      while (i < lines.length && lines[i].trim() && !/^(#{1,6}\s|```|[*-]\s|>\s)/.test(lines[i])) {
        para.push(lines[i]); i++;
      }
      html.push('<p>' + inline(para.join(' ')) + '</p>');
    }
    return html.join('\n');
  }
  // CF7: pull code spans into a placeholder (U+FFFC, built at runtime so the source stays
  // ASCII), then escape + format the whole string once — so emphasis/links may span across
  // a code span (e.g. **a `b` c**) — and finally restore the pre-escaped <code> spans.
  function inline(s) {
    var SENT = String.fromCharCode(0xFFFC);
    var codes = [];
    s = String(s).split(SENT).join(''); // drop any literal sentinel from the source (collision guard)
    s = s.replace(/`([^`]+)`/g, function (_, c) {
      codes.push('<code>' + esc(c) + '</code>');
      return SENT + (codes.length - 1) + SENT;
    });
    s = esc(s)
      .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
      .replace(/\*([^*]+)\*/g, '<em>$1</em>')
      // R3: escape attribute quotes and enforce a URL-scheme allowlist (untrusted source).
      .replace(/\[([^\]]+)\]\(([^)]+)\)/g, function (_, lab, href) {
        // Self-contained offline contract: only external schemes + in-document anchors.
        // Relative paths (/, ./, ../) would navigate the filesystem and break the bundle.
        var allowed = /^(https?:|mailto:|#)/i.test(href);
        var safe = (allowed ? href : '#').replace(/"/g, '%22').replace(/'/g, '%27');
        var external = /^(https?:|mailto:)/i.test(safe);
        return '<a href="' + safe + '"' + (external ? ' target="_blank" rel="noopener"' : '') + '>' + lab + '</a>';
      });
    return s.replace(new RegExp(SENT + '(\\d+)' + SENT, 'g'), function (m, n) {
      var j = Number(n);
      return j < codes.length ? codes[j] : m;
    });
  }
  function esc(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  function init() {
    bindNav();
    bindFilepathButtons();
    bindQuizzes();
    bindXrefs();
    var saved = null;
    try { saved = localStorage.getItem(STORAGE_KEYS.active); } catch (e) {}
    activate(saved && document.getElementById(saved) ? saved : (sections[0] || 'intro'));
    updateProgressDisplay();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
