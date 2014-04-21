/*	==========================================================================
	Arena Modulus Main Handler - [X6] Herbius - 31/08/11 - http://goo.gl/1SmnL
	==========================================================================
	
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

#include <sourcemod>	// Main SM functionality.
#include <sdktools>		// SDK Tools.

// ================================
// =========== Defines ============
// ================================

#define MAX_MODES	32

// ========== Debug Flags =========
// Different areas of the code can be enabled or disabled for debugging purposes.
// Setting the main DEBUG constant to different flags will allow for different debugging functionality.

#define DEBUG_NONE		0	// No debugging.
#define DEBUG_GENERAL	1	// General debugging.
#define DEBUG_VOTES		2	// Votes.

#define DEBUG			DEBUG_GENERAL | DEBUG_VOTES

// ========= State Flags ==========
// State flags control which functions and hooks will occur in the plugin.

#define STATE_NO_ACTIVITY	4	// Plugin loaded while a server is running. No activity will occur. Reset on MapStart.
#define STATE_DISABLED		2	// Plugin is disabled. No activity will occur apart from the checking of the disabled ConVar.
#define STATE_NOT_IN_ROUND	1	// A round is not being played. No custom mode events will run. Set on RoundWin/MapEnd, cleared on RoundStart.

// ======== Team Integers =========
#define TEAM_INVALID		-1
#define TEAM_UNASSIGNED		0
#define TEAM_SPECTATOR		1
#define TEAM_RED			2
#define TEAM_BLUE			3

// ========== Variables ===========
new g_PluginState;						// Global state of the plugin.
new String:g_ModeName[MAX_MODES][65];	// Holds the name of each registered mode.
new String:g_ModeDesc[MAX_MODES][129];	// Holds the description of each registered mode.
new g_ModeMinRed[MAX_MODES];			// Minimum number of players on Red for a mode to activate.
new g_ModeMinBlue[MAX_MODES];			// Minimum number of players on Blue for a mode to activate.
new g_RegisteredModes = -1;				// Holds the number of successfully registered modes. This is a 0-based index, so its current value at any time is the top array index.
new g_CurrentMode = -1;					// The mode that is currently playing. -1 will not match with external modes and will run a normal arena round.
new g_ModeQueue[MAX_MODES] = {-1, ...};	// Queue of modes to play. Next mode to play is at index 0.
new bool:AllowModeVotes = true;			// If this flag is set, votes will be enabled on RoundStart.

// ======== ConVar Handles ========
new Handle:cv_PluginEnabled = INVALID_HANDLE;	// Enables or disables the plugin. Changing this restarts the current map.

// ========= Menu Handles =========
new Handle:menu_ModeVote = INVALID_HANDLE;		// Handle to the mode voting menu.

// Timer handles
new Handle:timer_VotingEnded = INVALID_HANDLE;	// Handle to the VotingEnded timer.

// ======= Forward Handles ========
new Handle:fw_SearchForModes = INVALID_HANDLE;
new Handle:fw_RoundStart = INVALID_HANDLE;
new Handle:fw_RoundEnd = INVALID_HANDLE;
new Handle:fw_MapEnd = INVALID_HANDLE;

// ========= Plugin Info ==========
#define PLUGIN_NAME			"Arena Modulus: Main Handler"
#define PLUGIN_AUTHOR		"[X6] Herbius"
#define PLUGIN_DESCRIPTION	"Play a variety of arena mini-modes."
#define PLUGIN_VERSION		"1.0.0.0"
#define PLUGIN_URL			"http://goo.gl/1SmnL"

public Plugin:myinfo =
{
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = PLUGIN_URL
};

// ================================
// ==== Starup Initialisation =====
// ================================

/*	Natives and forwards go here.	*/
public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	CreateNative("ArenaMod_RegisterMode",		Native_RegisterMode);
	CreateNative("ArenaMod_CancelCurrentRound",	Native_CancelCurrentRound);
	
	fw_SearchForModes	= CreateGlobalForward("ArenaMod_SearchForModes",	ET_Ignore				);
	fw_RoundStart		= CreateGlobalForward("ArenaMod_RoundStart",		ET_Ignore, Param_Cell	);
	fw_RoundEnd			= CreateGlobalForward("ArenaMod_RoundEnd",			ET_Ignore, Param_Cell, Param_Cell	);
	fw_MapEnd			= CreateGlobalForward("ArenaMod_MapEnd",			ET_Ignore				);
	
	RegPluginLibrary("ArenaModulus");
	return APLRes_Success;
}

