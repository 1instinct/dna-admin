// The customer inbox (/admin/inbox): the conversation list, the chat and the customer's context.
// Polls with fetch while the tab is visible: the open conversation every 5 s (messages after the
// last one) and the list every 20 s (conversations changed since the last poll).
(function (window, document, $) {
  'use strict';

  var T = window.AdminTools;
  var MESSAGE_POLL_MS = 5000;
  var LIST_POLL_MS = 20000;
  var PAGE_SIZE = 25;
  var MESSAGES_PAGE = 50;

  function Inbox(root) {
    this.root = root;
    this.urls = JSON.parse(root.getAttribute('data-urls'));
    this.staff = JSON.parse(root.getAttribute('data-staff') || '[]');
    this.me = JSON.parse(root.getAttribute('data-me') || '{}');
    this.snooze = JSON.parse(root.getAttribute('data-snooze') || '[]');
    this.timeZone = root.getAttribute('data-time-zone');
    this.$ = function (role) { return root.querySelector('[data-role="' + role + '"]'); };
    this.filter = 'open';
    this.query = '';
    this.page = 1;
    this.order = [];
    this.byId = {};
    this.lastInbound = {};
    this.selectedId = null;
    this.messages = [];
    this.context = null;
    this.files = [];
    this.since = null;
    this.listLoaded = false;
    this.bind();
    this.loadList(true);
    var initial = root.getAttribute('data-initial');
    if (initial) this.select(initial);
    var self = this;
    this.listPoll = T.poll(function () { return self.pollList(); }, LIST_POLL_MS);
    this.messagePoll = T.poll(function () { return self.pollMessages(); }, MESSAGE_POLL_MS);
    this.setupNotifications();
  }

  Inbox.prototype.url = function (name, id, suffix) {
    var base = this.urls[name];
    if (!base) return null;
    return base.replace('__ID__', encodeURIComponent(id)) + (suffix || '');
  };

  Inbox.prototype.conversationUrl = function (id, suffix) {
    return this.url('conversation', id, suffix);
  };

  // --- Events -------------------------------------------------------------------------------------

  Inbox.prototype.bind = function () {
    var self = this;
    Array.prototype.forEach.call(this.root.querySelectorAll('[data-filter]'), function (button) {
      button.addEventListener('click', function () { self.setFilter(button.getAttribute('data-filter')); });
    });
    var search = this.$('search');
    var input = search.querySelector('input');
    var timer = null;
    search.addEventListener('submit', function (event) { event.preventDefault(); self.setQuery(input.value); });
    input.addEventListener('input', function () {
      window.clearTimeout(timer);
      timer = window.setTimeout(function () { self.setQuery(input.value); }, 350);
    });
    this.$('more').addEventListener('click', function () { self.page += 1; self.loadList(false); });
    this.$('conversations').addEventListener('click', function (event) {
      var item = event.target.closest('[data-conversation]');
      if (item) self.select(item.getAttribute('data-conversation'));
    });

    var composer = this.$('composer');
    var body = this.$('body');
    composer.addEventListener('submit', function (event) { event.preventDefault(); self.send(); });
    body.addEventListener('keydown', function (event) {
      if (event.key === 'Enter' && !event.shiftKey && !event.isComposing && event.keyCode !== 229) {
        event.preventDefault();
        self.send();
      }
    });
    this.$('note-toggle').addEventListener('change', function () { self.noteMode(this.checked); });
    this.$('attach').addEventListener('change', function () {
      Array.prototype.forEach.call(this.files, function (file) { self.files.push(file); });
      this.value = '';
      self.renderFiles();
    });
    this.$('files').addEventListener('click', function (event) {
      var button = event.target.closest('[data-remove-file]');
      if (!button) return;
      self.files.splice(Number(button.getAttribute('data-remove-file')), 1);
      self.renderFiles();
      self.$('body').focus();
    });
    this.$('messages').addEventListener('click', function (event) {
      if (event.target.closest('[data-role="older"]')) self.loadOlder();
    });
    this.$('context').addEventListener('click', function (event) {
      var button = event.target.closest('[data-context-action]');
      if (!button) return;
      var action = button.getAttribute('data-context-action');
      if (action === 'assign-me') self.update({ assignee_id: 'me' }, 'Assigned to you.');
      else if (action === 'close') self.update({ status: 'closed' }, 'Conversation closed.');
      else if (action === 'reopen') self.update({ status: 'open' }, 'Conversation reopened.');
      else if (action === 'snooze') self.update({ snooze: button.getAttribute('data-snooze') }, 'Snoozed ' + button.textContent.trim().toLowerCase() + '.');
    });
    this.$('context').addEventListener('change', function (event) {
      if (event.target.getAttribute('data-context-action') !== 'assign') return;
      var value = event.target.value;
      self.update({ assignee_id: value }, value ? 'Assigned to ' + event.target.options[event.target.selectedIndex].text + '.' : 'Unassigned.');
    });
  };

  Inbox.prototype.setFilter = function (filter) {
    if (filter === this.filter) return;
    this.filter = filter;
    Array.prototype.forEach.call(this.root.querySelectorAll('[data-filter]'), function (button) {
      var on = button.getAttribute('data-filter') === filter;
      button.classList.toggle('active', on);
      button.setAttribute('aria-pressed', on ? 'true' : 'false');
    });
    this.loadList(true);
  };

  Inbox.prototype.setQuery = function (query) {
    query = query.trim();
    if (query === this.query) return;
    this.query = query;
    this.loadList(true);
  };

  // --- The list -----------------------------------------------------------------------------------

  Inbox.prototype.listParams = function (extra) {
    var params = { filter: this.filter, per_page: PAGE_SIZE };
    if (this.query) params.q = this.query;
    Object.keys(extra || {}).forEach(function (k) { params[k] = extra[k]; });
    return Object.keys(params).map(function (k) { return encodeURIComponent(k) + '=' + encodeURIComponent(params[k]); }).join('&');
  };

  Inbox.prototype.loadList = function (reset) {
    var self = this;
    if (reset) this.page = 1;
    var list = this.$('conversations');
    list.setAttribute('aria-busy', 'true');
    var token = this.listToken = {};
    return T.request('GET', this.urls.conversations + '?' + this.listParams({ page: this.page })).then(function (body) {
      if (token !== self.listToken) return;
      if (reset) { self.order = []; self.byId = {}; }
      (body.data || []).forEach(function (c) { self.remember(c, true); });
      self.since = self.overlap(body.meta && body.meta.now);
      self.listLoaded = true;
      self.$('more').classList.toggle('d-none', !(body.meta && body.meta.total > self.order.length));
      self.renderList();
    }, function (error) {
      T.flash('error', error.message);
    }).then(function () { list.setAttribute('aria-busy', 'false'); });
  };

  // Polls overlap by two seconds; merging a conversation twice is harmless.
  Inbox.prototype.overlap = function (iso) {
    if (!iso) return this.since;
    return new Date(new Date(iso).getTime() - 2000).toISOString();
  };

  Inbox.prototype.pollList = function () {
    var self = this;
    this.refreshSummary();
    if (!this.since) return this.loadList(true);
    return T.request('GET', this.urls.conversations + '?' + this.listParams({ updated_since: this.since, per_page: 100 })).then(function (body) {
      var changed = body.data || [];
      changed.forEach(function (c) {
        self.notifyIfNew(c);
        self.remember(c, false);
      });
      self.since = self.overlap(body.meta && body.meta.now);
      if (changed.length) {
        self.sortList();
        self.renderList();
        if (self.selectedId && self.byId[self.selectedId] && changed.some(function (c) { return c.id === self.selectedId; })) {
          self.refreshConversation();
        }
      }
    }, function () { /* the next poll tries again */ });
  };

  Inbox.prototype.remember = function (conversation, initial) {
    if (!this.byId[conversation.id]) this.order.push(conversation.id);
    this.byId[conversation.id] = conversation;
    var last = conversation.last_message;
    if (initial && last && last.direction === 'inbound') this.lastInbound[conversation.id] = last.at;
  };

  Inbox.prototype.sortList = function () {
    var self = this;
    this.order.sort(function (a, b) {
      var at = function (c) { return (c.last_message && c.last_message.at) || c.updated_at || ''; };
      return at(self.byId[b]) < at(self.byId[a]) ? -1 : (at(self.byId[b]) > at(self.byId[a]) ? 1 : 0);
    });
  };

  Inbox.prototype.renderList = function () {
    var self = this;
    var list = this.$('conversations');
    list.innerHTML = '';
    this.order.forEach(function (id) { list.appendChild(self.renderListItem(self.byId[id])); });
    this.$('list-empty').classList.toggle('d-none', this.order.length > 0);
  };

  Inbox.prototype.renderListItem = function (c) {
    var name = (c.customer && (c.customer.name || c.customer.email)) || 'Visitor';
    var last = c.last_message;
    var unread = c.unread > 0;
    var preview = last ? (last.direction === 'outbound' ? 'You: ' : '') + last.body : 'No messages yet';
    var selected = c.id === this.selectedId;
    var label = name + (unread ? ', ' + c.unread + ' unread' : '') + (c.status !== 'open' ? ', ' + c.status : '');
    var button = T.el('button', {
      type: 'button',
      className: 'inbox__conversation' + (selected ? ' is-selected' : '') + (unread ? ' is-unread' : ''),
      data: { conversation: c.id },
      attrs: { 'aria-current': selected ? 'true' : null, 'aria-label': label + '. ' + preview }
    }, [
      T.el('span', { className: 'inbox__conversation-top' }, [
        unread ? T.el('span', { className: 'inbox__dot', attrs: { 'aria-hidden': 'true' } }) : null,
        T.el('span', { className: 'inbox__conversation-name', text: name }),
        T.el('span', { className: 'inbox__conversation-time', text: last ? T.formatTime(last.at) : '' })
      ]),
      T.el('span', { className: 'inbox__conversation-preview', text: preview }),
      T.el('span', { className: 'inbox__conversation-tags' }, [
        c.assignee ? T.el('span', { className: 'badge badge-light', text: c.assignee.id === this.me.id ? 'Mine' : c.assignee.email }) : null,
        c.status === 'snoozed' ? T.el('span', { className: 'badge badge-warning', text: 'Snoozed' }) : null,
        c.channel && c.channel !== 'web' ? T.el('span', { className: 'badge badge-info', text: c.channel }) : null
      ])
    ]);
    return T.el('li', {}, [button]);
  };

  // --- Summary and the sidebar badge ----------------------------------------------------------------

  Inbox.prototype.refreshSummary = function () {
    var self = this;
    T.request('GET', this.urls.summary).then(function (body) {
      var data = body.data || {};
      Array.prototype.forEach.call(document.querySelectorAll('[data-inbox-unread-badge]'), function (badge) {
        var count = Number(data.unread || 0);
        badge.classList.toggle('d-none', count === 0);
        var number = badge.querySelector('[data-count]');
        if (number) number.textContent = count;
      });
      ['open', 'unassigned'].forEach(function (key) {
        var badge = self.$('count-' + key);
        if (badge) badge.textContent = data[key];
      });
    }, function () {});
  };

  // --- One conversation --------------------------------------------------------------------------------

  Inbox.prototype.select = function (id) {
    var self = this;
    id = String(id);
    this.selectedId = id;
    this.messages = [];
    this.hasOlder = false;
    this.renderList();
    this.$('placeholder').classList.add('d-none');
    this.$('chat').classList.remove('d-none');
    this.$('messages').innerHTML = '';
    this.$('messages').setAttribute('aria-busy', 'true');
    if (window.history && window.history.replaceState) {
      window.history.replaceState(null, '', window.location.pathname + '?conversation=' + encodeURIComponent(id));
    }
    var token = this.selectToken = {};
    T.request('GET', this.conversationUrl(id)).then(function (body) {
      if (token !== self.selectToken) return;
      self.byId[id] = body.data;
      self.context = body.customer_context;
      self.renderHeader();
      self.renderContext();
      return T.request('GET', self.conversationUrl(id, '/messages') + '?limit=' + MESSAGES_PAGE).then(function (list) {
        if (token !== self.selectToken) return;
        self.messages = list.data || [];
        self.hasOlder = self.messages.length >= MESSAGES_PAGE;
        self.renderMessages(true);
        self.markRead();
      });
    }, function (error) {
      self.$('messages').setAttribute('aria-busy', 'false');
      T.flash('error', error.status === 404 ? 'That conversation no longer exists.' : error.message);
    });
  };

  Inbox.prototype.refreshConversation = function () {
    var self = this;
    var id = this.selectedId;
    if (!id) return;
    T.request('GET', this.conversationUrl(id)).then(function (body) {
      if (id !== self.selectedId) return;
      self.byId[id] = body.data;
      self.context = body.customer_context;
      self.renderHeader();
      self.renderContext();
    }, function () {});
  };

  Inbox.prototype.markRead = function () {
    var self = this;
    var id = this.selectedId;
    var conversation = this.byId[id];
    if (!conversation || !conversation.unread) return;
    T.request('POST', this.conversationUrl(id, '/read')).then(function (body) {
      self.byId[id] = body.data;
      self.renderList();
      self.refreshSummary();
    }, function () {});
  };

  Inbox.prototype.pollMessages = function () {
    var self = this;
    var id = this.selectedId;
    if (!id || this.messagesLoading) return null;
    var last = this.messages[this.messages.length - 1];
    var url = this.conversationUrl(id, '/messages') + (last ? '?after=' + encodeURIComponent(last.id) : '');
    return T.request('GET', url).then(function (body) {
      if (id !== self.selectedId) return;
      var known = {};
      self.messages.forEach(function (m) { known[m.id] = true; });
      var fresh = (body.data || []).filter(function (m) { return !known[m.id]; });
      if (!fresh.length) return;
      self.messages = self.messages.concat(fresh);
      self.appendMessages(fresh);
      var inbound = fresh.filter(function (m) { return m.direction === 'inbound'; });
      if (inbound.length) {
        var conversation = self.byId[id];
        if (conversation) conversation.unread = (conversation.unread || 0) + inbound.length;
        self.markRead();
      }
    }, function () {});
  };

  Inbox.prototype.loadOlder = function () {
    var self = this;
    var id = this.selectedId;
    var first = this.messages[0];
    if (!id || !first) return;
    this.messagesLoading = true;
    T.request('GET', this.conversationUrl(id, '/messages') + '?limit=' + MESSAGES_PAGE + '&before=' + encodeURIComponent(first.id)).then(function (body) {
      self.messagesLoading = false;
      if (id !== self.selectedId) return;
      var older = body.data || [];
      self.hasOlder = older.length >= MESSAGES_PAGE;
      self.messages = older.concat(self.messages);
      self.renderMessages(false);
      var anchor = self.$('messages').querySelector('[data-message="' + first.id + '"]');
      if (anchor) anchor.scrollIntoView();
    }, function (error) {
      self.messagesLoading = false;
      T.flash('error', error.message);
    });
  };

  // --- Drawing the chat ----------------------------------------------------------------------------

  var STATUS_BADGES = { open: 'badge-success', snoozed: 'badge-warning', closed: 'badge-secondary' };

  Inbox.prototype.renderHeader = function () {
    var c = this.byId[this.selectedId];
    if (!c) return;
    var name = (c.customer && (c.customer.name || c.customer.email)) || 'Visitor';
    this.$('chat-title').textContent = name;
    var parts = [];
    if (c.customer && c.customer.email && c.customer.email !== name) parts.push(c.customer.email);
    parts.push('via ' + (c.channel || 'web'));
    if (c.assignee) parts.push('assigned to ' + (c.assignee.id === this.me.id ? 'you' : c.assignee.email));
    if (c.status === 'snoozed' && c.snoozed_until) parts.push('snoozed until ' + T.formatTime(c.snoozed_until));
    this.$('chat-subtitle').textContent = parts.join(' · ');
    var status = this.$('chat-status');
    status.className = 'badge ' + (STATUS_BADGES[c.status] || 'badge-light');
    status.textContent = c.status ? c.status.charAt(0).toUpperCase() + c.status.slice(1) : '';
  };

  Inbox.prototype.renderMessages = function (scrollToEnd) {
    var box = this.$('messages');
    box.setAttribute('aria-busy', 'true');
    box.innerHTML = '';
    if (this.hasOlder) {
      box.appendChild(T.el('div', { className: 'text-center my-2' }, [
        T.el('button', { type: 'button', className: 'btn btn-link btn-sm', data: { role: 'older' }, text: 'Load earlier messages' })
      ]));
    }
    if (!this.messages.length) box.appendChild(T.el('p', { className: 'text-muted small text-center my-4', text: 'No messages yet.' }));
    var self = this;
    this.messages.forEach(function (m) { box.appendChild(self.renderMessage(m)); });
    if (scrollToEnd) box.scrollTop = box.scrollHeight;
    box.setAttribute('aria-busy', 'false');
  };

  Inbox.prototype.appendMessages = function (list) {
    var box = this.$('messages');
    var nearEnd = box.scrollHeight - box.scrollTop - box.clientHeight < 120;
    var empty = box.querySelector('p.text-muted');
    if (empty) empty.remove();
    var self = this;
    list.forEach(function (m) { box.appendChild(self.renderMessage(m)); });
    if (nearEnd) box.scrollTop = box.scrollHeight;
  };

  var DELIVERY = { sent: 'Sent', delivered: 'Delivered', failed: 'Not delivered' };

  Inbox.prototype.renderMessage = function (m) {
    var kind = m.direction === 'inbound' ? 'inbound' : (m.direction === 'note' ? 'note' : 'outbound');
    var author = (m.author && m.author.name) || (kind === 'inbound' ? 'Customer' : 'Staff');
    var label = kind === 'note' ? 'Internal note by ' + author : author;
    var attachments = (m.attachments || []).map(function (a) {
      var isImage = (a.content_type || '').indexOf('image/') === 0;
      return T.el('a', { className: 'inbox__attachment', href: a.url, target: '_blank', rel: 'noopener',
                         attrs: { 'aria-label': (isImage ? 'Image ' : 'File ') + a.filename + ' (opens in a new tab)' } }, [
        isImage ? T.el('img', { src: a.url, alt: a.filename, loading: 'lazy' }) : T.el('span', { text: '📎 ' + a.filename })
      ]);
    });
    var meta = [label, T.formatTime(m.created_at)];
    if (kind === 'outbound' && m.delivery) meta.push(DELIVERY[m.delivery] || m.delivery);
    if (m.channel && m.channel !== 'web') meta.push('via ' + m.channel);
    return T.el('div', { className: 'inbox__message inbox__message--' + kind, data: { message: m.id } }, [
      T.el('div', { className: 'inbox__bubble' }, [
        kind === 'note' ? T.el('span', { className: 'inbox__note-label', text: 'Note' }) : null,
        m.body ? T.el('div', { className: 'inbox__text', text: m.body }) : null,
        attachments.length ? T.el('div', { className: 'inbox__attachments' }, attachments) : null
      ]),
      T.el('div', { className: 'inbox__meta', text: meta.join(' · ') })
    ]);
  };

  // --- Composer --------------------------------------------------------------------------------------

  Inbox.prototype.noteMode = function (on) {
    var composer = this.$('composer');
    composer.classList.toggle('is-note', on);
    this.$('body').setAttribute('placeholder', on ? 'Write a note for your team…' : 'Write a reply…');
    this.$('composer-label').textContent = on ? 'Internal note' : 'Reply';
    this.$('send').textContent = on ? 'Add note' : 'Send';
  };

  Inbox.prototype.renderFiles = function () {
    var list = this.$('files');
    list.innerHTML = '';
    this.files.forEach(function (file, index) {
      list.appendChild(T.el('li', { className: 'inbox__file' }, [
        T.el('span', { text: file.name }),
        T.el('button', { type: 'button', className: 'btn btn-link btn-sm p-0 ml-2', data: { 'remove-file': index },
                         attrs: { 'aria-label': 'Remove ' + file.name }, text: 'Remove' })
      ]));
    });
    list.classList.toggle('d-none', this.files.length === 0);
  };

  Inbox.prototype.send = function () {
    var self = this;
    var id = this.selectedId;
    var body = this.$('body');
    var text = body.value.trim();
    if (!id || this.sending) return;
    if (!text && !this.files.length) { body.focus(); return; }
    var note = this.$('note-toggle').checked;
    var data = new window.FormData();
    data.append('body', text);
    data.append('note', note ? 'true' : 'false');
    this.files.forEach(function (file) { data.append('attachments[]', file, file.name); });
    this.sending = true;
    this.$('send').disabled = true;
    T.request('POST', this.conversationUrl(id, '/messages'), data).then(function (response) {
      self.sending = false;
      self.$('send').disabled = false;
      body.value = '';
      self.files = [];
      self.renderFiles();
      if (id === self.selectedId) {
        self.messages.push(response.data);
        self.appendMessages([response.data]);
        self.$('messages').scrollTop = self.$('messages').scrollHeight;
      }
      if (response.conversation) {
        self.remember(response.conversation, false);
        self.sortList();
        self.renderList();
      }
      T.announce(self.$('status'), note ? 'Note added.' : 'Reply sent.');
      body.focus();
    }, function (error) {
      self.sending = false;
      self.$('send').disabled = false;
      T.flash('error', error.message);
      body.focus();
    });
  };

  // --- Customer context --------------------------------------------------------------------------------

  Inbox.prototype.update = function (attrs, done) {
    var self = this;
    var id = this.selectedId;
    if (!id) return;
    T.request('PATCH', this.conversationUrl(id), attrs).then(function (body) {
      self.byId[id] = body.data;
      self.context = body.customer_context;
      self.renderHeader();
      self.renderContext();
      self.renderList();
      self.refreshSummary();
      T.announce(self.$('status'), done);
      T.flash('success', done);
    }, function (error) {
      T.flash('error', error.message);
    });
  };

  Inbox.prototype.renderContext = function () {
    var holder = this.$('context');
    var c = this.byId[this.selectedId];
    var ctx = this.context || {};
    holder.innerHTML = '';
    if (!c) return;
    var self = this;
    var section = function (title, children) {
      return T.el('section', { className: 'inbox__section' }, [T.el('h3', { className: 'inbox__section-title', text: title })].concat(children));
    };
    var link = function (href, text, external) {
      return href ? T.el('a', { href: href, text: text, target: external ? '_blank' : null, rel: external ? 'noopener' : null }) : T.el('span', { text: text });
    };

    // Contact
    var contact = ctx.contact || {};
    var contactLines = [
      T.el('div', { className: 'inbox__customer-name', text: contact.name || (c.customer && c.customer.name) || 'Visitor' })
    ];
    if (contact.email) contactLines.push(T.el('div', {}, [link('mailto:' + contact.email, contact.email)]));
    if (contact.phone) contactLines.push(T.el('div', {}, [link('tel:' + contact.phone, contact.phone)]));
    var records = [];
    if (contact.id) records.push(link(this.url('contact', contact.id), 'Contact record'));
    if (ctx.user && ctx.user.id) records.push(link(this.url('user', ctx.user.id), 'Customer account'));
    if (records.length) {
      contactLines.push(T.el('div', { className: 'inbox__links' }, records.reduce(function (out, a, i) {
        if (i) out.push(document.createTextNode(' · '));
        out.push(a);
        return out;
      }, [])));
    }
    holder.appendChild(section('Contact', contactLines));

    // Live session
    var session = ctx.session;
    if (session) {
      var lines = [
        T.el('div', { className: 'inbox__presence' }, [
          T.el('span', { className: 'inbox__online-dot' + (session.online ? ' is-online' : ''), attrs: { 'aria-hidden': 'true' } }),
          T.el('span', { text: session.online ? 'Online now' : 'Last seen ' + T.ago(session.last_seen_at) + ' ago' })
        ])
      ];
      if (session.current_url) {
        lines.push(T.el('div', { className: 'inbox__current-page' }, [
          T.el('span', { className: 'text-muted', text: session.online ? 'Viewing ' : 'Last page ' }),
          link(session.current_url, session.current_url, true)
        ]));
      }
      if (this.urls.visitor) lines.push(T.el('div', {}, [link(this.url('visitor', session.id), 'Visit details')]));
      holder.appendChild(section('Session', lines));
    }

    // Cart
    var cart = ctx.cart;
    if (cart) {
      var items = (cart.items || []).map(function (item) {
        return T.el('li', { className: 'inbox__cart-item' }, [
          item.image_url ? T.el('img', { src: item.image_url, alt: '', loading: 'lazy' }) : T.el('span', { className: 'inbox__cart-noimage', attrs: { 'aria-hidden': 'true' } }),
          T.el('span', { className: 'inbox__cart-name', text: item.name }),
          T.el('span', { className: 'inbox__cart-qty', text: '× ' + item.quantity })
        ]);
      });
      holder.appendChild(section('Cart', [
        T.el('ul', { className: 'list-unstyled mb-1' }, items),
        T.el('div', { className: 'small' }, [
          T.el('strong', { text: cart.total + ' ' + (cart.currency || '') }),
          ' · ',
          link(this.url('cart', cart.order_number), cart.order_number)
        ])
      ]));
    }

    // Recent orders
    var orders = ctx.recent_orders || [];
    holder.appendChild(section('Recent orders', orders.length ? [
      T.el('ul', { className: 'list-unstyled mb-0 inbox__orders' }, orders.map(function (o) {
        return T.el('li', {}, [
          link(self.url('order', o.number), o.number),
          T.el('span', { className: 'text-muted', text: ' · ' + o.total + ' · ' + (o.completed_at ? new Date(o.completed_at).toLocaleDateString() : o.state) })
        ]);
      }))
    ] : [T.el('p', { className: 'text-muted small mb-0', text: 'No orders yet.' })]));

    // Actions
    var select = T.el('select', { className: 'form-control', id: 'inbox-assignee', data: { 'context-action': 'assign' } }, [
      T.el('option', { value: '', text: 'Unassigned' })
    ].concat(this.staff.map(function (s) {
      return T.el('option', { value: s.id, text: s.id === self.me.id ? s.email + ' (you)' : s.email });
    })));
    select.value = c.assignee ? c.assignee.id : '';
    var assignMine = c.assignee && c.assignee.id === this.me.id;
    var snoozeMenuId = 'inbox-snooze-menu';
    var actions = [
      T.el('label', { htmlFor: 'inbox-assignee', className: 'small mb-1', text: 'Assigned to' }),
      T.el('div', { className: 'd-flex mb-3' }, [
        select,
        assignMine ? null : T.el('button', { type: 'button', className: 'btn btn-sm btn-outline-secondary ml-2 text-nowrap', data: { 'context-action': 'assign-me' }, text: 'Assign to me' })
      ])
    ];
    var buttons = [];
    if (c.status !== 'closed') {
      buttons.push(T.el('div', { className: 'dropdown d-inline-block mr-2' }, [
        T.el('button', { type: 'button', className: 'btn btn-sm btn-outline-secondary dropdown-toggle', id: snoozeMenuId,
                         attrs: { 'data-toggle': 'dropdown', 'aria-haspopup': 'true', 'aria-expanded': 'false' }, text: 'Snooze' }),
        T.el('div', { className: 'dropdown-menu', attrs: { 'aria-labelledby': snoozeMenuId } }, this.snooze.map(function (option) {
          return T.el('button', { type: 'button', className: 'dropdown-item', data: { 'context-action': 'snooze', snooze: option.key }, text: option.label });
        }))
      ]));
      buttons.push(T.el('button', { type: 'button', className: 'btn btn-sm btn-outline-danger', data: { 'context-action': 'close' }, text: 'Close' }));
    } else {
      buttons.push(T.el('button', { type: 'button', className: 'btn btn-sm btn-outline-primary', data: { 'context-action': 'reopen' }, text: 'Reopen' }));
    }
    if (c.status === 'snoozed') buttons.push(T.el('button', { type: 'button', className: 'btn btn-sm btn-link', data: { 'context-action': 'reopen' }, text: 'Wake now' }));
    actions.push(T.el('div', {}, buttons));
    actions.push(T.el('p', { className: 'text-muted small mt-2 mb-0', text: 'Snooze times are in ' + this.timeZone + '.' }));
    holder.appendChild(section('Conversation', actions));
  };

  // --- Desktop notifications ---------------------------------------------------------------------------

  Inbox.prototype.setupNotifications = function () {
    var toggles = document.querySelectorAll('[data-role="notify-toggle"]');
    if (!('Notification' in window)) return;
    var refresh = function () {
      Array.prototype.forEach.call(toggles, function (button) {
        button.classList.remove('d-none');
        if (window.Notification.permission === 'granted') {
          button.textContent = 'Desktop notifications on';
          button.disabled = true;
        } else if (window.Notification.permission === 'denied') {
          button.textContent = 'Notifications blocked in this browser';
          button.disabled = true;
        }
      });
    };
    Array.prototype.forEach.call(toggles, function (button) {
      button.addEventListener('click', function () {
        // Asked only here, after a click: never on page load.
        var asked = window.Notification.requestPermission(function () { refresh(); });
        if (asked && asked.then) asked.then(refresh);
      });
    });
    refresh();
    this.notificationsReady = true;
  };

  Inbox.prototype.notifyIfNew = function (c) {
    var last = c.last_message;
    if (!last || last.direction !== 'inbound') return;
    var seen = this.lastInbound[c.id];
    this.lastInbound[c.id] = last.at;
    if (seen && new Date(seen) >= new Date(last.at)) return;
    // Only messages from this poll's window: not an older one on a conversation first seen now.
    if (this.since && new Date(last.at) < new Date(this.since)) return;
    var name = (c.customer && (c.customer.name || c.customer.email)) || 'Visitor';
    if (c.id !== this.selectedId) T.announce(this.$('status'), 'New message from ' + name + '.');
    if (!this.notificationsReady || !('Notification' in window) || window.Notification.permission !== 'granted') return;
    if (c.id === this.selectedId && document.hasFocus()) return;
    var self = this;
    var notification = new window.Notification(name, { body: last.body, tag: 'inbox-' + c.id });
    notification.onclick = function () {
      window.focus();
      self.select(c.id);
      notification.close();
    };
  };

  document.addEventListener('DOMContentLoaded', function () {
    var root = document.getElementById('inbox');
    if (root) window.adminInbox = new Inbox(root);
  });
})(window, document, window.jQuery);
