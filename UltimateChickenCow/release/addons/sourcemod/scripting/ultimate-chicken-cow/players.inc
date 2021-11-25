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
#include "config-convars.inc"

enum SpecialJumpType
{
    SJT_NoJump,
    SJT_LongJump,       // A forward jump while the player is in contact with the floor
    SJT_WallClimb,      // An upward jump while the player is facing a wall
    SJT_Springboard,    // A jump off a wall that is behind the player
};

// TODO: We're doing lots of switching for various things here based on the jump type.
// Really we need a proper class to store the attributes for each jump type, to
// make the control flow easier to follow.
void PerformSpecialJump(int client, const float vel[3], const float angles[3], SpecialJumpType jumpType)
{
    // vel is local - +X is forward, +Y is left, +Z is up.

    // The following rules apply:
    // - If we're looking up, we want to apply full upward force and no forward force.
    // - If we're looking down, we don't want to apply any forward or upward force.
    // - If we're looking straight ahead, we want to apply half the force up and half forward.
    // - Yaw doesn't matter when applying force in the direction of motion.

    // Get the actual real-world velocity of the client.
    float worldVelocity[3] = { 0.0, ... };
    GetClientAbsVelocity(client, worldVelocity);

    if ( jumpType != SJT_LongJump )
    {
        // Take out some of the existing vertical velocity.
        worldVelocity[2] *= GetConVarFloat(cvWallClimbVerticalVelocityBlend);
    }

    // Prepare a vector for the velocity we will add.
    float extraVelocity[3] = { 0.0, ... };

    // Get movement key velocity.
    // The vel argument to this function represents the desired velocity, local to the player.
    // This is not the same as the client's actual world velocity.
    float moveKeyVelocity[3] = { 0.0, ... };
    GetAbsVelocity(vel, angles, moveKeyVelocity);
    moveKeyVelocity[2] = 0.0;

    // Get a direction vector from the movement key velocity.
    // TODO: For a springboard jump, we want to base movement
    // off the normal of the surface instead.
    extraVelocity[0] = moveKeyVelocity[0];
    extraVelocity[1] = moveKeyVelocity[1];
    NormalizeVector(extraVelocity, extraVelocity);

    if ( jumpType != SJT_WallClimb )
    {
        // Apply maximum forward force when we're looking straight ahead, when pitch is 0.
        // This is accomplished using cos(pitch).
        ScaleVector(extraVelocity, GetConVarFloat(jumpType == SJT_LongJump ? cvLongJumpForwardForce : cvSpringboardForwardForce) * Cosine(DegToRad(angles[0])));
    }

    // If this extra velocity would make us too fast on X or Y, clamp it.
    // We don't want to allow players to continually accumulate more and more velocity.
    float axisVelLimit = GetAxialVelocityLimitForJump(jumpType);
    extraVelocity[0] = LimitAxialVelocity(worldVelocity[0], extraVelocity[0], axisVelLimit);
    extraVelocity[1] = LimitAxialVelocity(worldVelocity[1], extraVelocity[1], axisVelLimit);

    // Apply maximum upward force when we're looking directly up,
    // but none at all when we're looking directly down.
    // This means the multiplier is 1 when the pitch is -90,
    // and 0 when the pitch is 90.
    // This is accomplished using sin((pitch/2) + 45).
    // Note that this is modified by which direction keys are currently being
    // held - if we're looking down but holding backwards, it's treated as if we were looking up.

    float pitch = -angles[0];
    if ( vel[0] < 0.0 )
    {
        pitch *= -1.0;
    }

    extraVelocity[2] = GetConVarFloat(cvWallClimbUpwardForce) * Sine(DegToRad((pitch / 2.0) + 45));

    // Combine with existing velocity and apply to client.
    AddVectors(worldVelocity, extraVelocity, worldVelocity);
    TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, worldVelocity);
}

