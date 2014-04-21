/*
	=== Arena Modulus ===
	Anything that needs to be done is marked with #TODO#.
	
	This plugin is split up into sections:
	- The first section is the main handler which deals with when the plugin is enabled or disabled, players voting for modes, etc.
	- Sections after this are specific to each mode and are called from the main handler section.
*/

#pragma semicolon 1

/*
	Debug flags - use a combination of these for enabling or disabling different debug code.
	
	0 - No debug.
	1 - General debug.
	2 - Votes
*/

#define DEBUG 1|2

#include <sourcemod>
#include include\arenamodulus.inc

#define PLUGIN_NAME			"Arena Modulus"
#define PLUGIN_AUTHOR		"[X6] Herbius"
#define PLUGIN_DESCRIPTION	"Play a variety of arena mini-modes."
#define PLUGIN_VERSION		"0.0.0.1"
#define PLUGIN_URL			"http://to.be.confirmed/"

// Variables:
new g_PluginState;				// Global state of the plugin.
new g_CurrentMode;				// ID of the current mode.
new bool:b_FirstRound = true;	// This flag is set when the first round is being played.


// ConVar handles:
new Handle:cv_PluginEnabled = INVALID_HANDLE;	// Enables or disables the plugin. Changing this restarts the current map.

// Other handles:
new Handle:menu_ModeVote = INVALID_HANDLE;		// Handle to the vote menu. The menu is created when the plugin starts.

/*	====================
	General Plugin Admin
	====================	*/

public Plugin:myinfo = 
{
	// This section should take care of itself nicely now.
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = PLUGIN_URL
}

