#include "include/patrol/patrol_plugin.h"

#include <flutter_linux/flutter_linux.h>

#define PATROL_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), patrol_plugin_get_type(), PatrolPlugin))

struct _PatrolPlugin {
  GObject parent_instance;
  FlMethodChannel* channel;
};

G_DEFINE_TYPE(PatrolPlugin, patrol_plugin, g_object_get_type())

static void patrol_plugin_handle_method_call(PatrolPlugin* self,
                                             FlMethodCall* method_call) {
  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  fl_method_call_respond(method_call, response, nullptr);
}

static void patrol_plugin_dispose(GObject* object) {
  G_OBJECT_CLASS(patrol_plugin_parent_class)->dispose(object);
}

static void patrol_plugin_class_init(PatrolPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = patrol_plugin_dispose;
}

static void patrol_plugin_init(PatrolPlugin* self) {}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
  PatrolPlugin* plugin = PATROL_PLUGIN(user_data);
  patrol_plugin_handle_method_call(plugin, method_call);
}

void patrol_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  PatrolPlugin* plugin =
      PATROL_PLUGIN(g_object_new(patrol_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar), "patrol", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      channel, method_call_cb, g_object_ref(plugin), g_object_unref);

  plugin->channel = FL_METHOD_CHANNEL(g_object_ref(channel));

  g_object_unref(plugin);
}
