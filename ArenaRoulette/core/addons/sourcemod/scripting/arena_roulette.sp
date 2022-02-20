#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include "pluginctl/pluginctl.inc"
#include "plugin_info.inc"
#include "natives.inc"

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNatives();
	RegPluginLibrary(LIBRARY_NAME);

	return APLRes_Success;
}

public void OnPluginStart()
{
	LogMessage("Starting: %s v%s", PLUGIN_NAME, PLUGIN_VERSION);
	PCtl_Initialise(PLUGIN_IDENT, PLUGIN_VERSION, OnPluginEnabledStateChanged);
}

public void OnPluginEnd()
{
	PCtl_Shutdown();
}

static stock void OnPluginEnabledStateChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	// Nothing here yet
}
