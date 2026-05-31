#include "include/patrol/patrol_plugin.h"

#include <flutter/plugin_registrar_windows.h>

#include "patrol_plugin.h"

void PatrolPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  patrol::PatrolPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