public OnPluginStart()
{
	LogMessage("===== Arena Modulus plugin started. Version: %s =====", PLUGIN_VERSION);	
	LoadTranslations("arena_modulus/ArenaModulus.phrases");
	AutoExecConfig(true, "arenamodulus", "sourcemod/arenamodulus");
	
	CreateConVar("arenamod_version",	PLUGIN_VERSION,	"Plugin version",	FCVAR_NOTIFY);
	
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
	
	HookEventEx("teamplay_round_start",		Event_RoundStart,	EventHookMode_Post);
	HookEventEx("teamplay_round_win",		Event_RoundWin,		EventHookMode_Post);
	
	// Set up the name and description translation tags for each mode.
	NameDescInit();
	
	// Set up the minimum players for each mode.
	MinimumPlayersInit();
	
	// --Plugin State--
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

/*	====================
	=== Round  Votes ===
	====================	*/

/*	Builds up the menu for clients to vote for the next mode.
	Returns the handle to the menu.	*/
Handle:BuildModeVoteMenu()
{
	new Handle:menu = CreateMenu(Handler_VoteMenu);
	
	if ( menu = INVALID_HANDLE ) return menu;
	
	decl String:MenuItem[65];
	
	Format(MenuItem, sizeof(MenuItem), "%T", "am_mode_vote_menu_title", LANG_SERVER);
	SetMenuTitle(menu, MenuItem);
	
	for ( new i = 1; i < en_Modes; i++ )
	{
		Format(MenuItem, sizeof(MenuItem), "%T", Mode_Name_Trans[i], LANG_SERVER);
		AddMenuItem(menu, MenuItem, MenuItem);
	}
	
	return menu;
}

/*	Vote menu handler.	*/
public Handler_VoteMenu(Handle:menu, MenuAction:action, param1, param2)
{
	// The value returned in param2 as the menu ID is one less than the item number.
	// This means that param2 returns a value that is one less than the enum value for a mode.
	
	// After select the menu will dissappear, so we don't need to do anything (the handle will be closed OnMapEnd).
	if ( action == MenuAction_Select )
	{
		ModeVoteCount(param2 + 1, true);
	}
}

/*	Holds the counts for each mode. Passing value as true adds a point to the counter.
	The mode parameter takes the enum value for the mode.
	Passing a mode value < 0 resets all the vote counts.
	If no second parameter is specified, only the value is returned.
	Vote counts remain until the next vote, in case a queue generate is called.	*/
ModeVoteCount(mode, bool:vote = false)
{
	static ModeVotes[en_Modes];
	
	if ( mode < 0 )
	{
		for ( new i = 0; i < _:en_Modes; i++ )
		{
			ModeVotes[i] = 0;
		}
		return 0;
	}
	
	if ( !vote ) return ModeVotes[mode];
	else return ModeVotes[mode]++;
}

/*	Timer called every second to refresh the vote scores in the hud hint.
	Once twenty seconds has passed, the votes are finalised and the timer is killed.	*/
public Action:Timer_ModeVoteRefresh(Handle:timer)
{
	static TimePassed;
	
	new TopThreeModes[3];				// Holds the indices of the three most popular modes.
	new TopThreeModesVotes[3];			// Holds the number of votes each of these modes has.
	
	if ( TimePassed < 20 )
	{
		#if (DEBUG & 2) == 2
		LogMessage("Vote refresh time passed: %d", TimePassed);
		#endif
		
		if ( FindTopThreeVotes(TopThreeModes, TopThreeModesVotes) )
		{
			decl String:Hint[430];
			
			// Top three votes so far:
			// 1. X (x)
			// 2. Y (y)
			// 3. Z (z)
			// [n seconds remaining]
			
			// Apparently you can'r format string arrays using Array[n]...
			decl String:String1[96];
			decl String:String2[96];
			decl String:String3[96];
			decl String:String4[96];
			decl String:String5[96];
			decl String:HintStrings[5][96];
			
			Format(String1, sizeof(String1), "%T", "am_mode_vote_results_title", LANG_SERVER);
			Format(String2, sizeof(String2), "1. %T (%d)", Mode_Name_Trans[TopThreeModes[0]], LANG_SERVER, TopThreeModesVotes[0]);
			Format(String3, sizeof(String3), "2. %T (%d)", Mode_Name_Trans[TopThreeModes[1]], LANG_SERVER, TopThreeModesVotes[1]);
			Format(String4, sizeof(String4), "3. %T (%d)", Mode_Name_Trans[TopThreeModes[2]], LANG_SERVER, TopThreeModesVotes[2]);
			Format(String5, sizeof(String5), "[%T]", "am_seconds_remaining", LANG_SERVER, 20-TimePassed);
			
			HintStrings[0] = String1;
			HintStrings[1] = String2;
			HintStrings[2] = String3;
			HintStrings[3] = String4;
			HintStrings[4] = String5;
			
			ImplodeStrings(HintStrings, 5, "/n", Hint, sizeof(Hint));
			PrintHintTextToAll(Hint);
		}
		
		TimePassed++;
		
		return Plugin_Continue;
	}
	else
	{
		#if (DEBUG & 2) == 2
		LogMessage("Vote refresh time passed: %d. Ending votes.", TimePassed);
		#endif
		
		if ( FindTopThreeVotes(TopThreeModes, TopThreeModesVotes) )
		{
			decl String:EndHint[334];
			
			// Final vote numbers:
			// 1. X (x)
			// 2. Y (y)
			// 3. Z (z)
			
			decl String:EndString1[96];
			decl String:EndString2[96];
			decl String:EndString3[96];
			decl String:EndString4[96];
			decl String:EndHintStrings[4][96];
			
			Format(EndString1, sizeof(EndString1), "%T", "am_mode_vote_results", LANG_SERVER);
			Format(EndString2, sizeof(EndString2), "1. %T (%d)", Mode_Name_Trans[TopThreeModes[0]], LANG_SERVER, TopThreeModesVotes[0]);
			Format(EndString3, sizeof(EndString3), "2. %T (%d)", Mode_Name_Trans[TopThreeModes[1]], LANG_SERVER, TopThreeModesVotes[1]);
			Format(EndString4, sizeof(EndString4), "3. %T (%d)", Mode_Name_Trans[TopThreeModes[2]], LANG_SERVER, TopThreeModesVotes[2]);
			
			EndHintStrings[0] = EndString1;
			EndHintStrings[1] = EndString2;
			EndHintStrings[2] = EndString3;
			EndHintStrings[3] = EndString4;
			
			ImplodeStrings(EndHintStrings, 4, "/n", EndHint, sizeof(EndHint));
			PrintHintTextToAll(EndHint);
		}
		
		TimePassed = 0;		
		return Plugin_Stop;
	}
}

bool:FindTopThreeVotes(Indices[], Votes[])
{
	new ModeIndex[en_Modes][2] = {-1, ...};	// First column is the index, second is the vote count.
	
	for ( new i = 0; i < en_Modes; i++ )
	{
		ModeIndex[i][0] = i;
		ModeIndex[i][1] = ModeVoteCount(i);
	}
	
	SelectionSort(ModeIndex, en_Modes);
	
	Indices[0] = ModeIndex[0][0];
	Votes[0] = ModeIndex[0][1];
	
	Indices[1] = ModeIndex[1][0];
	Votes[1] = ModeIndex[1][1];
	
	Indices[2] = ModeIndex[2][0];
	Votes[2] = ModeIndex[2][1];
	
	return true;
}

/*	====================
	==== Mode Queue ====
	====================	*/

/*	Checks the mode vote counts and generates the queue accordingly.
	Index 0 of the queue array will be the enum of the most popular mode,
	decreasing with each index.	*/
VotesToModeQueue(QueueArray[])
{
	new Buffer[en_Modes][2];
	
	// [n][0] is the enum index, [n][1] is the vote count.
	for ( new i = 0; i < en_Modes; i++ )
	{
		Buffer[i][0] = i;
		Buffer[i][1] = ModeVoteCount[i];
	}
	
	// Now Buffer contains the counts for each mode.
	// We need to order the counts so that QueueArray keeps the most popular enum mode at index 0,
	// the second most popular at index 1, etc.
	SelectionSort(Buffer, en_Modes);
	
	for ( new j = 0; j < en_Modes; j++ )
	{
		QueueArray[j] = Buffer[j][0];
	}
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

/*	Shifts the top value of the mode queue to the end, and
	shifts all of the other values up an index.	*/
UpdateModeQueue(Queue[], size)
{
	new TopIndex = Queue[0];
	
	// i is the index to place the new value into.
	for ( new i = 0; i < size; i++ )
	{
		if ( i = (size-1) )
		{
			Queue[i] = TopIndex;
			break;
		}
		else
		{
			Queue[i] = Queue[i+1];
		}
	}
	
	return;
}

/*	Returns the enum value of the best mode to playe next.
	If no requirements are met for any possible mode, MODE_NONE is returned.*/
ChooseNextMode()
{
	// This is the system for playing a mode:
	//	- Try to set up the current mode in the queue.
	//	- If this mode cannot be played (eg. too few players), make a note of the ID and try the next mode in the queue.
	//	- If the end of the queue is reached, go back to the start.
	//	- If the original mode is reached again, play a default arena around instead (MODE_NONE);
	
	if ( ValidateMode(ModeQueue[0]) ) return ModeQueue[0];
	
	new TopModeInQueue = ModeQueue[0];
	new ModeToPlay = MODE_NONE;
	
	// Only iterate through the required number of times (ie the number of indices ModeQueue has).
	for ( new i = 0; i < (en_Modes-1); i++ )
	{
		// Shift the indices
		UpdateModeQueue(ModeQueue, sizeof(ModeQueue));
		
		// If we've reached our original mode, break with MODE_NONE.
		if ( ModeQueue[0] = TopModeInQueue )
		{
			ModeToPlay = MODE_NONE;
			break;
		}
		
		// Check to see if the new mode can be played
		// If it can, return the mode number.
		if ( ValidateMode(ModeQueue[0]) ) ModeToPlay = ModeQueue[0];
	}
	
	return ModeToPlay;
}

/*	====================
	=== Event  Hooks ===
	====================	*/

/*
	This section contains all the hooks that may be required for different mini-modes.
	If a mode requires a hook, a switch case needs to be made with the mode's enum ID
	which calls the specific function defined by the mode.
	If a hook is not required for a mode, the switch falls down to the default case
	where Plugin_Continue is returned and the hook remains unmodified.
	If the plugin state is STATE_NO_ACTIVITY or STATE_DISABLED, no hooks will run.
	
	The RoundStart hook deals with the primary admin deciding whether or not a mode
	has a minimum number of players. If the minimum player count is not met, the next
	mode in the queue is selected. If no modes can be chosen, a normal round is played
	instead.
	
	The vote for the round after the one that's starting is also called here.
	
	A stalemate SHOULD never occur (since this is Arena), but maybe we should tell it to
	call RoundWin if it does, regardless?
*/

public OnMapStart()
{
	menu_ModeVote = BuildModeVoteMenu;
	
	// Set the first round var so that the round vote is called on the first round.
	b_FirstRound = true;
	
	// Set the NOT_IN_ROUND flag.
	g_PluginState &= STATE_NOT_IN_ROUND;
}

public OnMapEnd()
{
	// Set the NOT_IN_ROUND flag.
	g_PluginState &= STATE_NOT_IN_ROUND;
	
	if ( menu_ModeVote != INVALID_HANDLE )
	{
		CloseHandle(menu_ModeVote);
		menu_ModeVote = INVALID_HANDLE;
	}
	
	// #TODO#: Clean up all modes here, in case the map was changed while in the middle of a round.
}

public Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	if ( (g_PluginState & STATE_NO_ACTIVITY) = STATE_NO_ACTIVITY || (g_PluginState & STATE_DISABLED) = STATE_DISABLED ) return;
	
	// A new round has begun. Clear the NOT_IN_ROUND flag.
	g_PluginState |= ~STATE_NOT_IN_ROUND;
	
	// Find out which mode to play.
	g_CurrentMode = ChooseNextMode();
	
	// Set up the chosen mode.
	SetUpModeRoundStart(g_CurrentMode, event, name, dontBroadcast);
}

public Event_RoundWin(Handle:event, const String:name[], bool:dontBroadcast)
{
	// Set the NOT_IN_ROUND flag.
	g_PluginState &= STATE_NOT_IN_ROUND;
	
	// The round has ended: clean up and reset the mode to none in preparation for choosing at the next round.
	
	// #TODO#: Run the mode cleanup function here.
	// This should clean up any states that are left over from the round mode that has just been played.
	
	// Reset the current mode value after everything has been cleaned up.
	g_CurrentMode = MODE_NONE;
	b_FirstRound = false;
}

/*	====================
	 Handler  Functions 
	====================	*/

/*	Initialises the mode name and description arrays.
	New modes must register their name and description functions here.	*/
NameDescInit()
{
	LaS_SetNameAndDescription();		// Light and Sting
	Wetwork_SetNameAndDescription();	// Wetwork
	Sentries_SetNameAndDescription();	// Sentries
	Targets_SetNameAndDescription();	// Targets
	BossBattle_SetNameAndDescription();	// Boss Battle
	ShieldBash_SetNameAndDescription();	// Shield Bash
	SBombs_SetNameAndDescription();		// Sandvich Bombs
	
	return;
}

/*	Initialises the arrays for minimum player numbers.
	New modes must register their minimum player number functions here.	*/
MinimumPlayersInit()
{
	LaS_MinimumPlayers();
	Wetwork_MinimumPlayers();
	Sentries_MinimumPlayers();
	Targets_MinimumPlayers();
	BossBattle_MinimumPlayers();
	ShieldBash_MinimumPlayers();
	SBombs_MinimumPlayers();
}

/*	Runs the mode validation function for the specified mode.
	Returns true if the mode can be run, or false otherwise.
	New modes must register their validate functions here.
	If a mode is not recognised, the validation will return false.	*/
bool:ValidateMode(mode)
{
	switch (mode)
	{
		case MODE_LIGHT_STING:		return LaS_Validate();
		case MODE_WETWORK:			return Wetwork_Validate();
		case MODE_SENTRIES:			return Sentries_Validate();
		case MODE_TARGETS:			return Targets_Validate();
		case MODE_BOSS_BATTLE:		return BosBattle_Validate();
		case MODE_SHIELD_BASH:		return ShieldBash_Validate();
		case MODE_SANDVICH_BOMBS:	return SBombs_Validate();
		
		default: return false;
	}
}

/*	Runs the correct mode setup having been passed a mode enum value.	*/
SetUpModeRoundStart(mode, Handle:event, const String:name[], bool:dontBroadcast)
{
	switch (mode)
	{
		case MODE_LIGHT_STING:		LaS_RoundStart(event, name, dontBroadcast);
		case MODE_WETWORK:			Wetwork_RoundStart(event, name, dontBroadcast);
		case MODE_SENTRIES:			Sentries_RoundStart(event, name, dontBroadcast);
		case MODE_TARGETS:			Targets_RoundStart(event, name, dontBroadcast);
		case MODE_BOSS_BATTLE:		BossBattle_RoundStart(event, name, dontBroadcast);
		case MODE_SHIELD_BASH:		ShieldBash_RoundStart(event, name, dontBroadcast);
		case MODE_SANDVICH_BOMBS:	SBombs_RoundStart(event, name, dontBroadcast);
	}
	
	return;
}

CleanUpMode(mode)
{
	switch (mode)
	{
		case MODE_LIGHT_STING:		LaS_Cleanup();
		case MODE_WETWORK:			Wetwork_Cleanup();
		case MODE_SENTRIES:			Sentries_Cleanup();
		case MODE_TARGETS:			Targets_Cleanup();
		case MODE_BOSS_BATTLE:		BossBattle_Cleanup();
		case MODE_SHIELD_BASH:		ShieldBash_Cleanup();
		case MODE_SANDVICH_BOMBSH:	SBombs_Cleanup();
	}
}

/*	====================
	= Light and  Sting =
	====================
	Prefix: LaS				*/

LaS_SetNameAndDescription()
{
	Mode_Name_Trans[MODE_LIGHT_STING] = 		"am_name_light_sting";
	Mode_Description_Trans[MODE_LIGHT_STING] =	"am_desc_light_sting";
}

LaS_MinimumPlayers()
{
	Mode_MinimumPlayers[MODE_LIGHT_STING][TEAM_RED-2] = 1;
	Mode_MinimumPlayers[MODE_LIGHT_STING][TEAM_BLUE-2] = 1;
}

/*	Returns true if the mode is able to run.	*/
bool:LaS_Validate()
{
	if ( GetTeamClientCount(TEAM_RED) < Mode_MinimumPlayers[MODE_LIGHT_STING][TEAM_RED-2] ||
		GetTeamClientCount(TEAM_BLUE) < Mode_MinimumPlayers[MODE_LIGHT_STING][TEAM_BLUE-2] ) return false;
	
	return true;
}

/*	Sets up the mode.	*/
LaS_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	// #TODO#
}

