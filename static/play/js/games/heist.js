/* Heist controller: a different screen for the Guard and for each Thief.
 * Port of HeistControllerView.swift.
 */
(function () {
  'use strict';
  var AP = window.AP;
  var h = AP.h, C = AP.C, ui = AP.ui, kit = AP.kit, pd = AP.pd;

  var ARROWS = { dr: '↘', dl: '↙', ur: '↗', ul: '↖' };
  var DEFAULT_SLOTS = [
    { id: 'cam_tl', label: 'Top Left', direction: ARROWS.dr }, { id: 'cam_tr', label: 'Top Right', direction: ARROWS.dl },
    { id: 'cam_bl', label: 'Bottom Left', direction: ARROWS.ur }, { id: 'cam_br', label: 'Bottom Right', direction: ARROWS.ul }
  ];

  function header(icon, title, detail, tint, round) {
    return h('div', { class: 'shell-head', style: { gap: '14px' } },
      h('div', { class: 'idle', style: { '--dy': '2px', '--sc': '0.03', '--dur': '1.6s', width: '48px', height: '48px', borderRadius: '50%', flex: '0 0 auto',
          display: 'flex', alignItems: 'center', justifyContent: 'center', background: AP.grad([AP.alpha(tint, 0.75), AP.alpha(tint, 0.3)]) } }, AP.icon(icon, 21)),
      h('div', { class: 'col gap4 grow', style: { minWidth: 0 } },
        h('div', { style: { fontSize: '20px', fontWeight: 800 } }, title),
        h('div', { class: 'c-text2', style: { fontSize: '13px' } }, detail)),
      h('span', { style: { padding: '6px 10px', borderRadius: '999px', background: AP.alpha(tint, 0.15), color: tint, fontSize: '13px', fontWeight: 800, whiteSpace: 'nowrap' } },
        'Round ' + round));
  }
  function page(tint, head, kids) {
    return h('div', { class: 'shell', style: { background: 'linear-gradient(to bottom, ' + AP.alpha(tint, 0.14) + ', transparent 50%), var(--bg)' } },
      head, h('div', { class: 'col', style: { flex: '1 1 auto', minHeight: 0, justifyContent: 'center', overflowY: 'auto' } }, kids));
  }
  function pill(text, icon, tint) { return h('div', { class: 'px20 center', style: { display: 'flex' } }, kit.classicPill(text, icon, tint)); }

  function guard(ctx) {
    var active = [], submitted = false, tracked = 0;
    return function (d) {
      var phase = pd.str(d, 'phase', 'guard_sets'), round = pd.int(d, 'round');
      if (round !== tracked) { tracked = round; submitted = false; active = []; }
      var slots = pd.dicts(d, 'cameraSlots').filter(function (s) { return typeof s.id === 'string' && typeof s.label === 'string' && typeof s.direction === 'string'; });
      if (!pd.arr(d, 'cameraSlots').length) { slots = DEFAULT_SLOTS; }
      function toggle(id) {
        var i = active.indexOf(id);
        if (i >= 0) { active.splice(i, 1); } else if (active.length < 2) { active.push(id); }
        ctx.refresh();
      }
      var content;
      if (phase === 'guard_sets') {
        content = h('div', { class: 'col gap20', key: 'set', style: { padding: '8px 0' } },
          h('div', { class: 'col center gap4 txt-center px20' },
            h('div', { style: { fontSize: '22px', fontWeight: 800 } }, 'Choose cameras to activate'),
            h('div', { class: 'c-text3', style: { fontSize: '14px' } }, 'Max 2 cameras per round · ' + active.length + '/2')),
          h('div', { class: 'px20', style: { display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '14px' } }, slots.map(function (s) {
            var on = active.indexOf(s.id) >= 0, can = active.length < 2 || on;
            return h('button', { class: 'press', key: 'cam' + s.id, disabled: !can && !on,
              style: { appearance: 'none', padding: '20px 0', borderRadius: 'var(--r-button)', color: '#fff', opacity: can ? 1 : 0.4,
                background: on ? AP.grad([AP.alpha(C.red, 0.38), AP.alpha(C.red, 0.14)]) : C.surface,
                border: (on ? 2 : 1) + 'px solid ' + (on ? AP.alpha(C.red, 0.7) : 'rgba(255,255,255,0.06)'),
                boxShadow: on ? '0 5px 12px ' + AP.alpha(C.red, 0.3) : 'none', transform: on ? 'scale(1.04)' : 'none', transition: 'transform .38s var(--pop)',
                display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '10px' },
              onclick: function () { AP.haptic.tap(); toggle(s.id); } },
              h('span', { style: { fontSize: '36px', fontWeight: 700, color: on ? '#fff' : 'rgba(255,255,255,0.6)', lineHeight: 1 } }, s.direction),
              h('span', { style: { fontSize: '14px', fontWeight: 700, color: on ? '#fff' : C.text2, textAlign: 'center' } }, s.label),
              h('span', { style: { padding: '4px 10px', borderRadius: '999px', fontSize: '11px', fontWeight: 800, letterSpacing: '1px',
                  color: on ? '#fff' : C.text3, background: on ? C.red : 'rgba(255,255,255,0.05)' } }, on ? 'ACTIVE' : 'OFF'));
          })),
          submitted
            ? h('div', { class: 'ready-banner', key: 'locked', style: { margin: '0 20px' } }, AP.icon('checkmark.shield.fill', 20), 'Cameras Locked')
            : ui.ctlButton({ title: 'Lock Cameras', icon: 'shield.fill', tint: C.red,
                onClick: function () { if (submitted) { return; } submitted = true; ctx.send('set_cameras', { cameras: active.slice() }); ctx.refresh(); } }));
      } else {
        var on = slots.filter(function (s) { return active.indexOf(s.id) >= 0; });
        content = h('div', { class: 'col center gap16 pop-in', key: 'watch', style: { padding: '8px 0' } },
          kit.hero('video.fill', C.red),
          h('div', { style: { fontSize: '26px', fontWeight: 800, color: C.red } }, 'Cameras Active'),
          h('div', { class: 'c-text2', style: { fontSize: '15px' } }, 'Watching for thieves...'),
          h('div', { class: 'col gap10 w100', style: { paddingTop: '4px' } },
            on.length ? null : h('div', { class: 'c-text3 txt-center', style: { fontSize: '14px' } }, 'No cameras switched on this round'),
            on.map(function (s) {
              return h('div', { class: 'row gap12', key: 'on' + s.id, style: { margin: '0 20px', padding: '16px', borderRadius: 'var(--r-button)',
                  background: AP.alpha(C.red, 0.14), border: '1px solid ' + AP.alpha(C.red, 0.35) } },
                h('span', { style: { fontSize: '24px', fontWeight: 700 } }, s.direction),
                h('span', { class: 'grow', style: { fontSize: '17px', fontWeight: 700 } }, s.label),
                h('span', { class: 'row gap6', style: { fontSize: '12px', fontWeight: 800, color: C.red } },
                  h('span', { style: { width: '8px', height: '8px', borderRadius: '50%', background: C.red } }), 'ACTIVE'));
            })));
      }
      return page(C.red, header('shield.fill', 'You are the Guard', 'Only YOU can see camera positions', C.red, round), content);
    };
  }

  function thief(ctx) {
    var moved = false, tracked = 0;
    return function (d) {
      var phase = pd.str(d, 'phase', 'guard_sets'), round = pd.int(d, 'round');
      if (round !== tracked) { tracked = round; moved = false; }
      var col = typeof d.col === 'number' ? d.col : 1, row = typeof d.row === 'number' ? d.row : 1;
      var moving = phase === 'thieves_move';
      var vault = pd.bool(d, 'hasReachedVault'), caught = pd.bool(d, 'isCaught');
      function move(dir) { if (!moving || moved || caught) { return; } moved = true; ctx.send('move', { direction: dir }); ctx.refresh(); }
      function dirBtn(icon, label, dir) {
        return h('button', { class: 'press', key: 'dir' + dir,
          style: { appearance: 'none', width: '84px', height: '84px', borderRadius: '50%', color: '#fff', background: AP.grad([C.surface2, C.surface]),
            border: '1.5px solid ' + AP.alpha(C.cyan, 0.35), boxShadow: '0 4px 10px ' + AP.alpha(C.cyan, 0.12),
            display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: '4px' },
          onclick: function () { AP.haptic.tap(); move(dir); } },
          AP.icon(icon, 26), h('span', { style: { fontSize: '11px', fontWeight: 800, color: C.text2 } }, label));
      }
      var content;
      if (caught) {
        content = h('div', { class: 'col center gap16 pop-in', key: 'caught' }, kit.hero('exclamationmark.triangle.fill', C.red),
          h('div', { style: { fontSize: '26px', fontWeight: 800, color: C.red } }, 'You were caught!'),
          h('div', { class: 'c-text2', style: { fontSize: '15px', fontWeight: 500 } }, 'Watch the TV to see how it ends.'));
      } else {
        content = h('div', { class: 'col gap20', key: 'play' },
          h('div', { class: 'px20' }, h('div', { class: 'col gap10', style: { padding: '16px', borderRadius: 'var(--r-card)', background: C.surface } },
            h('div', { class: 'row gap10' }, h('span', { style: { color: C.cyan, display: 'inline-flex' } }, AP.icon('location.fill', 14)),
              h('span', { class: 'grow c-text2', style: { fontSize: '15px', fontWeight: 700 } }, 'Position'),
              h('span', { class: 'mono', style: { fontSize: '17px', fontWeight: 800, color: C.cyan } }, 'Col ' + col + '  Row ' + row)),
            vault ? h('div', { class: 'row gap6 pop-in', style: { alignSelf: 'center', padding: '7px 14px', borderRadius: '999px', background: C.yellow, color: '#000',
                fontSize: '13px', fontWeight: 800, letterSpacing: '1px' } }, AP.icon('star.fill', 13), 'VAULT REACHED') : null)),
          h('div', { class: 'col center gap14', style: { opacity: (moving && !moved) ? 1 : 0.3, pointerEvents: (moving && !moved) ? 'auto' : 'none', transition: 'opacity .2s' } },
            dirBtn('arrow.up', 'Up', 'up'),
            h('div', { class: 'row', style: { gap: '48px' } }, dirBtn('arrow.left', 'Left', 'left'), dirBtn('arrow.right', 'Right', 'right')),
            dirBtn('arrow.down', 'Down', 'down')),
          moved ? pill('Move sent — waiting for round end', 'hourglass', C.cyan)
            : (!moving ? pill('Guard is setting cameras...', 'eye') : null));
      }
      var warn = h('div', { class: 'center', style: { display: 'flex', padding: '8px 24px 24px' } },
        h('div', { class: 'row gap10', style: { padding: '11px 16px', borderRadius: '999px', background: AP.alpha(C.yellow, 0.1), fontSize: '14px', fontWeight: 700, color: C.text2 } },
          h('span', { style: { color: C.yellow, display: 'inline-flex' } }, AP.icon('exclamationmark.triangle.fill', 14)), 'Avoid red-lit tiles on the TV!'));
      return page(C.cyan, header('person.fill', 'You are a Thief', 'Reach the vault, then escape', C.cyan, round), [content, warn]);
    };
  }

  AP.controllers.heist = function (ctx) {
    var g = null, t = null;
    return function (d) {
      if (pd.str(d, 'role') === 'guard') { g = g || guard(ctx); return g(d); }
      t = t || thief(ctx); return t(d);
    };
  };
})();