public OnPluginStart()
{
	LogMessage("===== Arena Modulus Main Handler, Version: %s =====", PLUGIN_VERSION);
	LoadTranslations("arena_modulus/ArenaModulus.phrases");
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
	
	// Hooks:
	HookConVarChange(cv_PluginEnabled,	CvarChange);
	
	HookEventEx("teamplay_round_start",		Event_RoundStart,		EventHookMode_Post);
	HookEventEx("teamplay_round_win",		Event_RoundWin,			EventHookMode_Post);
	HookEventEx("teamplay_round_stalemate",	Event_RoundStalemate,	EventHookMode_Post);
	
	// ========= Plugin State =========
	// If the server is currently processing (ie. the plugin's just been loaded while a round is going on), set the state flag.
	// This flag will override ALL other flags and no plugin functionality will occur until a new map is loaded.
	if ( IsServerProcessing() )
	{
		g_PluginState |= STATE_NO_ACTIVITY;
		LogMessage("[AM] Arena Modulus plugin loaded while round is active. Plugin will be activated on map change.");
		PrintToChatAll("[AM] %T", "am_pluginloadnextmapchange", LANG_SERVER);
		
		return;
	}
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
	
	// If we're not active, the next time we become active will be when the map changes anyway, so we can leave this.
	if ( (g_PluginState & STATE_NO_ACTIVITY) == STATE_NO_ACTIVITY ) return;
	
	// Get the current map name
	decl String:mapname[64];
	GetCurrentMap(mapname, sizeof(mapname));
	LogMessage("[AM] Plugin state changed. Restarting map (%s)...", mapname);
	
	// Restart the map	
	ForceChangeLevel(mapname, "Arena Modulus enabled state changed, requires map restart.");
}

// ================================
// ===== Natives and Forwards =====
// ================================

/*	Called when a plugin acts upon the SearchForModes forward.
	Params: String:ModeName, String:ModeDesc, MinPlayersRed, MinPlayersBlue
	Returns the mode's ID.	*/
public Native_RegisterMode(Handle:plugin, numParams)
{
	#if (DEBUG & DEBUG_GENERAL) == DEBUG_GENERAL
	LogMessage("RegisterMode called.");
	#endif
	
	// If this has been called by a rogue plugin while we're in an abnormal state, return.
	// We do not want to be in a NO_ACTIVITY or DISABLED state or in a round (since MapStart
	// is called outside of a round).
	if (	(g_PluginState & STATE_NO_ACTIVITY)		== STATE_NO_ACTIVITY	||
			(g_PluginState & STATE_DISABLED)		== STATE_DISABLED		||
			(g_PluginState & STATE_NOT_IN_ROUND)	!= STATE_NOT_IN_ROUND	)
	{
		LogError("Warning: Plugin handle %d calling RegisterMode outside of SearchForModes.", plugin);
		return -1;
	}
	
	// If we are at the max number of modes, don't register.
	// g_RegisteredModes is 0-based, so account for this.
	if ( g_RegisteredModes >= (MAX_MODES - 1) )
	{
		LogError("ERROR: RegisterMode has reached the maximum number of modes (index is %d).", g_RegisteredModes);
		return -1;
	}
	
	// This SHOULDN'T happen, but if g_RegisteredModes is less than -1, let us know about it.
	if ( g_RegisteredModes < -1 )
	{
		LogError("CRITICAL ERROR: g_RegisteredModes is %d, less than -1! This is probably a code error and needs to be fixed.", g_RegisteredModes);
		return -1;
	}
	
	decl String:ModeName[65], String:ModeDesc[129];
	new MinPlayersRed, MinPlayersBlue, NameLength, DescLength;
	
	GetNativeStringLength(1, NameLength);
	GetNativeStringLength(2, DescLength);
	
	// If the name fits, retrieve it. Otherwise, make up a name.
	if ( NameLength <= 64 ) GetNativeString(1, ModeName, sizeof(ModeName));
	else
	{
		Format(ModeName, sizeof(ModeName), "TRUNCATEDNAME_%d", (g_RegisteredModes + 1));
		LogError("Warning: Mode %d's name was truncated.", (g_RegisteredModes + 1));
	}
	
	// Same for description.
	if ( NameLength <= 128 ) GetNativeString(1, ModeDesc, sizeof(ModeDesc));
	else
	{
		Format(ModeDesc, sizeof(ModeDesc), "TRUNCATEDDESCRIPTION_%d", (g_RegisteredModes + 1));
		LogError("Warning: Mode %d's description was truncated.", (g_RegisteredModes + 1));
	}
	
	MinPlayersRed = GetNativeCell(3);
	MinPlayersBlue = GetNativeCell(4);
	
	// Put all this info into our global variables:
	
	// Increment the registered mode count.
	g_RegisteredModes++;
	
	g_ModeName[g_RegisteredModes] = ModeName;
	g_ModeDesc[g_RegisteredModes] = ModeDesc;
	g_ModeMinRed[g_RegisteredModes] = MinPlayersRed;
	g_ModeMinBlue[g_RegisteredModes] = MinPlayersBlue;
	
	return g_RegisteredModes;
}

