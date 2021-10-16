#if defined _TF2UCC_CONFIG_CONVARS_INC
 #endinput
#endif
#define _TF2UCC_CONFIG_CONVARS_INC

#pragma semicolon 1
#pragma newdecls required

#include "pluginctl/pluginctl.inc"

stock ConVar cvLongJumpForwardForce = null;
stock ConVar cvWallClimbUpwardForce = null;
stock ConVar cvSpringboardForwardForce = null;
stock ConVar cvWallClimbVerticalVelocityBlend = null;
stock ConVar cvWallClimbTraceDist = null;
stock ConVar cvLongJumpMinInterval = null;
stock ConVar cvLongJumpMaxXYVelocity = null;
stock ConVar cvWallClimbMaxXYVelocity = null;
stock ConVar cvSpringboardMaxXYVelocity = null;

void CreateConfigConVars()
{
    cvLongJumpForwardForce =
        PCtl_CreatePrefixedConVar("longjump_forward_force",
                                  "200",
                                  "How much forward force to apply to a player when they perform a long jump.",
                                  FCVAR_NOTIFY | FCVAR_ARCHIVE,
                                  true,
                                  0.0,
                                  true,
                                  100000.0);

    cvWallClimbUpwardForce =
        PCtl_CreatePrefixedConVar("wallclimb_upward_force",
                                  "500",
                                  "How much upward forward force to apply to a player when they perform a wall climbing jump.",
                                  FCVAR_NOTIFY | FCVAR_ARCHIVE,
                                  true,
                                  0.0,
                                  true,
                                  100000.0);

    cvSpringboardForwardForce =
        PCtl_CreatePrefixedConVar("springboard_forward_force",
                                  "300",
                                  "How much forward force to apply to a player when they perform a wall springboard jump.",
                                  FCVAR_NOTIFY | FCVAR_ARCHIVE,
                                  true,
                                  0.0,
                                  true,
                                  100000.0);

    cvWallClimbVerticalVelocityBlend =
        PCtl_CreatePrefixedConVar("wallclimb_vertical_velocity_blend",
                                  "0.3",
                                  "How much existing vertical velocity to keep when applying wall climb force. 0 means fall velocity is completely overridden.",
                                  FCVAR_NOTIFY | FCVAR_ARCHIVE,
                                  true,
                                  0.0,
                                  true,
                                  1.0);

    cvWallClimbTraceDist =
        PCtl_CreatePrefixedConVar("wallclimb_tracedist",
                                  "4",
                                  "How far in the direction of motion to trace for collisions when wall climbing.",
                                  FCVAR_NOTIFY | FCVAR_ARCHIVE,
                                  true,
                                  0.1,
                                  true,
                                  500.0);

    cvLongJumpMinInterval =
        PCtl_CreatePrefixedConVar("longjump_mininterval",
                                  "500",
                                  "How quickly a client is able to perform consecutive long jumps, in ms.",
                                  FCVAR_NOTIFY | FCVAR_ARCHIVE,
                                  true,
                                  1.0,
                                  false);

    cvLongJumpMaxXYVelocity =
        PCtl_CreatePrefixedConVar("longjump_max_xy_velocity",
                                  "450",
                                  "Speed limit along the X or Y axis after a long jump impulse.",
                                  FCVAR_NOTIFY | FCVAR_ARCHIVE,
                                  true,
                                  0.0,
                                  true,
                                  10000.0);

    cvWallClimbMaxXYVelocity =
        PCtl_CreatePrefixedConVar("wallclimb_max_xy_velocity",
                                  "100",
                                  "Speed limit along the X or Y axis after a wall climb impulse.",
                                  FCVAR_NOTIFY | FCVAR_ARCHIVE,
                                  true,
                                  0.0,
                                  true,
                                  10000.0);

    cvSpringboardMaxXYVelocity =
        PCtl_CreatePrefixedConVar("springboard_max_xy_velocity",
                                  "450",
                                  "Speed limit along the X or Y axis after a wall springboard impulse.",
                                  FCVAR_NOTIFY | FCVAR_ARCHIVE,
                                  true,
                                  0.0,
                                  true,
                                  10000.0);
}

void DestroyConfigConVars()
{
    delete cvLongJumpForwardForce;
    cvLongJumpForwardForce = null;

    delete cvWallClimbUpwardForce;
    cvWallClimbUpwardForce = null;

    delete cvSpringboardForwardForce;
    cvSpringboardForwardForce = null;

    delete cvWallClimbVerticalVelocityBlend;
    cvWallClimbVerticalVelocityBlend = null;

    delete cvWallClimbTraceDist;
    cvWallClimbTraceDist = null;

    delete cvLongJumpMinInterval;
    cvLongJumpMinInterval = null;

    delete cvLongJumpMaxXYVelocity;
    cvLongJumpMaxXYVelocity = null;

    delete cvWallClimbMaxXYVelocity;
    cvWallClimbMaxXYVelocity = null;

    delete cvSpringboardMaxXYVelocity;
    cvSpringboardMaxXYVelocity = null;
}
