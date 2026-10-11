/* The Host Is Lying: press the host, then vote Trust or Liar. */
(function () {
  'use strict';
  var AP = window.AP;
  var h = AP.h, C = AP.C, ui = AP.ui, pd = AP.pd;

  var TELLS = [['hedge', 'Hedging'], ['overexplain', 'Over-explaining'], ['repeat', 'Said it twice'],
               ['stall', 'Stalling'], ['rushed', 'Talking fast']];

  function body(kids) { return h('div', { class: 'col gap16', style: { flex: '1 1 auto', minHeight: 0 } }, kids); }

  AP.controllers.host_lies = function (ctx) {
    var noted = {}, lastRound = -1;
    return function (d) {
      var phase = pd.str(d, 'phase', 'claim');
      var round = pd.int(d, 'round');
      if (round !== lastRound) { lastRound = round; noted = {}; }
      var statement = pd.str(d, 'statement');
      var defences = pd.dicts(d, 'defences');
      var my = pd.str(d, 'myVote');
      var rev = d.reveal && typeof d.reveal === 'object' ? d.reveal : null;

      var statementCard = statement && phase !== 'final'
        ? AP.promptCard(statement, phase === 'reveal' ? 'The host said' : 'The host says', C.orange) : null;

      var notes = h('div', { class: 'col gap8', key: 'notes', style: { padding: '0 20px' } },
        h('div', { class: 'c-text2', style: { fontSize: '12px', fontWeight: 800, letterSpacing: '2px' } }, 'TELLS YOU SPOT (JUST FOR YOU)'),
        h('div', { class: 'row gap8', style: { flexWrap: 'wrap' } }, TELLS.map(function (t) {
          var on = !!noted[t[0]];
          return h('button', { class: 'press', key: 'n-' + t[0],
            style: { appearance: 'none', padding: '8px 12px', borderRadius: '999px', fontSize: '14px', fontWeight: 700, color: '#fff',
              background: on ? AP.alpha(C.orange, 0.35) : C.surface, border: '1px solid ' + (on ? C.orange : 'transparent') },
            onclick: function () { noted[t[0]] = !noted[t[0]]; ctx.refresh(); } }, t[1]);
        })));

      var content;
      if (phase === 'claim') {
        content = AP.waiting('claim', 'ear.fill', 'Listen to the host', 'Hear how they say it, not just what they say');
      } else if (phase === 'grill') {
        content = h('div', { class: 'col gap14 pop-in', key: 'grill', style: { padding: '0 20px 12px' } },
          pd.bool(d, 'canPress')
            ? ui.bigButton({ title: 'Press the host', icon: 'exclamationmark.triangle.fill', colors: [C.orange, C.red],
                onClick: function () { ctx.send('press', {}); } })
            : h('div', { class: 'txt-center c-text2', style: { fontWeight: 600 } },
                pd.int(d, 'pressesLeft') > 0 ? 'You pressed. Listen to the answer.' : 'The host has been pressed enough.'),
          defences.map(function (x) {
            return h('div', { class: 'card', key: 'df-' + x.seq, style: { padding: '12px 14px' } },
              h('div', { class: 'c-text2', style: { fontSize: '12px', fontWeight: 800 } }, (x.by || 'Someone') + ' pressed'),
              h('div', { style: { fontSize: '17px', fontWeight: 700, marginTop: '4px' } }, '"' + x.text + '"'));
          }));
      } else if (phase === 'vote') {
        var choice = function (key, label, icon, colors) {
          var picked = my === key;
          return h('button', { class: 'press', key: 'v-' + key, disabled: !!my,
            style: { appearance: 'none', width: '100%', minHeight: '86px', borderRadius: 'var(--r-card)', color: '#fff', fontSize: '24px', fontWeight: 900,
              background: picked ? AP.grad(colors) : C.surface, border: '2px solid ' + (picked ? '#fff' : AP.alpha(colors[0], 0.5)),
              opacity: my && !picked ? 0.4 : 1 },
            onclick: function () { AP.haptic.tap(); ctx.send('vote', { side: key }); } }, label);
        };
        content = h('div', { class: 'col gap12 pop-in', key: 'vote', style: { padding: '0 20px 12px' } },
          choice('trust', 'Trust the host', 'checkmark.circle.fill', [C.green, C.cyan]),
          choice('liar', 'LIAR!', 'xmark.circle.fill', [C.red, C.orange]),
          my ? h('div', { class: 'txt-center c-text2', style: { fontWeight: 600 } }, 'Locked in. Waiting for everyone...') : null);
      } else if (phase === 'reveal' && rev) {
        var delta = typeof rev.delta === 'number' ? rev.delta : 0;
        content = h('div', { class: 'col gap12 pop-in', key: 'reveal', style: { padding: '0 20px 12px' } },
          h('div', { class: 'txt-center', style: { fontSize: '30px', fontWeight: 900, color: rev.isLie ? C.red : C.green } },
            rev.isLie ? 'The host lied!' : 'The host told the truth'),
          rev.isLie ? h('div', { class: 'card', style: { padding: '12px 14px' } },
            h('div', { class: 'c-text2', style: { fontSize: '12px', fontWeight: 800 } }, 'THE TRUTH'),
            h('div', { style: { fontSize: '17px', fontWeight: 700, marginTop: '4px' } }, rev.truth)) : null,
          h('div', { class: 'c-text2 txt-center', style: { fontWeight: 600 } }, rev.why),
          h('div', { class: 'txt-center c-text2', style: { fontSize: '14px' } },
            'Tells in this round: ' + (rev.tells && rev.tells.length ? rev.tells.join(', ') : 'none')),
          h('div', { class: 'txt-center', style: { fontSize: '22px', fontWeight: 900, color: delta > 0 ? C.green : (delta < 0 ? C.red : C.text2) } },
            delta > 0 ? '+' + delta : (delta < 0 ? String(delta) : 'No points')));
      } else {
        content = AP.waiting('end', 'party.popper.fill', 'Game over', 'Scores are on the TV');
      }

      var showNotes = phase === 'claim' || phase === 'grill' || phase === 'vote';
      return ui.shell({ title: 'The Host Is Lying',
          subtitle: phase === 'vote' ? 'Trust or Liar?' : (phase === 'grill' ? 'Press the host' : (phase === 'reveal' ? 'The verdict' : 'Listen closely')),
          secondsLeft: pd.int(d, 'secondsLeft') },
        body([statementCard, content, showNotes ? notes : null]));
    };
  };
})();
