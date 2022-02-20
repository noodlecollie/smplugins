#if defined _ARENAROULETTE_MODE_TABLE_INC
 #endinput
#endif

#define _ARENAROULETTE_MODE_TABLE_INC

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include "arena_roulette.inc"
#include "defs.inc"

enum struct ARMode
{
	Handle implementerPlugin;
	ArenaRouletteFwd_CanSelectMode canSelectMode;

	void SetForward(ArenaRoulette_ForwardType fwdType, Function fwdFunction)
	{
		switch ( fwdType )
		{
			case ArenaRouletteFwdType_CanSelectMode:
			{
				this.canSelectMode = view_as<ArenaRouletteFwd_CanSelectMode>(fwdFunction);
			}

			default:
			{
				LogError("ARMode::SetForward: Cannot set forward for unrecognised index %d", view_as<int>(fwdType));
			}
		}
	}
}

stock ARMode GlobalModeTable[MAX_MODES];

stock int FindNextFreeModeTableEntry()
{
	for ( int index = 0; index < MAX_MODES; ++index )
	{
		if ( GlobalModeTable[index].implementerPlugin == INVALID_HANDLE )
		{
			return index;
		}
	}

	return -1;
}
