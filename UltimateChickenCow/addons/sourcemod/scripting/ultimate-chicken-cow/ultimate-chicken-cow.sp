/*
 _________________________________________
/ Ultimate Chicken Cow - That competitive \
\ hazardous platformer, in TF2.           /
 -----------------------------------------
        \   ^__^
         \  (oo)\_______
            (__)\       )\/\
                ||----w |
                ||     ||

    First created: Saturday 5th May 2018,
    a sunny bank holiday.
*/

#include <sourcemod>

// Libraries
#include "pluginctl/pluginctl.inc"

#include "plugininfo.inc"
#include "config-cvars.inc"

#pragma semicolon 1
#pragma newdecls required

public void OnPluginStart()
{
    LogMessage("[Starting: %s v%s]", PLUGIN_NAME, PLUGIN_VERSION);

    PCtl_Initialise(PLUGIN_IDENT, PLUGIN_VERSION, OnPluginEnabledStateChanged);
    RegisterConfigCvars();
}

public void OnPluginEnd()
{
    LogMessage("Shutting down.");

    PCtl_Shutdown();
}

static stock void OnPluginEnabledStateChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
}
