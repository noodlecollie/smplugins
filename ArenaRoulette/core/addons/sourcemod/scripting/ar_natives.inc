#if defined _ARENAROULETTE_NATIVES_INC
 #endinput
#endif

#define _ARENAROULETTE_NATIVES_INC

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include "ar_defs.inc"
#include "arena_roulette.inc"
#include "mode_table.inc"

stock void CreateNatives()
{
	CreateNative("ArenaRoulette_RegisterMode", Native_RegisterMode);
}

stock any Native_RegisterMode(Handle plugin, int numParams)
{
	char modeName[MAX_MODE_NAME_LENGTH] = { '\0' };

	GetPluginInfo(plugin, PlInfo_Name, modeName, sizeof(modeName));

	int entryIndex = ARMode_FindNextFreeModeTableEntry();

	if ( entryIndex < 0 )
	{
		LogError("Could not find free entry in mode table to register mode for plugin %s", modeName);
		return false;
	}

	GlobalModeTable[entryIndex].implementerPlugin = plugin;

	if ( numParams % 2 != 0 )
	{
		LogMessage(
			"WARNING: ArenaRoulette_RegisterMode called by plugin %s with incorrect number of arguments," ...
			"truncating last argument.",
			modeName
		);

		numParams = (numParams / 2) * 2;
	}

	for ( int index = 0; index < numParams; index += 2 )
	{
		int fwdType = GetNativeCell(index);

		if ( fwdType <= view_as<int>(ArenaRouletteFwdType_Invalid) ||
		     fwdType >= view_as<int>(ArenaRouletteFwdType__Max__DoNotUse) )
		{
			LogMessage("WARNING: Skipping unrecognised forward index %d", fwdType);
			continue;
		}

		Function fwdFunc = GetNativeFunction(index + 1);

		GlobalModeTable[entryIndex].SetForward(view_as<ArenaRoulette_ForwardType>(fwdType), fwdFunc);
	}

	return true;
}
