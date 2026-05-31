#include "include/patrol/patrol_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <atspi/atspi.h>

#include <cstring>

#define PATROL_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), patrol_plugin_get_type(), PatrolPlugin))

struct _PatrolPlugin {
  GObject parent_instance;
  FlMethodChannel* channel;
  gboolean initialized;
};

G_DEFINE_TYPE(PatrolPlugin, patrol_plugin, g_object_get_type())

static void ensure_initialized(PatrolPlugin* self) {
  if (!self->initialized) {
    atspi_init();
    self->initialized = TRUE;
  }
}

static AtspiAccessible* find_element_recursive(AtspiAccessible* root,
                                                const gchar* name,
                                                const gchar* role_name,
                                                int depth) {
  if (depth > 50 || !root) return NULL;

  gboolean name_ok = (name == NULL);
  gboolean role_ok = (role_name == NULL);

  if (name) {
    gchar* el_name = atspi_accessible_get_name(root, NULL);
    if (el_name && g_strcmp0(el_name, name) == 0) name_ok = TRUE;
    g_free(el_name);
  }

  if (role_name) {
    gchar* el_role = atspi_accessible_get_role_name(root, NULL);
    if (el_role && g_strcmp0(el_role, role_name) == 0) role_ok = TRUE;
    g_free(el_role);
  }

  if (name_ok && role_ok) {
    g_object_ref(root);
    return root;
  }

  int count = atspi_accessible_get_child_count(root, NULL);
  for (int i = 0; i < count; i++) {
    AtspiAccessible* child = atspi_accessible_get_child_at_index(root, i, NULL);
    if (!child) continue;
    AtspiAccessible* found =
        find_element_recursive(child, name, role_name, depth + 1);
    g_object_unref(child);
    if (found) return found;
  }
  return NULL;
}

static AtspiAccessible* find_element_with_timeout(const gchar* name,
                                                   const gchar* role_name,
                                                   int timeout_ms) {
  GTimer* timer = g_timer_new();
  AtspiAccessible* found = NULL;

  while (g_timer_elapsed(timer, NULL) * 1000 < timeout_ms) {
    AtspiAccessible* desktop = atspi_get_desktop(0);
    if (desktop) {
      int app_count = atspi_accessible_get_child_count(desktop, NULL);
      for (int i = 0; i < app_count && !found; i++) {
        AtspiAccessible* app =
            atspi_accessible_get_child_at_index(desktop, i, NULL);
        if (app) {
          found = find_element_recursive(app, name, role_name, 0);
          g_object_unref(app);
        }
      }
      g_object_unref(desktop);
    }
    if (found) break;
    g_usleep(200000);
  }

  g_timer_destroy(timer);
  return found;
}

static gboolean click_at_coords(int x, int y) {
  gchar x_str[16], y_str[16];
  g_snprintf(x_str, sizeof(x_str), "%d", x);
  g_snprintf(y_str, sizeof(y_str), "%d", y);

  const gchar* move_argv[] = {"xdotool", "mousemove", x_str, y_str, NULL};
  const gchar* click_argv[] = {"xdotool", "click", "1", NULL};
  gint status = 0;

  g_spawn_sync(NULL, (gchar**)move_argv, NULL, G_SPAWN_SEARCH_PATH,
               NULL, NULL, NULL, NULL, &status, NULL);
  if (status != 0) {
    const gchar* ydot_argv[] = {"ydotool", "mousemove", "-a", x_str, y_str, NULL};
    g_spawn_sync(NULL, (gchar**)ydot_argv, NULL, G_SPAWN_SEARCH_PATH,
                 NULL, NULL, NULL, NULL, &status, NULL);
    if (status != 0) return FALSE;
    const gchar* yclick[] = {"ydotool", "click", "1", NULL};
    g_spawn_sync(NULL, (gchar**)yclick, NULL, G_SPAWN_SEARCH_PATH,
                 NULL, NULL, NULL, NULL, &status, NULL);
    return status == 0;
  }

  g_spawn_sync(NULL, (gchar**)click_argv, NULL, G_SPAWN_SEARCH_PATH,
               NULL, NULL, NULL, NULL, &status, NULL);
  return status == 0;
}