/*	Cleans up the mode.	*/
LaS_Cleanup()
{
	// #TODO#
}

/*	====================
	===== Wetwork ======
	====================
	Prefix: Wetwork			*/

Wetwork_SetNameAndDescription()
{
	Mode_Name_Trans[MODE_WETWORK] = 		"am_name_wetwork";
	Mode_Description_Trans[MODE_WETWORK] =	"am_desc_wetwork";
}

Wetwork_MinimumPlayers()
{
	Mode_MinimumPlayers[MODE_WETWORK][TEAM_RED-2] = 1;
	Mode_MinimumPlayers[MODE_WETWORK][TEAM_BLUE-2] = 1;
}

/*	Returns true if the mode is able to run.	*/
bool:Wetwork_Validate()
{
	if ( GetTeamClientCount(TEAM_RED) < Mode_MinimumPlayers[MODE_WETWORK][TEAM_RED-2] ||
		GetTeamClientCount(TEAM_BLUE) < Mode_MinimumPlayers[MODE_WETWORK][TEAM_BLUE-2] ) return false;
	
	return true;
}

/*	Sets up the mode.	*/
Wetwork_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	// #TODO#
}

/*	Cleans up the mode.	*/
Wetwork_Cleanup()
{
	// #TODO#
}

/*	====================
	===== Sentries =====
	====================
	Prefix: Sentries		*/

