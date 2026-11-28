// Shared helpers for the menu builder, inbox and visitors pages: JSON requests with the admin's
// session and CSRF token, a small DOM builder (text always goes in as textContent) and a polite
// screen reader announcer.
(function (window, document) {
  'use strict';

  function csrfToken() {
    var meta = document.querySelector('meta[name="csrf-token"]');
    return meta ? meta.getAttribute('content') : null;
  }

  // Resolves with the parsed JSON (or {} for an empty body). Rejects with
  // { status, code, message } from the server's { error: { code, message } }.
  function request(method, url, body) {
    var headers = { Accept: 'application/json', 'X-Requested-With': 'XMLHttpRequest' };
    var token = csrfToken();
    if (token) headers['X-CSRF-Token'] = token;
    var payload;
    if (body instanceof window.FormData) {
      payload = body;
    } else if (body !== undefined && body !== null) {
      headers['Content-Type'] = 'application/json';
      payload = JSON.stringify(body);
    }
    return window.fetch(url, { method: method, headers: headers, body: payload, credentials: 'same-origin' })
      .then(function (response) {
        return response.text().then(function (text) {
          var data = {};
          if (text) {
            try { data = JSON.parse(text); } catch (e) { data = {}; }
          }
          if (response.ok) return data;
          var error = (data && data.error) || {};
          var failure = new Error(error.message || ('The request failed (' + response.status + ').'));
          failure.status = response.status;
          failure.code = error.code || 'error';
          throw failure;
        });
      }, function () {
        var failure = new Error('Could not reach the server. Check your connection and try again.');
        failure.status = 0;
        failure.code = 'network';
        throw failure;
      });
  }

  // el('a', { href: url, className: 'x', text: 'Label', data: { id: 1 }, attrs: { 'aria-label': 'y' } }, [children])
  function el(tag, options, children) {
    var node = document.createElement(tag);
    options = options || {};
    Object.keys(options).forEach(function (key) {
      var value = options[key];
      if (value === null || value === undefined || value === false) return;
      if (key === 'text') node.textContent = value;
      else if (key === 'className') node.className = value;
      else if (key === 'data') Object.keys(value).forEach(function (k) { if (value[k] !== null && value[k] !== undefined) node.setAttribute('data-' + k, value[k]); });
      else if (key === 'attrs') Object.keys(value).forEach(function (k) { if (value[k] !== null && value[k] !== undefined && value[k] !== false) node.setAttribute(k, value[k]); });
      else if (key === 'on') Object.keys(value).forEach(function (k) { node.addEventListener(k, value[k]); });
      else node[key] = value;
    });
    (children || []).forEach(function (child) {
      if (child === null || child === undefined || child === false) return;
      node.appendChild(typeof child === 'string' ? document.createTextNode(child) : child);
    });
    return node;
  }

  function announce(region, text) {
    if (!region) return;
    region.textContent = '';
    window.setTimeout(function () { region.textContent = text; }, 50);
  }

  function flash(type, message) {
    if (typeof window.show_flash === 'function') window.show_flash(type, message);
  }

  // "3 min", "2 h", "4 d" since an ISO time.
  function ago(iso, now) {
    if (!iso) return '';
    var seconds = Math.max(0, Math.round(((now || Date.now()) - new Date(iso).getTime()) / 1000));
    if (seconds < 60) return seconds + ' s';
    if (seconds < 3600) return Math.floor(seconds / 60) + ' min';
    if (seconds < 86400) return Math.floor(seconds / 3600) + ' h';
    return Math.floor(seconds / 86400) + ' d';
  }

  function formatTime(iso) {
    if (!iso) return '';
    var date = new Date(iso);
    var today = new Date();
    var sameDay = date.toDateString() === today.toDateString();
    return sameDay ? date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
                   : date.toLocaleString([], { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
  }

  // Calls fn every `ms` while the tab is visible; a hidden tab pauses it and showing the tab runs
  // it at once. Returns { stop, now }.
  function poll(fn, ms) {
    var timer = null;
    var stopped = false;
    function schedule() {
      window.clearTimeout(timer);
      if (!stopped && !document.hidden) timer = window.setTimeout(tick, ms);
    }
    function tick() {
      if (stopped || document.hidden) return;
      var result = fn();
      if (result && typeof result.then === 'function') result.then(schedule, schedule);
      else schedule();
    }
    function onVisibility() {
      if (document.hidden) window.clearTimeout(timer);
      else tick();
    }
    document.addEventListener('visibilitychange', onVisibility);
    schedule();
    return {
      stop: function () { stopped = true; window.clearTimeout(timer); document.removeEventListener('visibilitychange', onVisibility); },
      now: function () { window.clearTimeout(timer); tick(); }
    };
  }

  window.AdminTools = {
    request: request,
    el: el,
    announce: announce,
    flash: flash,
    ago: ago,
    formatTime: formatTime,
    poll: poll
  };
})(window, document);
