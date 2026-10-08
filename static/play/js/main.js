/* Aurora Play web controller: render loop and the playing screen.
 *
 * Port of RootControllerView's switch plus ControllerGameView: one root, one
 * screen at a time, and the per-game controller factory kept alive for as
 * long as the phone stays on the same game.
 */
(function () {
  'use strict';
  var AP = window.AP;
  var h = AP.h, S = AP.S, ui = AP.ui;

  var root;
  var ctrl = null;   // { key, render, destroy }

  function makeContext() {
    var timers = [];
    var destroyers = [];
    return {
      get room() { return S.room; },
      get playerID() { return S.playerID; },
      get isHost() { return AP.isHost(); },
      get me() {
        var r = S.room;
        if (!r) { return null; }
        for (var i = 0; i < r.players.length; i++) { if (r.players[i].id === S.playerID) { return r.players[i]; } }
        return null;
      },
      send: function (action, data) { AP.act.sendAction(action, data); },
      refresh: function () { AP.changed(); },
      every: function (ms, fn) {
        var id = setInterval(function () { fn(); }, ms);
        timers.push(id);
        return id;
      },
      after: function (ms, fn) {
        var id = setTimeout(function () { fn(); }, ms);
        timers.push(id);
        return id;
      },
      clear: function (id) { clearInterval(id); clearTimeout(id); },
      onDestroy: function (fn) { destroyers.push(fn); },
      _destroy: function () {
        timers.forEach(function (t) { clearInterval(t); clearTimeout(t); });
        destroyers.forEach(function (f) { try { f(); } catch (e) { /* ignore */ } });
      }
    };
  }

  function destroyController() {
    if (ctrl) { ctrl.ctx._destroy(); ctrl = null; }
  }

  function controllerFor(room) {
    var key = room.code + '|' + room.gameID;
    if (ctrl && ctrl.key === key) { return ctrl; }
    destroyController();
    var factory = AP.controllers[room.gameID];
    var ctx = makeContext();
    ctrl = { key: key, ctx: ctx, render: null };
    if (factory) {
      try { ctrl.render = factory(ctx); } catch (e) { console.error('controller init failed', e); }
    }
    return ctrl;
  }

  AP.screens.playing = function () {
    var room = S.room;
    var g = AP.game(room.gameID);
    var content;
    if (g.retired) {
      content = AP.screens.retired(g);
    } else {
      var c = controllerFor(room);
      try {
        content = c.render ? c.render(S.privateData || {}) : ui.waitingState(g.icon, g.name, 'This game is not available in the browser yet.');
      } catch (e) {
        console.error('controller render failed', e);
        content = ui.waitingState('exclamationmark.triangle.fill', 'Something went wrong', 'Wait for the next round.');
      }
    }
    return h('div', { class: 'screen', style: { background: 'var(--bg)' } },
      h('div', { class: 'play-top' }, AP.leaveFab('sm')),
      h('div', { class: 'play-area' }, content),
      AP.micBar ? AP.micBar(room) : null);
  };

  function render() {
    if (!root) { return; }
    if (S.screen !== 'playing') { destroyController(); }
    var fn = AP.screens[S.screen];
    var node = fn ? fn() : h('div');
    var key = S.screen + (S.room ? S.room.code : '');
    node._key = key;
    AP.patch(root, node);
  }

  AP.start = function () {
    root = document.getElementById('screen-root');
    AP.setRenderer(render);
    var code = (document.body.getAttribute('data-code') || '').toUpperCase();
    AP.session.start(code);
    render();
  };
})();
