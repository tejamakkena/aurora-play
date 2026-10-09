/* Aurora Play web controller: icons.
 *
 * The iOS app draws SF Symbols, which do not exist in a browser, so each
 * symbol name the controllers use maps to a small inline SVG here. Icons are
 * keyed by the SF Symbol name so the ported code reads the same as the Swift.
 */
(function () {
  'use strict';
  var AP = window.AP = window.AP || {};

  var BG = 'var(--bg)';
  function disc() { return '<circle cx="12" cy="12" r="10" fill="currentColor" stroke="none"/>'; }
  function cut(d, w) { return '<path d="' + d + '" stroke="' + BG + '" stroke-width="' + (w || 2.6) + '" fill="none"/>'; }
  function fillPath(d) { return '<path d="' + d + '" fill="currentColor" stroke="none"/>'; }
  function strokePath(d) { return '<path d="' + d + '"/>'; }
  function sol(inner) { return '<g fill="currentColor" stroke="none">' + inner + '</g>'; }

  var HAND = 'M8 12V6.5a1.5 1.5 0 013 0V11m0-1V4.5a1.5 1.5 0 013 0V11m0-.5V6a1.5 1.5 0 013 0v7.5c0 4-2.5 7.5-6.5 7.5-3 0-4.5-1.5-6-4l-2-3.5a1.5 1.5 0 012.5-1.5L8 15';
  var STAR = 'M12 2.5l2.9 6.2 6.6.8-4.9 4.6 1.3 6.6L12 17.4 6.1 20.7l1.3-6.6L2.5 9.5l6.6-.8z';
  var HEART = 'M12 21s-8-5.2-8-11a4.5 4.5 0 018-2.8A4.5 4.5 0 0120 10c0 5.8-8 11-8 11z';

  var I = {
    'checkmark.circle.fill': disc() + cut('M7.5 12.5l3 3 6-6.5'),
    'checkmark': strokePath('M5 12.5l4.5 4.5L19 7'),
    'checkmark.seal.fill': fillPath('M12 1.5l2.6 2 3.2-.3 1.1 3 2.8 1.6-.9 3.1.9 3.1-2.8 1.6-1.1 3-3.2-.3-2.6 2-2.6-2-3.2.3-1.1-3-2.8-1.6.9-3.1-.9-3.1 2.8-1.6 1.1-3 3.2.3z') + cut('M8 12.3l2.8 2.8 5.2-5.6'),
    'checkmark.shield.fill': fillPath('M12 2l8 3v6c0 5-3.5 9-8 11-4.5-2-8-6-8-11V5z') + cut('M8.3 12l2.7 2.7 4.8-5.2'),
    'xmark': strokePath('M6 6l12 12M18 6L6 18'),
    'xmark.circle.fill': disc() + cut('M8.5 8.5l7 7M15.5 8.5l-7 7'),
    'xmark.circle': '<circle cx="12" cy="12" r="9.5"/>' + strokePath('M9 9l6 6M15 9l-6 6'),
    'xmark.octagon.fill': fillPath('M8 2h8l6 6v8l-6 6H8l-6-6V8z') + cut('M9 9l6 6M15 9l-6 6'),
    'minus.circle.fill': disc() + cut('M7 12h10'),
    'equal.circle.fill': disc() + cut('M8 9.5h8M8 14.5h8', 2.4),
    'plus': strokePath('M12 5v14M5 12h14'),
    'paperplane.fill': fillPath('M2.5 11.5L21.5 3 15 21l-3.8-7.2z'),
    'hourglass': strokePath('M7 3h10M7 21h10') + strokePath('M8 3v4l4 5-4 5v4M16 3v4l-4 5 4 5v4'),
    'tv': '<rect x="3" y="5" width="18" height="12" rx="2.5"/>' + strokePath('M8 21h8M12 17v4'),
    'tv.fill': '<rect x="2.5" y="4.5" width="19" height="13" rx="3" fill="currentColor" stroke="none"/>' + strokePath('M8 21h8M12 17.5V21'),
    'lock.fill': '<rect x="5" y="10.5" width="14" height="10.5" rx="2.5" fill="currentColor" stroke="none"/>' + strokePath('M8 10.5V8a4 4 0 018 0v2.5'),
    'star.fill': fillPath(STAR),
    'hand.tap.fill': fillPath('M9 12V6a1.8 1.8 0 013.6 0v5.2l3.4.9a2.2 2.2 0 011.6 2.5l-.8 4.4A3 3 0 0113.8 21H11a3.2 3.2 0 01-2.6-1.3L5.5 15.6a1.6 1.6 0 012.4-2.1z') + strokePath('M5.5 8.5a6 6 0 019 -3M3.5 8.5A8 8 0 0116 3'),
    'hand.raised.fill': fillPath('M7 11V6.2a1.5 1.5 0 013 0V10m0-.5V4.2a1.5 1.5 0 013 0V10m0-.2V5.2a1.5 1.5 0 013 0V12l.5-1.2a1.5 1.5 0 012.7 1.2l-2.3 6.5A5 5 0 0112.9 22H12a6 6 0 01-5.2-3L4.4 14.6a1.5 1.5 0 012.5-1.6L7 13z'),
    'hand.point.right.fill': fillPath('M3 10.5a2 2 0 012-2h7l-.5-1.8a1.7 1.7 0 013.1-1.4L16 7h2.5a2.5 2.5 0 012.5 2.5v6A5.5 5.5 0 0115.5 21H11a5 5 0 01-4-2l-3-4a1.5 1.5 0 012.3-1.8L7 14v-1.5H5a2 2 0 01-2-2z'),
    'hand.thumbsup.fill': fillPath('M2.5 10.5h4V21h-4zM8 10.5l3.5-7a2 2 0 012.6 1.6L13.5 9H19a2.2 2.2 0 012.2 2.7l-1.5 7A2.5 2.5 0 0117.3 21H8z'),
    'eye': strokePath('M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12z') + '<circle cx="12" cy="12" r="3"/>',
    'eye.fill': fillPath('M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12z') + '<circle cx="12" cy="12" r="3.2" fill="' + BG + '" stroke="none"/>',
    'eye.slash.fill': fillPath('M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12z') + '<circle cx="12" cy="12" r="3.2" fill="' + BG + '" stroke="none"/>' + '<path d="M4 4l16 16" stroke="' + BG + '" stroke-width="5"/>' + strokePath('M4 4l16 16'),
    'eyeglasses': '<circle cx="6.5" cy="14" r="3.8"/><circle cx="17.5" cy="14" r="3.8"/>' + strokePath('M10.3 14h3.4M2.7 14L5 7.5M21.3 14L19 7.5'),
    'wand.and.stars': strokePath('M4 20L15 9M13 5l1.6 1.4M17 3v3M19.5 7.5h3M18 11.5l1.5 1.5') + fillPath('M20 3.3l.8 1.7 1.7.8-1.7.8-.8 1.7-.8-1.7-1.7-.8 1.7-.8z'),
    'sparkles': fillPath('M9 3l1.8 5.2L16 10l-5.2 1.8L9 17l-1.8-5.2L2 10l5.2-1.8z') + fillPath('M18 13l1 2.7 2.7 1-2.7 1L18 20.5l-1-2.8-2.7-1 2.7-1z'),
    'shield.fill': fillPath('M12 2l8 3v6c0 5-3.5 9-8 11-4.5-2-8-6-8-11V5z'),
    'pencil': strokePath('M16.5 3.5l4 4L8 20l-5 1 1-5z'),
    'magnifyingglass': '<circle cx="10.5" cy="10.5" r="6.5"/>' + strokePath('M15.5 15.5L21 21'),
    'gamecontroller.fill': fillPath('M7 6h10a5 5 0 014.8 3.7l1 4A3.6 3.6 0 0116.7 17L15.5 15h-7l-1.2 2A3.6 3.6 0 011.2 13.7l1-4A5 5 0 017 6z') + cut('M7.5 9v4M5.5 11h4', 1.8) + '<circle cx="15.5" cy="10" r="1.1" fill="' + BG + '" stroke="none"/><circle cx="18" cy="12.2" r="1.1" fill="' + BG + '" stroke="none"/>',
    'exclamationmark.triangle.fill': fillPath('M10.3 3.6a2 2 0 013.4 0l8.4 14.6A2 2 0 0120.4 21H3.6a2 2 0 01-1.7-2.8z') + cut('M12 9.5v5M12 17.6v.1', 2.4),
    'door.left.hand.open': strokePath('M5 21V4.5A1.5 1.5 0 016.5 3h9A1.5 1.5 0 0117 4.5V21M3 21h18') + '<circle cx="13.8" cy="12.5" r="0.8" fill="currentColor"/>',
    'chevron.down': strokePath('M6 9l6 6 6-6'),
    'chevron.left': strokePath('M15 5l-7 7 7 7'),
    'chevron.right': strokePath('M9 5l7 7-7 7'),
    'trophy.fill': fillPath('M7 3h10v6a5 5 0 01-10 0zM5 4.5H3v2.2A3.3 3.3 0 006.2 10h.3a6.5 6.5 0 01-.7-1.7H5.9A1.9 1.9 0 015 6.7zM19 4.5h2v2.2A3.3 3.3 0 0117.8 10h-.3a6.5 6.5 0 00.7-1.7h.1A1.9 1.9 0 0019 6.7zM11 14h2v3h3v2.5H8V17h3z'),
    'medal.fill': fillPath('M7 2l3 6h4l3-6h-3l-2 4-2-4zM12 9a6 6 0 100 12 6 6 0 000-12z'),
    'trash': strokePath('M4 7h16M10 3h4M6 7l1 13h10l1-13M10 11v6M14 11v6'),
    'trash.fill': fillPath('M9 2.5h6l.8 1.5H21v2H3V4h5.2zM5 7.5h14l-1 13a1.5 1.5 0 01-1.5 1.4h-9A1.5 1.5 0 016 20.5z'),
    'shuffle': strokePath('M3 7h3.5c2 0 3.2 1 4.3 2.6l2.4 3.8c1.1 1.6 2.3 2.6 4.3 2.6H21M3 17h3.5c1.2 0 2.1-.4 2.9-1.1M14 8.4c.9-.9 1.9-1.4 3.2-1.4H21') + strokePath('M18 4l3 3-3 3M18 14l3 3-3 3'),
    'scope': '<circle cx="12" cy="12" r="8"/>' + strokePath('M12 2v4M12 18v4M2 12h4M18 12h4') + '<circle cx="12" cy="12" r="1.2" fill="currentColor"/>',
    'play.fill': fillPath('M7 4.5v15a1 1 0 001.5.9l12-7.5a1 1 0 000-1.8l-12-7.5A1 1 0 007 4.5z'),
    'stop.fill': '<rect x="6" y="6" width="12" height="12" rx="2" fill="currentColor" stroke="none"/>',
    'forward.fill': fillPath('M3 5.5v13a.9.9 0 001.4.8L12 14.3v4.2a.9.9 0 001.4.8l8-6.5a.9.9 0 000-1.6l-8-6.5A.9.9 0 0012 5.5v4.2L4.4 4.7A.9.9 0 003 5.5z'),
    'person.fill': '<circle cx="12" cy="7.5" r="4.2" fill="currentColor" stroke="none"/>' + fillPath('M3.5 21c0-4.6 3.8-7.5 8.5-7.5s8.5 2.9 8.5 7.5z'),
    'person.2.fill': '<circle cx="9" cy="8" r="3.6" fill="currentColor" stroke="none"/>' + fillPath('M2 20c0-3.9 3.1-6.2 7-6.2s7 2.3 7 6.2z') + '<circle cx="17" cy="8.6" r="2.8" fill="currentColor" stroke="none"/>' + fillPath('M16.5 14.2c3.2 0 5.5 1.9 5.5 5.3 0 .3 0 .5-.1.5h-4.2c.1-2-.4-4-1.2-5.8z'),
    'person.3.fill': '<circle cx="12" cy="7" r="3.2" fill="currentColor" stroke="none"/>' + fillPath('M6.5 19c0-3.6 2.4-5.6 5.5-5.6s5.5 2 5.5 5.6z') + '<circle cx="5" cy="9" r="2.4" fill="currentColor" stroke="none"/>' + fillPath('M1 19c0-2.8 1.5-4.4 3.7-4.4.5 0 1 .1 1.4.2-.9 1.2-1.4 2.6-1.5 4.2z') + '<circle cx="19" cy="9" r="2.4" fill="currentColor" stroke="none"/>' + fillPath('M23 19c0-2.8-1.5-4.4-3.7-4.4-.5 0-1 .1-1.4.2.9 1.2 1.4 2.6 1.5 4.2z'),
    'person.fill.xmark': '<circle cx="10" cy="7.5" r="4" fill="currentColor" stroke="none"/>' + fillPath('M2 21c0-4.4 3.6-7 8-7 1.3 0 2.5.2 3.5.7L11 21z') + strokePath('M16.5 14.5l5 5M21.5 14.5l-5 5'),
    'figure.and.child.holdinghands': '<circle cx="8" cy="5" r="2.4" fill="currentColor" stroke="none"/><circle cx="17" cy="9.5" r="1.8" fill="currentColor" stroke="none"/>' + strokePath('M8 8.5v7M8 15.5l-2.5 5.5M8 15.5l2.5 5.5M8 10.5l9 1.5M17 12.5v4M17 16.5l-1.2 4M17 16.5l1.2 4'),
    'figure.2.and.child.holdinghands': '<circle cx="6" cy="5" r="2.2" fill="currentColor" stroke="none"/><circle cx="18" cy="5" r="2.2" fill="currentColor" stroke="none"/><circle cx="12" cy="12" r="1.7" fill="currentColor" stroke="none"/>' + strokePath('M6 8v6.5M6 14.5L4 20M6 14.5L8 20M18 8v6.5M18 14.5l-2 5.5M18 14.5l2 5.5M6 9.5l6 3.5 6-3.5M12 14.5v3M12 17.5l-1 3M12 17.5l1 3'),
    'party.popper.fill': fillPath('M3 21l4-12 8 8z') + strokePath('M13 5l.5-2M17 8l2-1.5M17 3.5v1M20.5 12l1.5.5M12 9c0-2 1-3 3-3') + '<circle cx="19.5" cy="4.5" r="1" fill="currentColor"/>',
    'music.note': strokePath('M9 18V5l11-2v13') + '<circle cx="6.5" cy="18" r="2.8" fill="currentColor"/><circle cx="17.5" cy="16" r="2.8" fill="currentColor"/>',
    'music.note.list': strokePath('M3 6h11M3 11h11M3 16h6M17 19V8l4-1') + '<circle cx="15" cy="19" r="2.2" fill="currentColor"/>',
    'music.quarternote.3': strokePath('M8 17V4M16 17V4M8 4h8') + '<circle cx="5.5" cy="17.5" r="2.5" fill="currentColor"/><circle cx="13.5" cy="17.5" r="2.5" fill="currentColor"/><circle cx="21" cy="14" r="0" fill="currentColor"/>',
    'music.mic': '<rect x="9" y="2.5" width="6" height="11" rx="3" fill="currentColor" stroke="none"/>' + strokePath('M5.5 11a6.5 6.5 0 0013 0M12 17.5V21M8.5 21h7'),
    'mic.fill': '<rect x="9" y="2.5" width="6" height="12" rx="3" fill="currentColor" stroke="none"/>' + strokePath('M5.5 11.5a6.5 6.5 0 0013 0M12 18v3M8.5 21h7'),
    'mic': '<rect x="9" y="2.5" width="6" height="12" rx="3"/>' + strokePath('M5.5 11.5a6.5 6.5 0 0013 0M12 18v3M8.5 21h7'),
    'flag.checkered': strokePath('M5 21V3') + fillPath('M5 4h14l-2 4 2 4H5z') + '<path d="M9 4v8M13 4v8" stroke="' + BG + '" stroke-width="2"/>',
    'ear.fill': fillPath('M6 10a6 6 0 1112 0c0 2.6-1.4 3.8-2.6 5s-1.1 2.2-1.9 3.4A3.6 3.6 0 018 17.2') + cut('M9.2 10a2.8 2.8 0 015.6 0c0 1.4-1.2 1.8-1.8 2.6', 1.8),
    'chart.bar.fill': '<rect x="3.5" y="12" width="4.6" height="9" rx="1.2" fill="currentColor" stroke="none"/><rect x="9.7" y="4" width="4.6" height="17" rx="1.2" fill="currentColor" stroke="none"/><rect x="15.9" y="8.5" width="4.6" height="12.5" rx="1.2" fill="currentColor" stroke="none"/>',
    'bubble.left.and.bubble.right.fill': fillPath('M3 4.5A2.5 2.5 0 015.5 2H13a2.5 2.5 0 012.5 2.5V9A2.5 2.5 0 0113 11.5H8L4.5 14v-2.7A2.5 2.5 0 013 9z') + fillPath('M10 13.5h5.5A2.5 2.5 0 0118 11h.5a2.5 2.5 0 012.5 2.5V17a2.5 2.5 0 01-1.5 2.3V22L16 19.5h-3A2.5 2.5 0 0110.5 17z'),
    'brain': strokePath('M12 5.5V20M12 5.5A3.5 3.5 0 006 7a3 3 0 00-2 5 3 3 0 001.5 5A3.5 3.5 0 0012 18M12 5.5A3.5 3.5 0 0118 7a3 3 0 012 5 3 3 0 01-1.5 5A3.5 3.5 0 0112 18M8.5 11a2 2 0 002-2M15.5 11a2 2 0 01-2-2'),
    'brain.head.profile': strokePath('M12 5.5V20M12 5.5A3.5 3.5 0 006 7a3 3 0 00-2 5 3 3 0 001.5 5A3.5 3.5 0 0012 18M12 5.5A3.5 3.5 0 0118 7a3 3 0 012 5 3 3 0 01-1.5 5A3.5 3.5 0 0112 18'),
    'brain.filled.head.profile': fillPath('M12 4.5A4 4 0 005.8 6.5 3.6 3.6 0 003.3 12a3.6 3.6 0 001.5 5.3A4 4 0 0012 19.5zM12 4.5a4 4 0 016.2 2 3.6 3.6 0 012.5 5.5 3.6 3.6 0 01-1.5 5.3A4 4 0 0112 19.5z'),
    'bolt.fill': fillPath('M13.5 2L4.5 13.5H11L10 22l9-11.5h-6.5z'),
    'arrow.left.arrow.right': strokePath('M3 8h17M16 4l4 4-4 4M21 16H4M8 12l-4 4 4 4'),
    'arrow.clockwise': strokePath('M20 12a8 8 0 11-2.4-5.7M20 4v5h-5'),
    'arrow.counterclockwise': strokePath('M4 12a8 8 0 102.4-5.7M4 4v5h5'),
    'arrow.counterclockwise.circle.fill': disc() + cut('M8 12a4.2 4.2 0 101.3-3M8 7.3v2.2h2.2', 1.8),
    'arrow.up': strokePath('M12 20V4M5 11l7-7 7 7'),
    'arrow.down': strokePath('M12 4v16M5 13l7 7 7-7'),
    'arrow.left': strokePath('M20 12H4M11 5l-7 7 7 7'),
    'arrow.right': strokePath('M4 12h16M13 5l7 7-7 7'),
    'arrow.up.right': strokePath('M7 17L17 7M8 7h9v9'),
    'arrow.right.circle.fill': disc() + cut('M7 12h9M12.5 8.5L16 12l-3.5 3.5', 2.2),
    'arrow.left.circle': '<circle cx="12" cy="12" r="9.5"/>' + strokePath('M17 12H7M11.5 8L7.5 12l4 4'),
    'waveform': strokePath('M4 10v4M8 6v12M12 3v18M16 7v10M20 10v4'),
    'video.fill': '<rect x="2" y="6" width="14" height="12" rx="3" fill="currentColor" stroke="none"/>' + fillPath('M17.5 10.5l4.2-2.6a.5.5 0 01.8.4v7.4a.5.5 0 01-.8.4l-4.2-2.6z'),
    'film.fill': '<rect x="3" y="3" width="18" height="18" rx="3" fill="currentColor" stroke="none"/>' + '<path d="M7 3v18M17 3v18M3 8h4M3 12h4M3 16h4M17 8h4M17 12h4M17 16h4" stroke="' + BG + '" stroke-width="1.6"/>',
    'clapperboard.fill': fillPath('M3 9h18v10a2 2 0 01-2 2H5a2 2 0 01-2-2zM3.4 5.6l16-3.2.7 3.4-16 3.2z'),
    'theatermasks.fill': fillPath('M3 4h10v7a5 5 0 01-10 0z') + fillPath('M11 9h10v7a5 5 0 01-10 0z') + '<path d="M5.5 7.5l1.5 1M10 7.5l-1.5 1M14.5 13.5l1.5 1M19 13.5l-1.5 1" stroke="' + BG + '" stroke-width="1.6"/>',
    'suit.spade.fill': fillPath('M12 2C9 6.5 3.5 9.5 3.5 14a4.5 4.5 0 007.3 3.5c-.2 1.8-.9 3.1-2.3 4h7c-1.4-.9-2.1-2.2-2.3-4a4.5 4.5 0 007.3-3.5C20.5 9.5 15 6.5 12 2z'),
    'square.and.arrow.up': strokePath('M12 15V3M8 7l4-4 4 4M5 11v9h14v-9') ,
    'speaker.slash.fill': fillPath('M3 9.5h3.5L11 5.5v13l-4.5-4H3z') + strokePath('M15 9l6 6M21 9l-6 6'),
    'snowflake': strokePath('M12 2v20M4 7l16 10M20 7L4 17M9.5 3.5L12 6l2.5-2.5M9.5 20.5L12 18l2.5 2.5'),
    'server.rack': '<rect x="3" y="3.5" width="18" height="7" rx="2"/><rect x="3" y="13.5" width="18" height="7" rx="2"/>' + strokePath('M7 7h.01M7 17h.01'),
    'scissors': '<circle cx="6" cy="6.5" r="3"/><circle cx="6" cy="17.5" r="3"/>' + strokePath('M8.2 8.7L21 20M8.2 15.3L21 4'),
    'quote.opening': fillPath('M4 11a5 5 0 015-5v2.4A2.6 2.6 0 006.4 11H9v7H4zM13 11a5 5 0 015-5v2.4A2.6 2.6 0 0015.4 11H18v7h-5z'),
    'qrcode.viewfinder': strokePath('M3 8V5a2 2 0 012-2h3M16 3h3a2 2 0 012 2v3M21 16v3a2 2 0 01-2 2h-3M8 21H5a2 2 0 01-2-2v-3') + '<rect x="7.5" y="7.5" width="3.5" height="3.5" fill="currentColor"/><rect x="13" y="7.5" width="3.5" height="3.5" fill="currentColor"/><rect x="7.5" y="13" width="3.5" height="3.5" fill="currentColor"/>' + strokePath('M14 14h2.5v2.5M16.5 16.5V14'),
    'moon.fill': fillPath('M20.5 14.5A8.5 8.5 0 019.5 3.5 8.5 8.5 0 1020.5 14.5z'),
    'moon.zzz.fill': fillPath('M17 15A7 7 0 018.5 6.5 7 7 0 1017 15z') + strokePath('M15 3h4l-4 4h4M20 9h2l-2 2h2'),
    'moon.stars.fill': fillPath('M17 15A7 7 0 018.5 6.5 7 7 0 1017 15z') + fillPath('M19 3l.7 1.8 1.8.7-1.8.7L19 8l-.7-1.8-1.8-.7 1.8-.7z'),
    'location.fill': fillPath('M21 3L3 10.5l7.5 2.5L13 20.5z'),
    'lightbulb.fill': fillPath('M12 2a6.5 6.5 0 00-3.8 11.8c.6.5.8 1.1.8 1.7V17h6v-1.5c0-.6.2-1.2.8-1.7A6.5 6.5 0 0012 2z') + fillPath('M9.5 19h5v1a2.5 2.5 0 01-5 0z'),
    'key.fill': '<circle cx="8" cy="15" r="5" fill="currentColor" stroke="none"/>' + strokePath('M11.5 11.5L21 2M17 6l3 3M14 9l2 2'),
    'icloud.slash': strokePath('M6 18a4.5 4.5 0 01-.7-8.9A6 6 0 0117 8.5 4.8 4.8 0 0118 18H6zM3 3l18 18'),
    'hammer.fill': fillPath('M14 3h6v5h-3l-3-1.5zM14 7.5l3 1.5L6.5 20.5a2.1 2.1 0 01-3-3z'),
    'eyeglasses.fill': '',
    'delete.left': strokePath('M9 5h11a1 1 0 011 1v12a1 1 0 01-1 1H9L2.5 12z') + strokePath('M12.5 9.5l5 5M17.5 9.5l-5 5'),
    'crown.fill': fillPath('M3 7l4.5 4L12 4l4.5 7L21 7l-2 12H5z'),
    'cross.fill': fillPath('M9 2h6v7h7v6h-7v7H9v-7H2V9h7z'),
    'cpu': '<rect x="6" y="6" width="12" height="12" rx="2"/><rect x="9.5" y="9.5" width="5" height="5" rx="1"/>' + strokePath('M9 2v4M15 2v4M9 18v4M15 18v4M2 9h4M2 15h4M18 9h4M18 15h4'),
    'cloud.fog.fill': fillPath('M7 14a4.5 4.5 0 01-.5-9A6 6 0 0117.7 7 4 4 0 0117 14z') + strokePath('M4 17.5h16M7 21h10'),
    'cloud.drizzle.fill': fillPath('M7 14a4.5 4.5 0 01-.5-9A6 6 0 0117.7 7 4 4 0 0117 14z') + strokePath('M8 17l-1 3M12 17l-1 3M16 17l-1 3'),
    'clock.fill': disc() + cut('M12 6.5V12l3.5 2', 2.2),
    'timer.fill': '<circle cx="12" cy="13.5" r="8.5" fill="currentColor" stroke="none"/>' + strokePath('M9.5 2h5M12 2v3') + cut('M12 8.5v5l3 1.5', 2),
    'clipboard.fill': '<rect x="4.5" y="4" width="15" height="18" rx="2.5" fill="currentColor" stroke="none"/><rect x="8.5" y="2" width="7" height="4" rx="1.5" fill="currentColor"/>' + '<path d="M8 11h8M8 15h5" stroke="' + BG + '" stroke-width="1.8"/>',
    'character.bubble.fill': fillPath('M4 3h16a2 2 0 012 2v10a2 2 0 01-2 2h-6l-5 4v-4H4a2 2 0 01-2-2V5a2 2 0 012-2z') + cut('M8.5 13l2.6-6.5L13.7 13M9.4 11h3.4', 1.8),
    'antenna.radiowaves.left.and.right': strokePath('M12 12v9M8.5 8.5a5 5 0 000 7M15.5 8.5a5 5 0 010 7M5.5 5.5a9 9 0 000 13M18.5 5.5a9 9 0 010 13') + '<circle cx="12" cy="12" r="1.8" fill="currentColor"/>',
    'banknote.fill': '<rect x="2" y="6" width="20" height="12" rx="2.5" fill="currentColor" stroke="none"/><circle cx="12" cy="12" r="2.8" fill="' + BG + '" stroke="none"/>',
    'circle.grid.3x3.fill': sol('<circle cx="5" cy="5" r="2.2"/><circle cx="12" cy="5" r="2.2"/><circle cx="19" cy="5" r="2.2"/><circle cx="5" cy="12" r="2.2"/><circle cx="12" cy="12" r="2.2"/><circle cx="19" cy="12" r="2.2"/><circle cx="5" cy="19" r="2.2"/><circle cx="12" cy="19" r="2.2"/><circle cx="19" cy="19" r="2.2"/>'),
    'square.grid.3x3.fill': sol('<rect x="3" y="3" width="5.2" height="5.2" rx="1"/><rect x="9.4" y="3" width="5.2" height="5.2" rx="1"/><rect x="15.8" y="3" width="5.2" height="5.2" rx="1"/><rect x="3" y="9.4" width="5.2" height="5.2" rx="1"/><rect x="9.4" y="9.4" width="5.2" height="5.2" rx="1"/><rect x="15.8" y="9.4" width="5.2" height="5.2" rx="1"/><rect x="3" y="15.8" width="5.2" height="5.2" rx="1"/><rect x="9.4" y="15.8" width="5.2" height="5.2" rx="1"/><rect x="15.8" y="15.8" width="5.2" height="5.2" rx="1"/>'),
    'record.circle.fill': '<circle cx="12" cy="12" r="9.5"/><circle cx="12" cy="12" r="5" fill="currentColor"/>',
    'a.circle.fill': disc() + cut('M8 16.5l4-9 4 9M9.6 13.5h4.8', 2.2),
    'sailboat.fill': fillPath('M12 3v13H5zM13.5 6l6 10h-6zM3 18h18l-2 3H5z'),
    'dice.fill': '<rect x="3" y="3" width="18" height="18" rx="4" fill="currentColor" stroke="none"/><circle cx="8.5" cy="8.5" r="1.4" fill="' + BG + '" stroke="none"/><circle cx="15.5" cy="8.5" r="1.4" fill="' + BG + '" stroke="none"/><circle cx="12" cy="12" r="1.4" fill="' + BG + '" stroke="none"/><circle cx="8.5" cy="15.5" r="1.4" fill="' + BG + '" stroke="none"/><circle cx="15.5" cy="15.5" r="1.4" fill="' + BG + '" stroke="none"/>',
    'rectangle.stack.fill': '<rect x="3" y="3" width="18" height="4.5" rx="1.5" fill="currentColor" stroke="none" opacity="0.5"/><rect x="3" y="9.5" width="18" height="4.5" rx="1.5" fill="currentColor" stroke="none" opacity="0.75"/><rect x="3" y="16" width="18" height="5" rx="1.5" fill="currentColor" stroke="none"/>',
    'flame.fill': fillPath('M12 2c.6 3.2 3.5 4.8 5.2 7.4A7.2 7.2 0 0112 22a7 7 0 01-6.6-9.3c.6 1.4 1.5 2.3 2.7 2.8C7.8 12 9.6 5.5 12 2z'),
    'questionmark.bubble.fill': fillPath('M4 3h16a2 2 0 012 2v10a2 2 0 01-2 2h-6l-5 4v-4H4a2 2 0 01-2-2V5a2 2 0 012-2z') + cut('M9.8 8.2a2.4 2.4 0 114 1.8c-.8.6-1.8 1-1.8 2.2M12 14.4v.1', 2),
    'paintpalette.fill': fillPath('M12 2a10 10 0 100 20c1.4 0 2-.9 2-1.8 0-1.2-.9-1.4-.9-2.5 0-1 .8-1.7 1.9-1.7H17a5 5 0 005-5C22 6 17.5 2 12 2z') + '<circle cx="7.5" cy="11" r="1.5" fill="' + BG + '" stroke="none"/><circle cx="10.5" cy="6.8" r="1.5" fill="' + BG + '" stroke="none"/><circle cx="15.5" cy="7.5" r="1.5" fill="' + BG + '" stroke="none"/>',
    'circle': '<circle cx="12" cy="12" r="9.5"/>',
    'circle.fill': disc(),
    'house.fill': fillPath('M12 2.5L2 11h2.5v9.5h5.5v-6h4v6h5.5V11H22z'),
    'puzzlepiece.fill': fillPath('M10 3a2 2 0 014 0v2h4a2 2 0 012 2v3h-2a2 2 0 100 4h2v4a2 2 0 01-2 2h-3v-2a2 2 0 10-4 0v2H6a2 2 0 01-2-2v-4h2a2 2 0 100-4H4V7a2 2 0 012-2h4z'),
    'heart.fill': fillPath(HEART),
    'heart': strokePath(HEART),
    'square.grid.2x2.fill': sol('<rect x="3" y="3" width="8.2" height="8.2" rx="1.6"/><rect x="12.8" y="3" width="8.2" height="8.2" rx="1.6"/><rect x="3" y="12.8" width="8.2" height="8.2" rx="1.6"/><rect x="12.8" y="12.8" width="8.2" height="8.2" rx="1.6"/>'),
    'textformat.123': fillPath('M3 16.5V8.5L5 9.5V16.5zM8 10.5h4.5v2.5H10v1h2.5v2.5H8z') ,
    'burst.fill': fillPath('M12 1l2.2 5.3 5.1-2.6-1.6 5.5 5.8.6-4.7 3.3 3.6 4.5-5.6-1.1-.5 5.7L12 17.9 8.7 22.2l-.5-5.7-5.6 1.1L6.2 13 1.5 9.7l5.8-.6-1.6-5.5 5.1 2.6z'),
    'chart.line.uptrend.xyaxis': strokePath('M3 3v18h18M7 15l4-4 3 3 6-7M15 7h5v5'),
    'checkerboard.rectangle': '<rect x="3" y="3" width="18" height="18" rx="2"/>' + sol('<rect x="3" y="3" width="6" height="6"/><rect x="15" y="3" width="6" height="6"/><rect x="9" y="9" width="6" height="6"/><rect x="3" y="15" width="6" height="6"/><rect x="15" y="15" width="6" height="6"/>'),
    'hockey.puck.fill': '<ellipse cx="12" cy="9" rx="9" ry="4" fill="currentColor" stroke="none"/>' + fillPath('M3 9v6c0 2.2 4 4 9 4s9-1.8 9-4V9c0 2.2-4 4-9 4S3 11.2 3 9z'),
    'circle.dashed': '<circle cx="12" cy="12" r="9" stroke-dasharray="3.4 3"/>',
    'waveform.path': strokePath('M3 14c3 0 3-8 6-8s3 12 6 12 3-8 6-8'),
    'rectangle.grid.2x2.fill': sol('<rect x="3" y="4" width="8.2" height="7" rx="1.4"/><rect x="12.8" y="4" width="8.2" height="7" rx="1.4"/><rect x="3" y="13" width="8.2" height="7" rx="1.4"/><rect x="12.8" y="13" width="8.2" height="7" rx="1.4"/>'),
    'circle.grid.2x2.fill': sol('<circle cx="7" cy="7" r="3.6"/><circle cx="17" cy="7" r="3.6"/><circle cx="7" cy="17" r="3.6"/><circle cx="17" cy="17" r="3.6"/>'),
    'text.book.closed.fill': fillPath('M6 2h12a2 2 0 012 2v16a2 2 0 01-2 2H6a2 2 0 01-2-2V4a2 2 0 012-2z') + '<path d="M8 7h8M8 11h6" stroke="' + BG + '" stroke-width="1.6"/>',
    'globe': '<circle cx="12" cy="12" r="9.5"/>' + strokePath('M2.5 12h19M12 2.5c3 3 3 16 0 19M12 2.5c-3 3-3 16 0 19'),
    'figure.dance': '<circle cx="13" cy="4.5" r="2.2" fill="currentColor" stroke="none"/>' + strokePath('M13 8l-1 5-3 2M12 13l4 3 1 5M13 8l5-2M12 13l-1 8'),
    'triangle.fill': fillPath('M12 3l10 17.5H2z'),
    'diamond.fill': fillPath('M12 1.5l10 10.5-10 10.5L2 12z'),
    'square.fill': '<rect x="3" y="3" width="18" height="18" rx="2.5" fill="currentColor" stroke="none"/>',
    'door.left.hand.closed': '<rect x="5.5" y="3" width="13" height="18" rx="1.8"/><circle cx="15" cy="12" r="0.9" fill="currentColor"/>' + strokePath('M3 21h18'),
    'nosign': '<circle cx="12" cy="12" r="9.5"/>' + strokePath('M5.3 5.3l13.4 13.4'),
    'stopwatch.fill': '<circle cx="12" cy="13.5" r="8.5" fill="currentColor" stroke="none"/>' + strokePath('M9.5 2h5M12 2v3') + cut('M12 8.5v5.5l3 1.5', 2),
    'person': '<circle cx="12" cy="7.5" r="4"/>' + strokePath('M4 21c0-4.4 3.6-7 8-7s8 2.6 8 7'),
    'mappin': strokePath('M12 21s-7-6.2-7-11.5a7 7 0 0114 0C19 14.8 12 21 12 21z') + '<circle cx="12" cy="9.5" r="2.5"/>',
    'pawprint': '<circle cx="6" cy="10" r="2"/><circle cx="10" cy="5.5" r="2"/><circle cx="14.5" cy="5.5" r="2"/><circle cx="18.5" cy="10" r="2"/>' + strokePath('M12 12c-3 0-5.5 3-5.5 5.5 0 1.800 1.500 2.500 3 2.500 1.200 0 1.800-.5 2.500-.5s1.300.5 2.500.5c1.500 0 3-.7 3-2.500C17.500 15 15 12 12 12z'),
    'cube': strokePath('M12 2.5l9 4.500v10L12 21.500 3 17V7z M3 7l9 4.500L21 7M12 11.500v10'),
    'mappin.and.ellipse': strokePath('M12 21s-6-5.200-6-10a6 6 0 0112 0c0 4.800-6 10-6 10z') + '<circle cx="12" cy="11" r="2.200"/>',
    'chevron.up': strokePath('M6 15l6-6 6 6'),
    'minus': strokePath('M5 12h14'),
    'textformat.abc': strokePath('M3 17l4.500-11L12 17M4.500 13h5M14 11.500a3 3 0 015.500 1.500v4M19.500 15c-3 0-5.500.5-5.500 2.500 0 1.200 1 2 2.500 2 1.500 0 3-.8 3-2.500') ,
    'textformat': strokePath('M4 18L10 4l6 14M6 13.500h8M18 10h3M19.500 10v8'),
    'arrow.triangle.2.circlepath': strokePath('M4 11a8 8 0 0114-4.500M20 4v4h-4M20 13a8 8 0 01-14 4.500M4 20v-4h4'),
    'suit.heart.fill': fillPath('M12 21.500S3 15.500 3 9.200A5 5 0 0112 6.500a5 5 0 019 2.700c0 6.300-9 12.300-9 12.300z'),
    'suit.diamond.fill': fillPath('M12 1.500l8 10.500-8 10.500L4 12z'),
    'suit.club.fill': '<circle cx="12" cy="7" r="4.500" fill="currentColor" stroke="none"/><circle cx="6.500" cy="14" r="4.500" fill="currentColor" stroke="none"/><circle cx="17.500" cy="14" r="4.500" fill="currentColor" stroke="none"/>' + fillPath('M10.500 14h3l1.500 8h-6z'),
    '1.circle.fill': disc() + cut('M10 9.500l2.500-1.500v8', 2.200),
    '2.circle.fill': disc() + cut('M9.500 9.500a2.500 2.500 0 015 .5c0 2-5 3.500-5 6h5.200', 2),
    'person.fill.questionmark': '<circle cx="9.500" cy="7.500" r="4" fill="currentColor" stroke="none"/>' + fillPath('M2 21c0-4.400 3.400-7 7.500-7 1.200 0 2.300.2 3.200.7L11 21z') + strokePath('M15.500 15.500a2.500 2.500 0 114 1.800c-.8.600-1.500 1-1.500 2.200M18 22v.1'),
    'dot': '<circle cx="12" cy="12" r="3" fill="currentColor" stroke="none"/>',
    'sun.max.fill': '<circle cx="12" cy="12" r="4.5" fill="currentColor" stroke="none"/>' + strokePath('M12 2v2.5M12 19.5V22M2 12h2.5M19.5 12H22M4.9 4.9l1.8 1.8M17.3 17.3l1.8 1.8M4.9 19.1l1.8-1.8M17.3 6.7l1.8-1.8'),
    'questionmark': strokePath('M8.5 8.5a3.5 3.5 0 117 0c0 2.5-3.5 3-3.5 5.5M12 18.5v.1'),
    'exclamationmark': strokePath('M12 4v10M12 19v.1'),
    'info.circle.fill': disc() + cut('M12 11v6M12 7.6v.1', 2.4),
    'speaker.wave.2.fill': fillPath('M3 9.5h3.5L11 5.5v13l-4.5-4H3z') + strokePath('M15 9a4 4 0 010 6M17.5 6.5a8 8 0 010 11'),
    'rectangle.portrait.and.arrow.right': strokePath('M10 4H6a2 2 0 00-2 2v12a2 2 0 002 2h4M16 8l4 4-4 4M20 12H9')
  };

  function norm(name) {
    if (I[name]) { return I[name]; }
    // tolerate a missing ".fill"
    if (I[name + '.fill']) { return I[name + '.fill']; }
    return I.dot;
  }

  /** AP.icon('star.fill', 20, '#fff') -> inline <svg> element. */
  AP.icon = function (name, size, color, extra) {
    var s = size || 20;
    var svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('viewBox', '0 0 24 24');
    svg.setAttribute('width', s);
    svg.setAttribute('height', s);
    svg.setAttribute('fill', 'none');
    svg.setAttribute('stroke', 'currentColor');
    svg.setAttribute('stroke-width', '2');
    svg.setAttribute('stroke-linecap', 'round');
    svg.setAttribute('stroke-linejoin', 'round');
    svg.setAttribute('class', 'ic' + (extra ? ' ' + extra : ''));
    svg.setAttribute('aria-hidden', 'true');
    if (color) { svg.style.color = color; }
    svg.innerHTML = norm(name);
    return svg;
  };
  AP.hasIcon = function (name) { return !!I[name]; };
})();
