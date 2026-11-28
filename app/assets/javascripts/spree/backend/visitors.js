// Visitors, Live tab (/admin/visitors): the table of online sessions is redrawn from the server
// every 15 s while the tab is visible (GET /admin/visitors?rows=1 returns its rows).
(function (window, document) {
  'use strict';

  var T = window.AdminTools;
  var REFRESH_MS = 15000;

  document.addEventListener('DOMContentLoaded', function () {
    var root = document.getElementById('visitors-live');
    if (!root) return;
    var rows = root.querySelector('[data-role="rows"]');
    var count = root.querySelector('[data-role="count"]');
    var updated = root.querySelector('[data-role="updated"]');
    var url = root.getAttribute('data-rows-url');

    function refresh() {
      // Keeps the focus on the same row's button across the redraw.
      var focused = document.activeElement && rows.contains(document.activeElement) ? document.activeElement.closest('[data-session]') : null;
      var focusedId = focused && focused.getAttribute('data-session');
      return window.fetch(url, { headers: { Accept: 'text/html', 'X-Requested-With': 'XMLHttpRequest' }, credentials: 'same-origin' })
        .then(function (response) {
          if (!response.ok) throw new Error('refresh failed');
          return response.text();
        })
        .then(function (html) {
          rows.innerHTML = html;
          var first = rows.querySelector('[data-total]');
          if (first && count) count.textContent = first.getAttribute('data-total');
          if (updated) updated.textContent = 'Updated ' + new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' }) + '.';
          if (focusedId) {
            var row = rows.querySelector('[data-session="' + focusedId + '"]');
            var target = row && row.querySelector('a, button');
            if (target) target.focus();
          }
        })
        .catch(function () { /* the next refresh tries again */ });
    }

    T.poll(refresh, REFRESH_MS);
  });
})(window, document);
