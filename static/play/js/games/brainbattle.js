/* Brain Battle controller. Port of BrainBattleControllerView.swift.
 *
 * private_state (games/native_hub/engines/brain_battle.py): phase, round,
 * totalRounds, secondsLeft, kind, skill, prompt, options, visual, myAnswer,
 * locked, myScore, wasCorrect, pointsEarned, correctAnswer, isFastest, and at
 * the summary rank, brainTitle, brainScore, personalBest.
 */
(function () {
  'use strict';
  var AP = window.AP;
  var h = AP.h, C = AP.C, ui = AP.ui, kit = AP.kit, pd = AP.pd, waiting = AP.waiting;
  var TILES = ['#FF3D7F', '#3D8BFF', '#FFB020', '#22C77A'];
  var LETTERS = ['A', 'B', 'C', 'D'];
  function color(i) { return TILES[((i % 4) + 4) % 4]; }
  function letter(i) { return i >= 0 && i < 4 ? LETTERS[i] : String(i + 1); }

  function parseCells(v) {
    if (!Array.isArray(v)) { return []; }
    return v.filter(function (p) { return Array.isArray(p) && p.length >= 2 && typeof p[0] === 'number' && typeof p[1] === 'number'; })
      .map(function (p) { return [p[0], p[1]]; });
  }

  AP.controllers.brain_battle = function (ctx) {
    var pendingChoice = null, pendingPuzzle = '';
    var played = {};
    return function (d) {
      var phase = pd.str(d, 'phase'), puzzleID = pd.str(d, 'puzzleID');
      var round = pd.int(d, 'round'), totalRounds = pd.int(d, 'totalRounds', 12);
      var kind = pd.str(d, 'kind'), skill = pd.str(d, 'skill');
      var options = pd.strings(d, 'options');
      var myScore = pd.int(d, 'myScore');
      var myAnswer = typeof d.myAnswer === 'string' ? d.myAnswer : (pendingPuzzle === puzzleID ? pendingChoice : null);
      var locked = pd.bool(d, 'locked') || myAnswer !== null;
      var shapes = [];
      if (kind === 'rotation' && d.visual && Array.isArray(d.visual.choices)) { shapes = d.visual.choices.map(parseCells); }

      var subtitle = round <= 0 ? 'Get ready' : ('Round ' + round + ' of ' + totalRounds + (skill ? ' - ' + skill : ''));

      var scoreLine = h('div', { class: 'row gap10', style: { margin: '0 16px', padding: '12px 18px', borderRadius: 'var(--r-button)', background: C.surface } },
        h('span', { style: { color: C.yellow, display: 'inline-flex' } }, AP.icon('star.fill', 14)),
        h('span', { class: 'grow', style: { fontSize: '12px', fontWeight: 800, letterSpacing: '2px', color: C.text3 } }, 'SCORE'),
        h('span', { class: 'num', style: { fontSize: '22px', fontWeight: 800 } }, String(myScore)));

      function choose(opt) {
        if (locked) { return; }
        pendingChoice = opt; pendingPuzzle = puzzleID;
        AP.haptic.rigid();
        ctx.send('answer', { choice: opt });
        ctx.refresh();
      }

      var content;
      if (phase === 'memorize') {
        content = waiting('mem', 'eye.fill', 'Eyes on the TV!', 'Memorize the digits before they vanish.');
      } else if (phase === 'answer') {
        if (locked) {
          var answer = myAnswer || '';
          var idx = Math.max(options.indexOf(answer), 0);
          var tint = color(idx);
          content = h('div', { class: 'col center gap16 pop-in', key: 'locked', style: { padding: '24px', flex: '1 1 auto', justifyContent: 'center' } },
            h('div', { class: 'idle', style: { '--dy': '4px', '--sc': '0.03', '--dur': '1.6s' } },
              h('div', { style: { width: '100px', height: '100px', borderRadius: '50%', display: 'flex', alignItems: 'center', justifyContent: 'center',
                  background: AP.grad([AP.alpha(tint, 0.6), AP.alpha(tint, 0.25)]), boxShadow: '0 6px 16px ' + AP.alpha(tint, 0.4) } }, AP.icon('lock.fill', 44))),
            h('div', { style: { fontSize: '30px', fontWeight: 900 } }, 'Locked in'),
            h('div', { class: 'row gap12', style: { padding: '14px 22px', borderRadius: 'var(--r-button)', background: AP.grad([tint, AP.alpha(tint, 0.7)]),
                boxShadow: '0 6px 14px ' + AP.alpha(tint, 0.35) } },
              h('span', { style: { width: '44px', height: '44px', borderRadius: '50%', background: '#fff', color: tint, display: 'flex',
                  alignItems: 'center', justifyContent: 'center', fontSize: '26px', fontWeight: 900, flex: '0 0 auto' } }, letter(idx)),
              (kind === 'rotation' && idx < shapes.length)
                ? kit.shapeSvg(shapes[idx], '#ffffff', 2, 'width:120px;height:80px')
                : h('span', { style: { fontSize: '22px', fontWeight: 800 } }, answer)),
            h('div', { class: 'c-text2', style: { fontSize: '15px' } }, 'Waiting for everyone else...'));
        } else {
          var rows = [];
          for (var r = 0; r < Math.ceil(options.length / 2); r++) {
            rows.push(h('div', { class: 'row gap12', key: 'row' + r, style: { flex: '1 1 0', minHeight: '110px', alignItems: 'stretch' } },
              [r * 2, r * 2 + 1].map(function (i) { return i < options.length ? answerButton(i) : h('div', { class: 'grow' }); })));
          }
          content = h('div', { class: 'col gap12', key: 'answer', style: { flex: '1 1 auto', minHeight: 0, padding: '0 16px 20px' } },
            h('div', { class: 'c-text2 txt-center', style: { fontSize: '16px', fontWeight: 700 } },
              kind === 'rotation' ? 'Which shape is the first one turned?' : 'Pick your answer'), rows);
        }
      } else if (phase === 'reveal') {
        content = reveal();
      } else if (phase === 'summary' || phase === 'final') {
        content = finalCard();
      } else {
        content = waiting('ready', 'brain', 'Get ready', 'The first puzzle is on its way.');
      }

      function answerButton(i) {
        var c = color(i);
        var shape = i < shapes.length ? shapes[i] : [];
        var text = options[i];
        return h('button', { class: 'press grow', key: 'ab' + i,
          style: { appearance: 'none', border: '1.5px solid rgba(255,255,255,0.25)', borderRadius: 'var(--r-card)', color: '#fff', padding: '12px 0',
            background: AP.grad([c, AP.alpha(c, 0.65)]), boxShadow: '0 5px 12px ' + AP.alpha(c, 0.45),
            display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: '8px' },
          onclick: function () { choose(text); } },
          h('span', { style: { width: '38px', height: '38px', borderRadius: '50%', background: '#fff', color: c, display: 'flex',
              alignItems: 'center', justifyContent: 'center', fontSize: '22px', fontWeight: 900, flex: '0 0 auto' } }, letter(i)),
          shape.length ? kit.shapeSvg(shape, '#ffffff', 2, 'width:90%;height:70px;padding:0 10px')
            : h('span', { style: { fontSize: text.length > 14 ? '20px' : '26px', fontWeight: 700, padding: '0 8px', lineHeight: 1.1, textAlign: 'center' } }, text));
      }

      function reveal() {
        var was = typeof d.wasCorrect === 'boolean' ? d.wasCorrect : false;
        var answered = typeof d.myAnswer === 'string';
        var points = pd.int(d, 'pointsEarned');
        var fastest = pd.bool(d, 'isFastest');
        var ca = pd.str(d, 'correctAnswer');
        if (kind === 'rotation' && ca) { ca = 'Shape ' + ca; }
        var tint = was ? C.green : C.red;
        var key = 'reveal-' + puzzleID;
        if (!played[key]) { played[key] = 1; if (was) { AP.haptic.success(); } else { AP.haptic.error(); } }
        return h('div', { class: 'col center gap16', key: key, style: { padding: '24px', flex: '1 1 auto', justifyContent: 'center' } },
          h('div', { class: 'pop-in', style: { color: tint, filter: 'drop-shadow(0 0 18px ' + AP.alpha(tint, 0.6) + ')', display: 'inline-flex' } },
            AP.icon(was ? 'checkmark.circle.fill' : 'xmark.circle.fill', 96)),
          h('div', { style: { fontSize: '36px', fontWeight: 900 } }, was ? 'Correct!' : (answered ? 'Not quite' : 'Too slow!')),
          was ? h('div', { style: { fontSize: '44px', fontWeight: 800, color: tint } }, '+' + points) : null,
          fastest ? h('div', { class: 'row gap6', style: { padding: '8px 14px', borderRadius: '999px', background: C.yellow, color: '#000',
              fontSize: '14px', fontWeight: 800, letterSpacing: '1px' } }, AP.icon('bolt.fill', 14), 'FASTEST IN THE ROOM') : null,
          (!was && ca) ? h('div', { class: 'txt-center', style: { padding: '12px 18px', borderRadius: 'var(--r-button)', background: C.surface,
              fontSize: '20px', fontWeight: 800, color: 'rgba(255,255,255,0.85)' } }, 'Answer: ' + ca) : null);
      }

      function finalCard() {
        var rank = pd.int(d, 'rank');
        function stat(label, value) {
          return h('div', { class: 'col center gap4 grow', style: { padding: '14px 12px', borderRadius: 'var(--r-button)', background: C.surface } },
            h('div', { style: { fontSize: '30px', fontWeight: 800 } }, value),
            h('div', { style: { fontSize: '11px', fontWeight: 800, letterSpacing: '2px', color: C.text3, whiteSpace: 'nowrap' } }, label));
        }
        return h('div', { class: 'col center gap16 pop-in', key: 'final', style: { padding: '24px', flex: '1 1 auto', justifyContent: 'center' } },
          rank > 0 ? h('div', { style: { fontSize: '30px', fontWeight: 900, color: rank === 1 ? C.yellow : '#fff' } }, rank === 1 ? 'YOU WON!' : 'You placed #' + rank) : null,
          h('div', { class: 'idle', style: { '--dy': '4px', '--sc': '0.04', '--dur': '1.6s', color: C.pink } }, AP.icon('brain', 64)),
          h('div', { class: 'txt-center', style: { fontSize: '32px', fontWeight: 800 } }, pd.str(d, 'brainTitle', 'Brain in Training')),
          h('div', { class: 'row gap12 w100' }, stat('BRAIN SCORE', String(pd.int(d, 'brainScore'))), stat('POINTS', String(myScore))),
          pd.bool(d, 'personalBest') ? h('div', { class: 'row gap8', style: { padding: '10px 16px', borderRadius: '999px', background: C.green, color: '#000',
              fontSize: '17px', fontWeight: 800, boxShadow: '0 4px 10px ' + AP.alpha(C.green, 0.4) } }, AP.icon('star.fill', 16), 'New personal best!') : null);
      }

      return ui.shell({ title: 'Brain Battle', subtitle: subtitle, secondsLeft: phase === 'answer' ? pd.int(d, 'secondsLeft') : null },
        h('div', { class: 'col gap16', style: { flex: '1 1 auto', minHeight: 0, paddingTop: '12px' } }, scoreLine, content));
    };
  };
})();