Sentries_SetNameAndDescription()
{
	Mode_Name_Trans[MODE_SENTRIES] = 		"am_name_sentries";
	Mode_Description_Trans[MODE_SENTRIES] =	"am_desc_sentries";
}

Sentries_MinimumPlayers()
{
	Mode_MinimumPlayers[MODE_SENTRIES][TEAM_RED-2] = 1;
	Mode_MinimumPlayers[MODE_SENTRIES][TEAM_BLUE-2] = 1;
}

/*	Returns true if the mode is able to run.	*/
bool:Sentries_Validate()
{
	if ( GetTeamClientCount(TEAM_RED) < Mode_MinimumPlayers[MODE_SENTRIES][TEAM_RED-2] ||
		GetTeamClientCount(TEAM_BLUE) < Mode_MinimumPlayers[MODE_SENTRIES][TEAM_BLUE-2] ) return false;
	
	return true;
}

/*	Sets up the mode.	*/
Sentries_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	// #TODO#
}

/*	Cleans up the mode.	*/
Sentries_Cleanup()
{
	// #TODO#
}

/*	====================
	===== Targets ======
	====================
	Prefix: Targets		*/

Targets_SetNameAndDescription()
{
	Mode_Name_Trans[MODE_TARGETS] = 		"am_name_targets";
	Mode_Description_Trans[MODE_TARGETS] =	"am_desc_targets";
}

