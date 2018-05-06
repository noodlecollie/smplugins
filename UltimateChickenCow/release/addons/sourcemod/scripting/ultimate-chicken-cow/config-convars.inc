#if defined _TF2UCC_CONFIG_CONVARS_INC
 #endinput
#endif
#define _TF2UCC_CONFIG_CONVARS_INC

#pragma semicolon 1
#pragma newdecls required

#include "pluginctl/pluginctl.inc"

stock ConVar cvJumpForce = null;

void CreateConfigConVars()
{
    cvJumpForce = PCtl_CreatePrefixedConVar("jump_force",
                                            "550",
                                            "How much forward force to apply to a player when they jump.",
                                            FCVAR_NOTIFY,
                                            true,
                                            0.0,
                                            true,
                                            100000.0);
}

void DestroyConfigConVars()
{
    delete cvJumpForce;
    cvJumpForce = null;
}
