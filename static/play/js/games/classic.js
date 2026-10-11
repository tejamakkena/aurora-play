/* Classic games: Four in a Row, Roulette, Mafia, Raja Mantri.
 * Port of ClassicGameControllers.swift.
 */
(function () {
  'use strict';
  var AP = window.AP;
  var h = AP.h, C = AP.C, ui = AP.ui, kit = AP.kit, pd = AP.pd;

  function cap(s) { return s ? s.charAt(0).toUpperCase() + s.slice(1) : s; }

  // ---- Four in a Row -----------------------------------------------------------------
  var C4 = {
    red: ['#e8283b', '#ff8a8f', '#7a0b16'], yellow: ['#ffc61a', '#fff1a8', '#9a6a00'],
    green: ['#1fc96b', '#9cf5c2', '#0a6634'], blue: ['#35b4ff', '#c4ecff', '#0b5c9e']
  };
  function pal(id) { return C4[id] || ['#8a94a6', '#d5dbe6', '#3c4454']; }

  function disc(colorID, size) {
    var p = pal(colorID);
    return h('span', { style: { position: 'relative', display: 'inline-block', width: size + 'px', height: size + 'px', borderRadius: '50%', flex: '0 0 auto',
        background: 'radial-gradient(circle at 36% 30%, ' + p[1] + ', ' + p[0] + ' 45%, ' + p[2] + ' ' + Math.round(72) + '%)',
        boxShadow: 'inset 0 0 0 ' + Math.max(1, size * 0.05) + 'px ' + AP.alpha(p[2], 0.75) + ', 0 ' + (size * 0.05) + 'px ' + (size * 0.06) + 'px rgba(0,0,0,0.4)' } },
      h('span', { style: { position: 'absolute', width: (size * 0.52) + 'px', height: (size * 0.30) + 'px', borderRadius: '50%',
          left: (size * 0.5 - size * 0.26 - size * 0.09) + 'px', top: (size * 0.5 - size * 0.15 - size * 0.23) + 'px',
          background: 'linear-gradient(to bottom, rgba(255,255,255,0.75), rgba(255,255,255,0))' } }));
  }

  AP.controllers.connect4 = function (ctx) {
    var aimed = null, lastTurn = null;
    return function (d) {
      var mine = pd.bool(d, 'isMyTurn');
      var myColor = pd.str(d, 'color', 'red');
      var count = Math.min(Math.max(pd.int(d, 'cols', 7), 1), 16);
      var full = pd.arr(d, 'fullColumns').filter(function (x) { return typeof x === 'number'; });
      var currentName = pd.str(d, 'currentPlayerName'), currentColor = pd.str(d, 'currentColor');
      var turnOrder = pd.strings(d, 'turnOrder');
      var colors = d.colors && typeof d.colors === 'object' ? d.colors : {};
      var currentID = pd.str(d, 'currentPlayerID');
      if (lastTurn !== mine) { if (!mine) { aimed = null; } else { AP.haptic.thump(); } lastTurn = mine; }
      var p = pal(myColor);
      var spacing = count > 8 ? 4 : 6;

      var status;
      if (mine) {
        status = h('div', { class: 'col center gap4 pop-in', key: 'mine' },
          h('div', { style: { fontSize: '30px', fontWeight: 900, color: p[1] } }, 'Your move!'),
          h('div', { class: 'c-text3', style: { fontSize: '14px' } }, 'Drag to aim, let go to drop'));
      } else if (currentName) {
        status = h('div', { class: 'row gap10', key: 'wait', style: { padding: '10px 16px', borderRadius: '999px', background: C.surface } },
          currentColor ? disc(currentColor, 20) : null,
          h('span', { class: 'c-text2', style: { fontSize: '15px', fontWeight: 700 } }, 'Waiting for ' + currentName));
      } else {
        status = h('div', { key: 'w' }, kit.classicPill('Waiting...', 'hourglass'));
      }

      function colAt(el, clientX) {
        var rect = el.getBoundingClientRect();
        var colW = Math.max(10, (rect.width - spacing * (count - 1)) / count);
        var raw = Math.floor((clientX - rect.left) / (colW + spacing));
        return Math.min(Math.max(raw, 0), count - 1);
      }
      function aimTo(col) { if (col !== aimed) { aimed = col; if (navigator.vibrate) { navigator.vibrate(4); } ctx.refresh(); } }

      var cols = [];
      for (var col = 0; col < count; col++) { cols.push(column(col)); }
      function column(c) {
        var isFull = full.indexOf(c) >= 0;
        var on = aimed === c && !isFull;
        var fill = isFull ? 'rgba(255,255,255,0.03)'
          : (on ? 'linear-gradient(to bottom, ' + AP.alpha(p[0], 0.75) + ', ' + AP.alpha(p[2], 0.55) + ')'
            : 'linear-gradient(to bottom, ' + AP.alpha(C.blue, 0.32) + ', ' + AP.alpha(C.indigo, 0.18) + ')');
        return h('div', { key: 'c' + c, class: 'col center', style: { gap: '6px', minWidth: 0 } },
          h('div', { style: { height: '36px', display: 'flex', alignItems: 'center', justifyContent: 'center' } },
            on ? h('span', { class: 'pop-in' }, disc(myColor, 30))
               : h('span', { style: { color: 'rgba(255,255,255,' + (isFull ? 0.1 : 0.35) + ')', display: 'inline-flex' } }, AP.icon('chevron.down', 12))),
          h('div', { class: 'grow w100', style: { background: fill, borderRadius: Math.min(12, 10) + 'px', transition: 'background .2s',
              border: (on ? 2 : 1) + 'px solid ' + (on ? AP.alpha(p[1], 0.9) : 'rgba(255,255,255,0.08)'),
              boxShadow: on ? '0 4px 10px ' + AP.alpha(p[0], 0.45) : 'none', display: 'flex', alignItems: 'center', justifyContent: 'center',
              color: 'rgba(255,255,255,0.25)' } }, isFull ? AP.icon('xmark', 11) : null),
          h('div', { style: { fontSize: '12px', fontWeight: 800, color: on ? '#fff' : C.text3 } }, String(c + 1)));
      }

      var strip = h('div', { key: 'strip', style: { display: 'grid', gridTemplateColumns: 'repeat(' + count + ', 1fr)', gap: spacing + 'px', height: '260px',
          touchAction: 'none', opacity: mine ? 1 : 0.35, pointerEvents: mine ? 'auto' : 'none', transition: 'opacity .2s' },
        onpointerdown: function (ev) { ev.currentTarget.setPointerCapture(ev.pointerId); aimTo(colAt(ev.currentTarget, ev.clientX)); },
        onpointermove: function (ev) { if (ev.buttons || ev.pressure > 0) { aimTo(colAt(ev.currentTarget, ev.clientX)); } },
        onpointerup: function (ev) {
          aimTo(colAt(ev.currentTarget, ev.clientX));
          if (mine && aimed !== null && full.indexOf(aimed) < 0) { var col = aimed; aimed = null; AP.haptic.rigid(); ctx.send('drop', { column: col }); }
          else { aimed = null; }
          ctx.refresh();
        },
        onpointercancel: function () { aimed = null; ctx.refresh(); } }, cols);

      var order = turnOrder.length ? h('div', { class: 'row center gap12', style: { alignSelf: 'center', marginTop: '18px', padding: '10px 18px', borderRadius: '999px', background: C.surface } },
        turnOrder.map(function (pid, i) {
          var cur = pid === currentID;
          return h('span', { key: 'td' + i, style: { opacity: cur ? 1 : 0.5, padding: '4px', borderRadius: '50%', border: '2px solid ' + (cur ? 'rgba(255,255,255,0.9)' : 'transparent'), display: 'inline-flex' } },
            disc(colors[pid] || '', cur ? 26 : 18));
        })) : null;

      return kit.classicShell({ title: 'Four in a Row', subtitle: 'You are ' + cap(myColor),
          trailing: h('span', { class: 'idle', style: { '--dy': '2px', '--dur': '1.4s', display: 'inline-flex' } }, disc(myColor, 32)) },
        h('div', { class: 'col', style: { flex: '1 1 auto', minHeight: 0, justifyContent: 'center', overflowY: 'auto' } },
          h('div', { class: 'col center', style: { paddingBottom: '18px' } }, status),
          h('div', { style: { margin: '0 14px', padding: '12px', borderRadius: 'var(--r-card)', background: C.surface } }, strip),
          order));
    };
  };

  // ---- Roulette ------------------------------------------------------------------------
  var RED = [1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36];
  var CHIPS = [1, 5, 25, 100];
  var OUTSIDE = [['red', 'Red'], ['black', 'Black'], ['odd', 'Odd'], ['even', 'Even'], ['1-12', '1st 12'], ['13-24', '2nd 12'],
    ['25-36', '3rd 12'], ['low', '1–18'], ['high', '19–36']];

  AP.controllers.roulette = function (ctx) {
    var selected = 5;
    return function (d) {
      var chips = typeof d.chips === 'number' ? Math.trunc(d.chips) : 100;
      var bets = d.bets && typeof d.bets === 'object' ? d.bets : {};
      var spinning = pd.bool(d, 'isSpinning');
      var last = typeof d.lastResult === 'number' ? Math.trunc(d.lastResult) : null;
      var staked = Object.keys(bets).reduce(function (a, k) { return a + (typeof bets[k] === 'number' ? Math.trunc(bets[k]) : 0); }, 0);
      var hasBets = staked > 0;
      var isReady = pd.bool(d, 'isReady'), readyCount = pd.int(d, 'readyCount'), readyNeeded = pd.int(d, 'readyNeeded');
      var clock = pd.int(d, 'betSecondsLeft');
      var enabled = !spinning && selected <= chips;

      function place(target) { if (!spinning && selected <= chips) { ctx.send('place_bet', { target: target, amount: selected }); } }
      var spinLabel = spinning ? 'Spinning…'
        : (isReady ? 'Waiting for others (' + readyCount + '/' + readyNeeded + ')' + (clock > 0 ? ' · ' + clock + 's' : '')
          : (clock > 0 ? 'Done betting · ' + clock + 's' : 'Done betting - spin!'));
      var spinIcon = spinning ? 'arrow.triangle.2.circlepath' : (isReady ? 'hourglass' : 'checkmark.circle.fill');
      var canSpin = !spinning && hasBets && !isReady;

      var chipRow = h('div', { class: 'col gap8' }, ui.sectionLabel('Chip value'),
        h('div', { class: 'row gap10' }, CHIPS.map(function (v) {
          var aff = v <= chips && !spinning, sel = selected === v;
          return h('button', { class: 'press grow', key: 'chip' + v, disabled: !aff,
            style: { appearance: 'none', minHeight: '48px', borderRadius: 'var(--r-chip)', fontSize: '17px', fontWeight: 800, opacity: aff ? 1 : 0.35,
              color: sel ? '#000' : '#fff', background: sel ? AP.grad([C.yellow, C.orange]) : C.surface,
              border: sel ? '0' : '1px solid rgba(255,255,255,0.08)', boxShadow: sel ? '0 3px 8px ' + AP.alpha(C.yellow, 0.3) : 'none' },
            onclick: aff ? function () { AP.haptic.tap(); selected = v; ctx.refresh(); } : null }, '$' + v);
        })));

      var clear = h('button', { class: 'press', disabled: !hasBets || spinning,
        style: { appearance: 'none', width: '100%', minHeight: '50px', padding: '0 16px', borderRadius: 'var(--r-button)', display: 'flex', alignItems: 'center', gap: '8px',
          fontSize: '16px', fontWeight: 700, color: hasBets ? C.red : 'rgba(255,255,255,0.3)', background: hasBets ? AP.alpha(C.red, 0.14) : C.surface,
          border: '1.5px solid ' + (hasBets ? AP.alpha(C.red, 0.5) : 'rgba(255,255,255,0.06)') },
        onclick: function () { AP.haptic.warning(); if (!spinning) { ctx.send('clear_bets', {}); } } },
        AP.icon('trash.fill', 15), h('span', { class: 'grow', style: { textAlign: 'left' } }, hasBets ? 'Clear bets · $' + staked : 'Clear bets'),
        hasBets ? h('span', { style: { fontSize: '12px', fontWeight: 600, color: AP.alpha(C.red, 0.7) } }, 'refunds your stake') : null);

      var numbers = [];
      for (var n = 0; n <= 36; n++) {
        (function (n) {
          var amt = typeof bets[String(n)] === 'number' ? Math.trunc(bets[String(n)]) : 0;
          var fill = n === 0 ? '#0b7a3b' : (RED.indexOf(n) >= 0 ? '#c0202a' : '#15161a');
          numbers.push(h('button', { class: 'press', key: 'n' + n, disabled: !enabled,
            style: { appearance: 'none', minHeight: '38px', borderRadius: '8px', background: fill, color: '#fff', opacity: enabled ? 1 : 0.4,
              border: (amt > 0 ? 2 : 1) + 'px solid ' + (amt > 0 ? C.yellow : 'rgba(255,255,255,0.15)'),
              display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: '1px', padding: 0 },
            onclick: function () { AP.haptic.tap(); place(String(n)); } },
            h('span', { style: { fontSize: '14px', fontWeight: 800, lineHeight: 1 } }, String(n)),
            h('span', { style: { fontSize: '9px', fontWeight: 800, color: C.yellow, lineHeight: 1, minHeight: '9px' } }, amt > 0 ? '$' + amt : '')));
        })(n);
      }
      var numberGrid = h('div', { class: 'col gap8' }, ui.sectionLabel('Bet on a number'),
        h('div', { style: { display: 'grid', gridTemplateColumns: 'repeat(6, 1fr)', gap: '6px', padding: '10px', borderRadius: 'var(--r-card)', background: C.surface } }, numbers));

      var outside = h('div', { class: 'col gap8' }, ui.sectionLabel('Or an outside bet'),
        h('div', { style: { display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '10px' } }, OUTSIDE.map(function (t) {
          var amt = typeof bets[t[0]] === 'number' ? Math.trunc(bets[t[0]]) : 0;
          return h('button', { class: 'press', key: 'o-' + t[0], disabled: !enabled,
            style: { appearance: 'none', minHeight: '62px', padding: '0 6px', borderRadius: 'var(--r-chip)', color: '#fff', opacity: enabled ? 1 : 0.4,
              background: amt > 0 ? AP.alpha(C.green, 0.18) : C.surface, border: '1.5px solid ' + (amt > 0 ? AP.alpha(C.green, 0.6) : 'rgba(255,255,255,0.06)'),
              display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: '2px' },
            onclick: function () { AP.haptic.tap(); place(t[0]); } },
            h('span', { style: { fontSize: '16px', fontWeight: 700 } }, t[1]),
            h('span', { style: { fontSize: '13px', fontWeight: 800, color: C.green, minHeight: '16px' } }, amt > 0 ? '$' + amt : ''));
        })));

      var trailing = h('div', { class: 'row gap10', style: { flex: '0 0 auto' } },
        last !== null ? h('span', { style: { padding: '5px 10px', borderRadius: '999px', background: AP.alpha(C.yellow, 0.15), color: C.yellow,
            fontSize: '13px', fontWeight: 800, whiteSpace: 'nowrap' } }, 'Last ' + last) : null,
        h('span', { class: 'num', style: { fontSize: '20px', fontWeight: 800, color: C.green, whiteSpace: 'nowrap' } }, '$' + chips));

      var spinBar = h('div', { style: { borderTop: '1px solid rgba(255,255,255,0.06)', background: AP.alpha(C.surface, 0.7), paddingBottom: 'var(--safe-bottom)' } },
        h('div', { style: { padding: '12px 0' } },
          ui.ctlButton({ title: spinLabel, icon: spinIcon, tint: C.green, enabled: canSpin, onClick: function () { if (!spinning) { ctx.send('spin', {}); } } })),
        (!hasBets && !spinning) ? h('div', { class: 'txt-center c-text3', style: { fontSize: '13px', paddingBottom: '10px' } },
          'Tap a bet above to stake your $' + selected + ' chip') : null);

      return kit.classicShell({ title: 'Roulette',
          subtitle: spinning ? 'The wheel is spinning' : (hasBets ? 'Staked $' + staked : 'Place your bets'), trailing: trailing },
        h('div', { class: 'col', style: { flex: '1 1 auto', minHeight: 0 } },
          h('div', { class: 'scroll' }, h('div', { class: 'col gap16', style: { padding: '16px 20px 24px' } }, chipRow, clear, numberGrid, outside)),
          spinBar));
    };
  };

  // ---- Mafia ---------------------------------------------------------------------------
  AP.controllers.mafia = function (ctx) {
    return function (d) {
      var role = pd.str(d, 'role', 'town'), phase = pd.str(d, 'phase', 'day');
      var alive = pd.bool(d, 'isAlive', true);
      var players = pd.dicts(d, 'players');
      var myVote = typeof d.myVote === 'string' ? d.myVote : null;
      var invRes = typeof d.investigateResult === 'string' ? d.investigateResult : null;
      var invMafia = typeof d.investigateIsMafia === 'boolean' ? d.investigateIsMafia : (invRes ? /is Mafia!$/.test(invRes) : false);
      var myNight = typeof d.myNightTarget === 'string' ? d.myNightTarget : null;
      var team = pd.strings(d, 'mafiaTeam');
      var myID = pd.str(d, 'myID');
      var day = phase === 'day';
      var living = players.filter(function (p) { return typeof p.id === 'string' && typeof p.name === 'string' && p.isAlive !== false; });
      var others = living.filter(function (p) { return p.id !== myID; });

      var info = ({
        mafia: ['moon.stars.fill', C.red, 'Eliminate town at night'],
        sheriff: ['magnifyingglass', C.yellow, 'Investigate one player per night'],
        doctor: ['cross.fill', C.green, 'Save one player per night']
      })[role] || ['person.fill', C.blue, 'Vote out Mafia during the day'];

      var roleCard = h('div', { style: { margin: '10px 14px 0' } },
        h('div', { class: 'row gap14', style: { padding: '16px', borderRadius: 'var(--r-card)', background: C.surface, border: '1.5px solid ' + AP.alpha(info[1], 0.35) } },
          h('div', { class: 'idle', style: { '--dy': '2px', '--sc': '0.03', '--dur': '1.6s', width: '54px', height: '54px', borderRadius: '50%', flex: '0 0 auto',
              display: 'flex', alignItems: 'center', justifyContent: 'center', background: AP.grad([AP.alpha(info[1], 0.75), AP.alpha(info[1], 0.3)]) } }, AP.icon(info[0], 24)),
          h('div', { class: 'col gap4' },
            h('div', { style: { fontSize: '20px', fontWeight: 800, color: info[1] } }, cap(role)),
            h('div', { class: 'c-text2', style: { fontSize: '13px' } }, info[2]))));

      function title(text, tint) { return h('div', { class: 'txt-center px20', style: { fontSize: '22px', fontWeight: 800, color: tint } }, text); }
      function pickList(list, tint, selectedId, icon, badge, act) {
        return h('div', { class: 'col gap12 px20' }, list.map(function (p) {
          return kit.pickRow({ key: 'pk-' + p.id, text: p.name, tint: tint, selected: selectedId === p.id, badge: badge, icon: icon,
            onClick: function () { act(p.id); } });
        }));
      }

      var content;
      if (!alive) {
        content = h('div', { class: 'col center gap16 txt-center pop-in', key: 'dead', style: { padding: '20px 40px' } },
          kit.hero('person.fill.xmark', C.red), h('div', { style: { fontSize: '26px', fontWeight: 800, color: C.red } }, 'You were eliminated'),
          h('div', { class: 'c-text2', style: { fontSize: '15px', fontWeight: 500 } }, 'Watch the TV to see how the game ends.'));
      } else if (day) {
        content = h('div', { class: 'col gap12 pop-in', key: 'day', style: { padding: '20px 0' } },
          (role === 'sheriff' && invRes) ? h('div', { class: 'px20' }, kit.classicPill('Last night: ' + invRes, 'magnifyingglass', invMafia ? C.red : C.green)) : null,
          (role === 'mafia' && team.length) ? h('div', { class: 'px20' }, kit.classicPill('Fellow Mafia: ' + team.join(', '), 'person.2.fill', C.red)) : null,
          h('div', { style: { padding: '4px 24px 0' } }, ui.sectionLabel('Vote to eliminate')),
          pickList(living, C.red, myVote, null, 'Your vote', function (id) { ctx.send('vote', { targetID: id }); }));
      } else {
        var night;
        if (role === 'mafia') {
          night = [title('Choose your target', C.red),
            team.length ? h('div', { class: 'px20' }, kit.classicPill('Your fellow Mafia: ' + team.join(', '), 'person.2.fill', C.red)) : null,
            pickList(others, C.red, myNight, 'scope', null, function (id) { ctx.send('eliminate', { targetID: id }); })];
        } else if (role === 'doctor') {
          night = [title('Save someone tonight', C.green),
            pickList(living, C.green, myNight, 'cross.fill', null, function (id) { ctx.send('save', { targetID: id }); })];
        } else if (role === 'sheriff') {
          night = [title('Investigate a player', C.yellow),
            invRes ? h('div', { class: 'px20' }, kit.classicPill('Result: ' + invRes, 'magnifyingglass', invMafia ? C.red : C.green)) : null,
            myNight === null ? pickList(others, C.yellow, null, 'magnifyingglass', null, function (id) { ctx.send('investigate', { targetID: id }); })
              : h('div', { class: 'center', style: { display: 'flex' } }, kit.classicPill('One investigation per night. Sleep now.', 'moon.zzz.fill'))];
        } else {
          night = [h('div', { class: 'col center gap16 txt-center', style: { padding: '0 30px' } }, kit.hero('moon.fill', C.indigo),
            h('div', { style: { fontSize: '24px', fontWeight: 800 } }, 'Sleep tight…'),
            h('div', { class: 'c-text2', style: { fontSize: '15px', fontWeight: 500 } }, 'Mafia is choosing their target.'))];
        }
        content = h('div', { class: 'col gap12 pop-in', key: 'night-' + role, style: { padding: '20px 0' } }, night);
      }

      var chip = h('span', { class: 'row gap6', style: { padding: '7px 12px', borderRadius: '999px', fontSize: '14px', fontWeight: 800, flex: '0 0 auto',
          color: day ? C.yellow : C.cyan, background: AP.alpha(day ? C.yellow : C.cyan, 0.15) } },
        AP.icon(day ? 'sun.max.fill' : 'moon.stars.fill', 13), day ? 'Day' : 'Night');
      return kit.classicShell({ title: 'Mafia', subtitle: day ? 'Discuss, then vote' : 'Eyes closed, phones low',
          glow: day ? C.yellow : C.indigo, trailing: chip },
        h('div', { class: 'col', style: { flex: '1 1 auto', minHeight: 0 } }, roleCard, kit.centeredScroll(content)));
    };
  };

  // ---- Raja Mantri -------------------------------------------------------------------------
  AP.controllers.raja_mantri = function (ctx) {
    function roleColor(r) { return r === 'Raja' ? C.yellow : r === 'Mantri' ? C.purple : r === 'Chor' ? C.red : C.cyan; }
    function roleDesc(r) {
      return r === 'Raja' ? 'You are the King. Stay safe.' : r === 'Mantri' ? 'You are the Minister. Protect the Raja.'
        : r === 'Chor' ? 'You are the Thief. Hide your identity!' : 'You are the Guard. Find the Chor!';
    }
    return function (d) {
      var role = pd.str(d, 'role'), phase = pd.str(d, 'phase', 'deal');
      var players = pd.dicts(d, 'players').filter(function (p) { return typeof p.id === 'string' && typeof p.name === 'string'; });
      var score = typeof d.score === 'number' ? Math.trunc(d.score) : 0;
      var guessed = pd.bool(d, 'hasGuessed');
      var kids = [];
      if (role) {
        var tint = roleColor(role);
        kids.push(h('div', { class: 'px20 pop-in', key: 'role-' + role },
          h('div', { class: 'col center gap10 txt-center', style: { padding: '24px', borderRadius: 'var(--r-card)', background: C.surface, border: '1.5px solid ' + AP.alpha(tint, 0.35) } },
            h('div', { class: 'idle', style: { '--dy': '4px', '--sc': '0.03', '--dur': '1.6s', width: '104px', height: '104px', borderRadius: '50%', display: 'flex',
                alignItems: 'center', justifyContent: 'center', fontSize: '54px', fontWeight: 900, background: AP.grad([tint, AP.alpha(tint, 0.55)]),
                boxShadow: '0 8px 16px ' + AP.alpha(tint, 0.4) } }, role === 'Raja' ? 'R' : role === 'Mantri' ? 'M' : role === 'Chor' ? 'C' : '?'),
            h('div', { style: { fontSize: '34px', fontWeight: 900, color: tint } }, role),
            h('div', { class: 'c-text2', style: { fontSize: '15px', padding: '0 12px' } }, roleDesc(role)))));
      }
      if (role === 'Sipahi' && phase === 'guess' && !guessed) {
        kids.push(h('div', { class: 'col gap10 px20 pop-in', key: 'guess' },
          h('div', { class: 'txt-center', style: { fontSize: '24px', fontWeight: 800, color: C.yellow } }, 'Catch the Chor!'),
          h('div', { class: 'c-text2 txt-center', style: { fontSize: '15px', paddingBottom: '4px' } }, 'Who is the thief?'),
          players.map(function (p) {
            return kit.pickRow({ key: 'ac-' + p.id, text: p.name, tint: C.yellow, icon: 'hand.point.right.fill', onClick: function () { ctx.send('accuse', { targetID: p.id }); } });
          })));
      } else if (phase === 'wait' || guessed) {
        kids.push(h('div', { class: 'center', style: { display: 'flex' }, key: 'wait' }, kit.classicPill('Wait for the round to end', 'hourglass')));
      }
      return kit.classicShell({ title: 'Raja Mantri', trailing: kit.statBadge(score, 'SCORE') },
        kit.centeredScroll(h('div', { class: 'col gap20', style: { padding: '20px 0' } }, kids)));
    };
  };
})();
