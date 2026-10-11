/* Aurora Play web controller: pieces shared by several game controllers. */
(function () {
  'use strict';
  var AP = window.AP;
  var h = AP.h, C = AP.C;
  var kit = AP.kit = {};

  /** The backdrop most controllers sit on: Phone Play bg, optional top glow. */
  kit.page = function (glow, glowOpacity) {
    var kids = Array.prototype.slice.call(arguments, 2);
    var style = {};
    if (glow) {
      style.background = 'radial-gradient(circle 420px at 50% 0%, ' + AP.alpha(glow, glowOpacity || 0.28) + ', transparent), var(--bg)';
    }
    return h('div', { class: 'shell', style: style }, kids);
  };

  /** A tinted circle with an icon, e.g. QuizPadMessage's disc. */
  kit.disc = function (icon, size, tint, o) {
    o = o || {};
    return h('div', {
      class: o.cls || '',
      style: {
        width: size + 'px', height: size + 'px', borderRadius: '50%',
        background: o.solid ? tint : AP.alpha(tint, 0.85),
        boxShadow: '0 0 ' + (o.glow || 18) + 'px ' + AP.alpha(tint, 0.6),
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        color: o.color || '#fff', flex: '0 0 auto'
      }
    }, AP.icon(icon, o.iconSize || Math.round(size * 0.49)));
  };

  /** Big centred icon + title + detail (QuizPadMessage and its cousins). */
  kit.message = function (o) {
    var tint = o.tint || '#FACC15';
    return h('div', { class: 'col center gap16 txt-center pop-in', key: o.key,
        style: { padding: '28px', flex: '1 1 auto', justifyContent: 'center' } },
      h('div', { class: 'idle', style: { '--dy': '4px', '--sc': '0.03', '--dur': '1.6s' } },
        kit.disc(o.icon, 110, tint, { iconSize: 54 })),
      h('div', { style: { fontSize: '30px', fontWeight: 900 } }, o.title),
      o.detail ? h('div', { class: 'c-text2', style: { fontSize: '17px', fontWeight: 600 } }, o.detail) : null);
  };

  /** A small fixed-colour pill / capsule. */
  kit.capsule = function (text, bg, fg, o) {
    return h('span', { style: Object.assign({ display: 'inline-block', padding: '5px 12px', borderRadius: '999px',
      background: bg, color: fg, fontSize: '13px', fontWeight: 800, letterSpacing: '2px' }, o || {}) }, text);
  };

  /** Raised tile button: coloured face with a darker lip underneath. */
  kit.tile = function (o) {
    return h('button', {
      class: 'press ' + (o.cls || ''), key: o.key, disabled: !!o.disabled,
      style: Object.assign({
        appearance: 'none', border: 0, width: '100%', display: 'flex', alignItems: 'center', gap: o.gap || '14px',
        padding: o.padding || '0 16px', minHeight: (o.minHeight || 78) + 'px', textAlign: 'left', color: '#fff',
        borderRadius: o.radius || 'var(--r-button)',
        background: 'linear-gradient(180deg, ' + o.color + ', ' + AP.alpha(o.color, 0.82) + ')',
        boxShadow: '0 ' + (o.lip === undefined ? 5 : o.lip) + 'px 0 ' + AP.alpha(o.color, 0.5)
      }, o.style || {}),
      onclick: o.disabled ? null : o.onClick
    }, o.children);
  };

  /** Sleep-free number tween: calls step(value) a few times then stops. */
  kit.countUp = function (ctx, state, key, target, step) {
    if (state.key === key) { return state.value; }
    state.key = key; state.value = 0;
    var n = 0, steps = 20;
    var id = ctx.every(35, function () {
      n++;
      state.value = Math.round(target * n / steps);
      if (n >= steps) { ctx.clear(id); }
      ctx.refresh();
    });
    return 0;
  };

  /** midPadCard: surface card edged in an accent. */
  kit.card = function (accent, o) {
    o = o || {};
    var kids = Array.prototype.slice.call(arguments, 2);
    return h('div', {
      class: o.cls || '', key: o.key,
      style: Object.assign({ background: C.surface, borderRadius: o.radius || 'var(--r-card)',
        border: '1px solid ' + (accent ? AP.alpha(accent, 0.4) : 'rgba(255,255,255,0.06)') }, o.style || {})
    }, kids);
  };

  kit.label = function (text, color) {
    return h('div', { style: { fontSize: '12px', fontWeight: 800, letterSpacing: '2px', color: color || C.text3 } }, String(text).toUpperCase());
  };

  /** MidPadPill: a short status line in a tinted capsule. */
  kit.pill = function (text, icon, tint) {
    tint = tint || C.cyan;
    return h('div', { class: 'row gap6', style: { padding: '8px 14px', borderRadius: '999px', background: AP.alpha(tint, 0.14),
        color: tint, fontSize: '14px', fontWeight: 700, textAlign: 'center', justifyContent: 'center' } },
      icon ? AP.icon(icon, 13) : null, text);
  };

  /** A range slider in Phone Play colours. */
  kit.slider = function (o) {
    return h('input', { type: 'range', class: 'slider', key: o.key, min: o.min, max: o.max, step: o.step || 1,
      value: String(o.value), style: { '--fill': ((o.value - o.min) / Math.max(o.max - o.min, 1) * 100) + '%',
        '--tint': o.tint || C.cyan },
      oninput: function (ev) { o.onInput(parseFloat(ev.target.value)); } });
  };

  /** The round +/- buttons used by the steppers. */
  kit.stepButton = function (icon, enabled, tint, onClick) {
    return h('button', { class: 'press', disabled: !enabled,
      style: { appearance: 'none', border: 0, width: '44px', height: '44px', borderRadius: '50%', display: 'inline-flex',
        alignItems: 'center', justifyContent: 'center', color: enabled ? '#fff' : 'rgba(255,255,255,0.25)',
        background: enabled ? AP.alpha(tint, 0.35) : 'rgba(255,255,255,0.06)' },
      onclick: enabled ? function () { AP.haptic.tap(); onClick(); } : null }, AP.icon(icon, 17));
  };

  kit.fnv = function (str) {
    var hash = 2166136261;
    for (var i = 0; i < str.length; i++) {
      hash ^= str.charCodeAt(i);
      hash = Math.imul(hash, 16777619) >>> 0;
    }
    return hash >>> 0;
  };

  // ---- layout idioms shared by the game files --------------------------
  var ui = AP.ui, pd = AP.pd;
  function promptCard(text, label, accent, textColor) {
    return h('div', { class: 'px20', style: { paddingTop: '14px' } },
      h('div', { class: 'col center gap8 txt-center', style: { padding: '20px', borderRadius: 'var(--r-card)',
          background: C.surface, border: '1px solid ' + AP.alpha(accent || C.cyan, 0.35) } },
        label ? h('div', { style: { fontSize: '12px', fontWeight: 800, letterSpacing: '2px', color: accent || C.cyan } }, label.toUpperCase()) : null,
        h('div', { style: { fontSize: '22px', fontWeight: 800, color: textColor || '#fff', lineHeight: 1.2 } }, text)));
  }

  /** Vertically centred form area (the Spacer / content / Spacer idiom). */
  function centered(key) {
    var kids = Array.prototype.slice.call(arguments, 1);
    return h('div', { class: 'col gap14 pop-in', key: key, style: { flex: '1 1 auto', justifyContent: 'center', minHeight: 0 } }, kids);
  }

  function waiting(key, icon, text, detail) {
    var el = ui.waitingState(icon, text, detail);
    el._key = key;
    el.className += ' pop-in';
    return el;
  }


  AP.promptCard = promptCard;
  AP.centered = centered;
  AP.waiting = waiting;

  /** BrainShapeView: a polyomino drawn as rounded cubes with a faint extrusion. */
  kit.shapeSvg = function (cells, color, depth, extraStyle) {
    var NS = 'http://www.w3.org/2000/svg';
    var svg = document.createElementNS(NS, 'svg');
    svg.setAttribute('preserveAspectRatio', 'xMidYMid meet');
    svg.setAttribute('class', 'brain-shape');
    if (extraStyle) { svg.setAttribute('style', extraStyle); }
    if (!cells.length) { return svg; }
    depth = depth === undefined ? 3 : depth;
    var xs = cells.map(function (c) { return c[0]; }), ys = cells.map(function (c) { return c[1]; });
    var minX = Math.min.apply(null, xs), minY = Math.min.apply(null, ys);
    var cols = Math.max.apply(null, xs) - minX + 1, rows = Math.max.apply(null, ys) - minY + 1;
    var extra = 0.07 * depth + 0.1;
    var W = cols + extra, H = rows + extra;
    var gap = 0.08, ox = 0.05, oy = 0.05, r = 0.22, step = 0.07;
    svg.setAttribute('viewBox', '0 0 ' + W.toFixed(3) + ' ' + H.toFixed(3));
    var gid = 'bg' + color.replace(/[^a-z0-9]/gi, '');
    var out = '<defs><linearGradient id="' + gid + '" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="' + color +
      '"/><stop offset="1" stop-color="' + color + '" stop-opacity="0.72"/></linearGradient></defs>';
    function rect(cx, cy, off) {
      var x = ox + (cx - minX) + gap / 2 + off, y = oy + (cy - minY) + gap / 2 + off, w = 1 - gap;
      return { x: x, y: y, w: w };
    }
    for (var layer = depth; layer >= 1; layer--) {
      cells.forEach(function (c) {
        var q = rect(c[0], c[1], step * layer);
        out += '<rect x="' + q.x.toFixed(3) + '" y="' + q.y.toFixed(3) + '" width="' + q.w.toFixed(3) + '" height="' + q.w.toFixed(3) +
          '" rx="' + r + '" fill="rgba(0,0,0,0.55)"/><rect x="' + q.x.toFixed(3) + '" y="' + q.y.toFixed(3) + '" width="' + q.w.toFixed(3) +
          '" height="' + q.w.toFixed(3) + '" rx="' + r + '" fill="' + color + '" fill-opacity="0.35"/>';
      });
    }
    cells.forEach(function (c) {
      var q = rect(c[0], c[1], 0);
      out += '<rect x="' + q.x.toFixed(3) + '" y="' + q.y.toFixed(3) + '" width="' + q.w.toFixed(3) + '" height="' + q.w.toFixed(3) +
        '" rx="' + r + '" fill="url(#' + gid + ')" stroke="rgba(255,255,255,0.45)" stroke-width="0.04"/>' +
        '<rect x="' + (q.x + q.w * 0.1).toFixed(3) + '" y="' + (q.y + q.w * 0.1).toFixed(3) + '" width="' + (q.w * 0.64).toFixed(3) + '" height="' + (q.w * 0.64).toFixed(3) +
        '" rx="' + (r * 0.6).toFixed(3) + '" fill="rgba(255,255,255,0.16)"/>';
    });
    svg.innerHTML = out;
    return svg;
  };

  // ---- ClassicShell family (Four in a Row, Roulette, Mafia, Raja Mantri...) -----

  /** Header card with a trailing slot and an optional top glow. */
  kit.classicShell = function (o) {
    var kids = Array.prototype.slice.call(arguments, 1);
    var glow = o.glow || 'transparent';
    var head = h('div', { class: 'shell-head' },
      h('div', { class: 'col gap4 grow', style: { minWidth: 0 } },
        h('div', { style: { fontSize: '20px', fontWeight: 800, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' } }, o.title),
        o.subtitle ? h('div', { class: 'c-text2', style: { fontSize: '13px', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' } }, o.subtitle) : null),
      o.trailing || null);
    return h('div', { class: 'shell', style: { background: 'linear-gradient(to bottom, ' + AP.alpha(glow, 0.16) + ', transparent 50%), var(--bg)' } },
      head, h('div', { class: 'shell-body' }, kids));
  };

  /** ClassicPill: rounded status capsule. */
  kit.classicPill = function (text, icon, tint) {
    tint = tint || C.text2;
    return h('div', { class: 'row gap8', style: { padding: '10px 16px', borderRadius: '999px', background: AP.alpha(tint, 0.14), color: tint,
        fontSize: '15px', fontWeight: 700, textAlign: 'center', justifyContent: 'center' } },
      icon ? AP.icon(icon, 14) : null, text);
  };

  /** Number-over-label badge for a header's trailing slot. */
  kit.statBadge = function (value, label, tint) {
    tint = tint || C.cyan;
    return h('div', { class: 'col center', style: { padding: '6px 12px', borderRadius: 'var(--r-chip)', background: AP.alpha(tint, 0.12) } },
      h('div', { class: 'num', style: { fontSize: '20px', fontWeight: 800, color: tint } }, String(value)),
      h('div', { style: { fontSize: '10px', fontWeight: 800, letterSpacing: '1px', color: C.text3 } }, label));
  };

  /** The big gently-bobbing icon disc used for "sleeping", "eliminated", "won". */
  kit.hero = function (icon, tint, size) {
    size = size || 110;
    return h('div', { class: 'idle', style: { '--dy': '4px', '--sc': '0.03', '--dur': '1.6s', display: 'inline-flex' } },
      h('div', { style: { width: size + 'px', height: size + 'px', borderRadius: '50%', display: 'flex', alignItems: 'center', justifyContent: 'center',
          background: AP.grad([AP.alpha(tint, 0.6), AP.alpha(tint, 0.25)]), boxShadow: '0 8px 18px ' + AP.alpha(tint, 0.35) } },
        AP.icon(icon, Math.round(size * 0.44))));
  };

  /** A full-width pick-one row (vote, target, accuse) with a tint per role. */
  kit.pickRow = function (o) {
    return h('button', { class: 'press', key: o.key,
      style: { appearance: 'none', width: '100%', display: 'flex', alignItems: 'center', gap: '12px', padding: '16px 18px', textAlign: 'left',
        borderRadius: 'var(--r-button)', color: '#fff', background: o.selected ? AP.alpha(o.tint, 0.2) : C.surface,
        border: (o.selected ? 2 : 1) + 'px solid ' + (o.selected ? o.tint : 'rgba(255,255,255,0.06)') },
      onclick: function () { AP.haptic.tap(); o.onClick(); } },
      h('span', { class: 'grow', style: { fontSize: '17px', fontWeight: 700, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' } }, o.text),
      o.selected
        ? h('span', { class: 'row gap6', style: { fontSize: '14px', fontWeight: 800, color: o.tint } }, AP.icon('checkmark.circle.fill', 18), o.badge || null)
        : (o.icon ? h('span', { style: { color: AP.alpha(o.tint, 0.85), display: 'inline-flex' } }, AP.icon(o.icon, 16)) : null));
  };

  /** Scrolls when taller than the screen, centres vertically when it is not. */
  kit.centeredScroll = function () {
    var kids = Array.prototype.slice.call(arguments);
    return h('div', { class: 'scroll' }, h('div', { class: 'col', style: { minHeight: '100%', justifyContent: 'center' } }, kids));
  };
})();
