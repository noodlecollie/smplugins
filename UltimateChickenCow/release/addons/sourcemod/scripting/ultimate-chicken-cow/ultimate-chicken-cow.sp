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
#include <sdkhooks>

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
    LogMessage("Starting: %s v%s", PLUGIN_NAME, PLUGIN_VERSION);

    PCtl_Initialise(PLUGIN_IDENT, PLUGIN_VERSION, OnPluginEnabledStateChanged);
    CreateConfigConVars();
    ClientRecords_Initialise(ConstructClientRecord);
    InitForCurrentClients();
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
    float currentTime = GetGameTime();
    int currentFlags = GetEntityFlags(client);
    float minInterval = GetConVarFloat(cvLongJumpMinInterval) / 1000.0;

    bool attemptingLongJump =
         (buttons & IN_JUMP) == IN_JUMP                             // We must be pressing jump
         && !record.InJump                                          // We must have released the key after a previous jump
         && (buttons & IN_DUCK) == IN_DUCK                          // We must be pressing crouch
         && currentTime - record.LastLongJumpTime >= minInterval;   // Enough time must have passed since the last long jump.

    if ( attemptingLongJump )
    {
        bool canPerformLongJump =
            (currentFlags & FL_ONGROUND) == FL_ONGROUND // Either we're on the ground
            || ClientCanWallJump(client, vel, angles);  // or next to something we can springboard off.

        if ( canPerformLongJump )
        {
            // Apply forward force only when we're on the ground.
            PerformLongJump(client, vel, angles, (currentFlags & FL_ONGROUND) == FL_ONGROUND);

            record.LastLongJumpTime = currentTime;
        }
    }

    record.InJump = (buttons & IN_JUMP) == IN_JUMP;

    return Plugin_Continue;
}

static stock void OnPluginEnabledStateChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
}

static stock void InitForCurrentClients()
{
    for ( int client = 1; client <= MaxClients; ++client )
    {
        if ( IsClientConnected(client) )
        {
            OnClientConnected(client);
        }
    }
}

static stock void ConstructClientRecord(int client, Dynamic &item)
{
    item = UCC_ClientRecord(client);
}
