(function() {
  'use strict';

  function initThemeEditor() {
    var form = document.getElementById('theme-editor-form');
    if (!form) return;

    var preview = document.getElementById('theme-preview');
    if (!preview) return;

    function renderPreview() {
      var p = getValues();
      preview.style.background = p.background_color;
      preview.style.color = p.text_color;
      preview.style.fontFamily = p.font_family;
      preview.innerHTML =
        '<div style="display:flex; min-height: 280px;">' +
          '<div style="width: 140px; background:' + p.sidebar_color + '; border-right: 1px solid rgba(255,255,255,0.08); padding: 12px 8px;">' +
            '<div style="font-weight:600; font-size:11px; color:' + p.text_color + '; margin-bottom:16px; padding: 4px;">&#9776; Admin</div>' +
            '<div style="padding:6px 8px; margin-bottom:4px; border-radius:' + p.border_radius + '; background: linear-gradient(135deg, ' + p.primary_color + '1a, transparent); border-left: 2px solid ' + p.primary_color + '; color:' + p.primary_color + '; font-size:11px;">Dashboard</div>' +
            '<div style="padding:6px 8px; margin-bottom:4px; border-radius:' + p.border_radius + '; color: #94a3b8; font-size:11px;">Products</div>' +
            '<div style="padding:6px 8px; margin-bottom:4px; border-radius:' + p.border_radius + '; color: #94a3b8; font-size:11px;">Orders</div>' +
            '<div style="padding:6px 8px; border-radius:' + p.border_radius + '; color: #94a3b8; font-size:11px;">Settings</div>' +
          '</div>' +
          '<div style="flex:1; padding:16px;">' +
            '<div style="font-weight:600; font-size:14px; letter-spacing:-0.02em; margin-bottom:12px; color:' + p.text_color + ';">Dashboard</div>' +
            '<div style="background:' + p.surface_color + '; border: 1px solid rgba(255,255,255,0.08); border-radius:' + p.border_radius + '; overflow:hidden; margin-bottom:12px;">' +
              '<div style="padding:8px 12px; font-size:10px; text-transform:uppercase; letter-spacing:0.05em; color:#94a3b8; background: #232340;">Name &middot; Status &middot; Date</div>' +
              '<div style="padding:8px 12px; font-size:11px; border-bottom: 1px solid rgba(255,255,255,0.08);">Starter Kit &middot; Active &middot; Apr 24</div>' +
              '<div style="padding:8px 12px; font-size:11px;">Replacement &middot; Draft &middot; Apr 20</div>' +
            '</div>' +
            '<button style="background: linear-gradient(135deg, ' + p.primary_color + ', ' + p.secondary_color + '); color: white; border: none; padding: 6px 16px; border-radius:' + p.border_radius + '; font-size:12px; cursor:pointer;">Save Changes</button>' +
            '<div style="margin-top:12px; background:' + p.surface_color + '; border:1px solid rgba(255,255,255,0.08); border-radius:' + p.border_radius + '; padding:12px;">' +
              '<div style="font-size:11px; color:#94a3b8; text-transform:uppercase; letter-spacing:0.05em; margin-bottom:4px;">Revenue</div>' +
              '<div style="font-size:18px; font-weight:600; color:' + p.text_color + ';">$12,450</div>' +
            '</div>' +
          '</div>' +
        '</div>';
    }

    function getValues() {
      return {
        primary_color: getValue('primary_color'),
        secondary_color: getValue('secondary_color'),
        surface_color: getValue('surface_color'),
        background_color: getValue('background_color'),
        text_color: getValue('text_color'),
        sidebar_color: getValue('sidebar_color'),
        border_radius: form.querySelector('[name="admin_theme[border_radius]"]').value,
        font_family: form.querySelector('[name="admin_theme[font_family]"]').value
      };
    }

    function getValue(field) {
      var el = form.querySelector('#admin_theme_' + field);
      return el ? el.value : '';
    }

    // Sync color picker <-> text input
    form.querySelectorAll('input[type="color"]').forEach(function(picker) {
      var targetId = picker.getAttribute('data-target');
      var textInput = document.getElementById(targetId);
      if (!textInput) return;

      picker.addEventListener('input', function() {
        textInput.value = picker.value;
        renderPreview();
      });

      textInput.addEventListener('input', function() {
        if (/^#[0-9a-fA-F]{6}$/.test(textInput.value)) {
          picker.value = textInput.value;
        }
        renderPreview();
      });
    });

    // Other form inputs
    form.querySelectorAll('select, input[type="range"]').forEach(function(el) {
      el.addEventListener('input', renderPreview);
      el.addEventListener('change', renderPreview);
    });

    renderPreview();
  }

  // Turbolinks-compatible
  document.addEventListener('turbolinks:load', initThemeEditor);
  document.addEventListener('DOMContentLoaded', initThemeEditor);
})();
