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
#include "clientrecords/clientrecords.inc"

#include "plugininfo.inc"
#include "clientrecord.inc"

#pragma semicolon 1
#pragma newdecls required

public void OnPluginStart()
{
    LogMessage("[Starting: %s v%s]", PLUGIN_NAME, PLUGIN_VERSION);

    PCtl_Initialise(PLUGIN_IDENT, PLUGIN_VERSION, OnPluginEnabledStateChanged);
    ClientRecords_Initialise(ConstructClientRecord);
}

public void OnPluginEnd()
{
    LogMessage("Shutting down.");

    ClientRecords_Destroy();
    PCtl_Shutdown();
}

public void OnClientConnected(int client)
{
    ClientRecords_NotifyClientConnected(client);
}

public void OnClientDisconnect(int client)
{
    ClientRecords_NotifyClientDisconnected(client);
}

static stock void OnPluginEnabledStateChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
}

static stock void ConstructClientRecord(Dynamic &item)
{
    item = UCC_ClientRecord();
}
