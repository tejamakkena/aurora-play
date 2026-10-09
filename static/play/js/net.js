/* Aurora Play web controller: the /native Socket.IO connection.
 *
 * The same namespace, events and payloads the iOS controller uses
 * (ios/Shared/Networking/GameMessage.swift), so the server cannot tell this
 * controller from the app.
 */
(function () {
  'use strict';
  var AP = window.AP;

  function store(key, value) {
    try {
      if (value === undefined) { return window.localStorage.getItem(key); }
      if (value === null) { window.localStorage.removeItem(key); } else { window.localStorage.setItem(key, value); }
    } catch (e) { /* private mode: run without memory */ }
    return null;
  }
  AP.store = store;

  function uuid() {
    if (window.crypto && window.crypto.randomUUID) { return window.crypto.randomUUID(); }
    return 'web-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2, 10);
  }

  /** The id this browser sends as playerID (the app's device id). */
  AP.deviceID = function () {
    var id = store('aurora_device_id');
    if (!id) { id = 'web-' + uuid(); store('aurora_device_id', id); }
    return id;
  };

  var socket = null;
  var connected = false;
  var statusListeners = [];
  var connectListeners = [];

  AP.net = {
    get connected() { return connected; },

    connect: function () {
      if (socket) { return; }
      socket = window.io('/native', { reconnection: true, reconnectionDelay: 500, reconnectionDelayMax: 4000 });
      socket.on('connect', function () {
        connected = true;
        statusListeners.forEach(function (f) { f(true); });
        connectListeners.forEach(function (f) { f(); });
      });
      socket.on('disconnect', function () {
        connected = false;
        statusListeners.forEach(function (f) { f(false); });
      });
      socket.on('connect_error', function () {
        if (connected) { connected = false; }
        statusListeners.forEach(function (f) { f(false); });
      });
    },

    /** The tab woke up. A socket that is mid-connect or already backing off
     *  to retry (``active``) is left alone; one that gave up is restarted. */
    wake: function () {
      if (!socket || socket.connected || socket.active) { return; }
      socket.connect();
    },

    on: function (event, fn) { socket.on(event, fn); },
    off: function (event, fn) { socket.off(event, fn); },
    emit: function (event, payload) { socket.emit(event, payload); },
    onStatus: function (fn) { statusListeners.push(fn); },
    onConnected: function (fn) { connectListeners.push(fn); },
    offStatus: function (fn) { statusListeners = statusListeners.filter(function (f) { return f !== fn; }); }
  };
})();
