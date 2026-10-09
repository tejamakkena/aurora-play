/* Truth or Dare. The host phone runs the table (names, level, judging, end);
 * any other phone is a read-only view, except that the player on turn can
 * pick truth or dare and switch for themselves.
 */
(function () {
  'use strict';
  var AP = window.AP;
  var h = AP.h, C = AP.C, ui = AP.ui, pd = AP.pd;

  var TINT = C.pink;
  var LEVEL_LABEL = { family: 'Family', teens: 'Teens', adults: 'Adults' };
  var LEVEL_NOTE = { family: 'All ages', teens: 'Cheeky', adults: 'Party' };

  function body(kids) { return h('div', { class: 'col gap16', style: { flex: '1 1 auto', minHeight: 0 } }, kids); }

  function scoreRow(p, current) {
    var on = p.id === current;
    return h('div', { class: 'row', key: 'sc-' + p.id,
      style: { justifyContent: 'space-between', padding: '8px 12px', borderRadius: '12px',
        background: on ? AP.alpha(TINT, 0.22) : C.surface, border: '1px solid ' + (on ? TINT : 'transparent') } },
      h('span', { style: { fontWeight: 700 } }, p.name), h('span', { class: 'c-text2', style: { fontWeight: 800 } }, String(p.score)));
  }

  function endButton(ctx) {
    return ui.ghostButton({ title: 'End game', icon: 'xmark.circle.fill', onClick: function () {
      ui.confirm({ title: 'End the game and show the scores?', confirmTitle: 'End game',
        onConfirm: function () { ctx.send('end', {}); } });
    } });
  }

  AP.controllers.truth_or_dare = function (ctx) {
    var draft = '';
    return function (d) {
      var phase = pd.str(d, 'phase', 'setup');
      var isHost = pd.bool(d, 'isHost');
      var isMyTurn = pd.bool(d, 'isMyTurn');
      var people = pd.dicts(d, 'participants').filter(function (p) { return typeof p.id === 'string' && typeof p.name === 'string'; })
        .map(function (p) { return { id: p.id, name: p.name, score: typeof p.score === 'number' ? p.score : 0 }; });
      var current = pd.str(d, 'currentID');
      var who = pd.str(d, 'currentName');
      var kind = pd.str(d, 'kind');
      var prompt = pd.str(d, 'prompt');
      var level = pd.str(d, 'level', 'family');
      var min = pd.int(d, 'minPlayers') || 2;
      var content;

      if (phase === 'setup') {
        if (!isHost) {
          content = AP.waiting('setup', 'person.3.fill', 'The host is adding players', 'Look at the TV');
        } else {
          var add = function () {
            var v = draft.trim();
            if (!v) { return; }
            draft = '';
            ctx.send('add_names', { names: v });
            ctx.refresh();
          };
          content = h('div', { class: 'scroll pop-in', key: 'setup' },
            h('div', { class: 'col gap14', style: { padding: '0 20px 20px' } },
              h('div', { class: 'c-text2', style: { fontSize: '15px', fontWeight: 600 } },
                'Type a name and add it. Several names separated by commas work too.'),
              h('div', { class: 'row gap10' },
                h('div', { style: { flex: '1 1 auto', minWidth: 0 } },
                  ui.answerField({ key: 'td-name', placeholder: 'Player name', value: draft, maxLength: 20,
                    onInput: function (v) { draft = v; ctx.refresh(); }, onSubmit: add })),
                h('button', { class: 'btn-ctl press' + (draft.trim() ? '' : ' off'), disabled: !draft.trim(),
                  style: { '--tint': TINT, flex: '0 0 auto', padding: '0 18px' }, onclick: add }, 'Add')),
              h('div', { class: 'col gap8' }, people.map(function (p) {
                return h('div', { class: 'row', key: 'p-' + p.id,
                  style: { justifyContent: 'space-between', padding: '10px 14px', borderRadius: '12px', background: C.surface } },
                  h('span', { style: { fontWeight: 700 } }, p.name),
                  h('button', { class: 'press', 'aria-label': 'Remove ' + p.name,
                    style: { appearance: 'none', background: 'none', border: 0, color: C.text2, fontWeight: 800, fontSize: '16px' },
                    onclick: function () { ctx.send('remove_name', { id: p.id }); } }, 'Remove'));
              })),
              h('div', { class: 'c-text2', style: { fontSize: '13px', fontWeight: 700, letterSpacing: '0.08em' } }, 'LEVEL'),
              h('div', { class: 'row gap8' }, ['family', 'teens', 'adults'].map(function (l) {
                var sel = level === l;
                return h('button', { class: 'press', key: 'lv-' + l,
                  style: { appearance: 'none', flex: '1 1 0', padding: '10px 6px', borderRadius: '12px', color: '#fff',
                    background: sel ? AP.alpha(TINT, 0.3) : C.surface, border: '1px solid ' + (sel ? TINT : 'transparent') },
                  onclick: function () { ctx.send('set_level', { level: l }); } },
                  h('div', { style: { fontWeight: 800 } }, LEVEL_LABEL[l]),
                  h('div', { class: 'c-text2', style: { fontSize: '12px' } }, LEVEL_NOTE[l]));
              })),
              ui.ctlButton({ title: people.length >= min ? 'Start game' : 'Add at least ' + min + ' players', icon: 'play.fill',
                tint: TINT, enabled: people.length >= min, onClick: function () { ctx.send('start_play', {}); } }),
              endButton(ctx)));
        }
      } else if (phase === 'choose') {
        var canPick = isHost || isMyTurn;
        content = h('div', { class: 'col gap16 pop-in', key: 'choose', style: { flex: '1 1 auto', padding: '0 20px 20px', justifyContent: 'center' } },
          h('div', { class: 'txt-center', style: { fontSize: '30px', fontWeight: 800 } }, who),
          h('div', { class: 'txt-center c-text2', style: { fontSize: '17px', fontWeight: 600 } },
            canPick ? 'Truth or dare?' : 'is choosing: truth or dare?'),
          canPick ? h('div', { class: 'col gap12' },
            ui.bigButton({ title: 'Truth', icon: 'bubble.left.and.bubble.right.fill', colors: [C.cyan, C.blue], onClick: function () { ctx.send('choose', { kind: 'truth' }); } }),
            ui.bigButton({ title: 'Dare', icon: 'flame.fill', colors: [C.orange, C.red], onClick: function () { ctx.send('choose', { kind: 'dare' }); } })) : null);
      } else if (phase === 'prompt' || phase === 'punish') {
        var label = kind === 'truth' ? 'TRUTH' : kind === 'dare' ? 'DARE' : 'PUNISHMENT';
        var accent = kind === 'truth' ? C.cyan : kind === 'dare' ? C.orange : C.red;
        var canSwitch = pd.bool(d, 'canSwitch') && (isHost || isMyTurn);
        var buttons = [];
        if (isHost) {
          if (phase === 'punish') {
            buttons.push(ui.ctlButton({ title: 'Did the punishment', icon: 'checkmark.circle.fill', tint: C.green, onClick: function () { ctx.send('done', {}); } }));
            buttons.push(ui.ctlButton({ title: 'Refused (-2)', icon: 'xmark.circle.fill', tint: C.red, onClick: function () { ctx.send('skip', {}); } }));
          } else {
            buttons.push(ui.ctlButton({ title: kind === 'truth' ? 'Told the truth (+1)' : 'Did the dare (+2)', icon: 'checkmark.circle.fill',
              tint: C.green, onClick: function () { ctx.send('done', {}); } }));
            if (kind === 'truth') {
              buttons.push(ui.ctlButton({ title: 'Caught lying', icon: 'exclamationmark.triangle.fill', tint: C.red,
                onClick: function () { ctx.send('caught', {}); } }));
            }
            buttons.push(ui.ctlButton({ title: 'Skip (-1)', icon: 'forward.fill', tint: C.text2, onClick: function () { ctx.send('skip', {}); } }));
          }
        }
        if (canSwitch) {
          buttons.push(ui.ctlButton({ title: kind === 'truth' ? 'Switch to a dare' : 'Switch to a truth', icon: 'arrow.left.arrow.right',
            tint: C.purple, onClick: function () { ctx.send('switch', {}); } }));
        }
        content = h('div', { class: 'scroll pop-in', key: 'prompt' },
          h('div', { class: 'col gap14', style: { padding: '0 20px 20px' } },
            h('div', { class: 'txt-center', style: { fontSize: '22px', fontWeight: 800 } }, who),
            AP.promptCard(prompt, label, accent),
            isHost ? null : h('div', { class: 'txt-center c-text2', style: { fontWeight: 600 } }, 'The host judges this one'),
            buttons));
      } else {
        content = AP.waiting('over', 'party.popper.fill', 'Game over', 'Final scores are on the TV');
      }

      var scores = (phase === 'choose' || phase === 'prompt' || phase === 'punish')
        ? h('div', { class: 'col gap6', style: { padding: '0 20px 12px' } }, people.map(function (p) { return scoreRow(p, current); })) : null;
      var foot = (isHost && phase !== 'setup' && phase !== 'over') ? h('div', { style: { padding: '0 20px 16px' } }, endButton(ctx)) : null;
      return ui.shell({ title: 'Truth or Dare', subtitle: phase === 'setup' ? 'Add the players' : (LEVEL_LABEL[level] || '') + ' level' },
        body([content, scores, foot]));
    };
  };
})();
