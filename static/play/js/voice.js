/* The voice quizmaster mic bar. Port of Voice/TVMicController.swift.
 *
 * Exactly one phone per room is the ear: it claims the mic (claim_mic ->
 * mic_reassigned), arms speech recognition when the TV drives voice_state to
 * "listen", and streams partial and final transcripts back over
 * voice_transcript. The TV grades; this phone only transcribes. Uses the
 * browser's SpeechRecognition, so the bar is hidden where that is missing.
 */
(function () {
  'use strict';
  var AP = window.AP;
  var h = AP.h, C = AP.C, S = AP.S;

  var Recognition = window.SpeechRecognition || window.webkitSpeechRecognition;
  var mic = { micPlayerID: null, micPlayerName: null, voiceState: 'idle', listening: false, transcript: '', room: null };
  var rec = null, timer = null, attached = false, lastText = '', lastConf = 0, delivered = false;

  function isHolder() { return mic.micPlayerID !== null && mic.micPlayerID === S.playerID; }
  function emitTranscript(text, isFinal, confidence) {
    AP.net.emit('voice_transcript', { roomCode: mic.room, playerID: S.playerID, text: text, isFinal: isFinal, confidence: confidence || 0 });
  }

  function stopListening() {
    if (timer) { clearTimeout(timer); timer = null; }
    if (rec) { try { rec.onresult = rec.onend = rec.onerror = null; rec.abort(); } catch (e) { /* ignore */ } rec = null; }
    mic.listening = false;
  }
  function finish() {
    if (delivered) { return; }
    delivered = true;
    mic.listening = false;
    emitTranscript(lastText, true, lastConf);
    if (timer) { clearTimeout(timer); timer = null; }
    rec = null;
    AP.changed();
  }
  function startListening() {
    if (!Recognition || mic.listening) { return; }
    mic.transcript = ''; lastText = ''; lastConf = 0; delivered = false; mic.listening = true;
    try {
      rec = new Recognition();
      rec.continuous = false; rec.interimResults = true; rec.lang = 'en-US';
      rec.onresult = function (ev) {
        var text = '', conf = 0, n = 0;
        for (var i = 0; i < ev.results.length; i++) { text += ev.results[i][0].transcript; conf += ev.results[i][0].confidence || 0; n++; }
        lastText = text; lastConf = n ? conf / n : 0; mic.transcript = text;
        emitTranscript(text, false, 0);
        AP.changed();
      };
      rec.onerror = function () { finish(); };
      rec.onend = function () { finish(); };
      rec.start();
      timer = setTimeout(function () { try { rec.stop(); } catch (e) { finish(); } }, 10000);
    } catch (e) { mic.listening = false; }
    AP.changed();
  }

  function attach(room) {
    mic.room = room.code;
    if (attached) { return; }
    attached = true;
    AP.net.on('mic_reassigned', function (r) {
      if (!r || r.roomCode !== mic.room) { return; }
      mic.micPlayerID = r.playerID; mic.micPlayerName = r.playerName; AP.changed();
    });
    AP.net.on('voice_state', function (r) {
      if (!r || r.roomCode !== mic.room) { return; }
      mic.voiceState = r.state;
      if (r.state === 'listen' && isHolder()) { startListening(); } else { stopListening(); }
      if (r.state === 'ask' || r.state === 'idle') { mic.transcript = ''; }
      AP.changed();
    });
  }

  AP.micBar = function (room) {
    if (!Recognition) { return null; }
    attach(room);
    var holder = isHolder();
    var body;
    if (holder) {
      var canHold = mic.voiceState === 'listen';
      body = [
        h('button', { class: 'press', disabled: !canHold, 'aria-label': 'Hold to talk',
          style: { appearance: 'none', border: 0, width: '52px', height: '52px', borderRadius: '50%', color: '#fff', flex: '0 0 auto',
            background: mic.listening ? C.green : 'rgba(255,255,255,0.15)', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', touchAction: 'none' },
          onpointerdown: function () { if (isHolder() && mic.voiceState === 'listen') { startListening(); } },
          onpointerup: function () { if (rec) { try { rec.stop(); } catch (e) { finish(); } } } },
          AP.icon(mic.listening ? 'mic.fill' : 'mic', 24)),
        h('div', { class: 'col gap4', style: { minWidth: 0 } },
          h('span', { style: { fontSize: '15px', fontWeight: 700 } }, mic.listening ? "Listening -- you're the mic" : "You're the mic"),
          h('span', { style: { fontSize: '12px', color: 'rgba(255,255,255,0.55)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' } },
            mic.transcript ? mic.transcript : (mic.voiceState === 'listen' ? 'Hold the button and answer' : 'Wait for the question')))
      ];
    } else {
      body = [h('button', { class: 'press',
        style: { appearance: 'none', border: 0, padding: '12px 18px', borderRadius: '999px', background: 'rgba(255,255,255,0.12)', color: '#fff',
          display: 'inline-flex', alignItems: 'center', gap: '8px', fontSize: '15px', fontWeight: 700 },
        onclick: function () { AP.haptic.tap(); AP.net.emit('claim_mic', { roomCode: room.code, playerID: S.playerID }); } },
        AP.icon('mic.fill', 16), mic.micPlayerName || 'Take the mic')];
    }
    return h('div', { class: 'mic-bar', key: 'micbar' }, body);
  };
})();
