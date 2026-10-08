/* Aurora Play web controller: shared Phone Play components.
 *
 * Mirrors PhonePlayComponents.swift and ControllerKit.swift so every
 * controller built from these wears the same look as the iOS app.
 */
(function () {
  'use strict';
  var AP = window.AP;
  var h = AP.h;

  // ---- design tokens --------------------------------------------------
  var C = AP.C = {
    bg: 'var(--bg)', surface: 'var(--surface)', surface2: 'var(--surface2)',
    text2: 'var(--text2)', text3: 'var(--text3)',
    green: 'var(--green)', cyan: 'var(--cyan)', yellow: 'var(--yellow)',
    purple: 'var(--purple)', orange: 'var(--orange)', red: 'var(--red)',
    pink: 'var(--pink)', blue: 'var(--blue)', indigo: 'var(--indigo)',
    white: '#fff'
  };
  /** A colour at `a` opacity (0..1), usable with token strings and hex. */
  AP.alpha = function (color, a) {
    return 'color-mix(in srgb, ' + color + ' ' + Math.round(a * 100) + '%, transparent)';
  };
  AP.grad = function (colors, dir) {
    return 'linear-gradient(' + (dir || '135deg') + ', ' + colors.join(', ') + ')';
  };

  // ---- haptics (Android and desktop Chrome; iOS Safari has none) -------
  function vib(p) { try { if (navigator.vibrate) { navigator.vibrate(p); } } catch (e) { /* ignore */ } }
  AP.haptic = {
    tap: function () { vib(8); },
    thump: function () { vib(24); },
    rigid: function () { vib(14); },
    success: function () { vib([10, 40, 18]); },
    warning: function () { vib([20, 50, 20]); },
    error: function () { vib([30, 40, 30, 40, 30]); }
  };

  var ui = AP.ui = {};

  function click(fn, buzz) {
    return function (ev) {
      if (buzz !== false) { AP.haptic.tap(); }
      if (fn) { fn(ev); }
    };
  }

  ui.sectionLabel = function (text) {
    return h('div', { class: 'label' }, text);
  };

  ui.bigButton = function (o) {
    var on = o.enabled !== false;
    var colors = o.colors || [C.cyan, C.indigo];
    return h('button', {
      class: 'btn-big press' + (on ? '' : ' off'),
      style: { '--c1': colors[0], '--c2': colors[1] || colors[0] },
      disabled: !on,
      onclick: on ? click(o.onClick) : null
    }, o.icon ? AP.icon(o.icon, 22) : null, o.title);
  };

  ui.ghostButton = function (o) {
    return h('button', { class: 'btn-ghost press', onclick: click(o.onClick) },
      o.icon ? AP.icon(o.icon, 17) : null, o.title);
  };

  /** ControllerKit.BigButton: the primary action inside a game controller. */
  ui.ctlButton = function (o) {
    var on = o.enabled !== false;
    return h('div', { class: 'px20' },
      h('button', {
        class: 'btn-ctl press' + (on ? '' : ' off'),
        style: { '--tint': o.tint || C.cyan },
        disabled: !on,
        onclick: on ? click(o.onClick) : null
      }, o.icon ? AP.icon(o.icon, 20) : null, o.title));
  };

  ui.chip = function (o) {
    var colors = o.colors || [C.cyan, C.blue];
    return h('button', {
      class: 'chip press' + (o.selected ? ' sel' : '') + (o.subtitle ? ' has-sub' : ''),
      style: { '--c1': colors[0], '--c2': colors[1] || colors[0] },
      onclick: click(o.onClick)
    }, o.title, o.subtitle ? h('span', { class: 'sub' }, o.subtitle) : null);
  };

  ui.cap = function (o) {
    return h('button', {
      class: 'cap press' + (o.selected ? ' sel' : ''),
      style: { '--tint': o.tint || C.cyan },
      onclick: click(o.onClick)
    }, o.title);
  };

  ui.card = function (o) {
    o = o || {};
    var kids = Array.prototype.slice.call(arguments, 1);
    var el = h('div', {
      class: 'card' + (o.tint ? ' tinted' : '') + (o.cls ? ' ' + o.cls : ''),
      style: o.tint ? { '--tint': o.tint } : null
    });
    kids.forEach(function (k) { if (k !== null && k !== undefined) { el.appendChild(k.nodeType ? k : document.createTextNode(String(k))); } });
    return el;
  };

  ui.oneStopCard = function (tint) {
    var kids = Array.prototype.slice.call(arguments, 1);
    var el = h('div', { class: 'card-onestop', style: { '--tint': tint } });
    kids.forEach(function (k) { if (k) { el.appendChild(k); } });
    return el;
  };

  ui.topBar = function (o) {
    return h('div', { class: 'topbar' },
      h('div', { class: 'title' }, o.title || ''),
      h('button', { class: 'btn-pill press', onclick: click(o.onBack) },
        AP.icon('chevron.left', 15), o.backTitle || 'Back'),
      o.trailing || h('span'));
  };

  ui.timerChip = function (secondsLeft) {
    var tint = secondsLeft <= 5 ? C.red : (secondsLeft <= 10 ? C.orange : C.cyan);
    var frac = Math.min(1, secondsLeft / 30);
    var r = 21, circ = 2 * Math.PI * r;
    var svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('viewBox', '0 0 46 46');
    svg.setAttribute('width', 46);
    svg.setAttribute('height', 46);
    svg.innerHTML =
      '<circle cx="23" cy="23" r="' + r + '" fill="none" stroke="rgba(255,255,255,0.1)" stroke-width="4"/>' +
      '<circle cx="23" cy="23" r="' + r + '" fill="none" stroke="' + tint + '" stroke-width="4" stroke-linecap="round"' +
      ' stroke-dasharray="' + (circ * frac).toFixed(1) + ' ' + circ.toFixed(1) + '" transform="rotate(-90 23 23)"/>';
    return h('div', { class: 'timer-chip' }, svg, h('b', { style: { color: tint } }, String(secondsLeft)));
  };

  /** ControllerShell: header card with title / subtitle / countdown, then content. */
  ui.shell = function (o) {
    var kids = Array.prototype.slice.call(arguments, 1);
    var head = h('div', { class: 'shell-head' },
      h('div', { class: 'col gap4 grow' },
        h('div', { style: { fontSize: '20px', fontWeight: 800 } }, o.title),
        o.subtitle ? h('div', { class: 'c-text2', style: { fontSize: '13px' } }, o.subtitle) : null),
      (o.secondsLeft && o.secondsLeft > 0) ? ui.timerChip(o.secondsLeft) : null);
    var body = h('div', { class: 'shell-body' });
    kids.forEach(function (k) { if (k) { body.appendChild(k); } });
    return h('div', { class: 'shell' }, head, body);
  };

  ui.waitingState = function (icon, text, detail) {
    return h('div', { class: 'waiting-state' },
      h('div', { class: 'waiting-orb idle', style: { '--dy': '4px', '--sc': '0.03', '--dur': '1.6s' } },
        AP.icon(icon, 48)),
      h('div', { style: { fontSize: '22px', fontWeight: 800 } }, text),
      detail ? h('div', { class: 'c-text2', style: { fontSize: '15px', fontWeight: 500 } }, detail) : null);
  };

  ui.answerField = function (o) {
    return h('div', { class: 'px20' },
      h('input', {
        class: 'answer-field',
        key: o.key,
        type: 'text',
        placeholder: o.placeholder || '',
        value: o.value || '',
        autocomplete: 'off',
        autocorrect: 'off',
        autocapitalize: o.autocapitalize === false ? 'none' : 'words',
        spellcheck: 'false',
        maxlength: o.maxLength,
        oninput: function (ev) { if (o.onInput) { o.onInput(ev.target.value); } },
        onkeydown: function (ev) { if (ev.key === 'Enter' && o.onSubmit) { o.onSubmit(); } }
      }));
  };

  ui.choiceRow = function (o) {
    return h('button', {
      class: 'choice-row press' + (o.selected ? ' sel' : '') + (o.disabled ? ' dis' : ''),
      disabled: !!o.disabled,
      onclick: o.disabled ? null : click(o.onClick)
    },
      h('span', { class: 'grow' }, o.text, o.detail ? h('span', { class: 'detail' }, o.detail) : null),
      o.selected ? AP.icon('checkmark.circle.fill', 22, C.green) : null);
  };

  ui.avatar = function (name, ready) {
    return h('div', { class: 'avatar' + (ready ? ' ready' : '') }, String(name || '?').charAt(0).toUpperCase());
  };

  ui.tag = function (text, color) {
    return h('span', { class: 'tag', style: color ? { background: color } : null }, text);
  };

  ui.spinner = function () { return h('span', { class: 'spinner' }); };

  // ---- overlays ---------------------------------------------------------

  ui.toast = function (msg) {
    var app = document.getElementById('app');
    var t = h('div', { class: 'toast' }, msg);
    app.appendChild(t);
    setTimeout(function () { if (t.parentNode) { t.parentNode.removeChild(t); } }, 2200);
  };

  /** Bottom sheet confirmation, like confirmationDialog on iOS. */
  ui.confirm = function (o) {
    var app = document.getElementById('app');
    var scrim = h('div', { class: 'scrim', onclick: function (ev) { if (ev.target === scrim) { close(); } } },
      h('div', { class: 'sheet col gap12' },
        h('div', { class: 'txt-center', style: { fontSize: '15px', color: C.text2, fontWeight: 600 } }, o.title),
        h('button', {
          class: 'btn-big press', style: { '--c1': C.red, '--c2': C.red },
          onclick: function () { close(); o.onConfirm(); }
        }, o.confirmTitle || 'Confirm'),
        h('button', { class: 'btn-ghost press', onclick: close }, 'Cancel')));
    function close() { if (scrim.parentNode) { scrim.parentNode.removeChild(scrim); } }
    app.appendChild(scrim);
  };

  /** Safe getters over the untyped privateData dictionary (ControllerKit). */
  AP.pd = {
    str: function (d, k, f) { var v = d[k]; return typeof v === 'string' ? v : (f === undefined ? '' : f); },
    int: function (d, k, f) { var v = d[k]; return typeof v === 'number' ? Math.trunc(v) : (f === undefined ? 0 : f); },
    num: function (d, k, f) { var v = d[k]; return typeof v === 'number' ? v : (f === undefined ? 0 : f); },
    bool: function (d, k, f) { var v = d[k]; return typeof v === 'boolean' ? v : !!f; },
    strings: function (d, k) { var v = d[k]; return Array.isArray(v) ? v.filter(function (x) { return typeof x === 'string'; }) : []; },
    dicts: function (d, k) { var v = d[k]; return Array.isArray(v) ? v.filter(function (x) { return x && typeof x === 'object' && !Array.isArray(x); }) : []; },
    arr: function (d, k) { var v = d[k]; return Array.isArray(v) ? v : []; }
  };
  AP.ordinal = function (n) { return n === 1 ? '1st' : n === 2 ? '2nd' : n === 3 ? '3rd' : n + 'th'; };
})();
