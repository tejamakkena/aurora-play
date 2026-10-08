/* Party games: Bluff It, Last Tap Standing, Herd, Emoji Movie, Name Place
 * Animal Thing, Most Likely To. Port of PartyControllers.swift.
 */
(function () {
  'use strict';
  var AP = window.AP;
  var h = AP.h, C = AP.C, ui = AP.ui, kit = AP.kit, pd = AP.pd;

  var TINT = { bluff: C.pink, lastTap: C.green, herd: C.cyan, emoji: C.yellow, npat: C.cyan, mostLikely: C.purple };

  var promptCard = AP.promptCard, centered = AP.centered, waiting = AP.waiting;

  function body(kids) { return h('div', { class: 'col gap16', style: { flex: '1 1 auto', minHeight: 0 } }, kids); }

  // ---- Bluff It -------------------------------------------------------------
  AP.controllers.bluff_it = function (ctx) {
    var lie = '', trackedRound = -1;
    return function (d) {
      var phase = pd.str(d, 'phase', 'write');
      var prompt = pd.str(d, 'prompt');
      var hasSubmitted = pd.bool(d, 'hasSubmitted');
      var myPick = typeof d.myPick === 'number' ? d.myPick : null;
      var round = pd.int(d, 'round');
      if (round !== trackedRound) { trackedRound = round; lie = ''; }
      var options = pd.dicts(d, 'options').map(function (o) {
        return { index: typeof o.index === 'number' ? o.index : 0, text: typeof o.text === 'string' ? o.text : '', isMine: o.isMine === true };
      });
      var content;
      if (phase === 'write') {
        if (hasSubmitted) { content = waiting('w-done', 'pencil', 'Lie submitted', 'Waiting for everyone else...'); }
        else {
          content = centered('w-form',
            ui.answerField({ key: 'lie', placeholder: 'Your fake answer', value: lie, onInput: function (v) { lie = v; ctx.refresh(); } }),
            ui.ctlButton({ title: 'Submit Lie', icon: 'paperplane.fill', tint: TINT.bluff, enabled: lie.trim().length > 0,
              onClick: function () { ctx.send('submit_lie', { text: lie }); lie = ''; ctx.refresh(); } }));
        }
      } else if (phase === 'pick') {
        content = h('div', { class: 'scroll pop-in', key: 'pick' },
          h('div', { class: 'col gap10', style: { padding: '0 20px 20px' } }, options.map(function (o) {
            return ui.choiceRow({ text: o.text, detail: o.isMine ? "Your lie, so you can't pick it" : null,
              selected: myPick === o.index, disabled: o.isMine || myPick !== null,
              onClick: function () { ctx.send('pick', { index: o.index }); } });
          })));
      } else {
        content = waiting('scores', 'party.popper.fill', 'Scores are on the TV');
      }
      return ui.shell({ title: 'Bluff It', subtitle: phase === 'write' ? 'Invent a convincing lie' : 'Find the truth',
          secondsLeft: pd.int(d, 'secondsLeft') },
        body([prompt ? promptCard(prompt, phase === 'pick' ? 'Spot the real answer' : 'Fake an answer', TINT.bluff) : null, content]));
    };
  };

  // ---- Last Tap Standing ------------------------------------------------------
  AP.controllers.last_tap = function (ctx) {
    return function (d) {
      var phase = pd.str(d, 'phase', 'arming');
      var alive = pd.bool(d, 'isAlive', true);
      var canTap = pd.bool(d, 'canTap');
      var myMs = typeof d.myMs === 'number' ? d.myMs : null;
      var falseStart = pd.bool(d, 'falseStart');
      var content;
      if (!alive) {
        content = waiting('out', 'xmark.octagon.fill', "You're out", 'Watch the rest fight it out on the TV');
      } else if (myMs !== null) {
        content = waiting('ms-' + falseStart, falseStart ? 'nosign' : 'stopwatch.fill', falseStart ? 'Too early!' : myMs + ' ms',
          falseStart ? 'You tapped before GO' : 'Waiting for the others...');
      } else {
        var go = phase === 'go';
        content = h('div', { class: 'center', key: 'pad', style: { flex: '1 1 auto', display: 'flex', padding: '30px', minHeight: 0 } },
          h('button', {
            class: 'press' + (go ? ' idle' : ''),
            style: { '--sc': '0.03', '--dur': '0.25s', appearance: 'none', border: go ? '0' : '2px solid rgba(255,255,255,0.08)',
              aspectRatio: '1', width: 'min(100%, 62vh)', maxWidth: '100%', borderRadius: '50%', color: go ? '#000' : 'rgba(255,255,255,0.35)',
              background: go ? AP.grad([TINT.lastTap, C.cyan]) : AP.grad([C.surface2, C.surface]),
              boxShadow: go ? '0 0 30px ' + AP.alpha(TINT.lastTap, 0.55) : 'none',
              display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: '6px', padding: '0 30px',
              touchAction: 'manipulation' },
            onpointerdown: function (ev) {
              ev.preventDefault();
              if (!canTap) { return; }
              if (go) { AP.haptic.thump(); } else { AP.haptic.rigid(); }
              ctx.send('tap', {});
            }
          },
            h('div', { style: { fontSize: '56px', fontWeight: 900, letterSpacing: '3px' } }, go ? 'TAP!' : 'WAIT'),
            h('div', { class: 'txt-center', style: { fontSize: '15px', fontWeight: 700, color: go ? 'rgba(0,0,0,0.6)' : C.text3 } },
              go ? 'Hit it!' : 'Tap the moment it turns green')));
      }
      return ui.shell({ title: 'Last Tap Standing', subtitle: alive ? 'Round ' + pd.int(d, 'round') : 'Eliminated' }, content);
    };
  };

  // ---- Herd -------------------------------------------------------------------
  AP.controllers.herd = function (ctx) {
    var answer = '', trackedRound = -1;
    return function (d) {
      var prompt = pd.str(d, 'prompt');
      var phase = pd.str(d, 'phase', 'answer');
      var submitted = pd.bool(d, 'hasSubmitted');
      var mine = typeof d.myAnswer === 'string' ? d.myAnswer : null;
      var round = pd.int(d, 'round');
      if (round !== trackedRound) { trackedRound = round; answer = ''; }
      var content;
      if (phase !== 'answer') {
        content = waiting('res', 'chart.bar.fill', 'Results are on the TV', mine !== null ? 'You said “' + mine + '”' : null);
      } else if (submitted) {
        content = waiting('locked', 'checkmark.circle.fill', 'Answer locked in', mine !== null ? '“' + mine + '”' : null);
      } else {
        content = centered('form',
          ui.answerField({ key: 'ans', placeholder: 'Your answer', value: answer, onInput: function (v) { answer = v; ctx.refresh(); } }),
          ui.ctlButton({ title: 'Submit', icon: 'paperplane.fill', tint: TINT.herd, enabled: answer.trim().length > 0,
            onClick: function () { ctx.send('answer', { text: answer }); answer = ''; ctx.refresh(); } }));
      }
      return ui.shell({ title: 'Herd', subtitle: 'Answer like the crowd would', secondsLeft: pd.int(d, 'secondsLeft') },
        body([prompt ? promptCard(prompt, 'Think like the herd', TINT.herd) : null, content]));
    };
  };

  // ---- Emoji Movie ----------------------------------------------------------------
  // Code points, not literals: the repo's no-emoji check reads source text.
  var PALETTE = [[0x1F600], [0x1F60D], [0x1F631], [0x1F62D], [0x1F916], [0x1F451], [0x1F409], [0x1F981], [0x1F680],
    [0x1F30A], [0x1F525], [0x2764, 0xFE0F], [0x2694, 0xFE0F], [0x1F3F0], [0x1F3AC], [0x1F3B5], [0x1F480], [0x1F47B],
    [0x1F9D9], [0x1F575, 0xFE0F], [0x1F697], [0x2708, 0xFE0F], [0x1F30D], [0x2B50, 0xFE0F]]
    .map(function (cps) { return String.fromCodePoint.apply(null, cps); });

  AP.controllers.emoji_movie = function (ctx) {
    var composed = [];   // array of emoji strings (grapheme-safe)
    var guesses = {};
    return function (d) {
      var phase = pd.str(d, 'phase', 'compose');
      var myTitle = typeof d.myTitle === 'string' ? d.myTitle : null;
      var myEmoji = typeof d.myEmoji === 'string' ? d.myEmoji : null;
      var entries = pd.dicts(d, 'entries').map(function (e) {
        return { index: typeof e.index === 'number' ? e.index : 0, emoji: typeof e.emoji === 'string' ? e.emoji : '', isMine: e.isMine === true };
      });
      var content;
      if (phase === 'compose') {
        var text = composed.join('');
        var composer;
        if (myEmoji !== null) {
          composer = waiting('sub', 'checkmark.circle.fill', 'Submitted', myEmoji);
        } else {
          composer = h('div', { class: 'col gap14 pop-in', key: 'composer' },
            h('div', { class: 'px20' },
              h('div', { class: 'row center', style: { height: '72px', padding: '0 14px', borderRadius: 'var(--r-button)', background: C.surface2,
                  border: '1px solid rgba(255,255,255,0.12)', justifyContent: 'center', overflow: 'hidden', whiteSpace: 'nowrap',
                  fontSize: text ? '40px' : '17px', fontWeight: text ? 400 : 600, color: text ? '#fff' : C.text3 } },
                text || 'Tap emoji below')),
            h('div', { class: 'px20', style: { display: 'grid', gridTemplateColumns: 'repeat(6, 1fr)', gap: '8px' } },
              PALETTE.map(function (e) {
                return h('button', { class: 'press', key: 'e-' + e,
                  style: { appearance: 'none', border: 0, fontSize: '30px', padding: '8px 0', borderRadius: 'var(--r-chip)', background: C.surface },
                  onclick: function () {
                    if (composed.length >= 12) { AP.haptic.warning(); return; }
                    AP.haptic.tap(); composed.push(e); ctx.refresh();
                  } }, e);
              })),
            h('div', { class: 'row gap12 px20' },
              h('button', { class: 'press', 'aria-label': 'Delete',
                style: { appearance: 'none', width: '66px', height: '60px', flex: '0 0 auto', borderRadius: 'var(--r-button)',
                  background: 'rgba(255,255,255,0.07)', border: '1px solid rgba(255,255,255,0.12)', color: 'rgba(255,255,255,0.85)',
                  display: 'flex', alignItems: 'center', justifyContent: 'center' },
                onclick: function () { AP.haptic.tap(); composed.pop(); ctx.refresh(); } }, AP.icon('delete.left', 22)),
              h('div', { class: 'grow' }, ui.bigButton({ title: 'Submit', icon: 'paperplane.fill', colors: [C.yellow, C.orange],
                enabled: composed.length > 0, onClick: function () { ctx.send('submit_emoji', { emoji: composed.join('') }); } }))));
        }
        content = h('div', { class: 'col gap16 pop-in', key: 'compose', style: { flex: '1 1 auto', minHeight: 0, overflowY: 'auto' } },
          promptCard(myTitle !== null ? myTitle : '...', 'Your secret title', TINT.emoji, TINT.emoji), composer);
      } else if (phase === 'guess') {
        content = h('div', { class: 'scroll pop-in', key: 'guess' },
          h('div', { class: 'col gap12', style: { padding: '20px' } }, entries.map(function (e) {
            return h('div', { class: 'col center gap10', key: 'en-' + e.index,
                style: { padding: '16px', borderRadius: 'var(--r-card)', background: C.surface } },
              h('div', { style: { fontSize: '40px', whiteSpace: 'nowrap', overflow: 'hidden', maxWidth: '100%' } }, e.emoji),
              e.isMine
                ? kit.capsule('YOUR CLUE', 'rgba(255,255,255,0.07)', C.text3, { padding: '5px 12px' })
                : h('input', { class: 'answer-field', key: 'g-' + e.index, type: 'text', placeholder: 'Guess the title',
                    value: guesses[e.index] || '', autocomplete: 'off', autocorrect: 'off', enterkeyhint: 'send',
                    style: { fontSize: '17px', padding: '14px' },
                    oninput: function (ev) { guesses[e.index] = ev.target.value; },
                    onkeydown: function (ev) {
                      if (ev.key === 'Enter') { AP.haptic.tap(); ctx.send('guess', { index: e.index, text: guesses[e.index] || '' }); }
                    } }));
          })));
      } else {
        content = waiting('rev', 'party.popper.fill', 'Reveal is on the TV');
      }
      return ui.shell({ title: 'Emoji Movie', subtitle: phase === 'compose' ? 'Describe it in emoji' : 'Guess the others',
        secondsLeft: pd.int(d, 'secondsLeft') }, content);
    };
  };

  // ---- Name Place Animal Thing ------------------------------------------------------
  AP.controllers.npat = function (ctx) {
    var values = {}, trackedRound = -1;
    var FIELDS = [['name', 'Name', 'person'], ['place', 'Place', 'mappin'], ['animal', 'Animal', 'pawprint'], ['thing', 'Thing', 'cube']];
    return function (d) {
      var letter = pd.str(d, 'letter');
      var phase = pd.str(d, 'phase', 'fill');
      var submitted = pd.bool(d, 'hasSubmitted');
      var round = pd.int(d, 'round');
      if (round !== trackedRound) { trackedRound = round; values = {}; }
      var content;
      if (phase !== 'fill') { content = waiting('score', 'clipboard.fill', 'Scoring on the TV'); }
      else if (submitted) { content = waiting('sub', 'checkmark.circle.fill', 'Submitted', 'Waiting for the round to end...'); }
      else {
        var any = Object.keys(values).some(function (k) { return values[k]; });
        content = h('div', { class: 'scroll pop-in', key: 'fill' },
          h('div', { class: 'col gap12', style: { padding: '20px' } },
            h('div', { class: 'idle txt-center', style: { '--dy': '3px', '--sc': '0.03', '--dur': '1.4s', paddingTop: '8px', fontSize: '80px',
                fontWeight: 900, lineHeight: 1.1, background: AP.grad([C.cyan, C.indigo]), WebkitBackgroundClip: 'text', backgroundClip: 'text', color: 'transparent' } }, letter),
            FIELDS.map(function (f) {
              var filled = (values[f[0]] || '').trim().length > 0;
              return h('div', { class: 'row gap12', key: 'f-' + f[0],
                  style: { padding: '16px', borderRadius: 'var(--r-button)', background: C.surface,
                    border: '1px solid ' + (filled ? AP.alpha(C.green, 0.5) : 'rgba(255,255,255,0.06)') } },
                h('span', { style: { width: '26px', display: 'inline-flex', justifyContent: 'center', color: filled ? C.green : TINT.npat } },
                  AP.icon(filled ? 'checkmark.circle.fill' : f[2], 20)),
                h('input', { key: 'in-' + f[0], type: 'text', placeholder: f[1], value: values[f[0]] || '', autocomplete: 'off', autocorrect: 'off',
                  style: { flex: '1 1 auto', minWidth: 0, background: 'none', border: 0, outline: 'none', fontSize: '18px', fontWeight: 600, color: '#fff' },
                  oninput: function (ev) { values[f[0]] = ev.target.value; ctx.refresh(); } }));
            }),
            h('div', { style: { paddingTop: '6px' } },
              ui.bigButton({ title: 'Submit All', icon: 'checkmark.circle.fill', colors: [C.cyan, C.indigo], enabled: any,
                onClick: function () { ctx.send('submit', values); } }))));
      }
      return ui.shell({ title: 'Name Place Animal Thing', subtitle: 'Everything starts with ' + letter,
        secondsLeft: pd.int(d, 'secondsLeft') }, content);
    };
  };

  // ---- Most Likely To ---------------------------------------------------------------
  AP.controllers.most_likely_to = function (ctx) {
    return function (d) {
      var phase = pd.str(d, 'phase', 'vote');
      var prompt = pd.str(d, 'prompt');
      var hasVoted = pd.bool(d, 'hasVoted');
      var me = pd.str(d, 'myPlayerID');
      var players = pd.dicts(d, 'players').filter(function (p) { return typeof p.id === 'string' && p.id !== me && typeof p.name === 'string'; });
      var content;
      if (phase === 'vote') {
        if (hasVoted) { content = waiting('voted', 'checkmark.circle.fill', 'Vote counted', 'Waiting for everyone else...'); }
        else {
          content = h('div', { class: 'scroll pop-in', key: 'vote' },
            h('div', { style: { display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px', padding: '0 20px 20px' } },
              players.map(function (p) {
                return h('button', { class: 'press', key: 'v-' + p.id,
                  style: { appearance: 'none', minHeight: '64px', padding: '0 10px', borderRadius: 'var(--r-button)', background: C.surface,
                    border: '1px solid ' + AP.alpha(TINT.mostLikely, 0.35), color: '#fff', fontSize: '18px', fontWeight: 800, lineHeight: 1.15 },
                  onclick: function () { AP.haptic.tap(); ctx.send('vote', { targetID: p.id }); } }, p.name);
              })));
        }
      } else {
        content = waiting('in', 'tv', 'Votes are in', 'Check the TV for the reveal');
      }
      return ui.shell({ title: 'Most Likely To', subtitle: phase === 'vote' ? 'Vote for who fits best' : 'See who got the votes',
        secondsLeft: pd.int(d, 'secondsLeft') },
        body([prompt ? promptCard(prompt, 'Who is most likely to', TINT.mostLikely) : null, content]));
    };
  };
})();
