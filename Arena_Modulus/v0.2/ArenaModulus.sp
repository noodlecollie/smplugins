/*	===========================================================================
	Arena Modulus Main Handler - [X6] Herbius - 31/08/11 - http://x6herbius.com
	===========================================================================
	
	This is the main handler plugin for the Arena Modulus game mode. This
	plugin handles the rest of the modes, which must be created as separate
	plugins and include the forward functions from this handler.
	
	Any files (translations, configs, etc.) to do with this handler should be
	named "ArenaModulus". Folders should be named "arena_modulus". This is for
	general neatness and to tell the two apart.
*/

#pragma semicolon 1

// ================================
// =========== Includes ===========
// ================================

#include <sourcemod>		// Main SM functionality.
#include <sdktools>		// SDK Tools.

// ================================
// =========== Defines ============
// ================================

#define MAX_MODES			32		// The hard-coded maximum number of custom modes the handler will support.
#define FL_INDEX_LIMIT	31.0
#define PLAY_LIMIT		9999	// If a mode reaches this limit, all mode counts will wrap back down to zero.
#define MAX_PLAY_LIMIT	10000	// Arbitrary high number in order to check the mode that has been played the least number of times.
#define UNLOADED			10010	// Higher than MAX_PLAY_LIMIT; if a mode is unloaded, its tracker count will be set to this value.

// ========== Debug Flags =========
// Different areas of the code can be enabled or disabled for debugging purposes.
// Setting the main DEBUG constant to different flags will allow for different debugging functionality.

#define DEBUGFLAG_GENERAL			1	// General debugging.
#define DEBUGFLAG_MAPMODE			2	// Logging when the map is checked for Arena logic.
#define DEBUGFLAG_REGISTERMODES	4	// Logging when modes register their info into the handler.
#define DEBUGFLAG_ROUNDSTART		8	// Logging RoundStart events.
#define DEBUGFLAG_ROUNDEND			16	// Logging RoundEnd events.
#define DEBUGFLAG_BESTMODE			32	// Logging the choosing of modes.
#define DEBUGFLAG_DOUBLELOADING	64	// Investigating whether InitialiseMode gets run twice on plugin load.
#define DEBUGFLAG_FORWARDS			128	// Logging forward activity.

#define DEBUG						255

// ========= State Flags ==========
// State flags control which functions and hooks will occur in the plugin.

#define HIGHEST_STATE				8	// Convenience define. This should be the same as the highest state flag.

#define STATE_DISABLED				8	// Plugin is disabled. No activity will occur apart from the checking of the disabled ConVar.
#define STATE_NOT_ARENA				4	// No activity should occur because the map is not an arena map. Set on PluginStart and MapStart.
#define STATE_NOT_IN_ROUND			2	// A round is not being played. No custom mode events will run. Set on RoundWin/MapEnd, cleared on RoundStart.
#define STATE_SEARCHING_FOR_MODES	1	// Handler is broadcasting a search for modes.

// ========= Cleanup Modes ==========
#define CLEANUP_ROUNDSTART		0
#define CLEANUP_ROUNDWIN		1
#define CLEANUP_MAPSTART		2
#define CLEANUP_MAPEND			3
#define CLEANUP_PLAYERSPAWN	4

// ======== Team Integers =========
#define TEAM_INVALID			-1
#define TEAM_UNASSIGNED		0
#define TEAM_SPECTATOR		1
#define TEAM_RED				2
#define TEAM_BLUE				3

// ========== Variables ===========
new g_PluginState;											// Global state of the plugin.

// Mode data table variables:
new Mode_Count = -1;											// Holds the number of currently registered modes, but begins at -1 to provide an array index.
new String:Mode_Name[MAX_MODES][65];						// Holds the names of the resistered modes.
new String:Mode_Tagline[MAX_MODES][65];					// Holds the taglines of the registered modes.
new String:Mode_Desc[MAX_MODES][129];						// Holds the descriptions of the registered modes.
new Mode_MinRed[MAX_MODES];								// Holds the minimum number of players on Red for the mode to activate.
new Mode_MinBlue[MAX_MODES];								// Holds the minimum number of players on Blue for the mode to activate.
new Mode_TeamIndependent[MAX_MODES];						// If 1, the mode's minimum player counts are team independent.
new Mode_Tracker[MAX_MODES] = {MAX_PLAY_LIMIT, ...};	// Tracks the number of times a mode has been played. Reset on MapStart, MapEnd.
new CurrentMode = -1;										// ID of the mode chosen to be played. Set on RoundStart, reset on RoundEnd, RoundStalemate, MapEnd.
new bool:PluginStartInit = false;

// ======== ConVar Handles ========
new Handle:cv_PluginEnabled = INVALID_HANDLE;	// Enables or disables the plugin. Changing this restarts the current map.
new Handle:cv_ForceMode = INVALID_HANDLE;		// Set this ConVar to the index (beginning at 0) of a custom mode to force it to play. -1 ignores.

// ======== HUD Sync Handles ========
new Handle:hs_RoundInfo = INVALID_HANDLE;		// For displaying information about a round when it is chosen.

// ======== Forward Handles =======
new Handle:fw_SearchForModes = INVALID_HANDLE;	// Forward that calls for all modes to send their info.
new Handle:fw_RoundStart = INVALID_HANDLE;		// Forward called when the mode should perform any RoundStart tasks.
new Handle:fw_RoundEnd = INVALID_HANDLE;			// Forward called when the mode should perform any RoundEnd tasks.
new Handle:fw_MapEnd = INVALID_HANDLE;			// Forward called when the mode should perform any MapEnd tasks.
new Handle:fw_HLoad = INVALID_HANDLE;				// Forward called when the main handler loads.
new Handle:fw_HUnload = INVALID_HANDLE;			// Forward called if the main handler unloads.

// ========= Plugin Info ==========
#define PLUGIN_NAME			"Arena Modulus: Main Handler"
#define PLUGIN_AUTHOR		"[X6] Herbius"
#define PLUGIN_DESCRIPTION	"Play a variety of arena mini-modes."
#define PLUGIN_VERSION		"1.0.0.0"
#define PLUGIN_URL			"http://x6herbius.com/"

public Plugin:myinfo =
{
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = PLUGIN_URL
};

// ================================
// == Startup and Initialisation ==
// ================================