static void click_element(AtspiAccessible* el) {
  if (!el) return;

  AtspiAction* action = atspi_accessible_get_action_iface(el);
  if (action) {
    int n = atspi_action_get_n_actions(action, NULL);
    for (int i = 0; i < n; i++) {
      gchar* act_name = atspi_action_get_action_name(action, i, NULL);
      if (act_name && (g_strcmp0(act_name, "click") == 0 ||
                       g_strcmp0(act_name, "activate") == 0 ||
                       g_strcmp0(act_name, "press") == 0)) {
        atspi_action_do_action(action, i, NULL);
        g_free(act_name);
        g_object_unref(action);
        return;
      }
      g_free(act_name);
    }
    g_object_unref(action);
  }

  AtspiComponent* comp = atspi_accessible_get_component_iface(el);
  if (comp) {
    AtspiPoint* pos =
        atspi_component_get_position(comp, ATSPI_COORD_TYPE_SCREEN, NULL);
    AtspiPoint* size = atspi_component_get_size(comp, NULL);
    if (pos && size) {
      click_at_coords(pos->x + size->x / 2, pos->y + size->y / 2);
    }
    if (pos) g_free(pos);
    if (size) g_free(size);
    g_object_unref(comp);
  }
}

static gboolean type_text(const gchar* text) {
  const gchar* argv[] = {
      "xdotool", "type", "--clearmodifiers", "--", text, NULL};
  gint status = 0;
  g_spawn_sync(NULL, (gchar**)argv, NULL, G_SPAWN_SEARCH_PATH,
               NULL, NULL, NULL, NULL, &status, NULL);
  if (status != 0) {
    const gchar* ydot_argv[] = {"ydotool", "type", "--", text, NULL};
    g_spawn_sync(NULL, (gchar**)ydot_argv, NULL, G_SPAWN_SEARCH_PATH,
                 NULL, NULL, NULL, NULL, &status, NULL);
  }
  return status == 0;
}

static gboolean press_key_cmd(const gchar* key_spec) {
  const gchar* argv[] = {"xdotool", "key", key_spec, NULL};
  gint status = 0;
  g_spawn_sync(NULL, (gchar**)argv, NULL, G_SPAWN_SEARCH_PATH,
               NULL, NULL, NULL, NULL, &status, NULL);
  if (status != 0) {
    const gchar* ydot_argv[] = {"ydotool", "key", key_spec, NULL};
    g_spawn_sync(NULL, (gchar**)ydot_argv, NULL, G_SPAWN_SEARCH_PATH,
                 NULL, NULL, NULL, NULL, &status, NULL);
  }
  return status == 0;
}

static FlValue* element_to_map(AtspiAccessible* el) {
  FlValue* map = fl_value_new_map();
  gchar* el_name = atspi_accessible_get_name(el, NULL);
  if (el_name) {
    fl_value_set_string_take(map, "name", fl_value_new_string(el_name));
    g_free(el_name);
  }
  gchar* el_role = atspi_accessible_get_role_name(el, NULL);
  if (el_role) {
    fl_value_set_string_take(map, "className", fl_value_new_string(el_role));
    g_free(el_role);
  }
  AtspiComponent* comp = atspi_accessible_get_component_iface(el);
  if (comp) {
    AtspiPoint* pos =
        atspi_component_get_position(comp, ATSPI_COORD_TYPE_SCREEN, NULL);
    AtspiPoint* size = atspi_component_get_size(comp, NULL);
    if (pos) {
      fl_value_set_string_take(map, "x", fl_value_new_float((double)pos->x));
      fl_value_set_string_take(map, "y", fl_value_new_float((double)pos->y));
      g_free(pos);
    }
    if (size) {
      fl_value_set_string_take(map, "width",
                                fl_value_new_float((double)size->x));
      fl_value_set_string_take(map, "height",
                                fl_value_new_float((double)size->y));
      g_free(size);
    }
    g_object_unref(comp);
  }
  return map;
}

