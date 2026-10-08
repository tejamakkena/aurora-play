/* Aurora Play web controller: tiny DOM toolkit.
 *
 * h() builds elements, patch() morphs a live tree into a freshly built one so
 * controllers can simply re-render on every server update (the way SwiftUI
 * does) without losing focus, scroll position or running CSS transitions.
 */
(function () {
  'use strict';
  var AP = window.AP = window.AP || {};

  var SVG_NS = 'http://www.w3.org/2000/svg';
  var SVG_TAGS = { svg: 1, path: 1, circle: 1, rect: 1, g: 1, line: 1, polyline: 1,
                   polygon: 1, ellipse: 1, defs: 1, lineargradient: 1, stop: 1, text: 1 };

  function setProp(el, key, val) {
    if (val === undefined || val === null || val === false) {
      if (key === 'value') { el.value = ''; }
      return;
    }
    if (key === 'class') {
      if (el.namespaceURI === SVG_NS) { el.setAttribute('class', val); } else { el.className = val; }
    } else if (key === 'style') {
      if (typeof val === 'string') {
        el.style.cssText = val;
      } else {
        for (var s in val) {
          if (val[s] === null || val[s] === undefined) { continue; }
          if (s.indexOf('--') === 0) { el.style.setProperty(s, val[s]); } else { el.style[s] = val[s]; }
        }
      }
    } else if (key.slice(0, 2) === 'on' && typeof val === 'function') {
      el[key] = val;
      (el._evts = el._evts || {})[key] = true;
    } else if (key === 'value') {
      el.value = val;
    } else if (key === 'checked' || key === 'disabled' || key === 'selected') {
      el[key] = !!val;
      if (val) { el.setAttribute(key, ''); }
    } else if (key === 'key') {
      el._key = String(val);
    } else if (val === true) {
      el.setAttribute(key, '');
    } else {
      el.setAttribute(key, String(val));
    }
  }

  function append(el, kids) {
    for (var i = 0; i < kids.length; i++) {
      var k = kids[i];
      if (k === null || k === undefined || k === false || k === true) { continue; }
      if (Array.isArray(k)) { append(el, k); continue; }
      el.appendChild(k.nodeType ? k : document.createTextNode(String(k)));
    }
  }

  function h(tag, props) {
    var isSvg = !!SVG_TAGS[tag.toLowerCase()];
    var el = isSvg ? document.createElementNS(SVG_NS, tag) : document.createElement(tag);
    if (props) { for (var k in props) { setProp(el, k, props[k]); } }
    append(el, Array.prototype.slice.call(arguments, 2));
    return el;
  }

  // ---- morphing -------------------------------------------------------

  function sameKind(a, b) {
    if (a.nodeType !== b.nodeType) { return false; }
    if (a.nodeType === 3) { return true; }
    return a.nodeName === b.nodeName && (a._key || '') === (b._key || '') &&
           (a.type || '') === (b.type || '');
  }

  function syncAttrs(oldEl, newEl) {
    var i, name;
    // remove attributes that are gone
    for (i = oldEl.attributes.length - 1; i >= 0; i--) {
      name = oldEl.attributes[i].name;
      if (!newEl.hasAttribute(name) && name !== 'value' && name !== 'style' &&
          !(oldEl.nodeName === 'CANVAS' && (name === 'width' || name === 'height'))) {
        oldEl.removeAttribute(name);
      }
    }
    for (i = 0; i < newEl.attributes.length; i++) {
      name = newEl.attributes[i].name;
      var v = newEl.attributes[i].value;
      if (name === 'value' && /^(INPUT|TEXTAREA|SELECT)$/.test(oldEl.nodeName)) { continue; }
      if (oldEl.nodeName === 'CANVAS' && (name === 'width' || name === 'height')) { continue; }
      if (oldEl.getAttribute(name) !== v) { oldEl.setAttribute(name, v); }
    }
    // style: replace wholesale, but keep it cheap when unchanged
    var ns = newEl.getAttribute('style') || '';
    if ((oldEl.getAttribute('style') || '') !== ns) {
      if (ns) { oldEl.setAttribute('style', ns); } else { oldEl.removeAttribute('style'); }
    }
    // event handlers live as properties
    var evts = newEl._evts || {};
    var oldEvts = oldEl._evts || {};
    for (var e in oldEvts) { if (!evts[e]) { oldEl[e] = null; } }
    for (e in evts) { oldEl[e] = newEl[e]; }
    oldEl._evts = evts;
    oldEl._key = newEl._key;
    if (/^(INPUT|TEXTAREA|SELECT)$/.test(oldEl.nodeName)) {
      if (oldEl.type === 'checkbox' || oldEl.type === 'radio') {
        if (oldEl.checked !== newEl.checked) { oldEl.checked = newEl.checked; }
      } else if (oldEl.value !== newEl.value) {
        oldEl.value = newEl.value;
      }
      oldEl.disabled = newEl.disabled;
    }
  }

  function morphChildren(oldParent, newParent) {
    var oldKids = Array.prototype.slice.call(oldParent.childNodes);
    var newKids = Array.prototype.slice.call(newParent.childNodes);
    var keyed = {};
    var i;
    for (i = 0; i < oldKids.length; i++) {
      if (oldKids[i]._key) { keyed[oldKids[i]._key] = oldKids[i]; }
    }
    var cursor = 0;
    var used = [];
    for (i = 0; i < newKids.length; i++) {
      var nk = newKids[i];
      var match = null;
      if (nk._key) {
        match = keyed[nk._key] || null;
      } else {
        while (cursor < oldKids.length &&
               (oldKids[cursor]._key || used.indexOf(oldKids[cursor]) >= 0)) { cursor++; }
        if (cursor < oldKids.length && sameKind(oldKids[cursor], nk)) {
          match = oldKids[cursor];
          cursor++;
        }
      }
      var ref = oldParent.childNodes[i] || null;
      if (match) {
        used.push(match);
        if (match !== ref) { oldParent.insertBefore(match, ref); }
        morph(match, nk);
      } else {
        oldParent.insertBefore(nk, ref);
      }
    }
    // drop whatever was not reused
    for (i = oldParent.childNodes.length - 1; i >= newKids.length; i--) {
      oldParent.removeChild(oldParent.childNodes[i]);
    }
  }

  function morph(oldEl, newEl) {
    if (oldEl.nodeType === 3) {
      if (oldEl.nodeValue !== newEl.nodeValue) { oldEl.nodeValue = newEl.nodeValue; }
      return;
    }
    if (oldEl.nodeName === 'svg' || oldEl.namespaceURI === SVG_NS) {
      // SVG subtrees are small; swap content wholesale when it differs.
      if (oldEl.outerHTML !== newEl.outerHTML) { oldEl.replaceWith(newEl); }
      return;
    }
    syncAttrs(oldEl, newEl);
    morphChildren(oldEl, newEl);
  }

  /** Make `root`'s children match `tree` (a node or array of nodes). */
  function patch(root, tree) {
    var holder = document.createElement('div');
    append(holder, [tree]);
    morphChildren(root, holder);
  }

  AP.h = h;
  AP.patch = patch;
  AP.$ = function (sel, root) { return (root || document).querySelector(sel); };
})();
