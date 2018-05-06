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
#include "config-convars.inc"
#include "players.inc"

#pragma semicolon 1
#pragma newdecls required

public void OnPluginStart()
{
    LogMessage("[Starting: %s v%s]", PLUGIN_NAME, PLUGIN_VERSION);

    PCtl_Initialise(PLUGIN_IDENT, PLUGIN_VERSION, OnPluginEnabledStateChanged);
    CreateConfigConVars();
    ClientRecords_Initialise(ConstructClientRecord);
}

public void OnPluginEnd()
{
    LogMessage("Shutting down.");

    ClientRecords_Destroy();
    DestroyConfigConVars();
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

public Action OnPlayerRunCmd(int client,
                      int &buttons,
                      int &impulse,
                      float vel[3],
                      float angles[3],
                      int &weapon,
                      int &subtype,
                      int &cmdnum,
                      int &tickcount,
                      int &seed,
                      int mouse[2])
{
    UCC_ClientRecord record = view_as<UCC_ClientRecord>(ClientRecords_GetRecord(client));

    if ( (GetEntityFlags(client) & FL_ONGROUND) == FL_ONGROUND  // We must be on the ground
         && (buttons & IN_JUMP) == IN_JUMP                      // We must be pressing jump
         && !record.InJump                                      // We must have released the key after a previous jump
         && (buttons & IN_DUCK) == IN_DUCK )                    // We must be pressing crouch
    {
        PerformLongJump(client, vel, angles);
    }

    record.InJump = (buttons & IN_JUMP) == IN_JUMP;

    return Plugin_Continue;
}


static stock void OnPluginEnabledStateChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
}

static stock void ConstructClientRecord(int client, Dynamic &item)
{
    item = UCC_ClientRecord(client);
}