/*	Registers natives and forwards.	*/
public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	fw_SearchForModes =	CreateGlobalForward("ArenaMod_SearchForModes",	ET_Ignore);
	fw_RoundStart =		CreateGlobalForward("ArenaMod_RoundStart",		ET_Event, Param_Cell);
	fw_RoundEnd =		CreateGlobalForward("ArenaMod_RoundEnd",		ET_Event, Param_Cell, Param_Cell);
	fw_MapEnd =			CreateGlobalForward("ArenaMod_MapEnd",			ET_Ignore);
	fw_HLoad =			CreateGlobalForward("ArenaMod_HandlerLoad",	ET_Ignore);
	fw_HUnload =			CreateGlobalForward("ArenaMod_HandlerUnload",	ET_Ignore);
	
	CreateNative("ArenaMod_RegisterMode", Native_RegisterMode);
	CreateNative("ArenaMod_CancelCurrentRound", Native_CancelCurrentRound);
	CreateNative("ArenaMod_UnloadMode", Native_UnloadMode);
	
	RegPluginLibrary("ArenaModulus");
	return APLRes_Success;
}

public OnPluginStart()
{
	LogMessage("===== Arena Modulus Main Handler, Version: %s =====", PLUGIN_VERSION);
	LoadTranslations("arena_modulus/ArenaModulus.phrases");
	LoadTranslations("common.phrases");
	AutoExecConfig(true, "ArenaModulus", "sourcemod/arena_modulus");
	
	CreateConVar("arenamod_version", PLUGIN_VERSION, "Plugin version.", FCVAR_NOTIFY);
	
	cv_PluginEnabled  = CreateConVar("arenamod_enabled",
												"1",
												"Enables or disables the plugin. Changing this restarts the current map",
												FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
												true,
												0.0,
												true,
												1.0);
												
	cv_ForceMode = CreateConVar("arenamod_forcemode",
												"-1",
												"Set this ConVar to the index (beginning at 0) of a custom mode to force it to play. -1 ignores.",
												FCVAR_PLUGIN | FCVAR_NOTIFY,
												true,
												-1.0,
												true,
												FL_INDEX_LIMIT);
	
	#if DEBUG > 0
	RegConsoleCmd("arenamod_showflags",			Cmd_ShowFlags,				"Outputs the plugin's state flags to the client's console.");
	RegConsoleCmd("arenamod_showmodeinfo",		Cmd_ShowModeInfo,			"Outputs the plugin's mode information to the console, or info for a specific mode if an ID is given.");
	RegConsoleCmd("arenamod_showcurrentmode",	Cmd_ShowCurrentMode,		"Outputs the current mode info.");
	#endif
	
	RegConsoleCmd("am_currentmode",				Cmd_User_ShowCurrentMode,	"Displays the current mode info.");	// Used for clients in-game as opposed to a debug command.
	
	// Hooks:
	HookConVarChange(cv_PluginEnabled,	CvarChange);
	
	HookEventEx("teamplay_round_start",		Event_ArenaRoundStart,	EventHookMode_Post);
	HookEventEx("teamplay_round_win",		Event_RoundWin,			EventHookMode_Post);
	HookEventEx("teamplay_round_stalemate",	Event_RoundStalemate,	EventHookMode_Post);
	//HookEventEx("arena_round_start",			Event_ArenaRoundStart,	EventHookMode_Pre);
}

public OnAllPluginsLoaded()
{
	// Only continue on from this point if the round is already being played.
	if ( !IsServerProcessing() ) return;
	
	// Restart the current round.
	RoundWin(TEAM_UNASSIGNED);
	
	#if (DEBUG & DEBUGFLAG_GENERAL) == DEBUGFLAG_GENERAL
	LogMessage("[AM] Calling load notify forward...");
	#endif
	
	// Notify custom modes that we have loaded.
	Call_StartForward(fw_HLoad);	// Notify custom modes that we are loading.
	Call_Finish();
	
	// Call all the functions that are common to both MapStart and PluginStart.
	#if (DEBUG & DEBUGFLAG_DOUBLELOADING) == DEBUGFLAG_DOUBLELOADING
	LogMessage("Double load check: InitialiseMode being called from OnPluginStart.");
	#endif
	InitialiseMode();
	
	PluginStartInit = true;
}

public OnPluginEnd()
{
	Call_StartForward(fw_HUnload);	// Notify custom modes that we are unloading.
	Call_Finish();
}

/*	Holds all our plugin startup admin.
	Functions here are common to both MapStart and PluginStart.	*/
InitialiseMode()
{
	g_PluginState |= STATE_NOT_IN_ROUND;
	
	// If the map is not an Arena map, set our flag.
	if ( !IsArena() ) g_PluginState |= STATE_NOT_ARENA;
	else g_PluginState &= ~STATE_NOT_ARENA;
	
	// Only continue if it is clear to do so.
	if ( (g_PluginState & STATE_NOT_ARENA) == STATE_NOT_ARENA || (g_PluginState & STATE_DISABLED) == STATE_DISABLED ) return;
	
	#if (DEBUG & DEBUGFLAG_FORWARDS) == DEBUGFLAG_FORWARDS
	LogMessage("[AM] Running SearchForModes forward...");
	#endif
	
	// Search for modes.
	g_PluginState |= STATE_SEARCHING_FOR_MODES;
	Call_StartForward(fw_SearchForModes);
	
		// Modes will register their presence here.
	
	Call_Finish();
	g_PluginState &= ~STATE_SEARCHING_FOR_MODES;
	
	#if (DEBUG & DEBUGFLAG_FORWARDS) == DEBUGFLAG_FORWARDS
	LogMessage("[AM] SearchForModes forward is complete.");
	#endif
}

/*	Returns true if an arena logic entity can be found, false otherwise.	*/
stock bool:IsArena()
{
	#if (DEBUG & DEBUGFLAG_MAPMODE) == DEBUGFLAG_MAPMODE
	decl String:MapName[65];
	GetCurrentMap(MapName, sizeof(MapName));
	LogMessage("Checking whether the current map %s is an Arena map...", MapName);
	#endif
	
	if ( FindEntityByClassname(-1, "tf_logic_arena") != -1 )
	{
		#if (DEBUG & DEBUGFLAG_MAPMODE) == DEBUGFLAG_MAPMODE
		LogMessage("%s is an Arena map, returning true.", MapName);
		#endif
		
		return true;
	}
	else
	{
		#if (DEBUG & DEBUGFLAG_MAPMODE) == DEBUGFLAG_MAPMODE
		LogMessage("%s is not an Arena map, returning false.", MapName);
		#endif
		
		return false;
	}
}

