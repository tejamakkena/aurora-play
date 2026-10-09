/* Snakes & Ladders (shake to roll), Mind Meld, Speed Sculptor and Tambola.
 * Port of OtherControllerViews.swift.
 */
(function () {
  'use strict';
  var AP = window.AP;
  var h = AP.h, C = AP.C, ui = AP.ui, kit = AP.kit, pd = AP.pd;
  var waiting = AP.waiting, centered = AP.centered, promptCard = AP.promptCard;

  // ---- Snakes & Ladders ----------------------------------------------------
  var PIPS = {
    1: [[0.5, 0.5]], 2: [[0.26, 0.26], [0.74, 0.74]], 3: [[0.26, 0.26], [0.5, 0.5], [0.74, 0.74]],
    4: [[0.26, 0.26], [0.74, 0.26], [0.26, 0.74], [0.74, 0.74]],
    5: [[0.26, 0.26], [0.74, 0.26], [0.5, 0.5], [0.26, 0.74], [0.74, 0.74]],
    6: [[0.26, 0.22], [0.74, 0.22], [0.26, 0.5], [0.74, 0.5], [0.26, 0.78], [0.74, 0.78]]
  };
  function dieFace(value, size, rolling, glow) {
    return h('div', { class: rolling ? 'dice-roll' : '', style: { position: 'relative', width: size + 'px', height: size + 'px',
        borderRadius: (size * 0.18) + 'px', background: 'linear-gradient(to bottom, #fff, #eef0f4)', border: '2px solid rgba(0,0,0,0.08)',
        boxShadow: '0 8px 14px rgba(0,0,0,0.45)' + (glow ? ', 0 0 26px ' + AP.alpha(C.cyan, 0.45) : '') } },
      (PIPS[value] || []).map(function (p, i) {
        return h('span', { key: 'pip' + i, style: { position: 'absolute', width: (size * 0.15) + 'px', height: (size * 0.15) + 'px', borderRadius: '50%',
          background: 'var(--bg)', left: (p[0] * size - size * 0.075) + 'px', top: (p[1] * size - size * 0.075) + 'px' } });
      }));
  }

  AP.controllers.snake_ladder = function (ctx) {
    var lastRoll = null, rolling = false, busy = false, buzzedSeq = null, shakeOn = false;
    function roll() {
      var d = AP.S.privateData || {};
      if (!pd.bool(d, 'isMyTurn') || busy) { return; }
      busy = true; rolling = true;
      AP.haptic.thump();
      ctx.refresh();
      ctx.after(320, function () {
        var value = 1 + Math.floor(Math.random() * 6);
        lastRoll = value;
        ctx.send('roll', { value: value });
        ctx.refresh();
        ctx.after(280, function () { rolling = false; ctx.refresh(); });
        ctx.after(600, function () { busy = false; });
      });
    }
    function enableShake() {
      if (shakeOn) { return; }
      shakeOn = true;
      var last = 0;
      function onMotion(ev) {
        var a = ev.accelerationIncludingGravity;
        if (!a) { return; }
        var mag = Math.sqrt((a.x || 0) * (a.x || 0) + (a.y || 0) * (a.y || 0) + (a.z || 0) * (a.z || 0));
        var now = Date.now();
        if (mag > 28 && now - last > 900) { last = now; roll(); }
      }
      var go = function () { window.addEventListener('devicemotion', onMotion); ctx.onDestroy(function () { window.removeEventListener('devicemotion', onMotion); }); };
      try {
        if (window.DeviceMotionEvent && typeof window.DeviceMotionEvent.requestPermission === 'function') {
          window.DeviceMotionEvent.requestPermission().then(function (r) { if (r === 'granted') { go(); } }).catch(function () { /* tap still works */ });
        } else if (window.DeviceMotionEvent) { go(); }
      } catch (e) { /* tap still works */ }
    }
    return function (d) {
      var mine = pd.bool(d, 'isMyTurn'), again = pd.bool(d, 'rollAgain');
      var slide = d.lastSlide && typeof d.lastSlide === 'object' ? d.lastSlide : null;
      if (slide && typeof slide.seq === 'number' && slide.seq !== buzzedSeq) {
        buzzedSeq = slide.seq;
        if (slide.kind === 'snake') { AP.haptic.error(); } else if (slide.kind === 'ladder') { AP.haptic.success(); }
      }
      var die = h('button', { class: 'press idle', 'aria-label': 'Roll the dice', disabled: !mine,
        style: { appearance: 'none', border: 0, background: 'none', padding: 0, '--dy': '4px', '--dur': '1.3s' },
        onclick: function () { enableShake(); roll(); } }, dieFace(lastRoll || 0, 220, rolling, mine));
      return ui.shell({ title: 'Snakes & Ladders', subtitle: mine ? 'Your turn' : 'Waiting for your turn' },
        h('div', { class: 'col center', style: { flex: '1 1 auto', justifyContent: 'center', gap: '26px' } },
          die,
          lastRoll ? h('div', { class: 'num', style: { fontSize: '34px', fontWeight: 900 } }, 'You rolled ' + lastRoll + '!') : null,
          (again && mine) ? h('div', { class: 'pop-in', key: 'again' }, kit.pill('Rolled a 6, roll again!', 'arrow.counterclockwise.circle.fill', C.yellow)) : null,
          kit.pill(mine ? 'Shake or tap the die to roll!' : 'Not your turn...', mine ? 'hand.tap.fill' : 'hourglass', mine ? C.cyan : C.text3),
          typeof d.position === 'number' ? h('div', { class: 'c-text2', style: { fontSize: '15px' } }, 'Your position: ' + Math.trunc(d.position)) : null));
    };
  };

  // ---- Mind Meld ------------------------------------------------------------------
  AP.controllers.mind_meld = function (ctx) {
    var word = '', submittedRound = null, trackedRound = -1;
    return function (d) {
      var category = pd.str(d, 'category'), round = pd.int(d, 'round'), total = pd.int(d, 'totalRounds');
      var showReveal = pd.bool(d, 'showReveal');
      var myWord = typeof d.myWord === 'string' ? d.myWord : null;
      if (round !== trackedRound) { if (trackedRound !== -1) { word = ''; submittedRound = null; } trackedRound = round; }
      var submitted = pd.bool(d, 'hasSubmitted') || submittedRound === round;
      function submit() {
        var w = word.trim();
        if (!w || submitted) { return; }
        submittedRound = round;
        ctx.send('word', { word: w.toLowerCase() });
        ctx.refresh();
      }
      var card = h('div', { class: 'px20', style: { paddingTop: '14px' } },
        kit.card(C.purple, { cls: 'col center gap8 txt-center', style: { padding: '20px' } },
          h('div', { style: { fontSize: '12px', fontWeight: 800, letterSpacing: '2px', color: C.purple } }, 'CATEGORY'),
          h('div', { style: { fontSize: '26px', fontWeight: 900, lineHeight: 1.15 } }, category),
          h('div', { class: 'c-text2', style: { fontSize: '15px', whiteSpace: 'pre-line' } }, 'Type ONE word that fits the category.\nTry to match what others think!')));
      var content;
      if (showReveal) { content = waiting('rev', 'tv', 'Look at the TV for the melds!'); }
      else if (!submitted) {
        content = centered('form',
          ui.answerField({ key: 'mm', placeholder: 'Your word...', value: word, autocapitalize: false, onInput: function (v) { word = v; ctx.refresh(); }, onSubmit: submit }),
          ui.ctlButton({ title: 'Submit', icon: 'paperplane.fill', tint: C.purple, enabled: word.trim().length > 0, onClick: submit }));
      } else {
        content = waiting('done', 'brain.filled.head.profile', 'You said "' + (myWord !== null ? myWord : word) + '"', 'Waiting for the others...');
      }
      return ui.shell({ title: 'Mind Meld', subtitle: total > 0 ? 'Round ' + round + ' of ' + total : null },
        h('div', { class: 'col gap16', style: { flex: '1 1 auto', minHeight: 0 } }, card, content));
    };
  };

  // ---- Speed Sculptor --------------------------------------------------------------
  AP.controllers.speed_sculptor = function (ctx) {
    var lines = [], current = null, submittedRound = null, trackedRound = -1, canvasEl = null, sizeCss = { w: 1, h: 1 };
    function ensure(cv) {
      canvasEl = cv;
      var r = cv.getBoundingClientRect();
      var dpr = window.devicePixelRatio || 1;
      var w = Math.max(1, Math.round(r.width * dpr)), hh = Math.max(1, Math.round(r.height * dpr));
      sizeCss = { w: Math.max(r.width, 1), h: Math.max(r.height, 1) };
      if (cv.width !== w || cv.height !== hh) { cv.width = w; cv.height = hh; }
      return dpr;
    }
    function redraw() {
      var cv = canvasEl || document.getElementById('sculpt-canvas');
      if (!cv) { return; }
      var dpr = ensure(cv);
      var g = cv.getContext('2d');
      g.setTransform(1, 0, 0, 1, 0, 0);
      g.clearRect(0, 0, cv.width, cv.height);
      g.setTransform(dpr, 0, 0, dpr, 0, 0);
      g.lineCap = 'round'; g.lineJoin = 'round'; g.strokeStyle = '#000'; g.lineWidth = 4;
      lines.concat(current ? [current] : []).forEach(function (ln) {
        if (!ln.length) { return; }
        g.beginPath(); g.moveTo(ln[0][0], ln[0][1]);
        for (var i = 1; i < ln.length; i++) { g.lineTo(ln[i][0], ln[i][1]); }
        if (ln.length === 1) { g.lineTo(ln[0][0] + 0.1, ln[0][1]); }
        g.stroke();
      });
    }
    function pt(ev) { var r = ev.currentTarget.getBoundingClientRect(); return [ev.clientX - r.left, ev.clientY - r.top]; }
    return function (d) {
      var prompt = pd.str(d, 'prompt', '?'), round = pd.int(d, 'round');
      var voting = pd.bool(d, 'votingPhase');
      var myVote = typeof d.myVote === 'string' ? d.myVote : null;
      if (round !== trackedRound) { if (trackedRound !== -1) { lines = []; current = null; submittedRound = null; } trackedRound = round; }
      var submitted = pd.bool(d, 'hasSubmitted') || submittedRound === round;
      var cands = pd.arr(d, 'candidates').filter(function (c) { return c && typeof c.id === 'string'; })
        .map(function (c) { return { id: c.id, name: typeof c.playerName === 'string' ? c.playerName : 'Player' }; });

      var content;
      if (voting) {
        content = h('div', { class: 'scroll pop-in', key: 'vote' },
          h('div', { class: 'col gap10', style: { padding: '16px 20px 20px' } },
            h('div', { class: 'c-text2 txt-center', style: { fontSize: '15px', paddingBottom: '4px' } }, 'Look at the drawings on the TV and vote for your favourite'),
            cands.length ? null : h('div', { class: 'c-text3 txt-center', style: { fontSize: '15px' } }, 'No other drawings this round'),
            cands.map(function (c) { return ui.choiceRow({ text: c.name, selected: myVote === c.id, onClick: function () { ctx.send('vote', { targetID: c.id }); } }); })));
      } else {
        var cv = h('canvas', { id: 'sculpt-canvas', key: 'canvas',
          style: { width: '100%', flex: '1 1 auto', minHeight: '200px', background: '#fff', borderRadius: 'var(--r-card)',
            border: '2px solid ' + AP.alpha(C.purple, 0.5), touchAction: 'none', pointerEvents: submitted ? 'none' : 'auto', display: 'block' },
          onpointerdown: function (ev) {
            if (submitted) { return; }
            ev.currentTarget.setPointerCapture(ev.pointerId);
            ensure(ev.currentTarget);
            current = [pt(ev)];
            redraw();
          },
          onpointermove: function (ev) {
            if (!current) { return; }
            var p = pt(ev), last = current[current.length - 1];
            if (Math.hypot(p[0] - last[0], p[1] - last[1]) >= 3) { current.push(p); redraw(); }
          },
          onpointerup: function () { if (current) { lines.push(current); current = null; redraw(); } },
          onpointercancel: function () { if (current) { lines.push(current); current = null; redraw(); } } });
        content = h('div', { class: 'col gap10 pop-in', key: 'draw', style: { flex: '1 1 auto', minHeight: 0 } },
          h('div', { class: 'row px20', style: { paddingTop: '12px' } },
            h('span', { class: 'grow', style: { fontSize: '13px', fontWeight: 800, letterSpacing: '2px', color: C.purple } }, 'YOUR CANVAS'),
            submitted ? null : h('button', { class: 'btn-pill press', style: { color: 'rgba(255,255,255,0.85)', fontWeight: 700 },
              onclick: function () { AP.haptic.tap(); lines = []; current = null; redraw(); } }, AP.icon('trash', 13), 'Clear')),
          h('div', { class: 'col', style: { flex: '1 1 auto', minHeight: 0, padding: '0 16px' } }, cv),
          submitted ? h('div', { class: 'center', style: { display: 'flex', padding: '18px 0' } }, kit.pill('Submitted! Watch the TV.', 'checkmark.circle.fill', C.green))
            : h('div', { style: { padding: '0 0 12px' } }, ui.ctlButton({ title: 'Submit Drawing', icon: 'paperplane.fill', tint: C.purple, onClick: function () {
                if (submitted) { return; }
                submittedRound = round;
                var w = Math.max(sizeCss.w, 1), hh = Math.max(sizeCss.h, 1);
                var enc = lines.map(function (ln) { return ln.map(function (p) { return [Math.round(p[0] / w * 1000) / 1000, Math.round(p[1] / hh * 1000) / 1000]; }); });
                ctx.send('drawing', { lines: enc, prompt: prompt });
                ctx.refresh();
              } })));
        ctx.after(30, redraw);
      }
      return ui.shell({ title: 'Speed Sculptor', subtitle: voting ? 'Vote: best ' + prompt : 'Draw: ' + prompt, secondsLeft: pd.int(d, 'secondsLeft') }, content);
    };
  };

  // ---- Tambola -----------------------------------------------------------------------
  AP.controllers.tambola = function (ctx) {
    return function (d) {
      var ticket = pd.arr(d, 'ticket').map(function (row) { return (Array.isArray(row) ? row : []).map(function (n) { return typeof n === 'number' ? Math.trunc(n) : null; }); });
      var marked = pd.arr(d, 'marked').filter(function (x) { return typeof x === 'number'; });
      var called = pd.arr(d, 'calledOnTicket').filter(function (x) { return typeof x === 'number'; });
      var last = typeof d.lastCalled === 'number' ? Math.trunc(d.lastCalled) : null;
      var score = pd.int(d, 'score');
      var prizes = pd.dicts(d, 'prizes').filter(function (p) { return typeof p.type === 'string'; })
        .map(function (p) { return { type: p.type, label: typeof p.label === 'string' ? p.label : p.type, winner: typeof p.winnerName === 'string' ? p.winnerName : null }; });

      var lastCard = last !== null ? kit.card(C.yellow, { cls: 'col center', style: { padding: '12px 0' } },
        h('div', { style: { fontSize: '12px', fontWeight: 800, letterSpacing: '2px', color: C.text3 } }, 'LAST CALLED'),
        h('div', { class: 'num', key: 'lc' + last, style: { fontSize: '58px', fontWeight: 900, lineHeight: 1.1, background: AP.grad([C.yellow, C.orange]),
            WebkitBackgroundClip: 'text', backgroundClip: 'text', color: 'transparent' } }, String(last))) : null;

      var grid = h('div', { class: 'col', style: { gap: '5px', padding: '10px', borderRadius: 'var(--r-card)', background: C.surface, border: '1px solid rgba(255,255,255,0.06)' } },
        ticket.map(function (row, ri) {
          return h('div', { key: 'r' + ri, style: { display: 'grid', gridTemplateColumns: 'repeat(' + Math.max(row.length, 1) + ', 1fr)', gap: '4px' } },
            row.map(function (n, ci) {
              if (n === null) { return h('div', { key: 'c' + ci, style: { height: '42px', borderRadius: '9px', background: 'rgba(255,255,255,0.03)' } }); }
              var m = marked.indexOf(n) >= 0, c = called.indexOf(n) >= 0;
              return h('button', { class: 'press', key: 'c' + ci,
                style: { appearance: 'none', height: '42px', padding: 0, borderRadius: '9px', fontSize: '16px', fontWeight: 800, color: m ? '#000' : '#fff',
                  background: m ? AP.grad([C.green, AP.alpha(C.green, 0.7)]) : C.surface2, border: (c && !m) ? '2px solid ' + C.yellow : '2px solid transparent' },
                onclick: function () { AP.haptic.tap(); ctx.send(m ? 'unmark' : 'mark', { number: n }); } }, String(n));
            }));
        }));

      var prizeGrid = h('div', { style: { display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '10px' } }, prizes.map(function (p) {
        var open = p.winner === null;
        return h('button', { class: 'press', key: 'pz' + p.type, disabled: !open,
          style: { appearance: 'none', border: 0, minHeight: '50px', padding: '0 6px', borderRadius: 'var(--r-chip)', fontSize: '15px', fontWeight: 800,
            color: open ? '#000' : C.text3, background: open ? AP.grad([C.yellow, C.orange]) : C.surface,
            display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: '2px' },
          onclick: function () { AP.haptic.thump(); ctx.send('claim', { type: p.type }); } },
          h('span', null, p.label), p.winner ? h('span', { style: { fontSize: '12px', fontWeight: 600 } }, 'won by ' + p.winner) : null);
      }));

      return ui.shell({ title: 'Tambola', subtitle: 'Score ' + score },
        h('div', { class: 'scroll' }, h('div', { class: 'col gap14', style: { padding: '14px 16px 24px' } },
          lastCard, h('div', { class: 'c-text2 txt-center', style: { fontSize: '14px' } }, 'Tap called numbers on your ticket'), grid, prizeGrid)));
    };
  };
})();
