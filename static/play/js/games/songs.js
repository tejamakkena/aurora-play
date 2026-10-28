/* Never Have I Ever and Guess the Song. Port of NeverHaveIEverControllerView.swift
 * and GuessTheSongControllerView.swift. Server: games/native_hub/engines/
 * never_have_i_ever.py and guess_the_song.py.
 */
(function () {
  'use strict';
  var AP = window.AP;
  var h = AP.h, C = AP.C, ui = AP.ui, pd = AP.pd;

  var waiting = AP.waiting, promptCard = AP.promptCard;

  function body(kids) { return h('div', { class: 'col gap16', style: { flex: '1 1 auto', minHeight: 0 } }, kids); }

  // ---- Never Have I Ever ----------------------------------------------------------
  AP.controllers.never_have_i_ever = function (ctx) {
    return function (d) {
      var phase = pd.str(d, 'phase', 'answer');
      var statement = pd.str(d, 'statement');
      var mine = pd.str(d, 'myChoice');
      var isHost = pd.bool(d, 'isHost');
      var packs = pd.dicts(d, 'packChoices');
      var content;
      if (phase === 'pack') {
        if (isHost) {
          content = h('div', { class: 'scroll pop-in', key: 'packs' },
            h('div', { class: 'col gap10', style: { padding: '0 20px 20px' } }, packs.map(function (p) {
              return ui.choiceRow({ text: pd.str(p, 'name'),
                detail: (p.adult === true ? '18+  ' : '') + pd.str(p, 'blurb'),
                onClick: function () { AP.haptic.tap(); ctx.send('choose_pack', { pack: pd.str(p, 'id') }); } });
            })));
        } else {
          content = waiting('pack-wait', 'shuffle', 'The host is choosing a pack', 'Get ready to be honest');
        }
      } else if (phase === 'answer') {
        if (mine) {
          content = waiting('locked', 'checkmark.circle.fill', mine === 'have' ? 'You have' : 'Never',
            'Locked in. Waiting for the others...');
        } else {
          content = h('div', { class: 'col gap14 pop-in', key: 'pad', style: { padding: '0 20px 24px' } },
            promptCard(statement, 'Never have I ever...', C.orange),
            h('button', { class: 'press', key: 'have', style: { appearance: 'none', minHeight: '110px', borderRadius: 'var(--r-card)',
                color: '#000', fontSize: '28px', fontWeight: 900, background: C.orange, border: 0 },
              onclick: function () { AP.haptic.tap(); ctx.send('answer', { choice: 'have' }); } }, 'I have'),
            h('button', { class: 'press', key: 'never', style: { appearance: 'none', minHeight: '110px', borderRadius: 'var(--r-card)',
                color: '#000', fontSize: '28px', fontWeight: 900, background: C.cyan, border: 0 },
              onclick: function () { AP.haptic.tap(); ctx.send('answer', { choice: 'never' }); } }, 'Never'));
        }
      } else {
        content = waiting('reveal', 'tv', 'Look at the TV', mine === 'have' ? 'You owned up to that one' : 'You kept it to yourself');
      }
      return ui.shell({ title: 'Never Have I Ever',
          subtitle: phase === 'pack' ? (isHost ? 'Pick a pack' : 'The host is picking a pack')
            : phase === 'answer' ? 'Answer honestly. Nobody sees until the reveal.' : 'The reveal',
          secondsLeft: pd.int(d, 'secondsLeft') },
        body([content]));
    };
  };

  // ---- Guess the Song ---------------------------------------------------------------
  AP.controllers.guess_the_song = function (ctx) {
    return function (d) {
      var phase = pd.str(d, 'phase', 'guess');
      var word = pd.str(d, 'word');
      var isJudge = pd.bool(d, 'isJudge');
      var isGuesser = pd.bool(d, 'isGuesser');
      var answers = pd.strings(d, 'answers');
      var hint = typeof d.hint === 'string' ? d.hint : null;
      var hindi = typeof d.hindi === 'string' ? d.hindi : null;
      var judgeName = pd.str(d, 'judgeName', 'The judge');
      var team = d.activeTeam && typeof d.activeTeam === 'object' ? d.activeTeam : {};
      var teamName = typeof team.name === 'string' ? team.name : 'Everyone';
      var content;

      if (phase === 'reveal') {
        var guessed = pd.str(d, 'outcome') === 'guessed';
        content = h('div', { class: 'scroll pop-in', key: 'rev' },
          h('div', { class: 'col gap14 txt-center', style: { padding: '24px 24px 28px' } },
            h('div', { style: { fontSize: '34px', fontWeight: 900, color: guessed ? C.green : C.red } }, guessed ? 'Good job!' : 'Not guessed'),
            h('div', { class: 'c-text2', style: { fontWeight: 700 } }, word),
            (!guessed && answers.length) ? h('div', { class: 'col gap8' },
              h('div', { style: { fontSize: '12px', fontWeight: 800, letterSpacing: '3px', color: C.text2 } }, 'IT COULD HAVE BEEN'),
              answers.map(function (s) { return h('div', { style: { fontWeight: 700 } }, s); })) : null,
            h('div', { style: { fontSize: '18px', fontWeight: 800, color: C.yellow } }, pd.str(d, 'humor')),
            h('div', { class: 'c-text2', style: { fontSize: '14px' } }, pd.str(d, 'filler'))));
      } else {
        var kids = [promptCard(word, 'Name a song with...', C.pink),
          h('div', { class: 'txt-center c-text2', style: { fontSize: '13px', padding: '0 24px' } },
            'its Hindi meaning, the word in the title, or in the scene')];
        if (hint) { kids.push(h('div', { class: 'txt-center', style: { fontWeight: 800, color: C.yellow, fontSize: '20px' } }, 'Hindi: ' + hint)); }
        if (phase === 'verdict') {
          kids.push(h('div', { class: 'txt-center', style: { fontWeight: 800, color: C.orange } },
            'Time is up! ' + (isJudge ? 'Your call.' : 'Waiting for ' + judgeName + '...')));
        }
        if (isJudge) {
          kids.push(h('div', { class: 'col gap8', style: { margin: '0 20px', padding: '16px', borderRadius: 'var(--r-card)', background: C.surface } },
            h('div', { style: { fontSize: '12px', fontWeight: 800, letterSpacing: '3px', color: C.text2 } }, 'ANY OF THESE COUNTS'),
            answers.map(function (s) { return h('div', { style: { fontWeight: 700 } }, s); }),
            h('div', { class: 'c-text2', style: { fontSize: '12px' } }, 'Other songs that fit are fair game too.')));
          if (!hint && hindi && phase === 'guess') {
            kids.push(ui.ctlButton({ title: 'Give the Hindi hint (' + hindi + ')', icon: 'lightbulb.fill', tint: C.yellow,
              onClick: function () { ctx.send('hint', {}); } }));
          }
          kids.push(ui.ctlButton({ title: 'Guessed!', icon: 'checkmark.circle.fill', tint: C.green,
            onClick: function () { ctx.send('judge', { result: 'guessed' }); } }));
          kids.push(ui.ctlButton({ title: 'Not guessed', icon: 'xmark.circle.fill', tint: C.red,
            onClick: function () { ctx.send('judge', { result: 'missed' }); } }));
        } else if (isGuesser) {
          kids.push(h('div', { class: 'txt-center', style: { fontWeight: 700, color: C.cyan } },
            judgeName + ' is judging. Say your answers out loud.'));
        } else {
          kids.push(h('div', { class: 'txt-center c-text2', style: { fontWeight: 700 } }, 'Listen in. ' + teamName + ' is guessing.'));
        }
        content = h('div', { class: 'scroll pop-in', key: 'play' }, h('div', { class: 'col gap14', style: { paddingBottom: '24px' } }, kids));
      }
      return ui.shell({ title: 'Guess the Song',
          subtitle: phase === 'reveal' ? 'The verdict' : isJudge ? "You're the judge"
            : isGuesser ? 'Your turn. Shout a song!' : teamName + ' is guessing',
          secondsLeft: phase === 'reveal' ? 0 : pd.int(d, 'secondsLeft') },
        body([content]));
    };
  };
})();