static const gchar* get_string_arg(FlValue* args, const gchar* key) {
  FlValue* v = fl_value_lookup_string(args, key);
  if (v && fl_value_get_type(v) == FL_VALUE_TYPE_STRING)
    return fl_value_get_string(v);
  return NULL;
}

static int get_int_arg(FlValue* args, const gchar* key, int default_val) {
  FlValue* v = fl_value_lookup_string(args, key);
  if (v && fl_value_get_type(v) == FL_VALUE_TYPE_INT)
    return fl_value_get_int(v);
  return default_val;
}

static double get_double_arg(FlValue* args, const gchar* key,
                              double default_val) {
  FlValue* v = fl_value_lookup_string(args, key);
  if (!v) return default_val;
  if (fl_value_get_type(v) == FL_VALUE_TYPE_FLOAT) return fl_value_get_float(v);
  if (fl_value_get_type(v) == FL_VALUE_TYPE_INT)
    return (double)fl_value_get_int(v);
  return default_val;
}

static gboolean get_bool_arg(FlValue* args, const gchar* key,
                              gboolean default_val) {
  FlValue* v = fl_value_lookup_string(args, key);
  if (v && fl_value_get_type(v) == FL_VALUE_TYPE_BOOL)
    return fl_value_get_bool(v);
  return default_val;
}

