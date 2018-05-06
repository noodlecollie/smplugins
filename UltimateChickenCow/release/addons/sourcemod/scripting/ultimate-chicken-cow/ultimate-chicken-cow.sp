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
#include <sdktools>

// Libraries
#include "pluginctl/pluginctl.inc"
#include "clientrecords/clientrecords.inc"

#include "plugininfo.inc"
#include "clientrecord.inc"
#include "config-convars.inc"

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
    int currentFlags = GetEntityFlags(client);

    if ( (currentFlags & FL_ONGROUND) != FL_ONGROUND || (buttons & IN_JUMP) != IN_JUMP )
    {
        return Plugin_Continue;
    }

    // Velocity is local - +X is forward, +Y is left, +Z is up.

    // The following rules apply:
    // - If we're looking up, we want to apply full upward force and no forward force.
    // - If we're looking down, we don't want to apply any forward or upward force.
    // - If we're looking straight ahead, we want to apply half the force up and half forward.
    // - Yaw doesn't matter when applying force in the direction of motion.

    // Get 2D vectors from current angles.
    float fwd[3] = { 0.0, ... };
    float right[3] = { 0.0, ... };
    GetAngleVectors(angles, fwd, right, NULL_VECTOR);

    // Apply forward and right speed in both these directions.
    ScaleVector(fwd, vel[0]);
    ScaleVector(right, vel[1]);

    // Remember what this is as a single world velocity vector.
    float worldVelocity[3] = { 0.0, ... };
    AddVectors(fwd, right, worldVelocity);
    worldVelocity[2] = 0.0;

    // Duplicate this in order to use it for jump force calculations.
    float extraVelocity[3] = { 0.0, ... };
    extraVelocity[0] = worldVelocity[0];
    extraVelocity[1] = worldVelocity[1];
    NormalizeVector(extraVelocity, extraVelocity);

    // Apply maximum forward force when we're looking straight ahead, when pitch is 0.
    // This is accomplished using cos(pitch).
    ScaleVector(extraVelocity, Cosine(DegToRad(angles[0])));

    // Apply maximum upward force when we're looking directly up,
    // but none at all when we're looking directly down.
    // This means the multiplier is 1 when the pitch is -90,
    // and 0 when the pitch is 90.
    // This is accomplished using sin((pitch/2) + 45).
    extraVelocity[2] = Sine(DegToRad((-angles[0] / 2.0) + 45));

    // Multiply by our desired force.
    ScaleVector(extraVelocity, GetConVarFloat(cvJumpForce));

    // Add to existing velocity.
    AddVectors(worldVelocity, extraVelocity, worldVelocity);

    // Apply.
    TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, worldVelocity);

    return Plugin_Continue;
}


static stock void OnPluginEnabledStateChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
}

static stock void ConstructClientRecord(int client, Dynamic &item)
{
    item = UCC_ClientRecord(client);
}
