#include "include/patrol/patrol_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <atspi/atspi.h>

#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#define PATROL_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), patrol_plugin_get_type(), PatrolPlugin))

struct _PatrolPlugin {
  GObject parent_instance;
  FlMethodChannel* channel;
  gboolean initialized;
};

G_DEFINE_TYPE(PatrolPlugin, patrol_plugin, g_object_get_type())

static AtspiAccessible* find_element_recursive(AtspiAccessible* root,
                                                const gchar* name,
                                                const gchar* role_name,
                                                int depth) {
  if (depth > 20 || !root) return NULL;

  if (name) {
    gchar* el_name = atspi_accessible_get_name(root, NULL);
    if (el_name && g_strcmp0(el_name, name) == 0) {
      g_free(el_name);
      g_object_ref(root);
      return root;
    }
    g_free(el_name);
  }

  if (role_name) {
    gchar* el_role = atspi_accessible_get_role_name(root, NULL);
    if (el_role && g_strcmp0(el_role, role_name) == 0) {
      g_free(el_role);
      if (!name) {
        g_object_ref(root);
        return root;
      }
    }
    if (el_role) g_free(el_role);
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
    g_usleep(200000);  // 200ms
  }

  g_timer_destroy(timer);
  return found;
}

static gboolean click_at_coords(int x, int y) {
  gchar* cmd = g_strdup_printf("xdotool mousemove %d %d click 1", x, y);
  int ret = system(cmd);
  g_free(cmd);
  if (ret != 0) {
    // xdotool not available or X11 not running, try ydotool
    cmd = g_strdup_printf("ydotool mousemove -a %d %d && ydotool click 1", x, y);
    ret = system(cmd);
    g_free(cmd);
  }
  return ret == 0;
}

static gboolean type_text(const gchar* text) {
  // Use xdotool for typing
  gchar* escaped = g_shell_quote(text);
  gchar* cmd = g_strdup_printf("xdotool type --clearmodifiers -- %s", escaped);
  int ret = system(cmd);
  g_free(cmd);
  g_free(escaped);
  if (ret != 0) {
    escaped = g_shell_quote(text);
    cmd = g_strdup_printf("ydotool type -- %s", escaped);
    ret = system(cmd);
    g_free(cmd);
    g_free(escaped);
  }
  return ret == 0;
}

static gboolean press_key(int keycode, gboolean shift, gboolean ctrl,
                           gboolean alt) {
  GString* cmd = g_string_new("xdotool key ");
  if (ctrl) g_string_append(cmd, "ctrl+");
  if (shift) g_string_append(cmd, "shift+");
  if (alt) g_string_append(cmd, "alt+");
  g_string_append_printf(cmd, "%d", keycode);
  int ret = system(cmd->str);
  g_string_free(cmd, TRUE);
  return ret == 0;
}

