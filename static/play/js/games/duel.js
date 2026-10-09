/* Duel and co-op games: Defuse, Battleship, Heist Escape, Ludo, Teen Patti.
 * Port of DuelControllers.swift.
 */
(function () {
  'use strict';
  var AP = window.AP;
  var h = AP.h, C = AP.C, ui = AP.ui, kit = AP.kit, pd = AP.pd;
  var waiting = AP.waiting;

  function hint(text, icon, tint) {
    return h('div', { class: 'px20 center', style: { display: 'flex' } }, kit.classicPill(text, icon, tint));
  }
  function card(kids, accent, style) {
    return h('div', { style: Object.assign({ background: C.surface, borderRadius: 'var(--r-card)',
      border: accent ? '1px solid ' + AP.alpha(accent, 0.25) : '0' }, style || {}) }, kids);
  }
  function scrollCol(key, kids) {
    return h('div', { class: 'scroll', key: key }, h('div', { class: 'col gap16', style: { paddingBottom: '24px' } }, kids));
  }
  function arrowButton(icon, w, hh, onClick) {
    return h('button', { class: 'press', 'aria-label': icon,
      style: { appearance: 'none', width: w + 'px', height: hh + 'px', color: '#fff', borderRadius: 'var(--r-button)',
        background: AP.grad([C.surface2, C.surface]), border: '1.5px solid ' + AP.alpha(C.cyan, 0.3),
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center' },
      onclick: function () { AP.haptic.tap(); onClick(); } }, AP.icon(icon, Math.min(30, hh * 0.4)));
  }

  // ---- Defuse ------------------------------------------------------------------
  function wireColor(name) {
    switch (name) {
      case 'red': return C.red; case 'blue': return C.blue; case 'yellow': return C.yellow;
      case 'white': return '#fff'; case 'black': return '#121218'; default: return C.text3;
    }
  }
  AP.controllers.defuse = function (ctx) {
    return function (d) {
      var isDefuser = pd.bool(d, 'isDefuser');
      var strikes = pd.int(d, 'strikes');
      var moduleType = pd.str(d, 'moduleType');
      var manual = pd.strings(d, 'manual');
      var mod = d.module && typeof d.module === 'object' ? d.module : {};
      var finished = pd.bool(d, 'finished'), won = pd.bool(d, 'won');

      var strikeRow = h('div', { class: 'row center', style: { display: 'flex', justifyContent: 'center', gap: '10px', paddingTop: '14px' } },
        [0, 1, 2].map(function (i) {
          var hit = i < strikes;
          return h('span', { key: 'st' + i, style: { width: '38px', height: '38px', borderRadius: '50%', display: 'inline-flex', alignItems: 'center',
              justifyContent: 'center', color: hit ? '#fff' : 'rgba(255,255,255,0.2)', background: hit ? C.red : C.surface,
              boxShadow: hit ? '0 0 8px ' + AP.alpha(C.red, 0.5) : 'none', transform: hit ? 'none' : 'scale(0.9)', transition: 'transform .38s var(--pop)' } },
            AP.icon('xmark', 16));
        }));

      var body;
      if (finished) { body = waiting('fin', won ? 'heart.fill' : 'burst.fill', won ? 'Defused!' : 'Boom.'); }
      else if (isDefuser) {
        var inner;
        if (moduleType === 'wires') {
          var wires = (Array.isArray(mod.wires) ? mod.wires : []).filter(function (x) { return typeof x === 'string'; });
          inner = h('div', { class: 'col gap10 px20' }, wires.map(function (w, i) {
            return h('button', { class: 'press', key: 'w' + i,
              style: { appearance: 'none', border: 0, padding: '14px', borderRadius: 'var(--r-button)', background: C.surface, color: '#fff',
                display: 'flex', alignItems: 'center', gap: '14px' },
              onclick: function () { AP.haptic.rigid(); ctx.send('cut', { index: i }); } },
              h('span', { style: { width: '26px', fontSize: '17px', fontWeight: 800, color: C.text3 } }, String(i + 1)),
              h('span', { class: 'grow', style: { height: '14px', borderRadius: '999px', background: wireColor(w),
                  border: w === 'black' ? '1px solid rgba(255,255,255,0.45)' : '0', boxShadow: '0 0 6px ' + AP.alpha(wireColor(w), 0.45) } }),
              h('span', { class: 'row gap4', style: { padding: '8px 12px', borderRadius: '999px', background: AP.alpha(C.red, 0.85), fontSize: '13px', fontWeight: 800 } },
                AP.icon('scissors', 13), 'CUT'));
          }));
        } else if (moduleType === 'button') {
          var colour = typeof mod.colour === 'string' ? mod.colour : '';
          var wc = wireColor(colour);
          inner = h('div', { class: 'col center gap20', style: { paddingTop: '6px' } },
            h('div', { class: 'idle', style: { '--sc': '0.03', '--dur': '1.2s' } },
              h('div', { style: { width: '150px', height: '150px', borderRadius: '50%', display: 'flex', alignItems: 'center', justifyContent: 'center',
                  background: AP.grad([wc, AP.alpha(wc, 0.7)]), border: '3px solid rgba(255,255,255,0.25)', boxShadow: '0 8px 20px ' + AP.alpha(wc, 0.45),
                  fontSize: '20px', fontWeight: 800, color: colour === 'white' ? '#000' : '#fff' } }, typeof mod.label === 'string' ? mod.label : '')),
            h('div', { class: 'row gap12 px20 w100' },
              h('div', { class: 'grow' }, ui.bigButton({ title: 'TAP', icon: 'hand.tap.fill', colors: [C.green, AP.alpha(C.green, 0.65)], onClick: function () { ctx.send('button', { press: 'tap' }); } })),
              h('div', { class: 'grow' }, ui.bigButton({ title: 'HOLD', icon: 'hand.raised.fill', colors: [C.orange, AP.alpha(C.orange, 0.65)], onClick: function () { ctx.send('button', { press: 'hold' }); } }))));
        } else if (moduleType === 'symbols') {
          var symbols = (Array.isArray(mod.symbols) ? mod.symbols : []).filter(function (x) { return typeof x === 'string'; });
          inner = h('div', { class: 'px20', style: { display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px' } }, symbols.map(function (s, i) {
            return h('button', { class: 'press', key: 'sy' + i,
              style: { appearance: 'none', padding: '22px 0', borderRadius: 'var(--r-button)', color: '#fff', fontSize: '46px', fontWeight: 700,
                background: AP.grad([C.surface2, C.surface]), border: '1.5px solid ' + AP.alpha(C.purple, 0.3) },
              onclick: function () { AP.haptic.tap(); ctx.send('symbol', { index: i }); } }, s);
          }));
        } else { inner = h('div', { class: 'center', style: { display: 'flex' } }, ui.spinner()); }
        body = h('div', { class: 'col gap14', key: 'defuser' },
          hint('Describe what you see — they have the instructions', 'bubble.left.and.bubble.right.fill', C.orange), inner);
      } else {
        body = h('div', { class: 'col gap14', key: 'manual' },
          h('div', { class: 'col center gap6 txt-center px20' },
            h('div', { style: { fontSize: '13px', fontWeight: 800, letterSpacing: '3px', color: C.cyan } }, 'DEFUSAL MANUAL'),
            h('div', { class: 'c-text2', style: { fontSize: '14px' } }, "You can't see the bomb. Read this out loud.")),
          h('div', { style: { margin: '0 16px' } }, card(h('div', { class: 'col gap12', style: { padding: '18px' } },
            manual.map(function (line, i) { return h('div', { key: 'm' + i, style: { fontSize: '16px', fontWeight: 500, lineHeight: 1.35 } }, line); })), C.cyan)));
      }
      return ui.shell({ title: 'Defuse', subtitle: isDefuser ? 'You hold the bomb' : 'You have the manual', secondsLeft: pd.int(d, 'secondsLeft') },
        scrollCol('defuse', [strikeRow, body]));
    };
  };

  // ---- Battleship ----------------------------------------------------------------
  AP.controllers.battleship = function (ctx) {
    var showingFleet = false;
    function shotMap(d, key) {
      var out = {};
      pd.dicts(d, key).forEach(function (s) { if (typeof s.cell === 'number' && typeof s.result === 'string') { out[s.cell] = s.result; } });
      return out;
    }
    return function (d) {
      var size = pd.int(d, 'size', 8), mine = pd.bool(d, 'isMyTurn');
      var ships = pd.arr(d, 'myShips').map(function (s) { return (Array.isArray(s) ? s : []).filter(function (x) { return typeof x === 'number'; }); });
      var shipCells = {}; ships.forEach(function (s) { s.forEach(function (c) { shipCells[c] = true; }); });
      var shots = shotMap(d, 'myShots'), incoming = shotMap(d, 'incoming');

      var cells = [];
      for (var cell = 0; cell < size * size; cell++) {
        (function (cell) {
          var result = showingFleet ? incoming[cell] : shots[cell];
          var fill = result === 'hit' ? C.red : result === 'miss' ? 'rgba(255,255,255,0.12)'
            : (showingFleet && shipCells[cell]) ? AP.alpha(C.cyan, 0.85) : AP.alpha(C.blue, 0.22);
          var dis = showingFleet || !mine || shots[cell] !== undefined;
          cells.push(h('button', { class: 'press', key: 'b' + cell, disabled: dis,
            style: { appearance: 'none', border: 0, padding: 0, aspectRatio: '1', borderRadius: '5px', background: fill, color: '#fff',
              display: 'flex', alignItems: 'center', justifyContent: 'center' },
            onclick: dis ? null : function () { AP.haptic.rigid(); ctx.send('fire', { cell: cell }); } },
            result === 'hit' ? AP.icon('xmark', 11) : (result === 'miss' ? h('span', { style: { width: '6px', height: '6px', borderRadius: '50%', background: 'rgba(255,255,255,0.55)' } }) : null)));
        })(cell);
      }
      return ui.shell({ title: 'Battleship', subtitle: mine ? 'Your shot' : "Opponent's turn" },
        h('div', { class: 'col gap14', style: { flex: '1 1 auto', minHeight: 0, overflowY: 'auto', paddingBottom: '16px' } },
          h('div', { class: 'row gap10 px20', style: { paddingTop: '12px' } },
            ui.chip({ title: 'Fire', selected: !showingFleet, colors: [C.red, C.orange], onClick: function () { showingFleet = false; ctx.refresh(); } }),
            ui.chip({ title: 'My Fleet', selected: showingFleet, colors: [C.cyan, C.blue], onClick: function () { showingFleet = true; ctx.refresh(); } })),
          h('div', { style: { margin: '0 16px', padding: '10px', borderRadius: 'var(--r-card)', background: C.surface } },
            h('div', { style: { display: 'grid', gridTemplateColumns: 'repeat(' + Math.max(size, 1) + ', 1fr)', gap: '4px' } }, cells)),
          hint(showingFleet ? 'Your fleet — keep this hidden' : (mine ? 'Tap a square to fire' : 'Waiting...'),
            showingFleet ? 'eye.slash.fill' : (mine ? 'scope' : 'hourglass'), showingFleet ? C.orange : (mine ? C.red : C.text2))));
    };
  };

  // ---- Heist Escape -----------------------------------------------------------------
  AP.controllers.heist_escape = function (ctx) {
    return function (d) {
      var size = pd.int(d, 'size', 7), position = pd.int(d, 'position'), exitCell = pd.int(d, 'exitCell');
      var finished = pd.bool(d, 'finished'), won = pd.bool(d, 'won');
      var walls = {};
      pd.arr(d, 'myWalls').forEach(function (w) {
        if (Array.isArray(w) && w.length >= 2) { var a = Math.min(w[0], w[1]), b = Math.max(w[0], w[1]); walls[a + ',' + b] = true; }
      });
      function has(a, b) { return !!walls[Math.min(a, b) + ',' + Math.max(a, b)]; }
      var content;
      if (finished) {
        content = waiting('fin', won ? 'party.popper.fill' : 'exclamationmark.triangle.fill', won ? 'Escaped!' : 'Out of time');
      } else {
        var cells = [];
        for (var cell = 0; cell < size * size; cell++) {
          var bg = cell === position ? AP.alpha(C.cyan, 0.5) : (cell === exitCell ? AP.alpha(C.green, 0.4) : C.surface2);
          cells.push(h('div', { key: 'hc' + cell, style: { position: 'relative', aspectRatio: '1', borderRadius: '5px', background: bg, color: '#fff',
              display: 'flex', alignItems: 'center', justifyContent: 'center' } },
            cell === position ? AP.icon('person.fill', 12) : (cell === exitCell ? AP.icon('door.left.hand.open', 12) : null),
            ((cell % size) < size - 1 && has(cell, cell + 1)) ? h('span', { style: { position: 'absolute', right: 0, top: 0, bottom: 0, width: '3px', background: C.red } }) : null,
            (cell + size < size * size && has(cell, cell + size)) ? h('span', { style: { position: 'absolute', left: 0, right: 0, bottom: 0, height: '3px', background: C.red } }) : null));
        }
        function arrow(dir, icon) { return arrowButton(icon, 70, 58, function () { ctx.send('move', { direction: dir }); }); }
        content = h('div', { class: 'col gap14', key: 'play', style: { flex: '1 1 auto', minHeight: 0, overflowY: 'auto', paddingBottom: '16px' } },
          h('div', { style: { paddingTop: '12px' } }, hint('Only you can see these walls — describe them', 'eye.fill', C.orange)),
          h('div', { style: { margin: '0 16px', padding: '10px', borderRadius: 'var(--r-card)', background: C.surface } },
            h('div', { style: { display: 'grid', gridTemplateColumns: 'repeat(' + Math.max(size, 1) + ', 1fr)', gap: '3px' } }, cells)),
          h('div', { class: 'col center gap8', style: { paddingTop: '6px' } }, arrow('up', 'chevron.up'),
            h('div', { class: 'row gap8' }, arrow('left', 'chevron.left'), arrow('down', 'chevron.down'), arrow('right', 'chevron.right'))));
      }
      return ui.shell({ title: 'Heist Escape', subtitle: 'Your piece of the map', secondsLeft: pd.int(d, 'secondsLeft') }, content);
    };
  };

  // ---- Ludo ----------------------------------------------------------------------------
  AP.controllers.ludo = function (ctx) {
    var SEATS = [C.red, C.green, C.yellow, C.blue];
    var SAFE = [0, 13, 26, 39, 8, 21, 34, 47];
    return function (d) {
      var mine = pd.bool(d, 'isMyTurn'), die = pd.int(d, 'die'), canRoll = pd.bool(d, 'canRoll');
      var tokens = pd.arr(d, 'myTokens').filter(function (x) { return typeof x === 'number'; });
      var legal = pd.arr(d, 'legalMoves').filter(function (x) { return typeof x === 'number'; });
      var dests = pd.dicts(d, 'legalDests').filter(function (m) { return typeof m.token === 'number' && typeof m.dest === 'number'; });
      var seat = pd.int(d, 'seat'), name = pd.str(d, 'currentPlayerName');
      var seatColor = SEATS[((seat % 4) + 4) % 4];

      function positionLabel(v) {
        if (v < 0) { return 'Yard'; }
        if (v >= 105) { return 'Home'; }
        if (v >= 100) { return 'Home ' + (v - 100 + 1) + ' of 5'; }
        var abs = (seat * 13 + v) % 52;
        return 'Tile ' + (abs + 1) + (SAFE.indexOf(abs) >= 0 ? ' · safe' : '');
      }
      function destLabel(token) {
        var m = dests.filter(function (x) { return x.token === token; })[0];
        if (!m) { return null; }
        if (typeof m.destAbs === 'number') { return 'moves to tile ' + (m.destAbs + 1) + (SAFE.indexOf(m.destAbs) >= 0 ? ' · safe' : ''); }
        if (m.dest >= 105) { return 'moves home'; }
        return 'moves to home ' + (m.dest - 100 + 1) + ' of 5';
      }

      var content;
      if (!mine) {
        content = waiting('wait', 'hourglass', name ? 'Waiting for ' + name : 'Not your turn yet', 'Watch the board');
      } else {
        var dieBtn = h('div', { class: canRoll ? 'idle' : '', style: { '--sc': '0.035', '--dur': '1.1s', alignSelf: 'center', paddingTop: '20px' } },
          h('button', { class: 'press', disabled: !canRoll,
            style: { appearance: 'none', width: '180px', height: '180px', borderRadius: '50%', color: '#fff',
              border: '2px solid rgba(255,255,255,' + (canRoll ? 0.3 : 0.1) + ')',
              background: AP.grad([AP.alpha(seatColor, canRoll ? 0.9 : 0.35), AP.alpha(seatColor, canRoll ? 0.5 : 0.15)]),
              boxShadow: canRoll ? '0 8px 20px ' + AP.alpha(seatColor, 0.45) : 'none',
              display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: '6px' },
            onclick: function () { if (canRoll) { AP.haptic.thump(); ctx.send('roll', {}); } } },
            h('span', { class: 'num', style: { fontSize: '76px', fontWeight: 800, lineHeight: 1 } }, die > 0 ? String(die) : '–'),
            h('span', { style: { fontSize: '14px', fontWeight: 700, color: 'rgba(255,255,255,0.75)' } }, canRoll ? 'Tap to roll' : 'Rolled')));
        var picks = null;
        if (!canRoll) {
          picks = [h('div', { class: 'col gap10 px20 slide-in', key: 'tokens' }, tokens.map(function (v, i) {
            var ok = legal.indexOf(i) >= 0;
            return ui.choiceRow({ text: 'Token ' + (i + 1), detail: ok ? (destLabel(i) || positionLabel(v)) : positionLabel(v), disabled: !ok,
              onClick: function () { ctx.send('move', { token: i }); } });
          })), legal.length === 0 ? hint('No legal moves — passing', 'forward.fill', C.orange) : null];
        }
        content = h('div', { class: 'col gap20', key: 'mine', style: { flex: '1 1 auto', minHeight: 0, overflowY: 'auto', paddingBottom: '20px' } }, dieBtn, picks);
      }
      return ui.shell({ title: 'Ludo', subtitle: mine ? (canRoll ? 'Roll the dice' : 'Pick a token') : (name ? name + "'s turn" : 'Waiting for your turn') }, content);
    };
  };

  // ---- Teen Patti ------------------------------------------------------------------------
  AP.controllers.teen_patti = function (ctx) {
    function label(r) { return r === 14 ? 'A' : r === 13 ? 'K' : r === 12 ? 'Q' : r === 11 ? 'J' : String(r); }
    function fan(i, n) { return i * 7 - Math.max(n - 1, 0) * 3.5; }
    return function (d) {
      var blind = pd.bool(d, 'blind');
      var cards = pd.dicts(d, 'cards').map(function (c) { return { rank: typeof c.rank === 'number' ? c.rank : 0, suit: typeof c.suit === 'string' ? c.suit : '♠' }; });
      var chips = pd.int(d, 'chips'), pot = pd.int(d, 'pot'), callCost = pd.int(d, 'callCost');
      var canAct = pd.bool(d, 'canAct'), folded = pd.bool(d, 'folded');
      var body;
      if (folded) {
        body = waiting('fold', 'door.left.hand.open', 'You folded', 'Waiting for the hand to finish');
      } else {
        var hand;
        if (blind) {
          hand = [0, 1, 2].map(function (i) {
            var a = fan(i, 3);
            return h('div', { key: 'bk' + i, class: 'pop-in', style: { width: '74px', height: '106px', borderRadius: '12px', background: AP.grad([C.purple, C.indigo]),
                border: '2px solid rgba(255,255,255,0.25)', boxShadow: '0 5px 10px ' + AP.alpha(C.purple, 0.35), display: 'flex', alignItems: 'center',
                justifyContent: 'center', fontSize: '34px', fontWeight: 900, color: 'rgba(255,255,255,0.75)',
                transform: 'translateY(' + Math.abs(a) + 'px) rotate(' + a + 'deg)' } }, '?');
          });
        } else {
          hand = cards.map(function (c, i) {
            var a = fan(i, cards.length);
            var red = c.suit === '♥' || c.suit === '♦';
            return h('div', { key: 'cd' + i, class: 'pop-in', style: { width: '74px', height: '106px', borderRadius: '12px', background: 'linear-gradient(135deg, #fff, #eef0f4)',
                color: red ? '#d61f2c' : '#121826', boxShadow: '0 4px 8px rgba(0,0,0,0.35)', display: 'flex', flexDirection: 'column',
                alignItems: 'center', justifyContent: 'center', gap: '2px', transform: 'translateY(' + Math.abs(a) + 'px) rotate(' + a + 'deg)' } },
              h('span', { style: { fontSize: '30px', fontWeight: 800, lineHeight: 1 } }, label(c.rank)),
              h('span', { style: { fontSize: '24px', fontWeight: 400, lineHeight: 1 } }, c.suit));
          });
        }
        body = h('div', { class: 'col gap16', key: 'play' },
          h('div', { class: 'row center', style: { display: 'flex', justifyContent: 'center', gap: '10px', padding: '24px 0 6px' } }, hand),
          blind ? [hint('Playing blind — half price to stay in', 'eye.slash.fill', C.orange),
            ui.ctlButton({ title: 'See My Cards', icon: 'eye.fill', tint: C.yellow, onClick: function () { ctx.send('see', {}); } })] : null,
          h('div', { class: 'col gap10', style: { paddingTop: '6px' } },
            ui.ctlButton({ title: 'Call  (' + callCost + ')', tint: C.cyan, enabled: canAct, onClick: function () { ctx.send('call', {}); } }),
            ui.ctlButton({ title: 'Raise  (' + (callCost * 2) + ')', tint: C.green, enabled: canAct, onClick: function () { ctx.send('bet', {}); } }),
            h('div', { class: 'px20', style: { opacity: canAct ? 1 : 0.4, pointerEvents: canAct ? 'auto' : 'none' } },
              ui.ghostButton({ title: 'Fold', icon: 'xmark', onClick: function () { ctx.send('fold', {}); } }))),
          !canAct ? hint('Waiting for your turn...', 'hourglass') : null);
      }
      return ui.shell({ title: 'Teen Patti', subtitle: 'Chips ' + chips + ' · Pot ' + pot }, scrollCol('tp', [body]));
    };
  };
})();