/*	Cleans up depending on the mode.	*/
stock Cleanup( mode )
{
	switch (mode)
	{
		/*case CLEANUP_ROUNDSTART:	// TODO
		{
		
		}
		
		case CLEANUP_ROUNDWIN:	// TODO
		{
		
		}*/
		
		case CLEANUP_MAPSTART:
		{
			if ( hs_RoundInfo == INVALID_HANDLE )
			{
				hs_RoundInfo = CreateHudSynchronizer();
			}
		}
		
		case CLEANUP_MAPEND:	
		{
			// Clear out global variables;
			new Zero[MAX_MODES];
			Mode_MinRed = Zero;
			Mode_MinBlue = Zero;
			Mode_TeamIndependent = Zero;
			
			new Invalid[MAX_MODES] = {MAX_PLAY_LIMIT, ...};
			Mode_Tracker = Invalid;
			
			for ( new i = 0; i < MAX_MODES; i++ )
			{
				Mode_Name[i][0] = '\0';
				Mode_Tagline[i][0] = '\0';
				Mode_Desc[i][0] = '\0';
			}
			
			Mode_Count = -1;
			CurrentMode = -1;
			
			if ( hs_RoundInfo != INVALID_HANDLE )
			{
				CloseHandle(hs_RoundInfo);
			}
			
			PluginStartInit = false;
		}
	}
}

stock RoundWin( team = 0 )
{
	new ent = FindEntityByClassname2(-1, "team_control_point_master");
	
	if ( ent == -1 )
	{
		ent = CreateEntityByName("team_control_point_master");
		DispatchSpawn(ent);
		AcceptEntityInput(ent, "Enable");
	}
	
	SetVariantInt(team);
	AcceptEntityInput(ent, "SetWinner");
}

stock FindEntityByClassname2(startEnt, const String:classname[])
{
	// If startEnt isn't valid, shift it back to the nearest valid one.
	while (startEnt > -1 && !IsValidEntity(startEnt)) startEnt--;
	return FindEntityByClassname(startEnt, classname);
}

// ================================
// ====== Enabling/Disabling ======
// ================================

/*	Checks which ConVar has changed and does the relevant things.	*/
public CvarChange( Handle:convar, const String:oldValue[], const String:newValue[] )
{
	// If the enabled/disabled convar has changed, run PluginStateChanged
	if ( convar == cv_PluginEnabled ) PluginEnabledStateChanged(GetConVarBool(cv_PluginEnabled));
}

/*	Sets the enabled/disabled state of the plugin and restarts the map.
	Passing true enables, false disables.	*/
stock PluginEnabledStateChanged(bool:b_state)
{
	if ( b_state )
	{
		g_PluginState &= ~STATE_DISABLED;	// Clear the disabled flag.
	}
	else
	{
		g_PluginState |= STATE_DISABLED;	// Set the disabled flag.
	}
	
	// Get the current map name
	decl String:mapname[64];
	GetCurrentMap(mapname, sizeof(mapname));
	LogMessage("[AM] Plugin state changed. Restarting map (%s)...", mapname);
	
	// Restart the map	
	ForceChangeLevel(mapname, "Arena Modulus enabled state changed, requires map restart.");
}

/*
public Action:OnGetGameDescription(String:gameDesc[64])
{
	if ( (g_PluginState & STATE_DISABLED) != STATE_DISABLED )
	{
		Format(gameDesc, sizeof(gameDesc), "%s v%s", PLUGIN_NAME, PLUGIN_VERSION);
		return Plugin_Changed;
	}
	
	else return Plugin_Continue;
}
*/

// ================================
// ============ Hooks =============
// ================================

public OnMapStart()
{
	// Call all the functions that are common to both MapStart and PluginStart.
	
	if ( PluginStartInit ) return;
	
	#if (DEBUG & DEBUGFLAG_DOUBLELOADING) == DEBUGFLAG_DOUBLELOADING
	LogMessage("Double load check: InitialiseMode being called from OnMapStart.");
	#endif
	
	InitialiseMode();
}

public OnMapEnd()
{
	g_PluginState |= STATE_NOT_IN_ROUND;
	
	if ( (g_PluginState & STATE_NOT_ARENA) != STATE_NOT_ARENA && (g_PluginState & STATE_DISABLED) != STATE_DISABLED )
	{
		// Call MapEnd to clean up all modes.
		Call_StartForward(fw_MapEnd);
		Call_Finish();
	}
	
	Cleanup(CLEANUP_MAPEND);
}


/*public Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	g_PluginState &= ~STATE_NOT_IN_ROUND;
}*/

public Event_ArenaRoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	// Only continue if it is clear to do so.
	if ( (g_PluginState & STATE_NOT_ARENA) == STATE_NOT_ARENA || (g_PluginState & STATE_DISABLED) == STATE_DISABLED ) return;
	
	// This hook is called when all players spawn at the beginning of an Arena round (not when the round itself properly starts).
	// Players will respawn without dying if classes are changed, etc. This is where we need to do mode choice admin.
	// Set up a timer to choose the mode after 5 seconds.
	
	CreateTimer(5.0, DoRoundAdmin);
}

public Action:DoRoundAdmin(Handle:timer)
{
	RoundAdmin();
}

RoundAdmin()
{
	CurrentMode = ChooseBestMode2();
	
	new Action:RoundStartResult;
	
	#if (DEBUG & DEBUGFLAG_FORWARDS) == DEBUGFLAG_FORWARDS
	LogMessage("Running RoundStart forward...");
	#endif
	
	// Call RoundStart to initialise the chosen mode.
	Call_StartForward(fw_RoundStart);
	
	// Broadcast the chosen mode's ID.
	Call_PushCell(CurrentMode);
	
	// Make a note of our return value.
	Call_Finish(RoundStartResult);
	
	#if (DEBUG & DEBUGFLAG_FORWARDS) == DEBUGFLAG_FORWARDS
	LogMessage("RoundStart forward is complete.");
	#endif
	
	if ( CurrentMode > -1 && RoundStartResult == Plugin_Stop )
	{
		LogMessage("Mode %s (ID %d) failed to execute RoundStart properly (reported return value %d).", Mode_Name[CurrentMode], CurrentMode, RoundStartResult);
		return;
	}
	
	// Print to the HUD.
	SetHudTextParams(-1.0, -1.0,
						3.0,
						255, 253, 163, 255,
						0);
	
	decl String:RoundInfo[140];
	
	if ( CurrentMode > -1 && CurrentMode < MAX_MODES )
	{
		if ( Mode_Tagline[CurrentMode][0] == '\0' ) Format(RoundInfo, sizeof(RoundInfo), "%s", Mode_Name[CurrentMode]);
		else Format(RoundInfo, sizeof(RoundInfo), "%s \n %s", Mode_Name[CurrentMode], Mode_Tagline[CurrentMode]);
	
		// Display the mode info.
		if ( hs_RoundInfo != INVALID_HANDLE )
		{
			for (new client = 1; client <= MaxClients; client++)
			{
				if ( IsClientInGame(client) )
				{
					if ( GetClientTeam(client) == TEAM_RED || GetClientTeam(client) == TEAM_BLUE )
					{
						ShowSyncHudText(client, hs_RoundInfo, RoundInfo);
					}
				}
			}
		}
	}
}

