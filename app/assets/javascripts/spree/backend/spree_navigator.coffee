root = exports ? this

last_menu_rollback = null


handle_menu_ajax_error = (XMLHttpRequest, textStatus, errorThrown) ->
  $.jstree.rollback(last_menu_rollback)
  $("#ajax_error").show()
                  .html("<strong>" + server_error + "</strong><br />" + menu_tree_error)

handle_menu_move = (e, data) ->
  last_menu_rollback = data.rlbk
  position           = data.rslt.cp
  node               = data.rslt.o
  new_parent         = data.rslt.np
  url                = Spree.url(base_url).clone()
  url.setPath url.path() + '/' + node.prop("id")

  $.ajax
    type:     "POST",
    dataType: "json",
    url:      url.toString(),
    data:
      _method:   "put"
      menu_item:
        parent_id: new_parent.prop("id")
        position:  position
    error:    handle_menu_ajax_error
  true

handle_menu_create = (e, data) ->
  last_menu_rollback = data.rlbk
  node               = data.rslt.obj
  name               = data.rslt.name
  position           = data.rslt.position
  new_parent         = data.rslt.parent

  $.ajax
    type:     "POST"
    dataType: "json"
    url:      base_url.toString()
    data:
      menu_item:
        name:      name
        parent_id: new_parent.prop("id")
        position:  position
    error:    handle_menu_ajax_error
    success:  (data,result) ->
      node.prop('id', data.id)

handle_menu_rename = (e, data) ->
  last_menu_rollback = data.rlbk
  node               = data.rslt.obj
  name               = data.rslt.new_name
  url                = Spree.url(base_url).clone()
  url.setPath(url.path() + '/' + node.prop("id"))

  $.ajax
    type:     "POST"
    dataType: "json"
    url:      url.toString()
    data:
      _method:   "put",
      menu_item:
        name: name
    error:    handle_menu_ajax_error

handle_menu_delete = (e, data) ->
  last_menu_rollback = data.rlbk
  node               = data.rslt.obj
  delete_url         = base_url.clone()
  delete_url.setPath delete_url.path() + '/' + node.prop("id")

  jConfirm Spree.translations.are_you_sure_delete, Spree.translations.confirm_delete, (r) ->
    if r
      $.ajax
        type:     "POST"
        dataType: "json"
        url:      delete_url.toString()
        data:
          _method: "delete"
        error:    handle_menu_ajax_error
    else
      $.jstree.rollback(last_menu_rollback)
      last_menu_rollback = null


root.setup_menu_tree = () ->
  root.base_url = Spree.url(Spree.routes.admin_menu_items_path)
  $.ajax
    url:      Spree.url(base_url.path()).toString(),
    dataType: "json",
    success:  (menu_item) ->
      last_menu_rollback = null
      conf =
        json_data:
          data: menu_item
          ajax:
            url: (e) ->
              Spree.url(base_url.path() + '/' + e.prop('id') + '/children').toString()
        themes:
          theme: "apple"
          url: Spree.url(Spree.routes.jstree_theme_path)
        strings:
          new_node: new_menu
          loading: Spree.translations.loading + "..."
        crrm:
          move:
            check_move: (m) ->
              position   = m.cp
              node       = m.o
              new_parent = m.np
              # no parent or cant drag and drop
              return false if !new_parent || node.prop("rel") == "root"
              # can't drop before root
              return false if new_parent.prop("id") == "menu_tree" && position == 0
              true
        contextmenu:
          items: (obj) ->
            menu_tree_menu(obj, this)
        plugins: ["themes", "json_data", "dnd", "crrm", "contextmenu"]

      $("#menu_tree").jstree(conf)
        .bind("move_node.jstree", handle_menu_move)
        .bind("remove.jstree", handle_menu_delete)
        .bind("create.jstree", handle_menu_create)
        .bind("rename.jstree", handle_menu_rename)
        .bind "loaded.jstree", ->
          $(this).jstree("core").toggle_node($('.jstree-icon').first())


root.menu_tree_menu = (obj, context) ->
  admin_base_url = Spree.url(Spree.routes.admin_menu_items_path)
  edit_url       = admin_base_url.clone()
  edit_url.setPath(edit_url.path() + '/' + obj.attr("id") + "/edit");

  create:
    label:  "<i class='fa fa-plus'></i> " + Spree.translations.add,
    action: (obj) -> context.create(obj)
  rename:
    label:  "<i class='fa fa-pencil'></i> " + Spree.translations.rename,
    action: (obj) -> context.rename(obj)
  remove:
    label:  "<i class='fa fa-trash'></i> " + Spree.translations.remove,
    action: (obj) -> context.remove(obj)
  edit:
    separator_before: true,
    label:            "<i class='fa fa-edit'></i> " + Spree.translations.edit,
    action:           (obj) -> window.location = edit_url.toString()
