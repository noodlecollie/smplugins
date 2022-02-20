#if defined _ARENAROULETTE_MODE_TABLE_INC
 #endinput
#endif

#define _ARENAROULETTE_MODE_TABLE_INC

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include "arena_roulette.inc"
#include "ar_defs.inc"

enum struct ARMode
{
	Handle implementerPlugin;
	int numTimesPlayed;

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

stock int ARMode_FindNextFreeModeTableEntry()
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

stock void ARMode_ClearAllPlayCounters()
{
	for ( int index = 0; index < MAX_MODES; ++index )
	{
		GlobalModeTable[index].numTimesPlayed = 0;
	}
}

stock int ARMode_ChooseLeastPlayedMode()
{
	// Find number of modes with least number of plays
	// Put all these modes into an array (of MAX_MODES)
	// Choose a random index into this array
}