/*	Randomises the contents of a single-dimensional array.	*/
/*RandomiseArray(Target[], size)
{
	// Copy our target array.
	new Buffer[size];
	
	for ( new n = 0; n < size; n++ )
	{
		Buffer[n] = Target[n];
	}
	
	// Make a note of how much data is in the buffer
	new data = size;
	
	// While we still have data to copy:
	for ( new i = 0; i < size; i++ )
	{
		// Pick a random integer between 0 and data-1.
		new index = GetRandomInt(0, data-1);
		
		// Copy the data from this index in the buffer.
		Target[i] = Buffer[index];
		
		// Shift all the buffer data in an index higher than this down one index.
		for ( new j = index+1; j < data; j++ )
		{
			// Move the data from j into j-1.
			Buffer[j-1] = Buffer[j];
		}
		
		// Decrease our buffer data count by 1.
		data--;
	}
	
	// Target will now contain randomised data.
}*/

public Event_RoundWin(Handle:event, const String:name[], bool:dontBroadcast)
{
	g_PluginState |= STATE_NOT_IN_ROUND;
	
	// Only continue if it is clear to do so.
	if ( (g_PluginState & STATE_NOT_ARENA) == STATE_NOT_ARENA || (g_PluginState & STATE_DISABLED) == STATE_DISABLED ) return;
	
	new winning_team = GetEventInt(event, "team");
	
	// Call our RoundEnd function that will deal with tasks that are common to both RoundWin and RoundStalemate.
	Event_RoundEnd(winning_team);
}

public Event_RoundStalemate(Handle:event, const String:name[], bool:dontBroadcast)
{
	g_PluginState |= STATE_NOT_IN_ROUND;
	
	// Only continue if it is clear to do so.
	if ( (g_PluginState & STATE_NOT_ARENA) == STATE_NOT_ARENA || (g_PluginState & STATE_DISABLED) == STATE_DISABLED ) return;
	
	// Call our RoundEnd function that will deal with tasks that are common to both RoundWin and RoundStalemate.
	Event_RoundEnd(TEAM_UNASSIGNED);
}

/*	Localises the tasks common to both RoundWin and RoundStalemate.	*/
Event_RoundEnd(winning_team)
{	
	new Action:RoundEndResult;
	
	// Call RoundEnd to end the current mode.
	Call_StartForward(fw_RoundEnd);
	
	// Broadcast the mode's ID.
	Call_PushCell(CurrentMode);
	
	// Broadcast the team that won.
	Call_PushCell(winning_team);
	
	// Make a note of our return value.
	Call_Finish(RoundEndResult);
	
	// Increase the play count for the mode.
	// If by chance we happen to have reached MAX_PLAY_LIMIT, reset all mode counts to zero and then increment.
	// If this somehow ever reaches the max limit, I'll take a compass and carve "Fancy that!" on the side of my cock.
	// (See Tim Minchin.)
	
	// Check that the mode ID is not the one we just unloaded.
	if ( CurrentMode > -1 && CurrentMode <= Mode_Count && Mode_Tracker[CurrentMode]+1 >= PLAY_LIMIT && Mode_Tracker[CurrentMode] < UNLOADED )
	{
		for ( new i = 0; i <= Mode_Count; i++ )
		{
			Mode_Tracker[i] = 0;
		}
	}
	
	if ( CurrentMode > -1 && CurrentMode <= Mode_Count ) Mode_Tracker[CurrentMode]++;
	
	if ( CurrentMode > -1 && RoundEndResult == Plugin_Stop )
	{
		LogMessage("Mode %s (ID %d) failed to execute RoundEnd properly (reported return value %d).", Mode_Name[CurrentMode], CurrentMode, RoundEndResult);
	}
}

// ================================
// ======= Output Commands ========
// ================================

/*	Outputs the plugin's state flags to the client's console.	*/
public Action:Cmd_ShowFlags(client, args)
{
	if ( client < 0 ) return Plugin_Handled;
	if ( client > 0 && client <= MaxClients && !IsClientConnected(client) ) return Plugin_Handled;
	
	PrintToConsole(client, "Total flag value: %d", g_PluginState);
	
	if ( g_PluginState < 1 )
	{
		PrintToConsole(client, "No flags are set.");
		
		return Plugin_Handled;
	}
	
	for ( new i = 1; i <= HIGHEST_STATE; i = i*2 )
	{
		if ( (g_PluginState & i) == i ) PrintToConsole(client, "Flag %d is set.", i);
		else PrintToConsole(client, "Flag %d is not set.", i);
	}
	
	return Plugin_Handled;
}

/*	Outputs the values of the global variables.
	If a value is specified, outputs just the information for this array index.	*/
