#if defined _TF2UCC_CONFIG_CONVARS_INC
 #endinput
#endif
#define _TF2UCC_CONFIG_CONVARS_INC

#pragma semicolon 1
#pragma newdecls required

#include "pluginctl/pluginctl.inc"

stock ConVar cvLongJumpForwardForce = null;
stock ConVar cvWallJumpUpwardForce = null;
stock ConVar cvWallJumpVerticalVelocityBlend = null;
stock ConVar cvWallJumpTraceDist = null;
stock ConVar cvLongJumpMinInterval = null;
stock ConVar cvLongJumpMaxXYVelocity = null;
stock ConVar cvWallJumpMapXYVelocity = null;

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

    cvWallJumpUpwardForce =
        PCtl_CreatePrefixedConVar("walljump_upward_force",
                                  "500",
                                  "How much upward forward force to apply to a player when they perform a wall jump.",
                                  FCVAR_NOTIFY | FCVAR_ARCHIVE,
                                  true,
                                  0.0,
                                  true,
                                  100000.0);

    cvWallJumpVerticalVelocityBlend =
        PCtl_CreatePrefixedConVar("walljump_vertical_velocity_blend",
                                  "0.3",
                                  "How much existing vertical velocity to keep when applying walljump force. 0 means fall velocity is completely overridden.",
                                  FCVAR_NOTIFY | FCVAR_ARCHIVE,
                                  true,
                                  0.0,
                                  true,
                                  1.0);

    cvWallJumpTraceDist =
        PCtl_CreatePrefixedConVar("walljump_tracedist",
                                  "4",
                                  "How far in the direction of motion to trace for collisions when wall jumping.",
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

    cvWallJumpMapXYVelocity =
        PCtl_CreatePrefixedConVar("walljump_max_xy_velocity",
                                  "100",
                                  "Speed limit along the X or Y axis after a wall jump impulse.",
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

    delete cvWallJumpUpwardForce;
    cvWallJumpUpwardForce = null;

    delete cvWallJumpVerticalVelocityBlend;
    cvWallJumpVerticalVelocityBlend = null;

    delete cvWallJumpTraceDist;
    cvWallJumpTraceDist = null;

    delete cvLongJumpMinInterval;
    cvLongJumpMinInterval = null;

    delete cvLongJumpMaxXYVelocity;
    cvLongJumpMaxXYVelocity = null;

    delete cvWallJumpMapXYVelocity;
    cvWallJumpMapXYVelocity = null;
}