/*	Called when a mode requests to cancel the round in progress.
	Params: modeID
	No return.	*/
public Native_CancelCurrentRound(Handle:plugin, numParams)
{
	// End the round in a stalemate.
	// This will call the RoundEnd forward as well.
	
	ForceTeamWin(TEAM_UNASSIGNED);
	return;
}

// ================================
// ============ Hooks =============
// ================================

public OnMapStart()
{
	// Clear the NO_ACTIVITY flag.
	g_PluginState &= ~STATE_NO_ACTIVITY;
	
	AllowModeVotes = true;
	
	// If disabled, return.
	if ( (g_PluginState & STATE_DISABLED) == STATE_DISABLED ) return;
	
	// ====================
	// == SearchForModes ==
	// ====================
	#if (DEBUG & DEBUG_GENERAL) == DEBUG_GENERAL
	LogMessage("Calling SearchForModes...");
	#endif
	
	Call_StartForward(fw_SearchForModes);
	Call_Finish();
	
	menu_ModeVote = BuildModeVoteMenu();
}

public OnMapEnd()
{
	// Set the NOT_IN_ROUND flag.
	g_PluginState |= STATE_NOT_IN_ROUND;
	
	// ====================
	// ====== MapEnd ======
	// ====================
	Call_StartForward(fw_MapEnd);
	Call_Finish();
	
	if ( AllowModeVotes ) VotingEnded();
	
	// Clean up all the mode info.
	ClearAllModes();
	
	if ( menu_ModeVote != INVALID_HANDLE)
	{
		CloseHandle(menu_ModeVote);
		menu_ModeVote = INVALID_HANDLE;
	}
	
	if ( timer_VotingEnded != INVALID_HANDLE )
	{
		KillTimer(timer_VotingEnded);
		timer_VotingEnded = INVALID_HANDLE;
	}
}

/*	Called when a new round begins.	*/
public Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	// Clear the NOT_IN_ROUND flag.
	g_PluginState &= ~STATE_NOT_IN_ROUND;
	
	if (	(g_PluginState & STATE_NO_ACTIVITY)	== STATE_NO_ACTIVITY	||
			(g_PluginState & STATE_DISABLED) 	== STATE_DISABLED		) return;
	
	if ( g_RegisteredModes >= 0 )
	{
		if ( AllowModeVotes && menu_ModeVote != INVALID_HANDLE )
		{
			g_CurrentMode = -1;
			
			VoteCounter(-1);
			
			for ( new i = 1; i <= MaxClients; i++ )
			{
				if ( IsClientInGame(i) )
				{
					if ( GetClientTeam(i) == TEAM_RED || GetClientTeam(i) == TEAM_BLUE )
					{
						DisplayMenu(menu_ModeVote, i, 20);
					}
				}
			}
			
			timer_VotingEnded = CreateTimer(20.0, Timer_VotingEnded, _, TIMER_FLAG_NO_MAPCHANGE);
		}
		else
		{
			// #TODO#: ChooseBestMode function which deals with everything that needs to happen.
		}
	}
	else g_CurrentMode = -1;
	
	// ====================
	// ==== RoundStart ====
	// ====================
	Call_StartForward(fw_RoundStart);
	Call_PushCell(g_CurrentMode);
	Call_Finish();
}