Targets_MinimumPlayers()
{
	Mode_MinimumPlayers[MODE_TARGETS][TEAM_RED-2] = 1;
	Mode_MinimumPlayers[MODE_TARGETS][TEAM_BLUE-2] = 1;
}

/*	Returns true if the mode is able to run.	*/
bool:Targets_Validate()
{
	if ( GetTeamClientCount(TEAM_RED) < Mode_MinimumPlayers[MODE_TARGETS][TEAM_RED-2] ||
		GetTeamClientCount(TEAM_BLUE) < Mode_MinimumPlayers[MODE_TARGETS][TEAM_BLUE-2] ) return false;
	
	return true;
}

/*	Sets up the mode.	*/
Targets_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	// #TODO#
}

/*	Cleans up the mode.	*/
Targets_Cleanup()
{
	// #TODO#
}

/*	====================
	=== Boss Battle ====
	====================
	Prefix: BossBattle		*/

BossBattle_SetNameAndDescription()
{
	Mode_Name_Trans[MODE_BOSS_BATTLE] = 		"am_name_bossbattle";
	Mode_Description_Trans[MODE_BOSS_BATLE] =	"am_desc_bossbattle";
}

BossBattle_MinimumPlayers()
{
	Mode_MinimumPlayers[MODE_BOSS_BATTLE][TEAM_RED-2] = 1;
	Mode_MinimumPlayers[MODE_BOSS_BATTLE][TEAM_BLUE-2] = 1;
}

