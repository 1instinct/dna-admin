(function() {
  'use strict';

  var API_URL = '/api/v1/content_assets';
  var selectedAsset = {};

  function loadAssets(modalId, search, tag) {
    var url = API_URL + '?limit=50';
    if (search) url += '&search=' + encodeURIComponent(search);
    if (tag) url += '&tag=' + encodeURIComponent(tag);

    var grid = document.querySelector('.content-asset-grid[data-modal-id="' + modalId + '"]');
    if (!grid) return;
    grid.innerHTML = '<p style="grid-column:1/-1;text-align:center;">Loading...</p>';

    fetch(url)
      .then(function(r) { return r.json(); })
      .then(function(data) {
        var assets = data.response_data.content_assets || [];
        grid.innerHTML = '';
        if (assets.length === 0) {
          grid.innerHTML = '<p style="grid-column:1/-1;text-align:center;color:#999;">No images found.</p>';
          return;
        }
        assets.forEach(function(asset) {
          var thumb = asset.urls && (asset.urls.small || asset.urls.original) || '';
          var card = document.createElement('div');
          card.className = 'content-asset-thumb';
          card.setAttribute('data-asset-id', asset.id);
          card.setAttribute('data-asset-url', asset.urls.original || '');
          card.setAttribute('data-modal-id', modalId);
          card.style.cssText = 'cursor:pointer;border:2px solid transparent;border-radius:4px;overflow:hidden;background:#f8f9fa;';
          card.innerHTML =
            '<img src="' + thumb + '" style="width:100%;height:100px;object-fit:cover;" alt="' + (asset.alt_text || '') + '">' +
            '<div style="padding:4px;font-size:11px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">' +
              (asset.original_filename || '') +
            '</div>';
          card.addEventListener('click', function() {
            grid.querySelectorAll('.content-asset-thumb').forEach(function(el) {
              el.style.borderColor = 'transparent';
            });
            card.style.borderColor = '#007bff';
            selectedAsset[modalId] = asset.urls.original || '';
            var selectBtn = document.querySelector('.content-asset-select-btn[data-modal-id="' + modalId + '"]');
            if (selectBtn) selectBtn.disabled = false;
          });
          grid.appendChild(card);
        });

        var tags = [];
        assets.forEach(function(a) { if (a.tag && tags.indexOf(a.tag) === -1) tags.push(a.tag); });
        var tagSelect = document.querySelector('.content-asset-tag-filter[data-modal-id="' + modalId + '"]');
        if (tagSelect && tagSelect.options.length <= 1) {
          tags.sort().forEach(function(t) {
            var opt = document.createElement('option');
            opt.value = t;
            opt.textContent = t.charAt(0).toUpperCase() + t.slice(1);
            tagSelect.appendChild(opt);
          });
        }
      })
      .catch(function() {
        grid.innerHTML = '<p style="grid-column:1/-1;text-align:center;color:red;">Failed to load images.</p>';
      });
  }

  $(document).on('shown.bs.modal', '.content-asset-picker-modal', function() {
    var modalId = this.id;
    selectedAsset[modalId] = null;
    var selectBtn = document.querySelector('.content-asset-select-btn[data-modal-id="' + modalId + '"]');
    if (selectBtn) selectBtn.disabled = true;
    loadAssets(modalId, '', '');
  });

  var searchTimeout;
  $(document).on('input', '.content-asset-search', function() {
    var input = this;
    var modalId = input.getAttribute('data-modal-id');
    var tag = document.querySelector('.content-asset-tag-filter[data-modal-id="' + modalId + '"]');
    clearTimeout(searchTimeout);
    searchTimeout = setTimeout(function() {
      loadAssets(modalId, input.value, tag ? tag.value : '');
    }, 300);
  });

  $(document).on('change', '.content-asset-tag-filter', function() {
    var modalId = this.getAttribute('data-modal-id');
    var search = document.querySelector('.content-asset-search[data-modal-id="' + modalId + '"]');
    loadAssets(modalId, search ? search.value : '', this.value);
  });

  $(document).on('click', '.content-asset-select-btn', function() {
    var modalId = this.getAttribute('data-modal-id');
    var targetFieldId = this.getAttribute('data-target-field');
    var url = selectedAsset[modalId];
    if (url && targetFieldId) {
      var field = document.getElementById(targetFieldId);
      if (field) {
        field.value = url;
        field.dispatchEvent(new Event('change'));
      }
      var preview = document.getElementById('preview_' + targetFieldId);
      if (preview) {
        preview.innerHTML = '<img src="' + url + '" style="max-width:60px;max-height:40px;margin-left:8px;border-radius:4px;">';
      }
    }
    $('#' + modalId).modal('hide');
  });

  $(document).on('change', '.content-asset-inline-upload', function() {
    var fileInput = this;
    var modalId = fileInput.getAttribute('data-modal-id');
    var file = fileInput.files[0];
    if (!file) return;

    var formData = new FormData();
    formData.append('file', file);
    formData.append('alt_text', file.name.replace(/\.[^.]+$/, ''));

    var token = document.querySelector('meta[name="csrf-token"]');

    fetch(API_URL, {
      method: 'POST',
      headers: {
        'X-CSRF-Token': token ? token.getAttribute('content') : '',
        'X-Spree-Token': (window.Spree && window.Spree.api_key) || ''
      },
      body: formData
    })
    .then(function(r) { return r.json(); })
    .then(function(data) {
      if (data.response_code === 200) {
        var search = document.querySelector('.content-asset-search[data-modal-id="' + modalId + '"]');
        var tag = document.querySelector('.content-asset-tag-filter[data-modal-id="' + modalId + '"]');
        loadAssets(modalId, search ? search.value : '', tag ? tag.value : '');
      } else {
        alert('Upload failed: ' + (data.response_message || 'Unknown error'));
      }
    })
    .catch(function() { alert('Upload failed.'); });

    fileInput.value = '';
  });
})();
