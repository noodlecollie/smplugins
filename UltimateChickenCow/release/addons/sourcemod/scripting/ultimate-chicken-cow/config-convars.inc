#if defined _TF2UCC_CONFIG_CONVARS_INC
 #endinput
#endif
#define _TF2UCC_CONFIG_CONVARS_INC

#pragma semicolon 1
#pragma newdecls required

#include "pluginctl/pluginctl.inc"

stock ConVar cvJumpForce = null;
stock ConVar cvWallJumpTraceDist = null;

void CreateConfigConVars()
{
    cvJumpForce = PCtl_CreatePrefixedConVar("jump_force",
                                            "550",
                                            "How much forward force to apply to a player when they jump.",
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
}

void DestroyConfigConVars()
{
    delete cvJumpForce;
    cvJumpForce = null;

    delete cvWallJumpTraceDist;
    cvWallJumpTraceDist = null;
}