public Action:Cmd_ShowModeInfo(client, args)
{
	if ( client < 0 ) return Plugin_Handled;
	if ( client > 0 && client <= MaxClients && !IsClientConnected(client) ) return Plugin_Handled;
	
	PrintToConsole(client, "Currently registered modes: %d.", Mode_Count+1);
	
	decl String:QueueValue[32];
	
	// If no other arguments, output all information.
	if ( GetCmdArgs() <= 0 )
	{
		for ( new i = 0; i < MAX_MODES; i++ )
		{
			switch (Mode_Tracker[i])
			{
				case PLAY_LIMIT: 		QueueValue = "PLAY_LIMIT";
				case MAX_PLAY_LIMIT:	QueueValue = "MAX_PLAY_LIMIT";
				case UNLOADED:			QueueValue = "UNLOADED";
				default:				IntToString(Mode_Tracker[i], QueueValue, sizeof(QueueValue));
			}
			
			PrintToConsole(client, "Index: %d\nName: %s; %s; Description: %s\nMin Red: %d, Blue: %d, Independent: %d, Queue value: %s.", i, Mode_Name[i], Mode_Tagline[i], Mode_Desc[i], Mode_MinRed[i], Mode_MinBlue[i], Mode_TeamIndependent[i], QueueValue);
			
			/*PrintToConsole(client, "Index: %d | Name: %s; %s.", i, Mode_Name[i], Mode_Tagline[i]);
			PrintToConsole(client, "Description: %s", Mode_Desc[i]);
			PrintToConsole(client, "Min Red: %d, Blue: %d, Independent: %d, Queue value: %s.", Mode_MinRed[i], Mode_MinBlue[i], Mode_TeamIndependent[i], QueueValue);*/
		}
	}
	else
	{
		new String:sIndex[8];
		GetCmdArg(1, sIndex, sizeof(sIndex));
		new Index = StringToInt(sIndex, sizeof(sIndex));
		
		if ( Index < 0 || Index >= MAX_MODES )
		{
			PrintToConsole(client, "Mode index number %d is out of range (must be between 0 and %d inclusive).", Index, MAX_MODES-1);
		}
		else
		{
			switch (Mode_Tracker[Index])
			{
				case PLAY_LIMIT: 		QueueValue = "PLAY_LIMIT";
				case MAX_PLAY_LIMIT:	QueueValue = "MAX_PLAY_LIMIT";
				case UNLOADED:			QueueValue = "UNLOADED";
				default:				IntToString(Mode_Tracker[Index], QueueValue, sizeof(QueueValue));
			}
			
			PrintToConsole(client, "Index: %d\nName: %s; %s; Description: %s\nMin Red: %d, Blue: %d, Independent: %d, Queue value: %s.", Index, Mode_Name[Index], Mode_Tagline[Index], Mode_Desc[Index], Mode_MinRed[Index], Mode_MinBlue[Index], Mode_TeamIndependent[Index], QueueValue);
		}
	}
	
	return Plugin_Handled;
}

/*	Outputs current mode info.	*/
public Action:Cmd_ShowCurrentMode(client, args)
{
	if ( client < 0 ) return Plugin_Handled;
	if ( client > 0 && client <= MaxClients && !IsClientConnected(client) ) return Plugin_Handled;
	
	if ( CurrentMode < 0 ) PrintToConsole(client, "CurrentMode is %d, normal Arena round is running.", CurrentMode);
	else PrintToConsole(client, "Current mode: ID %d; Name: %s.", CurrentMode, Mode_Name[CurrentMode]);
	
	return Plugin_Handled;
}

/*	Outputs current mode info.	*/
public Action:Cmd_User_ShowCurrentMode(client, args)
{
	if ( client < 1 ) return Plugin_Handled;
	if ( client > 0 && client <= MaxClients && !IsClientConnected(client) ) return Plugin_Handled;
	
	if ( CurrentMode < 0 || CurrentMode >= MAX_MODES )
	{
		PrintToChat(client, "%T", "am_no_current_mode", client);
		return Plugin_Handled;
	}
	
	new Handle:Panel = CreatePanel();
	
	SetPanelTitle(Panel, Mode_Name[CurrentMode]);
	DrawPanelText(Panel, Mode_Tagline[CurrentMode]);
	
	new String:Buffer[129];
	Format(Buffer, sizeof(Buffer), "%T", "am_no_description", LANG_SERVER);
	
	if ( StrEqual(Mode_Desc[CurrentMode], Buffer) )
	{
		DrawPanelText(Panel, Mode_Desc[CurrentMode]);
	}
	else
	{
		Format(Buffer, sizeof(Buffer), "%T", "am_description", client);
		DrawPanelItem(Panel, Buffer);
	}
	
	Format(Buffer, sizeof(Buffer), "%T", "Exit", client);
	DrawPanelItem(Panel, Buffer);
	
	SendPanelToClient(Panel, client, Handler_ModeInfo, 20);
	
	CloseHandle(Panel);
	
	return Plugin_Handled;
}

public Handler_ModeInfo(Handle:menu, MenuAction:action, param1, param2)
{
	if (action == MenuAction_Select)
	{
		if ( param2 == 1 )	// Show description
		{
			// By the time this handler is called the mode that was playing beforehand could have finished, so check the details again.
			if ( CurrentMode < 0 || CurrentMode >= MAX_MODES ) return;
			
			new Handle:panel = CreatePanel();
			SetPanelTitle(panel, Mode_Name[CurrentMode]);
			
			DrawPanelText(panel, Mode_Desc[CurrentMode]);
			
			decl String:Buffer[65];
			Format(Buffer, sizeof(Buffer), "%T", "Exit", param1);
			DrawPanelItem(panel, Buffer);
	
			SendPanelToClient(panel, param1, Handler_ModeInfoDesc, 20);
			
			CloseHandle(panel);
		}
	}
}

public Handler_ModeInfoDesc(Handle:menu, MenuAction:action, param1, param2)
{
	if (action == MenuAction_Cancel) return;
}

// ================================
// ======= Custom Functions =======
// ================================

