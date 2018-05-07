#if defined _TF2UCC_CONFIG_CONVARS_INC
 #endinput
#endif
#define _TF2UCC_CONFIG_CONVARS_INC

#pragma semicolon 1
#pragma newdecls required

#include "pluginctl/pluginctl.inc"

stock ConVar cvLongJumpForwardForce = null;
stock ConVar cvWallJumpUpwardForce = null;
stock ConVar cvWallJumpTraceDist = null;
stock ConVar cvLongJumpMinInterval = null;

void CreateConfigConVars()
{
    cvLongJumpForwardForce = PCtl_CreatePrefixedConVar("longjump_forward_force",
                                                       "200",
                                                       "How much forward force to apply to a player when they perform a long jump.",
                                                       FCVAR_NOTIFY | FCVAR_ARCHIVE,
                                                       true,
                                                       0.0,
                                                       true,
                                                       100000.0);

    cvWallJumpUpwardForce = PCtl_CreatePrefixedConVar("walljump_upward_force",
                                                      "500",
                                                      "How much upward forward force to apply to a player when they perform a wall jump.",
                                                      FCVAR_NOTIFY | FCVAR_ARCHIVE,
                                                      true,
                                                      0.0,
                                                      true,
                                                      100000.0);

    cvWallJumpTraceDist = PCtl_CreatePrefixedConVar("walljump_tracedist",
                                                    "4",
                                                    "How far in the direction of motion to trace for collisions when wall jumping.",
                                                    FCVAR_NOTIFY | FCVAR_ARCHIVE,
                                                    true,
                                                    0.1,
                                                    true,
                                                    500.0);

    cvLongJumpMinInterval = PCtl_CreatePrefixedConVar("longjump_mininterval",
                                                      "500",
                                                      "How quickly a client is able to perform consecutive long jumps, in ms.",
                                                      FCVAR_NOTIFY | FCVAR_ARCHIVE,
                                                      true,
                                                      1.0,
                                                      false);
}

void DestroyConfigConVars()
{
    delete cvLongJumpForwardForce;
    cvLongJumpForwardForce = null;

    delete cvWallJumpUpwardForce;
    cvWallJumpUpwardForce = null;

    delete cvWallJumpTraceDist;
    cvWallJumpTraceDist = null;

    delete cvLongJumpMinInterval;
    cvLongJumpMinInterval = null;
}