static void handle_method_call(FlMethodChannel* channel,
                                FlMethodCall* method_call,
                                gpointer user_data) {
  PatrolPlugin* self = PATROL_PLUGIN(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  g_autoptr(FlMethodResponse) response = NULL;

  if (g_strcmp0(method, "initialize") == 0) {
    if (!self->initialized) {
      atspi_init();
      self->initialized = TRUE;
    }
    response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_null()));
  } else if (g_strcmp0(method, "tap") == 0) {
    if (!self->initialized) atspi_init();

    const gchar* name = NULL;
    const gchar* role = NULL;
    int timeout = 10000;

    FlValue* v = fl_value_lookup_string(args, "name");
    if (v && fl_value_get_type(v) == FL_VALUE_TYPE_STRING)
      name = fl_value_get_string(v);
    v = fl_value_lookup_string(args, "className");
    if (v && fl_value_get_type(v) == FL_VALUE_TYPE_STRING)
      role = fl_value_get_string(v);
    v = fl_value_lookup_string(args, "timeoutMs");
    if (v && fl_value_get_type(v) == FL_VALUE_TYPE_INT)
      timeout = fl_value_get_int(v);

    AtspiAccessible* el = find_element_with_timeout(name, role, timeout);
    if (el) {
      // Try AT-SPI Action interface first
      AtspiAction* action = atspi_accessible_get_action_iface(el);
      gboolean clicked = FALSE;
      if (action) {
        int n = atspi_action_get_n_actions(action, NULL);
        for (int i = 0; i < n; i++) {
          gchar* act_name = atspi_action_get_action_name(action, i, NULL);
          if (act_name && (g_strcmp0(act_name, "click") == 0 ||
                           g_strcmp0(act_name, "activate") == 0 ||
                           g_strcmp0(act_name, "press") == 0)) {
            atspi_action_do_action(action, i, NULL);
            clicked = TRUE;
            g_free(act_name);
            break;
          }
          g_free(act_name);
        }
        g_object_unref(action);
      }

      if (!clicked) {
        // Fall back to coordinate click
        AtspiComponent* comp = atspi_accessible_get_component_iface(el);
        if (comp) {
          AtspiPoint* pos =
              atspi_component_get_position(comp, ATSPI_COORD_TYPE_SCREEN, NULL);
          AtspiPoint* size =
              atspi_component_get_size(comp, NULL);
          if (pos && size) {
            click_at_coords(pos->x + size->x / 2, pos->y + size->y / 2);
          }
          if (pos) g_free(pos);
          if (size) g_free(size);
          g_object_unref(comp);
        }
      }
      g_object_unref(el);
      response = FL_METHOD_RESPONSE(
          fl_method_success_response_new(fl_value_new_null()));
    } else {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "ELEMENT_NOT_FOUND", "No element matching criteria", NULL));
    }
  } else if (g_strcmp0(method, "tapAt") == 0) {
    FlValue* vx = fl_value_lookup_string(args, "x");
    FlValue* vy = fl_value_lookup_string(args, "y");
    int x = 0, y = 0;
    if (vx) x = (int)(fl_value_get_type(vx) == FL_VALUE_TYPE_FLOAT
                           ? fl_value_get_float(vx)
                           : fl_value_get_int(vx));
    if (vy) y = (int)(fl_value_get_type(vy) == FL_VALUE_TYPE_FLOAT
                           ? fl_value_get_float(vy)
                           : fl_value_get_int(vy));
    click_at_coords(x, y);
    response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_null()));
  } else if (g_strcmp0(method, "enterText") == 0) {
    FlValue* vtext = fl_value_lookup_string(args, "text");
    if (vtext && fl_value_get_type(vtext) == FL_VALUE_TYPE_STRING) {
      const gchar* name = NULL;
      FlValue* vname = fl_value_lookup_string(args, "name");
      if (vname && fl_value_get_type(vname) == FL_VALUE_TYPE_STRING)
        name = fl_value_get_string(vname);

      if (name) {
        int timeout = 10000;
        FlValue* vt = fl_value_lookup_string(args, "timeoutMs");
        if (vt && fl_value_get_type(vt) == FL_VALUE_TYPE_INT)
          timeout = fl_value_get_int(vt);

        AtspiAccessible* el = find_element_with_timeout(name, NULL, timeout);
        if (el) {
          // Try EditableText interface
          AtspiEditableText* edit =
              atspi_accessible_get_editable_text_iface(el);
          if (edit) {
            const gchar* text = fl_value_get_string(vtext);
            // Clear existing text
            AtspiText* text_iface = atspi_accessible_get_text_iface(el);
            if (text_iface) {
              int len = atspi_text_get_character_count(text_iface, NULL);
              if (len > 0) atspi_editable_text_delete_text(edit, 0, len, NULL);
              g_object_unref(text_iface);
            }
            atspi_editable_text_insert_text(edit, 0, fl_value_get_string(vtext),
                                             strlen(fl_value_get_string(vtext)),
                                             NULL);
            g_object_unref(edit);
          } else {
            // Focus and type via xdotool
            AtspiComponent* comp = atspi_accessible_get_component_iface(el);
            if (comp) {
              atspi_component_grab_focus(comp, NULL);
              g_usleep(100000);
              g_object_unref(comp);
            }
            type_text(fl_value_get_string(vtext));
          }
          g_object_unref(el);
          response = FL_METHOD_RESPONSE(
              fl_method_success_response_new(fl_value_new_null()));
        } else {
          response = FL_METHOD_RESPONSE(fl_method_error_response_new(
              "ELEMENT_NOT_FOUND", "No element matching criteria", NULL));
        }
      } else {
        type_text(fl_value_get_string(vtext));
        response = FL_METHOD_RESPONSE(
            fl_method_success_response_new(fl_value_new_null()));
      }
    } else {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "MISSING_TEXT", "text argument required", NULL));
    }
  } else if (g_strcmp0(method, "isElementVisible") == 0) {
    if (!self->initialized) atspi_init();

    const gchar* name = NULL;
    const gchar* role = NULL;

    FlValue* v = fl_value_lookup_string(args, "name");
    if (v && fl_value_get_type(v) == FL_VALUE_TYPE_STRING)
      name = fl_value_get_string(v);
    v = fl_value_lookup_string(args, "className");
    if (v && fl_value_get_type(v) == FL_VALUE_TYPE_STRING)
      role = fl_value_get_string(v);

    AtspiAccessible* el = find_element_with_timeout(name, role, 500);
    gboolean visible = el != NULL;
    if (el) g_object_unref(el);
    response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_bool(visible)));
  } else if (g_strcmp0(method, "findElement") == 0) {
    if (!self->initialized) atspi_init();

    const gchar* name = NULL;
    const gchar* role = NULL;
    int timeout = 10000;

    FlValue* v = fl_value_lookup_string(args, "name");
    if (v && fl_value_get_type(v) == FL_VALUE_TYPE_STRING)
      name = fl_value_get_string(v);
    v = fl_value_lookup_string(args, "className");
    if (v && fl_value_get_type(v) == FL_VALUE_TYPE_STRING)
      role = fl_value_get_string(v);
    v = fl_value_lookup_string(args, "timeoutMs");
    if (v && fl_value_get_type(v) == FL_VALUE_TYPE_INT)
      timeout = fl_value_get_int(v);

    AtspiAccessible* el = find_element_with_timeout(name, role, timeout);
    if (el) {
      FlValue* map = fl_value_new_map();
      gchar* el_name = atspi_accessible_get_name(el, NULL);
      if (el_name) {
        fl_value_set_string_take(map, "name", fl_value_new_string(el_name));
        g_free(el_name);
      }
      gchar* el_role = atspi_accessible_get_role_name(el, NULL);
      if (el_role) {
        fl_value_set_string_take(map, "className",
                                  fl_value_new_string(el_role));
        g_free(el_role);
      }
      AtspiComponent* comp = atspi_accessible_get_component_iface(el);
      if (comp) {
        AtspiPoint* pos =
            atspi_component_get_position(comp, ATSPI_COORD_TYPE_SCREEN, NULL);
        AtspiPoint* size = atspi_component_get_size(comp, NULL);
        if (pos) {
          fl_value_set_string_take(map, "x",
                                    fl_value_new_float((double)pos->x));
          fl_value_set_string_take(map, "y",
                                    fl_value_new_float((double)pos->y));
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
      g_object_unref(el);
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(map));
    } else {
      response = FL_METHOD_RESPONSE(
          fl_method_success_response_new(fl_value_new_null()));
    }
  } else if (g_strcmp0(method, "pressKey") == 0) {
    FlValue* vk = fl_value_lookup_string(args, "keyCode");
    int keycode = vk ? fl_value_get_int(vk) : 0;
    gboolean shift = FALSE, ctrl = FALSE, alt_key = FALSE;
    FlValue* vs = fl_value_lookup_string(args, "shift");
    if (vs) shift = fl_value_get_bool(vs);
    vs = fl_value_lookup_string(args, "ctrl");
    if (vs) ctrl = fl_value_get_bool(vs);
    vs = fl_value_lookup_string(args, "alt");
    if (vs) alt_key = fl_value_get_bool(vs);
    press_key(keycode, shift, ctrl, alt_key);
    response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_null()));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, NULL);
}

static void patrol_plugin_class_init(PatrolPluginClass* klass) {}

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
      plugin->channel, handle_method_call, plugin, g_object_unref);

  g_object_unref(plugin);
}
