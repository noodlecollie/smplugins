/*
  _______ ______ ___    _____  __  __ 
 |__   __|  ____|__ \  |  __ \|  \/  |
    | |  | |__     ) | | |  | | \  / |
    | |  |  __|   / /  | |  | | |\/| |
    | |  | |     / /_  | |__| | |  | |
    |_|  |_|    |____| |_____/|_|  |_|

    A deathmatch game mode for TF2.
    Initially created by [X6] Herbius on 05/11/12 at 14:02.
*/

#include <sourcemod>
#include "pluginctl/pluginctl.inc"

#include "include/plugininfo.inc"
#include "include/weaponsetreader.inc"

#pragma semicolon 1
#pragma newdecls required

static const char _RequiredLibraries[][] =
{
    "tf2idb",
};

public void OnPluginStart()
{
    LogMessage("========== %s [v%s] ==========", PLUGIN_NAME, PLUGIN_VERSION);
    
    PCtl_Initialise("tf2dm", PLUGIN_VERSION, OnPluginEnabledStateChanged);
    WepSetRx_Initialise();
    
    PCtl_PerformPluginLoadTasks();
}

public void OnPluginEnd()
{
    LogMessage("Shutting down.");
    
    WepSetRx_Shutdown();
    PCtl_Shutdown(OnPluginEnabledStateChanged);
}

public void OnAllPluginsLoaded()
{
    PCtl_EnsureDependenciesExist(_RequiredLibraries, sizeof(_RequiredLibraries));
}

public void OnPluginEnabledStateChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    
}