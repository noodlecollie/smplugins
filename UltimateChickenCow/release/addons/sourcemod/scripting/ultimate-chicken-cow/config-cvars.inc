#if defined _TF2UCC_CONFIG_CVARS_INC
 #endinput
#endif
#define _TF2UCC_CONFIG_CVARS_INC

#pragma semicolon 1
#pragma newdecls required

#include "plugininfo.inc"

stock ConVar cvActivePlayerGroupSize = null;
stock ConVar cvActiveBuilderGroupSize = null;

void RegisterConfigCvars()
{
    char maxPlayersString[10];
    FormatEx(maxPlayersString, sizeof(maxPlayersString), "%d", MAXPLAYERS);

    cvActivePlayerGroupSize =
        PCtl_CreatePrefixedConVar("active_player_group_size",
                                  "4",
                                  "Max number of players who are allowed to attempt the puzzle at once. Remaining players are made builders/spectators.",
                                  FCVAR_NOTIFY,
                                  true,
                                  1.0,
                                  true,
                                  view_as<float>(MAXPLAYERS));

    cvActiveBuilderGroupSize =
        PCtl_CreatePrefixedConVar("active_builder_group_size",
                                  maxPlayersString,
                                  "Max number of players who are allowed to place traps. Remaining players are made spectators.",
                                  FCVAR_NOTIFY,
                                  true,
                                  1.0,
                                  true,
                                  view_as<float>(MAXPLAYERS));
}
