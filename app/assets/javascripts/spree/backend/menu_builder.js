// The menu builder (/admin/menus): one location's items as a nested list. Drag (SortableJS, which
// Spree's backend already loads), the row buttons or Alt+Arrow keys move items; every move is
// saved at once and the tree is redrawn from the server's answer, or put back as it was with a
// flash message when the server refuses it.
(function (window, document, $) {
  'use strict';

  var T = window.AdminTools;

  function MenuBuilder(root) {
    this.root = root;
    this.treeUrl = root.getAttribute('data-tree-url');
    this.itemsUrl = root.getAttribute('data-items-url');
    this.kinds = JSON.parse(root.getAttribute('data-link-kinds') || '[]');
    this.list = root.querySelector('[data-role="root"]');
    this.empty = root.querySelector('[data-role="empty"]');
    this.loading = root.querySelector('[data-role="loading"]');
    this.status = root.querySelector('[data-role="status"]');
    this.modal = document.getElementById('menu-item-modal');
    this.deleteModal = document.getElementById('menu-delete-modal');
    this.tree = [];
    this.sortables = [];
    this.busy = false;
    this.bind();
    this.load();
  }

  MenuBuilder.prototype.bind = function () {
    var self = this;
    this.root.addEventListener('click', function (event) {
      var button = event.target.closest('[data-action]');
      if (!button || !self.root.contains(button)) return;
      var item = button.closest('[data-id]');
      var id = item ? item.getAttribute('data-id') : null;
      var action = button.getAttribute('data-action');
      if (action === 'add-root') self.inlineAdd(null, null, button);
      else if (!id) return;
      else if (action === 'up') self.step(id, 'up');
      else if (action === 'down') self.step(id, 'down');
      else if (action === 'indent') self.step(id, 'indent');
      else if (action === 'outdent') self.step(id, 'outdent');
      else if (action === 'add-child') self.inlineAdd(id, null, button);
      else if (action === 'add-sibling') self.inlineAdd(null, id, button);
      else if (action === 'edit') self.openEdit(id, button);
      else if (action === 'delete') self.confirmDelete(id, button);
      else return;
      event.preventDefault();
    });
    this.list.addEventListener('keydown', function (event) {
      if (!event.altKey || event.target.closest('.menu-tree__inline')) return;
      var item = event.target.closest('[data-id]');
      if (!item) return;
      var moves = { ArrowUp: 'up', ArrowDown: 'down', ArrowRight: 'indent', ArrowLeft: 'outdent' };
      var move = moves[event.key];
      if (!move) return;
      event.preventDefault();
      self.step(item.getAttribute('data-id'), move, event.target.getAttribute('data-action') || 'handle');
    });
    this.bindModal();
    this.bindDeleteModal();
  };

  // --- Loading and drawing -----------------------------------------------------------------------

  MenuBuilder.prototype.load = function () {
    var self = this;
    T.request('GET', this.treeUrl).then(function (body) {
      self.tree = body.data || [];
      self.render();
    }, function (error) {
      self.loading.textContent = error.message;
    });
  };

  MenuBuilder.prototype.render = function (focus) {
    this.sortables.forEach(function (s) { s.destroy(); });
    this.sortables = [];
    this.loading.classList.add('d-none');
    this.list.innerHTML = '';
    var self = this;
    this.tree.forEach(function (node, index) { self.list.appendChild(self.renderNode(node, 1, index, self.tree.length)); });
    this.empty.classList.toggle('d-none', this.tree.length > 0);
    this.makeSortable(this.list);
    Array.prototype.forEach.call(this.list.querySelectorAll('.menu-tree__children'), function (ul) { self.makeSortable(ul); });
    if (focus) this.focus(focus.id, focus.action);
  };

  MenuBuilder.prototype.renderNode = function (node, level, index, count) {
    var name = node.name || 'Untitled';
    var icon = function (glyph) { return T.el('span', { attrs: { 'aria-hidden': 'true' }, text: glyph }); };
    var button = function (action, label, glyph, disabled) {
      return T.el('button', {
        type: 'button', className: 'btn btn-sm btn-outline-secondary menu-tree__step', disabled: disabled,
        data: { action: action }, attrs: { 'aria-label': label + ': ' + name, title: label }
      }, [icon(glyph)]);
    };
    var link = node.link;
    var linkLabel = null;
    if (link && link.kind !== 'url') {
      var kind = this.kinds.filter(function (k) { return k.kind === link.kind; })[0];
      linkLabel = T.el('span', { className: 'badge badge-info menu-tree__kind', text: (kind ? kind.label : link.kind) + ': ' + (link.title || link.id) });
    }
    var urlNode = node.url
      ? T.el('a', { className: 'menu-tree__url', href: node.url, target: '_blank', rel: 'noopener', text: node.url,
                    attrs: { 'aria-label': 'Storefront link ' + node.url + ' (opens in a new tab)' } })
      : T.el('span', { className: 'menu-tree__url menu-tree__url--none', text: 'No link' });

    var menuId = 'menu-item-more-' + node.id;
    var more = T.el('div', { className: 'dropdown d-inline-block' }, [
      T.el('button', {
        type: 'button', className: 'btn btn-sm btn-outline-secondary dropdown-toggle', id: menuId,
        attrs: { 'data-toggle': 'dropdown', 'aria-haspopup': 'true', 'aria-expanded': 'false', 'aria-label': 'More actions: ' + name }
      }, ['More']),
      T.el('div', { className: 'dropdown-menu dropdown-menu-right', attrs: { 'aria-labelledby': menuId } }, [
        T.el('button', { type: 'button', className: 'dropdown-item', data: { action: 'add-sibling' }, text: 'Add item below' }),
        T.el('button', { type: 'button', className: 'dropdown-item', data: { action: 'add-child' }, text: 'Add item inside' }),
        T.el('div', { className: 'dropdown-divider' }),
        T.el('button', { type: 'button', className: 'dropdown-item text-danger', data: { action: 'delete' },
                         text: node.children.length ? 'Delete…' : 'Delete' })
      ])
    ]);

    var row = T.el('div', { className: 'menu-tree__row' + (node.is_visible ? '' : ' menu-tree__row--hidden') }, [
      T.el('button', {
        type: 'button', className: 'menu-tree__handle btn btn-link', data: { action: 'handle' },
        attrs: { 'aria-label': 'Move ' + name + '. Level ' + level + ', item ' + (index + 1) + ' of ' + count + '. Use Alt and the arrow keys to move it.', title: 'Drag to move' }
      }, [icon('⋮⋮')]),
      T.el('div', { className: 'menu-tree__main' }, [
        T.el('div', { className: 'menu-tree__title' }, [
          T.el('span', { className: 'menu-tree__name', text: name }),
          node.is_visible ? null : T.el('span', { className: 'badge badge-secondary ml-2', text: 'Hidden' }),
          node.item_target === '_blank' ? T.el('span', { className: 'badge badge-light ml-2', text: 'New tab' }) : null
        ]),
        T.el('div', { className: 'menu-tree__meta' }, [urlNode, linkLabel])
      ]),
      T.el('div', { className: 'menu-tree__actions' }, [
        T.el('div', { className: 'btn-group mr-2', attrs: { role: 'group', 'aria-label': 'Move ' + name } }, [
          button('up', 'Move up', '↑', index === 0),
          button('down', 'Move down', '↓', index === count - 1),
          button('outdent', 'Outdent', '←', level === 1),
          button('indent', 'Indent', '→', index === 0)
        ]),
        T.el('button', { type: 'button', className: 'btn btn-sm btn-primary mr-2', data: { action: 'edit' },
                         attrs: { 'aria-label': 'Edit ' + name }, text: 'Edit' }),
        more
      ])
    ]);

    var self = this;
    var children = T.el('ul', { className: 'menu-tree__children list-unstyled', attrs: { 'aria-label': 'Items inside ' + name } });
    node.children.forEach(function (child, i) { children.appendChild(self.renderNode(child, level + 1, i, node.children.length)); });
    return T.el('li', { className: 'menu-tree__item', data: { id: node.id } }, [row, children]);
  };

  MenuBuilder.prototype.makeSortable = function (ul) {
    if (!window.Sortable) return;
    var self = this;
    this.sortables.push(window.Sortable.create(ul, {
      group: 'menu-tree',
      handle: '.menu-tree__handle',
      draggable: '.menu-tree__item',
      animation: 150,
      fallbackOnBody: true,
      swapThreshold: 0.65,
      emptyInsertThreshold: 12,
      ghostClass: 'menu-tree__item--ghost',
      onEnd: function (event) {
        if (event.from === event.to && event.oldIndex === event.newIndex) return;
        var parent = event.to.closest('.menu-tree__item');
        self.save(event.item.getAttribute('data-id'), parent ? parent.getAttribute('data-id') : null, event.newIndex, 'handle');
      }
    }));
  };

  MenuBuilder.prototype.focus = function (id, action) {
    var item = this.list.querySelector('[data-id="' + id + '"]');
    if (!item) return;
    var target = item.querySelector('.menu-tree__row [data-action="' + (action || 'handle') + '"]');
    if (!target || target.disabled) target = item.querySelector('.menu-tree__handle');
    target.focus();
  };

  // --- Tree helpers --------------------------------------------------------------------------------

  MenuBuilder.prototype.locate = function (id, nodes, parent) {
    nodes = nodes || this.tree;
    for (var i = 0; i < nodes.length; i++) {
      if (nodes[i].id === String(id)) return { node: nodes[i], parent: parent || null, siblings: nodes, index: i };
      var found = this.locate(id, nodes[i].children, nodes[i]);
      if (found) return found;
    }
    return null;
  };

  function countDescendants(node) {
    return node.children.reduce(function (sum, child) { return sum + 1 + countDescendants(child); }, 0);
  }

  function clone(tree) { return JSON.parse(JSON.stringify(tree)); }

  // --- Moves -----------------------------------------------------------------------------------------

  MenuBuilder.prototype.step = function (id, move, focusAction) {
    var at = this.locate(id);
    if (!at) return;
    var parentId = at.parent ? at.parent.id : null;
    var position;
    if (move === 'up') {
      if (at.index === 0) return;
      position = at.index - 1;
    } else if (move === 'down') {
      if (at.index >= at.siblings.length - 1) return;
      position = at.index + 1;
    } else if (move === 'indent') {
      if (at.index === 0) return;
      var above = at.siblings[at.index - 1];
      parentId = above.id;
      position = above.children.length;
    } else if (move === 'outdent') {
      if (!at.parent) return;
      var grand = this.locate(at.parent.id);
      parentId = grand.parent ? grand.parent.id : null;
      position = grand.index + 1;
    }
    this.save(id, parentId, position, focusAction || move);
  };

  // Applies the move locally, then saves it; the server's tree replaces the local one.
  MenuBuilder.prototype.save = function (id, parentId, position, focusAction) {
    var self = this;
    var before = clone(this.tree);
    var at = this.locate(id);
    if (!at) return;
    var node = at.siblings.splice(at.index, 1)[0];
    var target = parentId ? this.locate(parentId) : null;
    var list = target ? target.node.children : this.tree;
    list.splice(Math.min(position, list.length), 0, node);
    this.render({ id: id, action: focusAction });

    T.request('PATCH', this.treeUrl, { nodes: [{ id: id, parent_id: parentId, position: position }] }).then(function (body) {
      self.tree = body.data || [];
      self.render({ id: id, action: focusAction });
      var now = self.locate(id);
      if (now) {
        var where = now.parent ? 'inside ' + now.parent.name : 'at the top level';
        T.announce(self.status, node.name + ' moved to position ' + (now.index + 1) + ' ' + where + '.');
      }
    }, function (error) {
      self.tree = before;
      self.render({ id: id, action: focusAction });
      T.flash('error', error.message);
      T.announce(self.status, 'Not moved. ' + error.message);
    });
  };

  // --- Inline add --------------------------------------------------------------------------------------

  // A name field in place: inside parentId (last), right after afterId, or at the end of the top level.
  MenuBuilder.prototype.inlineAdd = function (parentId, afterId, trigger) {
    var self = this;
    var existing = this.root.querySelector('.menu-tree__inline');
    if (existing) existing.remove();
    var input = T.el('input', { type: 'text', className: 'form-control form-control-sm', id: 'menu-inline-name',
                                maxLength: 255, placeholder: 'Item name', attrs: { autocomplete: 'off', required: 'required' } });
    var cancel = function () {
      form.parentNode.remove();
      if (trigger && document.body.contains(trigger)) trigger.focus();
      else if (afterId || parentId) self.focus(afterId || parentId);
    };
    var form = T.el('form', { className: 'menu-tree__inline-form d-flex align-items-center' }, [
      T.el('label', { className: 'sr-only', htmlFor: 'menu-inline-name', text: 'New item name' }),
      input,
      T.el('button', { type: 'submit', className: 'btn btn-sm btn-primary ml-2', text: 'Add' }),
      T.el('button', { type: 'button', className: 'btn btn-sm btn-outline-secondary ml-2', text: 'Cancel', on: { click: cancel } })
    ]);
    var holder = T.el('li', { className: 'menu-tree__inline' }, [form]);
    if (afterId) {
      var sibling = this.list.querySelector('[data-id="' + afterId + '"]');
      sibling.parentNode.insertBefore(holder, sibling.nextSibling);
    } else if (parentId) {
      this.list.querySelector('[data-id="' + parentId + '"] > .menu-tree__children').appendChild(holder);
    } else {
      this.list.appendChild(holder);
      this.empty.classList.add('d-none');
    }
    input.addEventListener('keydown', function (event) {
      if (event.key === 'Escape') { event.preventDefault(); cancel(); }
    });
    form.addEventListener('submit', function (event) {
      event.preventDefault();
      var name = input.value.trim();
      if (!name) { input.focus(); return; }
      input.disabled = true;
      var body = { menu_item: { name: name, parent_id: parentId, is_visible: true } };
      if (afterId) body.after_id = afterId;
      T.request('POST', self.itemsUrl, body).then(function (response) {
        self.tree = response.tree || [];
        self.render({ id: response.data.id, action: 'edit' });
        T.announce(self.status, name + ' added. Choose Edit to give it a link.');
      }, function (error) {
        input.disabled = false;
        input.focus();
        T.flash('error', error.message);
      });
    });
    input.focus();
  };

  // --- Edit modal --------------------------------------------------------------------------------------

  MenuBuilder.prototype.bindModal = function () {
    var self = this;
    var modal = this.modal;
    if (!modal) return;
    this.form = modal.querySelector('[data-role="item-form"]');
    this.kindSelect = modal.querySelector('#menu-item-kind');
    this.recordSelect = $(modal.querySelector('#menu-item-record'));
    this.kindSelect.addEventListener('change', function () { self.showKind(true); });
    this.form.addEventListener('submit', function (event) { event.preventDefault(); self.submitEdit(); });
    $(modal).on('shown.bs.modal', function () { modal.querySelector('#menu-item-name').focus(); });
    $(modal).on('hidden.bs.modal', function () { self.restoreFocus(); });
  };

  MenuBuilder.prototype.restoreFocus = function () {
    if (this.returnFocus && this.returnFocus.id) this.focus(this.returnFocus.id, this.returnFocus.action);
    else if (this.returnFocus && this.returnFocus.element) this.returnFocus.element.focus();
    this.returnFocus = null;
  };

  MenuBuilder.prototype.openEdit = function (id, trigger) {
    var at = this.locate(id);
    if (!at) return;
    var node = at.node;
    this.editing = node;
    this.returnFocus = { id: id, action: trigger.getAttribute('data-action') === 'edit' ? 'edit' : null };
    var modal = this.modal;
    modal.querySelector('#menu-item-modal-title').textContent = 'Edit ' + (node.name || 'item');
    modal.querySelector('#menu-item-name').value = node.name || '';
    modal.querySelector('#menu-item-target').value = node.item_target === '_blank' ? '_blank' : '_self';
    modal.querySelector('#menu-item-visible').checked = node.is_visible !== false;
    modal.querySelector('#menu-item-url').value = node.link && node.link.kind === 'url' ? node.link.url : '';
    this.kindSelect.value = node.link ? node.link.kind : '';
    this.showKind(false);
    if (node.link && node.link.kind !== 'url') {
      this.recordSelect.empty().append(new window.Option(node.link.title || ('#' + node.link.id), node.link.id, true, true)).trigger('change');
    }
    this.formError('');
    $(modal).modal('show');
  };

  MenuBuilder.prototype.showKind = function (reset) {
    var kind = this.kindSelect.value;
    var option = this.kindSelect.options[this.kindSelect.selectedIndex];
    var resource = option ? option.getAttribute('data-resource') : null;
    this.modal.querySelector('[data-role="url-group"]').classList.toggle('d-none', kind !== 'url');
    this.modal.querySelector('[data-role="record-group"]').classList.toggle('d-none', !resource);
    if (!resource) return;
    this.modal.querySelector('[data-role="record-label"]').textContent = option.textContent;
    this.setupRecordSelect(resource, option.textContent, reset);
  };

  // Select2 over the admin's resource search (/api/admin_native/v1/resources/:key?q=), with the
  // signed-in admin's API key the way Spree's own pickers send it.
  MenuBuilder.prototype.setupRecordSelect = function (resource, label, reset) {
    var select = this.recordSelect;
    if (select.data('select2')) select.select2('destroy');
    if (reset) select.empty();
    select.select2({
      dropdownParent: $(this.modal),
      width: '100%',
      placeholder: 'Search ' + label.toLowerCase() + 's',
      minimumInputLength: 1,
      ajax: {
        url: window.Spree.pathFor('api/admin_native/v1/resources/' + resource),
        dataType: 'json',
        delay: 250,
        headers: { 'X-Spree-Token': window.Spree.api_key },
        data: function (params) { return { q: params.term, per_page: 20, page: params.page || 1 }; },
        processResults: function (body, params) {
          var meta = body.meta || {};
          var page = params.page || 1;
          return {
            results: (body.data || []).map(function (row) { return { id: row.id, text: row.title + (row.subtitle ? ' — ' + row.subtitle : '') }; }),
            pagination: { more: meta.total_count ? page * (meta.per_page || 20) < meta.total_count : false }
          };
        }
      }
    });
  };

  MenuBuilder.prototype.formError = function (message) {
    var box = this.modal.querySelector('[data-role="form-error"]');
    box.textContent = message;
    box.classList.toggle('d-none', !message);
  };

  MenuBuilder.prototype.submitEdit = function () {
    var self = this;
    var modal = this.modal;
    var name = modal.querySelector('#menu-item-name').value.trim();
    if (!name) { this.formError('Give the item a name.'); modal.querySelector('#menu-item-name').focus(); return; }
    var kind = this.kindSelect.value;
    var link = null;
    if (kind === 'url') {
      var url = modal.querySelector('#menu-item-url').value.trim();
      if (!url) { this.formError('Enter a URL, or choose Nothing.'); modal.querySelector('#menu-item-url').focus(); return; }
      link = { kind: 'url', url: url };
    } else if (kind) {
      var id = this.recordSelect.val();
      if (!id) { this.formError('Choose what the item links to.'); this.recordSelect.select2('open'); return; }
      link = { kind: kind, id: id };
    }
    var submit = modal.querySelector('[data-role="submit"]');
    submit.disabled = true;
    var node = this.editing;
    T.request('PATCH', this.itemsUrl.replace(/(\.json)?$/, '/' + node.id + '.json'), {
      menu_item: {
        name: name,
        link: link || { kind: '' },
        item_target: modal.querySelector('#menu-item-target').value,
        is_visible: modal.querySelector('#menu-item-visible').checked
      }
    }).then(function (response) {
      submit.disabled = false;
      self.tree = response.tree || [];
      self.render();
      $(modal).modal('hide');
      T.announce(self.status, name + ' saved.');
    }, function (error) {
      submit.disabled = false;
      self.formError(error.message);
    });
  };

  // --- Delete ------------------------------------------------------------------------------------------

  MenuBuilder.prototype.bindDeleteModal = function () {
    var self = this;
    if (!this.deleteModal) return;
    this.deleteModal.querySelector('[data-role="confirm"]').addEventListener('click', function () { self.destroy(); });
    $(this.deleteModal).on('shown.bs.modal', function () { self.deleteModal.querySelector('[data-role="confirm"]').focus(); });
    $(this.deleteModal).on('hidden.bs.modal', function () { self.restoreFocus(); });
  };

  MenuBuilder.prototype.confirmDelete = function (id) {
    var at = this.locate(id);
    if (!at) return;
    var node = at.node;
    var count = countDescendants(node);
    this.deleting = { node: node, withChildren: count > 0, at: at };
    this.returnFocus = { id: id, action: 'edit' };
    var message = this.deleteModal.querySelector('[data-role="message"]');
    var confirm = this.deleteModal.querySelector('[data-role="confirm"]');
    if (count > 0) {
      message.textContent = node.name + ' has ' + count + (count === 1 ? ' item' : ' items') + ' inside it. ' +
        'An item with items inside is only deleted together with them. To keep them, close this and move them out first.';
      confirm.textContent = 'Delete ' + node.name + ' and ' + count + (count === 1 ? ' item' : ' items');
    } else {
      message.textContent = 'Delete ' + node.name + ' from this menu?';
      confirm.textContent = 'Delete';
    }
    $(this.deleteModal).modal('show');
  };

  MenuBuilder.prototype.destroy = function () {
    var self = this;
    var target = this.deleting;
    if (!target) return;
    var confirm = this.deleteModal.querySelector('[data-role="confirm"]');
    confirm.disabled = true;
    var url = this.itemsUrl.replace(/(\.json)?$/, '/' + target.node.id + '.json') + (target.withChildren ? '?with_children=1' : '');
    T.request('DELETE', url).then(function (response) {
      confirm.disabled = false;
      // Focus moves to the item that takes its place, else the one before, else its parent.
      var siblings = target.at.siblings;
      var next = siblings[target.at.index + 1] || siblings[target.at.index - 1] || target.at.parent;
      self.returnFocus = next ? { id: next.id, action: 'handle' } : { element: self.root.querySelector('[data-action="add-root"]') };
      self.tree = response.tree || [];
      self.render();
      $(self.deleteModal).modal('hide');
      T.announce(self.status, target.node.name + ' deleted.');
    }, function (error) {
      confirm.disabled = false;
      $(self.deleteModal).modal('hide');
      T.flash('error', error.message);
    });
  };

  document.addEventListener('DOMContentLoaded', function () {
    var root = document.getElementById('menu-builder');
    if (root) window.menuBuilder = new MenuBuilder(root);
  });
})(window, document, window.jQuery);