static void handle_method_call(FlMethodChannel* channel,
                                FlMethodCall* method_call,
                                gpointer user_data) {
  PatrolPlugin* self = PATROL_PLUGIN(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  g_autoptr(FlMethodResponse) response = NULL;

  if (g_strcmp0(method, "initialize") == 0) {
    ensure_initialized(self);
    response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_null()));

  } else if (g_strcmp0(method, "tap") == 0 ||
             g_strcmp0(method, "doubleTap") == 0) {
    ensure_initialized(self);
    const gchar* name = get_string_arg(args, "name");
    const gchar* role = get_string_arg(args, "className");
    int timeout = get_int_arg(args, "timeoutMs", 10000);
    gboolean is_double = g_strcmp0(method, "doubleTap") == 0;

    AtspiAccessible* el = find_element_with_timeout(name, role, timeout);
    if (el) {
      click_element(el);
      if (is_double) {
        g_usleep(100000);
        click_element(el);
      }
      g_object_unref(el);
      response = FL_METHOD_RESPONSE(
          fl_method_success_response_new(fl_value_new_null()));
    } else {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "ELEMENT_NOT_FOUND", "No element matching criteria", NULL));
    }

  } else if (g_strcmp0(method, "tapAt") == 0) {
    int x = (int)get_double_arg(args, "x", 0);
    int y = (int)get_double_arg(args, "y", 0);
    click_at_coords(x, y);
    response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_null()));

  } else if (g_strcmp0(method, "enterText") == 0) {
    ensure_initialized(self);
    const gchar* text = get_string_arg(args, "text");
    if (!text) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "MISSING_TEXT", "text argument required", NULL));
    } else {
      const gchar* name = get_string_arg(args, "name");
      if (name) {
        int timeout = get_int_arg(args, "timeoutMs", 10000);
        AtspiAccessible* el = find_element_with_timeout(name, NULL, timeout);
        if (el) {
          AtspiEditableText* edit =
              atspi_accessible_get_editable_text_iface(el);
          if (edit) {
            AtspiText* text_iface = atspi_accessible_get_text_iface(el);
            if (text_iface) {
              int len = atspi_text_get_character_count(text_iface, NULL);
              if (len > 0)
                atspi_editable_text_delete_text(edit, 0, len, NULL);
              g_object_unref(text_iface);
            }
            atspi_editable_text_insert_text(edit, 0, text, strlen(text), NULL);
            g_object_unref(edit);
          } else {
            AtspiComponent* comp = atspi_accessible_get_component_iface(el);
            if (comp) {
              atspi_component_grab_focus(comp, NULL);
              g_usleep(100000);
              g_object_unref(comp);
            }
            type_text(text);
          }
          g_object_unref(el);
          response = FL_METHOD_RESPONSE(
              fl_method_success_response_new(fl_value_new_null()));
        } else {
          response = FL_METHOD_RESPONSE(fl_method_error_response_new(
              "ELEMENT_NOT_FOUND", "No element matching criteria", NULL));
        }
      } else {
        type_text(text);
        response = FL_METHOD_RESPONSE(
            fl_method_success_response_new(fl_value_new_null()));
      }
    }

  } else if (g_strcmp0(method, "isElementVisible") == 0) {
    ensure_initialized(self);
    const gchar* name = get_string_arg(args, "name");
    const gchar* role = get_string_arg(args, "className");
    AtspiAccessible* el = find_element_with_timeout(name, role, 500);
    gboolean visible = el != NULL;
    if (el) g_object_unref(el);
    response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_bool(visible)));

  } else if (g_strcmp0(method, "findElement") == 0) {
    ensure_initialized(self);
    const gchar* name = get_string_arg(args, "name");
    const gchar* role = get_string_arg(args, "className");
    int timeout = get_int_arg(args, "timeoutMs", 10000);
    AtspiAccessible* el = find_element_with_timeout(name, role, timeout);
    if (el) {
      response = FL_METHOD_RESPONSE(
          fl_method_success_response_new(element_to_map(el)));
      g_object_unref(el);
    } else {
      response = FL_METHOD_RESPONSE(
          fl_method_success_response_new(fl_value_new_null()));
    }

  } else if (g_strcmp0(method, "findElements") == 0) {
    ensure_initialized(self);
    const gchar* name = get_string_arg(args, "name");
    const gchar* role = get_string_arg(args, "className");

    FlValue* list = fl_value_new_list();
    AtspiAccessible* desktop = atspi_get_desktop(0);
    if (desktop) {
      int app_count = atspi_accessible_get_child_count(desktop, NULL);
      for (int i = 0; i < app_count; i++) {
        AtspiAccessible* app =
            atspi_accessible_get_child_at_index(desktop, i, NULL);
        if (app) {
          AtspiAccessible* found =
              find_element_recursive(app, name, role, 0);
          if (found) {
            fl_value_append_take(list, element_to_map(found));
            g_object_unref(found);
          }
          g_object_unref(app);
        }
      }
      g_object_unref(desktop);
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(list));

  } else if (g_strcmp0(method, "pressKey") == 0) {
    int keycode = get_int_arg(args, "keyCode", 0);
    gboolean shift = get_bool_arg(args, "shift", FALSE);
    gboolean ctrl = get_bool_arg(args, "ctrl", FALSE);
    gboolean alt_key = get_bool_arg(args, "alt", FALSE);

    GString* spec = g_string_new(NULL);
    if (ctrl) g_string_append(spec, "ctrl+");
    if (shift) g_string_append(spec, "shift+");
    if (alt_key) g_string_append(spec, "alt+");
    g_string_append_printf(spec, "%d", keycode);
    press_key_cmd(spec->str);
    g_string_free(spec, TRUE);

    response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_null()));

  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, NULL);
}

static void patrol_plugin_dispose(GObject* object) {
  PatrolPlugin* self = PATROL_PLUGIN(object);
  g_clear_object(&self->channel);
  G_OBJECT_CLASS(patrol_plugin_parent_class)->dispose(object);
}

static void patrol_plugin_class_init(PatrolPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = patrol_plugin_dispose;
}

static void patrol_plugin_init(PatrolPlugin* self) {
  self->initialized = FALSE;
  self->channel = NULL;
}

void patrol_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  PatrolPlugin* plugin =
      PATROL_PLUGIN(g_object_new(patrol_plugin_get_type(), NULL));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  plugin->channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "pl.leancode.patrol/desktopAutomator",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      plugin->channel, handle_method_call, g_object_ref(plugin),
      g_object_unref);

  g_object_unref(plugin);
}