/*	Chooses the best mode to play, or -1 (normal round) on error.	*/
/*stock ChooseBestMode()
{
	// Return -1 if any of the following is true:
	if ( Mode_Count < 0 || Mode_Count >= MAX_MODES )
	{
		LogMessage("ChooseBestMode: Mode_Count %d out of range,	returning -1.", Mode_Count);
		return -1;
	}
	
	if ( GetTeamClientCount(TEAM_RED) == 0 && GetTeamClientCount(TEAM_BLUE) == 0 )
	{
		LogMessage("ChooseBestMode: No players on active teams, returning -1.");
		return -1;
	}
	
	// What we want to do here:
	//- Create a randomised array of the indices for the modes we have registered.
	//- Check the tracker count for each of these indices in the order they appear in the array.
	//- Choose the mode with the lowest tracker count.
	
	new Buffer[Mode_Count+1];
	
	// Set all the values.
	for ( new i = 0; i <= Mode_Count; i++ )
	{
		Buffer[i] = i;
	}
	
	// Randomise the values.
	RandomiseArray(Buffer, Mode_Count+1);
	
	new MinValue = MAX_PLAY_LIMIT+1;
	new Mode = -1;
	new ModesFound = 0;
	
	// For each of the registered modes.
	for ( new j = 0; j <= Mode_Count; j++ )
	{
		#if (DEBUG & DEBUGFLAG_BESTMODE) == DEBUGFLAG_BESTMODE
		LogMessage("ChooseBestMode: Checking buffer index %d - mode ID %d (%s)...", j, Buffer[j], Mode_Name[Buffer[j]]);
		#endif
		
		// If the mode has been played less times than modes we have found before, make a note of which mode this is.
		if ( Mode_Tracker[Buffer[j]] <= MinValue )
		{
			#if (DEBUG & DEBUGFLAG_BESTMODE) == DEBUGFLAG_BESTMODE
			LogMessage("Mode ID %d (%s) has been played %d times, less times than the modes checked so far (min %d).", Buffer[j], Mode_Name[Buffer[j]], Mode_Tracker[Buffer[j]], MinValue);
			#endif
			
			// Check team numbers
			if ( Mode_TeamIndependent[Buffer[j]] >= 1 )
			{
				#if (DEBUG & DEBUGFLAG_BESTMODE) == DEBUGFLAG_BESTMODE
				LogMessage("Mode ID %d (%s) uses independent team number checking.", Buffer[j], Mode_Name[Buffer[j]]);
				#endif
				
				if ( (GetTeamClientCount(TEAM_RED) + GetTeamClientCount(TEAM_BLUE)) >= (Mode_MinRed[Buffer[j]] + Mode_MinBlue[Buffer[j]]) )
				{
					#if (DEBUG & DEBUGFLAG_BESTMODE) == DEBUGFLAG_BESTMODE
					LogMessage("Red + Blue count = %d, Minimum count = %d, counts are adequate.", (GetTeamClientCount(TEAM_RED) + GetTeamClientCount(TEAM_BLUE)), (Mode_MinRed[Buffer[j]] + Mode_MinBlue[Buffer[j]]));
					#endif
					
					MinValue = Mode_Tracker[Buffer[j]];
					Mode = Buffer[j];
				}
			}
			else
			{
				#if (DEBUG & DEBUGFLAG_BESTMODE) == DEBUGFLAG_BESTMODE
				LogMessage("Mode ID %d (%s) does not use independent team number checking.", Buffer[j], Mode_Name[Buffer[j]]);
				#endif
				
				if ( GetTeamClientCount(TEAM_RED) >= Mode_MinRed[Buffer[j]] && GetTeamClientCount(TEAM_BLUE) >= Mode_MinBlue[Buffer[j]] )
				{
					#if (DEBUG & DEBUGFLAG_BESTMODE) == DEBUGFLAG_BESTMODE
					LogMessage("Red: %d, Blue: %d, Min Red: %d, Min Blue: %d, counts are adequate.", GetTeamClientCount(TEAM_RED), GetTeamClientCount(TEAM_BLUE), Mode_MinRed[Buffer[j]], Mode_MinBlue[Buffer[j]]);
					#endif
					
					MinValue = Mode_Tracker[Buffer[j]];
					Mode = Buffer[j];
				}
			}
			
		}
	}
	
	#if (DEBUG & DEBUGFLAG_BESTMODE) == DEBUGFLAG_BESTMODE
	LogMessage("ChooseBestMode: Mode chosen is ID %d (%s).", Mode, Mode_Name[Mode]);
	#endif
	
	return Mode;
}*/

/*	Chooses the best mode to play, or -1 (normal round) on error.	*/
stock ChooseBestMode2()
{
	// Return -1 if any of the following is true:
	if ( Mode_Count < 0 || Mode_Count >= MAX_MODES )
	{
		LogMessage("ChooseBestMode: Mode_Count %d out of range,	returning -1.", Mode_Count);
		return -1;
	}
	
	if ( GetTeamClientCount(TEAM_RED) == 0 && GetTeamClientCount(TEAM_BLUE) == 0 )
	{
		LogMessage("ChooseBestMode: No players on active teams, returning -1.");
		return -1;
	}
	
	new ForceMode = GetConVarInt(cv_ForceMode);
	
	if ( ForceMode >= 0 )	// Force mode ConVar has been changed.
	{
		if ( ForceMode > Mode_Count )
		{
			LogMessage("Trying to force non-existent mode with index %d, ignoring.", ForceMode);
			PrintToChatAll("%T", "am_force_mode_invalid", LANG_SERVER);
		}
		else
		{
			LogMessage("Mode %s with ID %d being forced manually, team counts will be DISREGARDED.", Mode_Name[ForceMode], ForceMode);
			return ForceMode;
		}
	}
	
	/* What we want to do here:
	- Check the tracker count for each mode.
		If the count is higher than our current lowest play count, or equal to MAX_PLAY_LIMIT, do nothing.
		If the count is less than our current lowest play count, or equal to the count but the recorded mode ID is not valid,
		make a note of the mode ID and set the simultaneous count to 1.
		If the count is equal to the current lowest play count, record the mode ID and increment the simultaneous count.
	- If the resultant mode ID is not valid, return -1.
	- If the simultaneous count is 1, choose the mode with the lowest tracker count.
	- If the simultaneous count is greater than 1, choose a random mode ID from the recorded IDs.*/
	
	new MinValue = MAX_PLAY_LIMIT+1;
	new Modes[MAX_MODES] = {-1, ...};
	new Simultaneous = 0;	// This will hold the total number of lowest-played modes, whose max index in the Modes array will be Simultaneous - 1.
	
	for ( new i = 0; i <= Mode_Count; i++ )
	{
		if ( Mode_Tracker[i] > MinValue || Mode_Tracker[i] >= MAX_PLAY_LIMIT )
		{
			// Do nothing.
			#if (DEBUG & DEBUGFLAG_BESTMODE) == DEBUGFLAG_BESTMODE
			LogMessage("Mode %d not lower than minimum number of plays.", i);
			#endif
		}
		else if ( Mode_Tracker[i] < MinValue )
		{
			#if (DEBUG & DEBUGFLAG_BESTMODE) == DEBUGFLAG_BESTMODE
			LogMessage("Mode %d lower than the modes checked so far.", i);
			#endif
			
			// Check that the mode can be played.
			if ( Mode_TeamIndependent[i] >= 1 )	// Check team counts ignoring specific teams.
			{
				#if (DEBUG & DEBUGFLAG_BESTMODE) == DEBUGFLAG_BESTMODE
				LogMessage("Team counts checked independently.");
				#endif
				
				if ( (GetTeamClientCount(TEAM_RED) + GetTeamClientCount(TEAM_BLUE)) >= (Mode_MinRed[i] + Mode_MinBlue[i]) )
				{
					#if (DEBUG & DEBUGFLAG_BESTMODE) == DEBUGFLAG_BESTMODE
					LogMessage("Team counts are adequate.");
					#endif
					
					Modes[0] = i;
					Simultaneous = 1;
					MinValue = Mode_Tracker[i];
				}
			}
			else	// Check individual team counts.
			{
				#if (DEBUG & DEBUGFLAG_BESTMODE) == DEBUGFLAG_BESTMODE
				LogMessage("Team counts not checked independently.");
				#endif
				
				if ( GetTeamClientCount(TEAM_RED) >= Mode_MinRed[i] && GetTeamClientCount(TEAM_BLUE) >= Mode_MinBlue[i] )
				{
					#if (DEBUG & DEBUGFLAG_BESTMODE) == DEBUGFLAG_BESTMODE
					LogMessage("Team counts are adequate.");
					#endif
					
					Modes[0] = i;
					Simultaneous = 1;
					MinValue = Mode_Tracker[i];
				}
			}
		}
		else
		{
			#if (DEBUG & DEBUGFLAG_BESTMODE) == DEBUGFLAG_BESTMODE
			LogMessage("Mode %d has equal plays to the lowest mode(s) checked so far.", i);
			#endif
			
			// Check that the mode can be played.
			if ( Mode_TeamIndependent[i] >= 1 )	// Check team counts ignoring specific teams.
			{
				#if (DEBUG & DEBUGFLAG_BESTMODE) == DEBUGFLAG_BESTMODE
				LogMessage("Team counts checked independently.");
				#endif
				
				if ( (GetTeamClientCount(TEAM_RED) + GetTeamClientCount(TEAM_BLUE)) >= (Mode_MinRed[i] + Mode_MinBlue[i]) )
				{
					#if (DEBUG & DEBUGFLAG_BESTMODE) == DEBUGFLAG_BESTMODE
					LogMessage("Team counts are adequate.");
					#endif
					
					Modes[Simultaneous] = i;
					Simultaneous++;
				}
			}
			else	// Check individual team counts.
			{
				#if (DEBUG & DEBUGFLAG_BESTMODE) == DEBUGFLAG_BESTMODE
				LogMessage("Team counts not checked independently.");
				#endif
				
				if ( GetTeamClientCount(TEAM_RED) >= Mode_MinRed[i] && GetTeamClientCount(TEAM_BLUE) >= Mode_MinBlue[i] )
				{
					#if (DEBUG & DEBUGFLAG_BESTMODE) == DEBUGFLAG_BESTMODE
					LogMessage("Team counts are adequate.");
					#endif
					
					Modes[Simultaneous] = i;
					Simultaneous++;
				}
			}
		}
	}
	
	if ( Simultaneous < 1 )
	{
		LogMessage("ChooseBestMode: No best mode found (found %d), returning -1.", Simultaneous);
		return -1;
	}
	
	// If Simultaneous has recorded modes, the team counts are valid.
	// Choose an index between 0 and Simultaneous-1 (if Simultaneous is 1, index will be 0).
	
	#if (DEBUG & DEBUGFLAG_BESTMODE) == DEBUGFLAG_BESTMODE
	LogMessage("ChooseBestMode: Modes found:");
	
	for ( new i = 0; i < Simultaneous; i++ )
	{
		LogMessage("Mode ID: %d, Name: %s.", Modes[i], Mode_Name[Modes[i]]);
	}
	#endif
	
	new Mode = Modes[GetRandomInt(0, Simultaneous-1)];
	
	#if (DEBUG & DEBUGFLAG_BESTMODE) == DEBUGFLAG_BESTMODE
	LogMessage("ChooseBestMode: Mode chosen is ID %d (%s).", Mode, Mode_Name[Mode]);
	#endif
	
	return Mode;
}