/*	Called when a round is won.	*/
public Event_RoundWin(Handle:event, const String:name[], bool:dontBroadcast)
{
	// Set the NOT_IN_ROUND flag.
	g_PluginState |= STATE_NOT_IN_ROUND;
	
	g_CurrentMode = -1;
	AllowModeVotes = false;
	
	if (	(g_PluginState & STATE_NO_ACTIVITY)	== STATE_NO_ACTIVITY	||
			(g_PluginState & STATE_DISABLED) 	== STATE_DISABLED		) return;
	
	UsrEvent_RoundEnd(g_CurrentMode, GetEventInt(event, "team"));
}

/*	Called when a round is drawn.	*/
public Event_RoundStalemate(Handle:event, const String:name[], bool:dontBroadcast)
{
	// Set the NOT_IN_ROUND flag.
	g_PluginState |= STATE_NOT_IN_ROUND;
	
	g_CurrentMode = -1;
	AllowModeVotes = false;
	
	if (	(g_PluginState & STATE_NO_ACTIVITY)	== STATE_NO_ACTIVITY	||
			(g_PluginState & STATE_DISABLED) 	== STATE_DISABLED		) return;
	
	UsrEvent_RoundEnd(g_CurrentMode, TEAM_UNASSIGNED);
}

/*	Called by either RoundWin or RoundStalemate.	*/
UsrEvent_RoundEnd(modeID, winningteam)
{
	if ( timer_VotingEnded != INVALID_HANDLE )
	{
		KillTimer(timer_VotingEnded);
		timer_VotingEnded = INVALID_HANDLE;
	}
	
	if ( AllowModeVotes )
	{
		#if (DEBUG & DEBUG_VOTES) == DEBUG_VOTES
		LogMessage("VotingEnded() called due to end of round.");
		#endif
		
		VotingEnded();
	}
	
	// ====================
	// ===== RoundEnd =====
	// ====================
	Call_StartForward(fw_RoundEnd);
	Call_PushCell(modeID);
	Call_PushCell(winningteam);
	Call_Finish();
}

// ================================
// ========== Round Win ===========
// ================================

/*	Ends the round and wins it for the specified team.	*/
stock ForceTeamWin(team)
{
    new ent = FindEntityByClassname2(-1, "team_control_point_master");
    if (ent == -1)
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
    /* If startEnt isn't valid shifting it back to the nearest valid one */
    while (startEnt > -1 && !IsValidEntity(startEnt)) startEnt--;
    return FindEntityByClassname(startEnt, classname);
}

// ================================
// === Resetting Mode Counters ====
// ================================

stock ClearAllModes()
{
	for ( new i = 0; i < MAX_MODES; i++ )
	{
		g_ModeName[i][0] = '\0';	// Terminate the string early.
		g_ModeDesc[i][0] = '\0';
		g_ModeMinRed[i] = 0;
		g_ModeMinBlue[i] = 0;
	}
	
	for ( new i = 0; i < MAX_MODES; i++ )
	{
		g_ModeQueue[i] = -1;
	}
	
	VoteCounter(-1);
	g_CurrentMode = -1;
	g_RegisteredModes = -1;
	
	return;
}

// ================================
// ========== Mode Votes ==========
// ================================

/*	Builds up the menu for clients to vote for the next mode.
	Returns the handle to the menu.	*/
