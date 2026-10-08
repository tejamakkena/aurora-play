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

  kit.fnv = function (str) {
    var hash = 2166136261;
    for (var i = 0; i < str.length; i++) {
      hash ^= str.charCodeAt(i);
      hash = Math.imul(hash, 16777619) >>> 0;
    }
    return hash >>> 0;
  };
})();
