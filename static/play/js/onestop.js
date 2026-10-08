/* The host's one-stop lobby panels and the running Game Night.
 * Port of OneStop/GameNightViews.swift and OneStop/QuizMakerViews.swift.
 * Server: games/game_night.py, games/ai_decks.py and the start_night /
 * next_game / end_night / set_custom_questions handlers.
 */
(function () {
  'use strict';
  var AP = window.AP;
  var h = AP.h, C = AP.C, ui = AP.ui, kit = AP.kit, S = AP.S;

  var NIGHT = [C.purple, C.pink, C.orange];
  var QUIZ = [C.cyan, C.blue, C.indigo];

  function oneStopCard(tint, kids, o) {
    o = o || {};
    var el = h('div', { class: 'card-onestop', key: o.key, style: Object.assign({ '--tint': tint }, o.padding ? { padding: o.padding } : {}) });
    kids.forEach(function (k) { if (k) { el.appendChild(k); } });
    return el;
  }
  function secondary(title, icon, tint, onClick) {
    tint = tint || '#fff';
    return h('button', { class: 'press grow',
      style: { appearance: 'none', padding: '13px 8px', borderRadius: 'var(--r-button)', background: AP.alpha(tint, 0.08), border: '1px solid ' + AP.alpha(tint, 0.3),
        color: AP.alpha(tint, 0.9), fontSize: '16px', fontWeight: 700, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '8px', width: '100%' },
      onclick: function () { AP.haptic.tap(); onClick(); } }, AP.icon(icon, 15), title);
  }
  function toggle(on, tint, onChange) {
    return h('button', { class: 'switch' + (on ? ' on' : ''), style: { '--tint': tint }, 'aria-pressed': String(!!on),
      onclick: function () { AP.haptic.tap(); onChange(!on); } });
  }
  function gradIcon(icon, size) {
    return h('span', { style: { display: 'inline-flex', width: size + 'px', height: size + 'px', color: NIGHT[1] } }, AP.icon(icon, size));
  }
  function jsonFetch(url, opts) {
    return window.fetch(url, opts).then(function (r) { return r.ok ? r.json() : null; }).catch(function () { return null; });
  }

  // ---- Game Night planner (host, lobby, no night yet) -------------------------------
  var plan = { expanded: false, kids: false, minutes: 45, playlist: [], gameMinutes: {}, loading: false, reload: 0, starting: false, loadedKey: '' };

  function loadPlaylist(room) {
    var players = Math.max(1, room.players.length);
    var key = [plan.expanded, plan.kids, plan.minutes, players, plan.reload].join('-');
    if (key === plan.loadedKey) { return; }
    plan.loadedKey = key;
    if (!plan.expanded) { plan.loading = false; return; }
    plan.loading = true;
    jsonFetch('/api/picker?players=' + players + '&kids=' + (plan.kids ? '1' : '0')).then(function (data) {
      if (plan.loadedKey !== key) { return; }
      var out = [], lengths = {}, spent = 0;
      ((data && data.games) || []).forEach(function (p) {
        if (spent >= plan.minutes || out.length >= 8) { return; }
        if (!p || typeof p.id !== 'string' || out.indexOf(p.id) >= 0) { return; }
        out.push(p.id); lengths[p.id] = p.minutes; spent += p.minutes || 0;
      });
      plan.playlist = out; plan.gameMinutes = lengths; plan.loading = false;
      AP.changed();
    });
  }

  function planner(room) {
    loadPlaylist(room);
    var total = plan.playlist.reduce(function (a, g) { return a + (plan.gameMinutes[g] || 0); }, 0);
    var players = Math.max(1, room.players.length);
    var head = h('button', { class: 'press', style: { appearance: 'none', border: 0, background: 'none', width: '100%', display: 'flex', alignItems: 'center', gap: '12px', color: '#fff', padding: 0, textAlign: 'left' },
      onclick: function () { AP.haptic.tap(); plan.expanded = !plan.expanded; AP.changed(); } },
      gradIcon('moon.stars.fill', 26),
      h('span', { class: 'grow col gap4' }, h('span', { style: { fontSize: '17px', fontWeight: 800 } }, 'Game Night'),
        h('span', { style: { fontSize: '12px', color: 'rgba(255,255,255,0.55)', fontWeight: 500 } }, 'A playlist of games with one big scoreboard')),
      h('span', { style: { color: 'rgba(255,255,255,0.5)', display: 'inline-flex', transform: plan.expanded ? 'rotate(180deg)' : 'none', transition: 'transform .3s' } }, AP.icon('chevron.down', 15)));
    var body = null;
    if (plan.expanded) {
      var rows = plan.playlist.map(function (gid, i) {
        var g = AP.game(gid);
        return h('div', { class: 'row gap12', key: 'pl' + gid, style: { padding: '8px 12px', borderRadius: 'var(--r-chip)', background: 'rgba(255,255,255,0.05)' } },
          h('span', { style: { width: '22px', height: '22px', borderRadius: '50%', background: C.orange, color: '#000', fontSize: '12px', fontWeight: 800,
              display: 'flex', alignItems: 'center', justifyContent: 'center', flex: '0 0 auto' } }, String(i + 1)),
          h('span', { style: { width: '24px', display: 'inline-flex', justifyContent: 'center', color: 'rgba(255,255,255,0.85)' } }, AP.icon(g.icon, 18)),
          h('span', { class: 'grow', style: { fontSize: '15px', fontWeight: 700, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' } }, g.name),
          plan.gameMinutes[gid] ? h('span', { style: { fontSize: '12px', color: 'rgba(255,255,255,0.45)' } }, plan.gameMinutes[gid] + ' min') : null,
          plan.playlist.length > 1 ? h('button', { class: 'press', 'aria-label': 'Remove ' + g.name, style: { appearance: 'none', border: 0, background: 'none', padding: 0, color: 'rgba(255,255,255,0.3)', display: 'inline-flex' },
            onclick: function () { AP.haptic.tap(); plan.playlist = plan.playlist.filter(function (x) { return x !== gid; }); AP.changed(); } }, AP.icon('xmark.circle.fill', 18)) : null);
      });
      body = h('div', { class: 'col gap14 rise-in', key: 'planbody', style: { marginTop: '14px' } },
        h('div', { class: 'row gap12' },
          h('div', { class: 'grow col gap4' },
            h('span', { class: 'row gap8', style: { fontSize: '15px', fontWeight: 700, color: 'rgba(255,255,255,0.85)' } }, AP.icon('figure.and.child.holdinghands', 17), 'Kids learning mode'),
            h('span', { style: { fontSize: '12px', color: 'rgba(255,255,255,0.55)', fontWeight: 500 } }, 'Only quizzes, puzzles, words and brain games, with kid-level questions')),
          toggle(plan.kids, C.pink, function (v) { plan.kids = v; AP.changed(); })),
        h('div', { class: 'row gap8' }, h('span', { style: { color: 'rgba(255,255,255,0.5)', display: 'inline-flex' } }, AP.icon('clock.fill', 17)),
          [30, 45, 60].map(function (m) { return ui.cap({ title: m + ' min', selected: plan.minutes === m, tint: C.orange, onClick: function () { plan.minutes = m; AP.changed(); } }); })),
        h('div', { class: 'col gap8' },
          h('div', { class: 'row' }, h('span', { class: 'grow', style: { fontSize: '12px', fontWeight: 800, letterSpacing: '2px', color: 'rgba(255,255,255,0.5)' } }, "TONIGHT'S PLAYLIST"),
            plan.loading ? ui.spinner() : h('button', { class: 'press', style: { appearance: 'none', border: 0, background: 'none', color: C.orange, fontSize: '12px', fontWeight: 600, display: 'inline-flex', alignItems: 'center', gap: '4px' },
              onclick: function () { AP.haptic.tap(); plan.reload++; AP.changed(); } }, AP.icon('shuffle', 13), 'Shuffle')),
          (!plan.playlist.length && !plan.loading)
            ? h('div', { style: { fontSize: '13px', color: 'rgba(255,255,255,0.55)', fontWeight: 500 } }, 'The TV will pick a balanced mix for ' + players + ' player' + (players === 1 ? '' : 's') + ' when you start.')
            : [rows, total > 0 ? h('div', { style: { fontSize: '12px', color: 'rgba(255,255,255,0.45)', fontWeight: 500 } }, 'About ' + total + ' minutes, ' + plan.playlist.length + ' game' + (plan.playlist.length === 1 ? '' : 's')) : null]),
        ui.bigButton({ title: plan.starting ? 'Starting...' : 'Start Game Night', icon: 'sparkles', colors: [NIGHT[0], NIGHT[1]], enabled: !plan.starting && !plan.loading,
          onClick: function () {
            plan.starting = true;
            var payload = { roomCode: room.code, minutes: plan.minutes, kids: plan.kids };
            if (plan.playlist.length) { payload.playlist = plan.playlist.slice(); }
            AP.net.emit('start_night', payload);
            setTimeout(function () { plan.starting = false; AP.changed(); }, 4000);
            AP.changed();
          } }));
    }
    return oneStopCard(C.purple, [head, body], { key: 'planner' });
  }

  // ---- Running night: pieces -------------------------------------------------------------
  function gameIcon(gid) { return AP.game(gid).icon; }

  function standingsList(standings, limit, myID) {
    return h('div', { class: 'col gap6' }, standings.slice(0, limit).map(function (row) {
      var me = row.playerID === myID;
      return h('div', { class: 'row gap10', key: 'sd' + row.playerID, style: { padding: '7px 12px', borderRadius: 'var(--r-chip)', background: me ? AP.alpha(C.cyan, 0.12) : 'rgba(255,255,255,0.04)' } },
        h('span', { style: { width: '24px', height: '24px', borderRadius: '50%', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: '12px', fontWeight: 800,
            color: row.rank <= 3 ? '#000' : 'rgba(255,255,255,0.7)', background: AP.rankColor(row.rank), flex: '0 0 auto' } }, String(row.rank)),
        h('span', { style: { fontSize: '15px', fontWeight: me ? 700 : 400, color: me ? C.cyan : '#fff', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' } }, row.name),
        row.isBot ? h('span', { style: { fontSize: '11px', color: C.orange } }, 'BOT') : null,
        me ? h('span', { style: { fontSize: '11px', fontWeight: 800, color: C.cyan } }, 'YOU') : null,
        h('span', { class: 'spacer' }),
        h('span', { class: 'num', style: { fontSize: '15px', fontWeight: 700 } }, row.points + ' pts'));
    }).concat(standings.length > limit ? [h('div', { class: 'txt-center', style: { fontSize: '11px', color: 'rgba(255,255,255,0.4)' } }, '+ ' + (standings.length - limit) + ' more')] : []));
  }

  function championBanner(st) {
    return h('div', { class: 'row gap14', style: { padding: '14px', borderRadius: 'var(--r-button)', background: AP.grad([AP.alpha(C.yellow, 0.25), AP.alpha(C.orange, 0.12)]) } },
      h('span', { class: 'pulse', style: { color: C.yellow, display: 'inline-flex', filter: 'drop-shadow(0 0 8px ' + AP.alpha(C.yellow, 0.7) + ')' } }, AP.icon('crown.fill', 30)),
      h('div', { class: 'col gap4' },
        h('span', { style: { fontSize: '11px', fontWeight: 800, letterSpacing: '2px', color: AP.alpha(C.yellow, 0.8) } }, 'CHAMPION'),
        h('span', { style: { fontSize: '22px', fontWeight: 800 } }, st.name),
        h('span', { style: { fontSize: '12px', color: 'rgba(255,255,255,0.6)' } }, st.points + ' night points')));
  }

  function gameRow(label, gid, highlight) {
    return h('div', { class: 'row gap12' },
      h('span', { style: { width: '40px', height: '40px', borderRadius: 'var(--r-chip)', display: 'flex', alignItems: 'center', justifyContent: 'center', flex: '0 0 auto',
          background: highlight ? AP.grad(NIGHT) : 'rgba(255,255,255,0.08)' } }, AP.icon(gameIcon(gid), 20)),
      h('div', { class: 'col gap4' }, h('span', { style: { fontSize: '11px', fontWeight: 800, letterSpacing: '1.5px', color: 'rgba(255,255,255,0.5)' } }, label),
        h('span', { style: { fontSize: '15px', fontWeight: 800 } }, AP.game(gid).name)));
  }

  function playlistStrip(night) {
    return h('div', { class: 'hscroll', style: { padding: '4px 2px' } }, night.playlist.map(function (gid, i) {
      var done = i < night.index, cur = i === night.index;
      return h('span', { key: 'st' + i, style: { width: '30px', height: '30px', borderRadius: '50%', display: 'flex', alignItems: 'center', justifyContent: 'center', flex: '0 0 auto',
          color: cur ? '#000' : 'rgba(255,255,255,' + (done ? 0.4 : 0.8) + ')', background: cur ? C.orange : 'rgba(255,255,255,' + (done ? 0.04 : 0.1) + ')',
          border: (cur || done) ? '1px solid transparent' : '1px solid ' + AP.alpha(C.orange, 0.3), transform: cur ? 'scale(1.12)' : 'none', transition: 'transform .4s var(--pop)' } },
        AP.icon(gameIcon(gid), 14));
    }));
  }

  function endConfirm(room) {
    ui.confirm({ title: 'End Game Night now? The scoreboard is cleared for everyone.', confirmTitle: 'End night',
      onConfirm: function () { AP.net.emit('end_night', { roomCode: room.code }); } });
  }

  function nightStatus(room) {
    var night = room.night, host = AP.isHost();
    var nextId = night.next;
    var kids = [
      h('div', { class: 'row gap10' }, gradIcon(night.finished ? 'crown.fill' : 'moon.stars.fill', 26),
        h('div', { class: 'col gap4' }, h('span', { style: { fontSize: '17px', fontWeight: 800 } }, night.finished ? 'Game Night is over' : 'Game Night'),
          h('span', { style: { fontSize: '12px', color: 'rgba(255,255,255,0.55)', fontWeight: 500 } },
            night.finished ? (night.gamesPlayed === 1 ? '1 game played' : night.gamesPlayed + ' games played')
              : 'Game ' + Math.min(night.index + 1, night.playlist.length) + ' of ' + night.playlist.length)))
    ];
    if (night.finished) { if (night.standings.length) { kids.push(championBanner(night.standings[0])); } }
    else {
      kids.push(playlistStrip(night));
      kids.push(h('div', { class: 'col gap8' },
        night.current ? gameRow('UP NOW', night.current, true) : null,
        nextId ? gameRow('THEN', nextId, false) : (night.current ? h('div', { style: { fontSize: '12px', fontWeight: 600, color: C.orange } }, 'Last game of the night') : null)));
    }
    if (night.standings.length) { kids.push(standingsList(night.standings, night.finished ? 8 : 5, S.playerID)); }
    if (host) {
      if (night.finished) { kids.push(h('div', { class: 'row' }, secondary('Close Game Night', 'xmark.circle', C.pink, function () { AP.net.emit('end_night', { roomCode: room.code }); }))); }
      else {
        kids.push(h('div', { class: 'row gap10' },
          secondary(night.next ? 'Skip game' : 'Finish night', 'forward.fill', C.orange, function () { AP.net.emit('next_game', { roomCode: room.code }); }),
          secondary('End night', 'stop.fill', C.pink, function () { endConfirm(room); })));
      }
    }
    var el = oneStopCard(C.purple, [], { key: 'nightstatus' });
    kids.forEach(function (k) { if (k) { el.appendChild(k); } });
    el.style.display = 'flex'; el.style.flexDirection = 'column'; el.style.gap = '14px';
    return el;
  }

  var sent = false;
  function nightResultsPanel(room) {
    var night = room.night, host = AP.isHost();
    var next = night.next;
    var kids = [h('div', { class: 'row gap8' }, gradIcon(night.finished ? 'crown.fill' : 'moon.stars.fill', 20),
      h('span', { class: 'grow', style: { fontSize: '15px', fontWeight: 800 } }, night.finished ? 'Game Night champion' : 'Game Night standings'),
      h('span', { class: 'num', style: { fontSize: '12px', color: 'rgba(255,255,255,0.5)' } }, night.gamesPlayed + '/' + night.playlist.length))];
    if (night.finished && night.standings.length) { kids.push(championBanner(night.standings[0])); }
    if (night.standings.length) { kids.push(standingsList(night.standings, night.finished ? 5 : 3, S.playerID)); }
    if (host) {
      if (night.finished) {
        kids.push(ui.bigButton({ title: 'Close Game Night', icon: 'checkmark.circle.fill', colors: [NIGHT[0], NIGHT[1]], onClick: function () { AP.net.emit('end_night', { roomCode: room.code }); } }));
      } else {
        kids.push(ui.bigButton({ title: next ? 'Next game: ' + AP.game(next).name : 'Crown the champion', icon: 'forward.fill', colors: [NIGHT[0], NIGHT[1]], enabled: !sent,
          onClick: function () { sent = true; AP.net.emit('next_game', { roomCode: room.code }); setTimeout(function () { sent = false; AP.changed(); }, 3000); AP.changed(); } }));
        kids.push(h('button', { class: 'press', style: { appearance: 'none', border: 0, background: 'none', color: 'rgba(255,255,255,0.55)', fontSize: '13px', fontWeight: 600 },
          onclick: function () { AP.haptic.tap(); endConfirm(room); } }, 'End night early'));
      }
    } else if (!night.finished) {
      kids.push(h('div', { class: 'row', style: { justifyContent: 'center', gap: '8px' } }, ui.spinner(),
        h('span', { style: { fontSize: '13px', color: 'rgba(255,255,255,0.6)' } }, next ? 'Next up: ' + AP.game(next).name : 'Waiting for the host')));
    }
    var el = oneStopCard(C.purple, [], { key: 'nightresults', padding: '14px' });
    kids.forEach(function (k) { if (k) { el.appendChild(k); } });
    el.style.display = 'flex'; el.style.flexDirection = 'column'; el.style.gap = '12px';
    return el;
  }

  // ---- Make-your-own quiz ----------------------------------------------------------------------
  var quiz = { open: false, stage: 'compose', topic: '', count: 10, familySafe: true, language: 'en', drafts: [], expanded: null, slow: false, retrying: false,
    loadedCount: 0, loadedTopic: '', token: 0, error: '' };
  var draftSeq = 0;
  var makerEl = null;
  var SUGGESTIONS = ['Cricket', 'Bollywood 90s', 'Space', 'Telugu cinema', 'Animals', 'World capitals', 'Food', 'Science'];
  var LETTERS = ['A', 'B', 'C', 'D'];

  function mkDraft(q) {
    var opts = (q.options || []).slice(0, 4); while (opts.length < 4) { opts.push(''); }
    return { id: ++draftSeq, question: q.question || '', options: opts, correct: (q.correct_answer >= 0 && q.correct_answer <= 3) ? q.correct_answer : 0 };
  }
  function asQuestion(d) {
    return { question: d.question.trim(), options: d.options.map(function (o) { return o.trim(); }), correct_answer: d.correct };
  }
  function complete(d) {
    var q = asQuestion(d);
    var uniq = {}; q.options.forEach(function (o) { uniq[o.toLowerCase()] = 1; });
    return q.question.length > 0 && q.options.length === 4 && q.options.every(function (o) { return o.length > 0; }) && Object.keys(uniq).length === 4 && q.correct_answer >= 0 && q.correct_answer <= 3;
  }

  function quizMaker(room) {
    var kids = [];
    kids.push(h('div', { class: 'row gap12' },
      h('span', { style: { color: QUIZ[0], display: 'inline-flex' } }, AP.icon('wand.and.stars', 26)),
      h('div', { class: 'col gap4' }, h('span', { style: { fontSize: '17px', fontWeight: 800 } }, 'Make a quiz'),
        h('span', { style: { fontSize: '12px', color: 'rgba(255,255,255,0.55)', fontWeight: 500 } },
          room.gameID === 'trivia' ? 'Any topic. Your questions play first.' : 'Any topic. Your questions play first in Trivia.'))));
    if (quiz.loadedCount > 0) {
      var noun = quiz.loadedCount === 1 ? 'question' : 'questions';
      kids.push(h('div', { class: 'row gap8 pop-in', key: 'loaded', style: { padding: '10px', borderRadius: 'var(--r-chip)', background: AP.alpha(C.green, 0.12) } },
        h('span', { style: { color: C.green, display: 'inline-flex' } }, AP.icon('checkmark.seal.fill', 17)),
        h('span', { class: 'grow', style: { fontSize: '13px', fontWeight: 600, color: 'rgba(255,255,255,0.85)' } },
          quiz.loadedTopic ? quiz.loadedCount + ' ' + noun + ' on ' + quiz.loadedTopic + ' loaded' : quiz.loadedCount + ' custom ' + noun + ' loaded'),
        h('button', { class: 'press', style: { appearance: 'none', border: 0, background: 'none', color: C.pink, fontSize: '12px', fontWeight: 700 },
          onclick: function () { AP.haptic.tap(); AP.net.emit('set_custom_questions', { roomCode: room.code, questions: [] }); quiz.loadedCount = 0; quiz.loadedTopic = ''; AP.changed(); } }, 'Clear')));
    }
    kids.push(secondary(quiz.loadedCount > 0 ? 'Make another quiz' : 'Write a quiz with AI', 'sparkles', C.cyan, function () { openMaker(room); }));
    var el = oneStopCard(C.cyan, [], { key: 'quizcard' });
    kids.forEach(function (k) { el.appendChild(k); });
    el.style.display = 'flex'; el.style.flexDirection = 'column'; el.style.gap = '12px';
    return el;
  }

  function openMaker(room) {
    quiz.open = true; quiz.stage = 'compose'; quiz.roomCode = room.code;
    if (!makerEl) { makerEl = h('div', { class: 'maker' }); document.getElementById('app').appendChild(makerEl); }
    renderMaker();
  }
  function closeMaker() {
    quiz.open = false; quiz.token++;
    if (makerEl && makerEl.parentNode) { makerEl.parentNode.removeChild(makerEl); }
    makerEl = null;
  }
  function label(t) { return h('div', { style: { fontSize: '12px', fontWeight: 800, letterSpacing: '2px', color: 'rgba(255,255,255,0.5)' } }, t); }

  function renderMaker() {
    if (!quiz.open || !makerEl) { return; }
    var body;
    var topic = quiz.topic.trim();
    if (quiz.stage === 'compose') {
      body = h('div', { class: 'scroll', key: 'compose' }, h('div', { class: 'col gap20', style: { padding: '20px' } },
        h('div', { class: 'col gap8' }, label('TOPIC'),
          h('input', { class: 'answer-field', key: 'topic', type: 'text', placeholder: 'e.g. Tollywood 2000s', value: quiz.topic, maxlength: 80, autocomplete: 'off',
            style: { fontSize: '20px', padding: '14px', borderRadius: 'var(--r-chip)' },
            oninput: function (ev) { quiz.topic = ev.target.value.slice(0, 80); renderMaker(); },
            onkeydown: function (ev) { if (ev.key === 'Enter') { generate(); } } }),
          h('div', { class: 'hscroll' }, SUGGESTIONS.map(function (s) { return ui.cap({ title: s, selected: topic === s, tint: C.cyan, onClick: function () { quiz.topic = s; renderMaker(); } }); }))),
        oneStopCard(C.purple, [h('div', { class: 'col gap14' },
          h('div', { class: 'row gap8' }, h('span', { class: 'grow' }, label('QUESTIONS')),
            [5, 10, 15].map(function (c) { return ui.cap({ title: String(c), selected: quiz.count === c, tint: C.purple, onClick: function () { quiz.count = c; renderMaker(); } }); })),
          h('div', { style: { height: '1px', background: 'rgba(255,255,255,0.1)' } }),
          h('div', { class: 'col gap8' }, label('LANGUAGE'), h('div', { class: 'row gap8' },
            [['en', 'English'], ['te', 'Telugu'], ['hi', 'Hindi']].map(function (p) { return ui.cap({ title: p[1], selected: quiz.language === p[0], tint: C.orange, onClick: function () { quiz.language = p[0]; renderMaker(); } }); }))),
          h('div', { style: { height: '1px', background: 'rgba(255,255,255,0.1)' } }),
          h('div', { class: 'row' }, h('span', { class: 'grow row gap8', style: { fontSize: '15px', fontWeight: 700, color: 'rgba(255,255,255,0.85)' } }, AP.icon('figure.2.and.child.holdinghands', 17), 'Family safe'),
            toggle(quiz.familySafe, C.green, function (v) { quiz.familySafe = v; renderMaker(); })))]),
        ui.bigButton({ title: 'Write my quiz', icon: 'wand.and.stars', colors: [QUIZ[0], QUIZ[1]], enabled: topic.length > 0, onClick: generate }),
        h('div', { class: 'txt-center', style: { fontSize: '12px', color: 'rgba(255,255,255,0.4)' } }, 'The first request can take up to a minute while the server wakes up.')));
    } else if (quiz.stage === 'loading') {
      body = h('div', { class: 'col center gap20 txt-center', key: 'loading', style: { flex: '1 1 auto', justifyContent: 'center', padding: '28px' } },
        h('span', { class: 'pulse', style: { color: QUIZ[0], display: 'inline-flex' } }, AP.icon('wand.and.stars', 64)),
        h('div', { style: { fontSize: '20px', fontWeight: 700 } }, 'Writing ' + quiz.count + ' questions about ' + topic), ui.spinner(),
        quiz.slow ? h('div', { style: { fontSize: '14px', color: 'rgba(255,255,255,0.6)' } }, quiz.retrying ? 'Almost there. The server just woke up, asking again.'
          : 'The server is waking up. This can take up to a minute the first time.') : null,
        h('div', { class: 'w100', style: { paddingTop: '30px' } }, secondary('Cancel', 'xmark', '#fff', function () { quiz.token++; quiz.stage = 'compose'; renderMaker(); })));
    } else if (quiz.stage === 'failed') {
      body = h('div', { class: 'col center gap20 txt-center', key: 'failed', style: { flex: '1 1 auto', justifyContent: 'center', padding: '28px' } },
        h('span', { style: { color: C.orange, display: 'inline-flex' } }, AP.icon('cloud.drizzle.fill', 56)),
        h('div', { style: { fontSize: '20px', fontWeight: 700 } }, 'No questions this time'),
        h('div', { style: { fontSize: '14px', color: 'rgba(255,255,255,0.65)' } }, quiz.error),
        h('div', { class: 'col gap10 w100', style: { paddingTop: '20px' } }, ui.bigButton({ title: 'Try again', icon: 'arrow.clockwise', colors: [QUIZ[0], QUIZ[1]], onClick: generate }),
          secondary('Change topic', 'pencil', '#fff', function () { quiz.stage = 'compose'; renderMaker(); })));
    } else {
      var ready = quiz.drafts.filter(complete).length;
      body = h('div', { class: 'col', key: 'preview', style: { flex: '1 1 auto', minHeight: 0 } },
        h('div', { class: 'scroll' }, h('div', { class: 'col gap12', style: { padding: '20px' } },
          h('div', { class: 'col gap4' }, h('span', { style: { fontSize: '20px', fontWeight: 800 } }, topic),
            h('span', { style: { fontSize: '12px', color: 'rgba(255,255,255,0.55)' } }, 'Tap a question to edit it. Tap an answer to mark it correct.')),
          quiz.drafts.map(function (d, i) { return draftCard(d, i + 1); }),
          quiz.drafts.length ? null : h('div', { class: 'txt-center', style: { fontSize: '13px', color: 'rgba(255,255,255,0.55)', paddingTop: '20px' } }, 'All questions deleted. Start over to write a new set.'))),
        h('div', { class: 'col gap10', style: { padding: '12px 20px calc(16px + var(--safe-bottom))', background: 'rgba(11,11,18,0.96)' } },
          ready < quiz.drafts.length ? h('div', { class: 'txt-center', style: { fontSize: '12px', color: C.orange } },
            (quiz.drafts.length - ready) + ' unfinished question' + (quiz.drafts.length - ready === 1 ? '' : 's') + ' will be skipped.') : null,
          ui.bigButton({ title: ready === 1 ? 'Use this question' : 'Use these ' + ready + ' questions', icon: 'paperplane.fill', colors: [C.green, C.cyan], enabled: ready > 0,
            onClick: function () {
              var qs = quiz.drafts.filter(complete).map(asQuestion);
              if (!qs.length) { return; }
              AP.net.emit('set_custom_questions', { roomCode: quiz.roomCode, questions: qs });
              quiz.loadedCount = qs.length; quiz.loadedTopic = topic;
              closeMaker(); AP.changed();
            } }),
          h('button', { class: 'press', style: { appearance: 'none', border: 0, background: 'none', color: 'rgba(255,255,255,0.55)', fontSize: '13px', fontWeight: 600 },
            onclick: function () { AP.haptic.tap(); quiz.stage = 'compose'; renderMaker(); } }, 'Start over')));
    }
    AP.patch(makerEl, [
      h('div', { class: 'maker-bar', key: 'bar' }, h('span', { style: { width: '60px' } }), h('span', { class: 't' }, 'Make a quiz'),
        h('button', { class: 'btn-pill press', onclick: function () { AP.haptic.tap(); closeMaker(); } }, 'Close')),
      body]);
  }

  function draftCard(d, number) {
    var open = quiz.expanded === d.id, ok = complete(d);
    var tint = ok ? C.cyan : C.orange;
    var correctText = (d.options[d.correct] || '').trim() || 'No answer marked';
    var head = h('button', { class: 'press', style: { appearance: 'none', border: 0, background: 'none', color: '#fff', width: '100%', textAlign: 'left', padding: 0, display: 'flex', alignItems: 'flex-start', gap: '12px' },
      onclick: function () { AP.haptic.tap(); quiz.expanded = open ? null : d.id; renderMaker(); } },
      h('span', { style: { width: '26px', height: '26px', borderRadius: '50%', background: tint, color: '#000', fontSize: '12px', fontWeight: 800, display: 'flex', alignItems: 'center', justifyContent: 'center', flex: '0 0 auto' } }, String(number)),
      h('span', { class: 'grow col gap4' }, h('span', { style: { fontSize: '15px', fontWeight: 700 } }, d.question || 'Untitled question'),
        open ? null : h('span', { class: 'row gap6', style: { fontSize: '12px', color: C.green } }, AP.icon('checkmark.circle.fill', 13), correctText)),
      h('span', { style: { color: 'rgba(255,255,255,0.45)', display: 'inline-flex', transform: open ? 'rotate(180deg)' : 'none', transition: 'transform .3s' } }, AP.icon('chevron.down', 13)));
    var editor = open ? h('div', { class: 'col gap10', key: 'ed' + d.id, style: { marginTop: '12px' } },
      h('textarea', { class: 'textarea', rows: 3, key: 'q' + d.id, value: d.question, placeholder: 'Question', oninput: function (ev) { d.question = ev.target.value; } }),
      [0, 1, 2, 3].map(function (i) {
        var isC = d.correct === i;
        return h('div', { class: 'row gap10', key: 'o' + d.id + i },
          h('button', { class: 'press', 'aria-label': 'Mark option ' + LETTERS[i] + ' correct', style: { appearance: 'none', border: 0, width: '30px', height: '30px', borderRadius: '50%', flex: '0 0 auto',
              background: isC ? C.green : 'rgba(255,255,255,0.08)', color: isC ? '#000' : 'rgba(255,255,255,0.7)', fontSize: '12px', fontWeight: 700, display: 'flex', alignItems: 'center', justifyContent: 'center' },
            onclick: function () { AP.haptic.tap(); d.correct = i; renderMaker(); } }, isC ? AP.icon('checkmark', 13) : LETTERS[i]),
          h('input', { class: 'input-sm', key: 'oi' + d.id + i, type: 'text', placeholder: 'Option ' + LETTERS[i], value: d.options[i], style: { background: isC ? AP.alpha(C.green, 0.15) : 'rgba(255,255,255,0.05)' },
            oninput: function (ev) { d.options[i] = ev.target.value.slice(0, 80); } }));
      }),
      h('div', { class: 'row' }, ok ? null : h('span', { class: 'row gap6 grow', style: { fontSize: '11px', color: C.orange } }, AP.icon('exclamationmark.triangle.fill', 12), 'Needs a question and 4 different answers'),
        h('span', { class: 'spacer' }),
        h('button', { class: 'press', style: { appearance: 'none', border: 0, background: 'none', color: C.pink, fontSize: '12px', fontWeight: 600, display: 'inline-flex', alignItems: 'center', gap: '4px' },
          onclick: function () { AP.haptic.warning(); quiz.drafts = quiz.drafts.filter(function (x) { return x.id !== d.id; }); if (quiz.expanded === d.id) { quiz.expanded = null; } renderMaker(); } },
          AP.icon('trash', 13), 'Delete'))) : null;
    return oneStopCard(tint, [head, editor], { key: 'dr' + d.id, padding: '14px' });
  }

  function generate() {
    var topic = quiz.topic.trim();
    if (!topic) { return; }
    var token = ++quiz.token;
    quiz.stage = 'loading'; quiz.slow = false; quiz.retrying = false;
    renderMaker();
    var started = Date.now();
    var slowTimer = setTimeout(function () { if (quiz.token === token) { quiz.slow = true; renderMaker(); } }, 7000);
    function request() {
      return jsonFetch('/api/decks/generate', { method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ kind: 'quiz', topic: topic, count: quiz.count, familySafe: quiz.familySafe, language: quiz.language }) })
        .then(function (data) { return ((data && data.items) || []).map(function (q) { return mkDraft(q); }).filter(complete); });
    }
    request().then(function (items) {
      if (quiz.token !== token) { return null; }
      if (!items.length && Date.now() - started > 15000) { quiz.slow = true; quiz.retrying = true; renderMaker(); return request(); }
      return items;
    }).then(function (items) {
      clearTimeout(slowTimer);
      if (items === null || quiz.token !== token) { return; }
      if (!items.length) {
        quiz.error = 'The quiz writer did not answer. The server may still be waking up, or AI questions are switched off. Wait a moment and try again, or try a different topic.';
        quiz.stage = 'failed';
      } else { quiz.drafts = items; quiz.expanded = null; quiz.stage = 'preview'; }
      renderMaker();
    });
  }

  AP.lobbyExtras = { planner: planner, quizMaker: quizMaker, nightStatus: nightStatus };
  AP.nightResultsPanel = nightResultsPanel;
})();