/*	Returns true if the mode is able to run.	*/
bool:BossBattle_Validate()
{
	if ( GetTeamClientCount(TEAM_RED) < Mode_MinimumPlayers[MODE_BOSS_BATTLE][TEAM_RED-2] ||
		GetTeamClientCount(TEAM_BLUE) < Mode_MinimumPlayers[MODE_BOSS_BATTLE][TEAM_BLUE-2] ) return false;
	
	return true;
}

/*	Sets up the mode.	*/
BossBattle_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	// #TODO#
}

/*	Cleans up the mode.	*/
BossBattle_Cleanup()
{
	// #TODO#
}

/*	====================
	=== Shield Bash ====
	====================
	Prefix: ShieldBash		*/

ShieldBash_SetNameAndDescription()
{
	Mode_Name_Trans[MODE_SHIELD_BASH] = 		"am_name_shieldbash";
	Mode_Description_Trans[MODE_SHIELD_BASH] =	"am_desc_shieldbash";
}

ShieldBash_MinimumPlayers()
{
	Mode_MinimumPlayers[MODE_SHIELD_BASH][TEAM_RED-2] = 1;
	Mode_MinimumPlayers[MODE_SHIELD_BASH][TEAM_BLUE-2] = 1;
}

/*	Returns true if the mode is able to run.	*/
bool:ShieldBash_Validate()
{
	if ( GetTeamClientCount(TEAM_RED) < Mode_MinimumPlayers[MODE_SHIELD_BASH][TEAM_RED-2] ||
		GetTeamClientCount(TEAM_BLUE) < Mode_MinimumPlayers[MODE_SHIELD_BASH][TEAM_BLUE-2] ) return false;
	
	return true;
}

/*	Sets up the mode.	*/
ShieldBash_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	// #TODO#
}

/*	Cleans up the mode.	*/
ShieldBash_Cleanup()
{
	// #TODO#
}

/*	====================
	== Sandvich Bombs ==
	====================
	Prefix: SBombs		*/

SBombs_SetNameAndDescription()
{
	Mode_Name_Trans[MODE_SANDVICH_BOMBS] = 			"am_name_sandvich_bombs";
	Mode_Description_Trans[MODE_SANDVICH_BOMBS] =	"am_desc_sandvich_bombs";
}

SBombs_MinimumPlayers()
{
	Mode_MinimumPlayers[MODE_SANDVICH_BOMBS][TEAM_RED-2] = 1;
	Mode_MinimumPlayers[MODE_SANDVICH_BOMBS][TEAM_BLUE-2] = 1;
}

/*	Returns true if the mode is able to run.	*/
bool:SBombs_Validate()
{
	if ( GetTeamClientCount(TEAM_RED) < Mode_MinimumPlayers[MODE_SANDVICH_BOMBS][TEAM_RED-2] ||
		GetTeamClientCount(TEAM_BLUE) < Mode_MinimumPlayers[MODE_SANDVICH_BOMBS][TEAM_BLUE-2] ) return false;
	
	return true;
}

/*	Sets up the mode.	*/
SBombs_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	// #TODO#
}

/*	Cleans up the mode.	*/
SBombs_Cleanup()
{
	// #TODO#
}