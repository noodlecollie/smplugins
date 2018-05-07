#if defined _TF2UCC_PLAYERS_INC
 #endinput
#endif
#define _TF2UCC_PLAYERS_INC

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#include "smlib/math.inc"
#include "smlib/arrays.inc"

void PerformLongJump(int client, const float vel[3], const float angles[3])
{
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
}

bool GetClientContactNormal(int client, float[3] contact)
{
    float velocity[3] = { 0.0, ... };
    velocity[0] = GetEntPropFloat(client, Prop_Send, "m_vecVelocity[0]");
    velocity[1] = GetEntPropFloat(client, Prop_Send, "m_vecVelocity[1]");
    velocity[2] = GetEntPropFloat(client, Prop_Send, "m_vecVelocity[2]");

    if ( velocity[0] != 0.0 || velocity[1] != 0.0 || velocity[2] != 0.0 )
    {
        NormalizeVector(velocity, velocity);
    }
    else
    {
        // Just trace down via gravity.
        Math_MakeVector(0.0, 0.0, -1.0, velocity);
    }

    ScaleVector(velocity, GetConVarFloat(cvWallJumpTraceDist));

    float mins[3] = { 0.0, ... };
    float maxs[3] = { 0.0, ... };
    float origin[3] = { 0.0, ... };
    GetEntPropVector(client, Prop_Send, "m_vecMins", mins);
    GetEntPropVector(client, Prop_Send, "m_vecMaxs", maxs);
    GetClientAbsOrigin(client, origin);

    float target[3] = { 0.0, ... };
    AddVectors(origin, velocity, target);

    Handle trace = TR_TraceHullFilterEx(origin, target, mins, maxs, MASK_SOLID, TraceFilterIgnoreClient, client);
    bool didHit = TR_DidHit(trace);

    if ( didHit )
    {
        TR_GetPlaneNormal(trace, contact);
    }

    CloseHandle(trace);
    return didHit;
}

static stock bool TraceFilterIgnoreClient(int entity, int contentsMask, any data)
{
    return entity != view_as<int>(data);
}