/*	Randomises the contents of a single-dimensional array.	*/
/*RandomiseArray(Target[], size)
{
	// Copy our target array.
	new Buffer[size];
	
	for ( new n = 0; n < size; n++ )
	{
		Buffer[n] = Target[n];
	}
	
	// Make a note of how much data is in the buffer
	new data = size;
	
	// While we still have data to copy:
	for ( new i = 0; i < size; i++ )
	{
		// Pick a random integer between 0 and data-1.
		new index = GetRandomInt(0, data-1);
		
		// Copy the data from this index in the buffer.
		Target[i] = Buffer[index];
		
		// Shift all the buffer data in an index higher than this down one index.
		for ( new j = index+1; j < data; j++ )
		{
			// Move the data from j into j-1.
			Buffer[j-1] = Buffer[j];
		}
		
		// Decrease our buffer data count by 1.
		data--;
	}
	
	// Target will now contain randomised data.
}*/

// ================================
// =========== Natives ============
// ================================

/*	Registers a mode into the plugin.
	Params:
	String:ModeName			Name of the mode. Should be translated into LANG_SERVER before being passed. Max length 64 characters.
	String:ModeTagline		Tagline to display to players when the round starts. Should be translated into LANG_SERVER before being passed. Max length 64 characters.
	String:ModeDesc			Description of the mode. Should be translated into LANG_SERVER before being passed. Max length 128 characters.
	MinPlayersRed			Minimum number of players that must be on the Red team for this mode to activate.
	MinPlayersBlue			Minimum number of players that must be on the Blue team for this mode to activate.
	bool:TeamIndependent	If true, team-specific counts will be ignored and the total number of min players (MinPlayersRed + MinPlayersBlue) will be checked regardless of teams.
							Use this if you require a minimum number of players but it doesn't matter whether they are on Red or Blue.	*/