SpecialJumpType ClientCanPerformSpecialJump(int client, const float[3] localVelocity, const float[3] angles)
{
    // If the player is on the ground, we only allow long jumps.
    if ( (GetEntityFlags(client) & FL_ONGROUND) == FL_ONGROUND )
    {
        LogMessage("Can perform long jump");
        return SJT_LongJump;
    }

    float worldVelocity[3] = { 0.0, ... };
    GetAbsVelocity(localVelocity, angles, worldVelocity);

    NormalizeVector(worldVelocity, worldVelocity);
    ScaleVector(worldVelocity, GetConVarFloat(cvWallClimbTraceDist));

    float mins[3] = { 0.0, ... };
    float maxs[3] = { 0.0, ... };
    float origin[3] = { 0.0, ... };
    GetClientBounds(client, mins, maxs);
    GetClientAbsOrigin(client, origin);

    // Squish the bounds a little, just in case the floor or ceiling is rough.
    origin[2] += 16.0;
    mins[2] += 16.0;
    maxs[2] -= 16.0;

    // First of all, perform a trace in the direction of movement.
    float target[3] = { 0.0, ... };
    AddVectors(origin, worldVelocity, target);

    Handle trace = TR_TraceHullFilterEx(origin, target, mins, maxs, MASK_SOLID, TraceFilterIgnoreClient, client);
    bool didHit = TR_DidHit(trace);
    CloseHandle(trace);

    if ( didHit )
    {
        LogMessage("Can perform wall climb");
        return SJT_WallClimb;
    }

    // Also perform a trace for whatever is behind the client.
    float backwards[3] = { 0.0, ... };
    GetAngleVectors(angles, backwards, NULL_VECTOR, NULL_VECTOR);
    NegateVector(backwards);

    // Only use the X and Y components of this vector.
    backwards[2] = 0.0;

    // Only trace backwards if we have a proper backwards direction in X/Y.
    if ( !IsNullVector(backwards) )
    {
        // Calculate the target to trace to.
        NormalizeVector(backwards, backwards);
        ScaleVector(backwards, GetConVarFloat(cvWallClimbTraceDist));
        AddVectors(origin, backwards, target);

        Handle backTrace = TR_TraceHullFilterEx(origin, target, mins, maxs, MASK_SOLID, TraceFilterIgnoreClient, client);
        didHit = TR_DidHit(backTrace);
        CloseHandle(backTrace);

        if ( didHit )
        {
            LogMessage("Can perform springboard");
            return SJT_Springboard;
        }
    }

    LogMessage("Can't perform special jump");
    return SJT_NoJump;
}

static stock float GetAxialVelocityLimitForJump(SpecialJumpType jumpType)
{
    switch ( jumpType )
    {
        case SJT_LongJump:
        {
            return GetConVarFloat(cvLongJumpMaxXYVelocity);
        }

        case SJT_WallClimb:
        {
            return GetConVarFloat(cvWallClimbMaxXYVelocity);
        }

        case SJT_Springboard:
        {
            return GetConVarFloat(cvSpringboardMaxXYVelocity);
        }

        default:
        {
            return 0.0;
        }
    }
}

static stock bool TraceFilterIgnoreClient(int entity, int contentsMask, any data)
{
    return entity != view_as<int>(data);
}

static stock void GetAbsVelocity(const float[3] localVelocity, const float[3] angles, float[3] absVelocity)
{
    // Get 2D vectors from current angles.
    float fwd[3] = { 0.0, ... };
    float right[3] = { 0.0, ... };
    GetAngleVectors(angles, fwd, right, NULL_VECTOR);

    // Apply forward and right speed in both these directions.
    ScaleVector(fwd, localVelocity[0]);
    ScaleVector(right, localVelocity[1]);

    // Add to form a single vector.
    AddVectors(fwd, right, absVelocity);

    // Include Z motion (no conversion required).
    absVelocity[2] = localVelocity[2];
}

static stock void GetClientBounds(int client, float[3] mins, float[3] maxs)
{
    GetEntPropVector(client, Prop_Send, "m_vecMins", mins);
    GetEntPropVector(client, Prop_Send, "m_vecMaxs", maxs);
}

static stock void GetClientAbsVelocity(int client, float[3] velocity)
{
    velocity[0] = GetEntPropFloat(client, Prop_Send, "m_vecVelocity[0]");
    velocity[1] = GetEntPropFloat(client, Prop_Send, "m_vecVelocity[1]");
    velocity[2] = GetEntPropFloat(client, Prop_Send, "m_vecVelocity[2]");
}

static stock float LimitAxialVelocity(float currentVelocity, float velocityToAdd, float limit)
{
    float outVelocity = velocityToAdd;

    if ( FloatAbs(currentVelocity + outVelocity) > limit )
    {
        outVelocity = limit - FloatAbs(currentVelocity);

        if ( outVelocity < 0.0 )
        {
            outVelocity = 0.0;
        }
        else if ( velocityToAdd < 0.0 )
        {
            // If the original velocity on this axis was negative, invert our calculation.
            outVelocity *= -1.0;
        }
    }

    return outVelocity;
}