stock Handle:BuildModeVoteMenu()
{
	new Handle:menu = CreateMenu(Handler_VoteMenu);
	
	if ( menu == INVALID_HANDLE ) return menu;
	if ( g_RegisteredModes < 0 ) return INVALID_HANDLE;
	
	decl String:MenuItem[65];
	
	Format(MenuItem, sizeof(MenuItem), "%T", "am_mode_vote_menu_title", LANG_SERVER);
	SetMenuTitle(menu, MenuItem);
	
	// Go up to and including g_RegisteredModes, since this represents the top array index we have info for.
	for ( new i = 0; i <= g_RegisteredModes; i++ )
	{
		MenuItem = g_ModeName[i];
		AddMenuItem(menu, MenuItem, MenuItem);
	}
	
	return menu;
}

/*	Vote menu handler.	*/
public Handler_VoteMenu(Handle:menu, MenuAction:action, param1, param2)
{
	// The value returned in param2 as the menu ID is one less than the item number (ie. if the player selected item 9,
	// param2 would hold the value 8).
	// Since the indices of the modes start at 0 but menu items at 1, param2 will hold the index value for a mode.
	
	// After select the menu will dissappear, so we don't need to do anything (the handle will be closed OnMapEnd).
	if ( action == MenuAction_Select )
	{
		if ( AllowModeVotes ) VoteCounter(param2);
	}
}

/*	Vote counter.
	Mode is the mode to add the count to.
	If vote is false, only the value for the mode will be returned.
	If mode < 0, the counter will be reset.
	Returns -1 if mode is out of range.	*/
stock VoteCounter(mode, bool:vote = true)
{
	static ModeVotes[MAX_MODES];
	
	if ( mode < 0 )
	{
		for ( new i = 0; i < MAX_MODES; i++ )
		{
			ModeVotes[i] = 0;
		}
		
		return 0;
	}
	
	if ( mode >= MAX_MODES ) return -1;
	
	if ( vote ) ModeVotes[mode]++;
	
	return ModeVotes[mode];
}

/*	Fired 20 seconds after voting has started.	*/
public Action:Timer_VotingEnded(Handle:timer)
{
	#if (DEBUG & DEBUG_VOTES) == DEBUG_VOTES
	LogMessage("VotingEnded() called due to timer expiring.");
	#endif
	
	VotingEnded();
	
	return Plugin_Stop;
}

/*	Called when voting has ended; prevents any more votes from being counted and populates the queue.	*/
stock VotingEnded()
{
	AllowModeVotes = false;
	
	// Votes will be held in the VoteCounter function. Make a note of each of these and create ourselves a new array.
	new TempVoteQueue[g_RegisteredModes+1][2];	// [n][0] is the mode index, [n][1] is its vote count.
	
	for ( new i = 0; i < g_RegisteredModes+1; i++ )
	{
		TempVoteQueue[i][0] = i;
		TempVoteQueue[i][1] = VoteCounter(i, false);
	}
	
	// Order TempVoteQueue according to [n][1];
	SelectionSort(TempVoteQueue, g_RegisteredModes+1);
	
	// Put the ordered array values into the mode queue.
	for ( new i = 0; i < g_RegisteredModes+1; i++ )
	{
		g_ModeQueue[i] = TempVoteQueue[i][0];
		
		#if (DEBUG & DEBUG_VOTES) == DEBUG_VOTES
		LogMessage("g_ModeQueue[%d] = %d", i, g_ModeQueue[i]);
		#endif 
	}
	
	return;
}

/*	Sorts a two-dimensional array [n][2] into descending order according to the number in the second column.	*/
SelectionSort(arr[][], size) 
{
	for ( new pass = 0; pass < size - 1; pass++ ) 
	{
		new indexOfMax = pass;
		
		for ( new j = pass + 1; j < size; j++ )
		{
			if ( arr[j][1] > arr[pass][1] ) indexOfMax = j;
		}
		
		Swap (arr[pass][0], arr[indexOfMax][0]);
		Swap (arr[pass][1], arr[indexOfMax][1]);
	}
}

Swap(&x, &y) 
{ 
	new temp = x; 
	x = y; 
	y = temp; 
}