public Native_RegisterMode( Handle:plugin, numParams )
{
	#if (DEBUG & DEBUGFLAG_REGISTERMODES) == DEBUGFLAG_REGISTERMODES
	LogMessage("Native RegisterMode has been called. Current Mode_Count = %d. MAX_MODES = %d.", Mode_Count, MAX_MODES);
	#endif
	
	// Check to see if the plugin is broadcasting for modes.
	if ( (g_PluginState & STATE_SEARCHING_FOR_MODES) != STATE_SEARCHING_FOR_MODES )
	{
		#if (DEBUG & DEBUGFLAG_REGISTERMODES) == DEBUGFLAG_REGISTERMODES
		LogMessage("ABORT: Handler not currently broadcasting a mode search, returning -10.");
		#endif
		
		return -10;
	}
	
	// Check to see if we already have the max amount of modes.
	if ( Mode_Count >= (MAX_MODES - 1) )
	{
		#if (DEBUG & DEBUGFLAG_REGISTERMODES) == DEBUGFLAG_REGISTERMODES
		LogMessage("ABORT: Mode_Count >= MAX_MODES (%d >= %d), returning -10.", Mode_Count, MAX_MODES);
		#endif
		
		return -10;	// The maximum value of Mode_Count will be MAX_MODES - 1 as Mode_Count is the array index.
	}
	
	// Increment Mode_Count ready for new data.
	Mode_Count++;
	
	// Pull down our values.
	decl String:ModeName[65];
	decl String:ModeTagline[65];
	decl String:ModeDesc[129];
	Mode_MinRed[Mode_Count] = GetNativeCell(4);
	Mode_MinBlue[Mode_Count] = GetNativeCell(5);
	Mode_TeamIndependent[Mode_Count] = GetNativeCell(6);
	
	// Check our string lengths and modify accordingly.
	new NameLength, TagLength, DescLength;
	
	GetNativeStringLength(1, NameLength);
	if ( NameLength <= 0 )
	{
		Format(ModeName, sizeof(ModeName), "Untitled mode %d", Mode_Count+1);
		
		#if (DEBUG & DEBUGFLAG_REGISTERMODES) == DEBUGFLAG_REGISTERMODES
		LogMessage("Mode has no name (length %d). Renamed to %s", NameLength, ModeName);
		#endif
	}
	else
	{
		GetNativeString(1, ModeName, sizeof(ModeName));
		
		#if (DEBUG & DEBUGFLAG_REGISTERMODES) == DEBUGFLAG_REGISTERMODES
		LogMessage("Mode name: %s", ModeName);
		#endif
	}
	
	Mode_Name[Mode_Count] = ModeName;
	
	GetNativeStringLength(2, TagLength);
	if ( TagLength <= 0 )
	{
		ModeTagline[0] = '\0';
		
		#if (DEBUG & DEBUGFLAG_REGISTERMODES) == DEBUGFLAG_REGISTERMODES
		LogMessage("Mode has no tagline (length %d).", TagLength);
		#endif
	}
	else
	{
		GetNativeString(2, ModeTagline, sizeof(ModeTagline));
		
		#if (DEBUG & DEBUGFLAG_REGISTERMODES) == DEBUGFLAG_REGISTERMODES
		LogMessage("Mode tag line: %s", ModeTagline);
		#endif
	}
	
	Mode_Tagline[Mode_Count] = ModeTagline;
	
	GetNativeStringLength(3, DescLength);
	if ( DescLength <= 0 )
	{
		Format (ModeDesc, sizeof(ModeDesc), "%T", "am_no_description", LANG_SERVER);
		
		#if (DEBUG & DEBUGFLAG_REGISTERMODES) == DEBUGFLAG_REGISTERMODES
		LogMessage("Mode has no description (length %d). Renamed to %s", DescLength, ModeDesc);
		#endif
	}
	else
	{
		GetNativeString(3, ModeDesc, sizeof(ModeDesc));
		
		#if (DEBUG & DEBUGFLAG_REGISTERMODES) == DEBUGFLAG_REGISTERMODES
		LogMessage("Mode description: %s", ModeDesc);
		#endif
	}
	
	Mode_Desc[Mode_Count] = ModeDesc;
	
	// Check the rest of our values and clamp accordingly.
	if ( Mode_MinRed[Mode_Count] < 0 )
	{
		#if (DEBUG & DEBUGFLAG_REGISTERMODES) == DEBUGFLAG_REGISTERMODES
		LogMessage("MinRed value %d for mode %s out of bounds, clamping to 0.", Mode_MinRed[Mode_Count], ModeName);
		#endif
		
		Mode_MinRed[Mode_Count] = 0;
	}
	/*else if ( Mode_MinRed[Mode_Count] > 32 )	// Commented this out - modes can specify player counts that are very large in order to disable themselves.
	{
		#if (DEBUG & DEBUGFLAG_REGISTERMODES) == DEBUGFLAG_REGISTERMODES
		LogMessage("MinRed value %d for mode %s out of bounds, clamping to 32.", Mode_MinRed[Mode_Count], ModeName);
		#endif
		
		Mode_MinRed[Mode_Count] = 32;
	}*/
	
	if ( Mode_MinBlue[Mode_Count] < 0 )
	{
		#if (DEBUG & DEBUGFLAG_REGISTERMODES) == DEBUGFLAG_REGISTERMODES
		LogMessage("MinBlue value %d for mode %s out of bounds, clamping to 0.", Mode_MinBlue[Mode_Count], ModeName);
		#endif
		
		Mode_MinBlue[Mode_Count] = 0;
	}
	/*else if ( Mode_MinBlue[Mode_Count] > 32 )
	{
		#if (DEBUG & DEBUGFLAG_REGISTERMODES) == DEBUGFLAG_REGISTERMODES
		LogMessage("MinBlue value %d for mode %s out of bounds, clamping to 32.", Mode_MinBlue[Mode_Count], ModeName);
		#endif
		
		Mode_MinBlue[Mode_Count] = 32;
	}*/
	
	if ( Mode_TeamIndependent[Mode_Count] < 0 )
	{
		#if (DEBUG & DEBUGFLAG_REGISTERMODES) == DEBUGFLAG_REGISTERMODES
		LogMessage("TeamIndependent value %d for mode %s out of bounds, clamping to 0.", Mode_TeamIndependent[Mode_Count], ModeName);
		#endif
		
		Mode_TeamIndependent[Mode_Count] = 0;
	}
	else if ( Mode_TeamIndependent[Mode_Count] > 1 )
	{
		#if (DEBUG & DEBUGFLAG_REGISTERMODES) == DEBUGFLAG_REGISTERMODES
		LogMessage("TeamIndependent value %d for mode %s out of bounds, clamping to 1.", Mode_TeamIndependent[Mode_Count], ModeName);
		#endif
		
		Mode_TeamIndependent[Mode_Count] = 1;
	}
	
	Mode_Tracker[Mode_Count] = 0;
	
	// Return the mode ID value.
	return Mode_Count;
}

/*	Cancels the current round in progress.
	Params:
	modeID	ID of the mode calling the function.	*/
public Native_CancelCurrentRound( Handle:plugin, numParams )
{
	// End the round as a stalemate.
	RoundWin(TEAM_UNASSIGNED);
}

/*	Notifies the handler that a custom mode has been unloaded.
	The mode data will stay in the handler until the next map load, but will no longer be selected to be played.
	If the mode concerned is being played when this call is made, the round will end.
	Params:
	modeID	ID of the mode calling the function.	*/
public Native_UnloadMode( Handle:plugin, numParams )
{
	new Unload = GetNativeCell(1);
	
	// If the mode that is unloading is the mode we are currently playing, end the round.
	if ( CurrentMode == Unload ) RoundWin(TEAM_UNASSIGNED);
	
	// Nullify the tracker value for the unloaded mode so that it does not get selected again.
	Mode_Tracker[Unload] = UNLOADED;
}