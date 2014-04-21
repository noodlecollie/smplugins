/*
  _______ ______ ___    ____  _       _                            _ 
 |__   __|  ____|__ \  |  _ \(_)     | |                          | |
    | |  | |__     ) | | |_) |_  ___ | |__   __ _ ______ _ _ __ __| |
    | |  |  __|   / /  |  _ <| |/ _ \| '_ \ / _` |_  / _` | '__/ _` |
    | |  | |     / /_  | |_) | | (_) | | | | (_| |/ / (_| | | | (_| |
    |_|  |_|    |____| |____/|_|\___/|_| |_|\__,_/___\__,_|_|  \__,_|
	
	[X6] Herbius, 16th April 2012
*/

#include <sourcemod>
#include <tf2>
#include <sdktools>

#pragma semicolon 1

#define DONTCOMPILE	0
#define DEVELOPER	1

// Plugin defines
#define PLUGIN_NAME			"TF Biohazard"
#define PLUGIN_AUTHOR		"[X6] Herbius"
#define PLUGIN_DESCRIPTION	"Hold off the zombies to win the round!"
#define PLUGIN_VERSION		"0.0.0.1"
#define PLUGIN_URL			"http://x6herbius.com/"

// State flags
// Control what aspects of the plugin will run.
#define STATE_DISABLED		8	// Plugin is disabled via convar. No gameplay-modifying activity will occur.
#define STATE_FEW_PLAYERS	4	// There are not enough players to begin a game.
#define STATE_NOT_IN_ROUND	2	// Round has ended or has not yet begun.
#define STATE_AWAITING		1	// A round has started and the Blue team is empty because no-one has yet become a zombie.

// Debug flags
// Used with tfbh_debug to display debug messages to the server console.
#define DEBUG_GENERAL		1	// General debugging.
#define DEBUG_TEAMCHANGE	2	// Debugging team changes.

// Cleanup flags
// Pass one of these to Cleanup() to specify what to clean up.
// This is mainly to keep things tidy and avoid doing these operations
// all over the code.
#define CLEANUP_ROUNDEND	1
#define CLEANUP_FIRSTSTART	2
#define CLEANUP_ENDALL		3
#define CLEANUP_ROUNDSTART	4
#define CLEANUP_MAPSTART	5
#define CLEANUP_MAPEND		6

// Team integers
// Used with ChangeClientTeam() etc.
// I know there are proper enums but I got used to using this way and it works.
#define TEAM_INVALID		-1
#define TEAM_UNASSIGNED		0
#define TEAM_SPECTATOR		1
#define TEAM_RED			2
#define TEAM_BLUE			3

// Other defines

// Change the following to specify what the plugin should change the balancing
// CVars to. Must be integers.
#define DES_UNBALANCE		0	// Desired value for mp_teams_unbalance_limit
#define DES_AUTOBALANCE		0	// Desired value for mp_autoteambalance
#define DES_SCRAMBLE		0	// Desired value for mp_scrambleteams_auto

new g_PluginState;		// Holds the global state of the plugin.
new g_Disconnect;		// Sidesteps team count issues by tracking the index of a disconnecting player. See Event_TeamsChange.
new bool:b_AllowChange;	// If true, team changes will not be blocked.

// Player data
new g_userIDMap[MAXPLAYERS];					// For a userID at index n, this player's data will be found in index n of the rest of the data arrays.
												// If index n < 1, index n in data arrays is free for use.
new bool:g_Zombie[MAXPLAYERS] = {true, ...};	// True if the player is infected, false otherwise. Should start true so that Blue is the team new players join into.

// ConVars
new Handle:cv_PluginEnabled = INVALID_HANDLE;	// Enables or disables the plugin.
new Handle:cv_Debug = INVALID_HANDLE;			// Enables or disables debugging using debug flags.

// Stock ConVars and values.
// We keep track of the server's values for these ConVars when the plugin is loaded but not active.
// When they change, we update their values in the variables below.
// When the plugin is active, we set all of the ConVars to 0 (because team balancing will get in the way).
// If the plugin is unloaded, we can then set the ConVars back to the values they were before we loaded.
new Handle:cv_Unbalance = INVALID_HANDLE;		// Handle to mp_teams_unbalance_limit.
new Handle:cv_Autobalance = INVALID_HANDLE;		// Handle to mp_autoteambalance.
new Handle:cv_Scramble = INVALID_HANDLE;		// Handle to mp_scrambleteams_auto.
new cvdef_Unbalance;							// Original value of mp_teams_unbalance_limit.
new cvdef_Autobalance;							// Original value of mp_autoteambalance.
new cvdef_Scramble;								// Original value of mp_scrambleteams_auto.

public Plugin:myinfo = 
{
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = PLUGIN_URL
}

public OnPluginStart()
{
	LogMessage("== %s v%s ==", PLUGIN_NAME, PLUGIN_VERSION);
	
	LoadTranslations("TFBiohazard/TFBiohazard_phrases");
	LoadTranslations("common.phrases");
	AutoExecConfig(true, "TFBiohazard", "sourcemod/TFBiohazard");
	
	// Plugin version convar
	CreateConVar("tfbh_version", PLUGIN_VERSION, "Plugin version.", FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_DONTRECORD);
	
	// ConVars
	cv_PluginEnabled  = CreateConVar("tfbh_enabled",
										"1",
										"Enables or disables the plugin.",
										FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
										true,
										0.0,
										true,
										1.0);

	cv_Debug  = CreateConVar("tfbh_debug",
										"3",
										"Enables or disables debugging using debug flags.",
										FCVAR_PLUGIN | FCVAR_ARCHIVE | FCVAR_DONTRECORD,
										true,
										0.0);
	
	cv_Unbalance = FindConVar("mp_teams_unbalance_limit");
	cv_Autobalance = FindConVar("mp_autoteambalance");
	cv_Scramble = FindConVar("mp_scrambleteams_auto");
	
	HookEventEx("teamplay_round_start",		Event_RoundStart,		EventHookMode_Post);
	HookEventEx("teamplay_round_win",		Event_RoundWin,			EventHookMode_Post);
	HookEventEx("teamplay_round_stalemate",	Event_RoundStalemate,	EventHookMode_Post);
	HookEventEx("player_team",				Event_TeamsChange,		EventHookMode_Post);
	HookEventEx("teamplay_setup_finished",	Event_SetupFinished,	EventHookMode_Post);
	
	AddCommandListener(TeamChange, "jointeam");	// For blocking team change commands.
	
	HookConVarChange(cv_PluginEnabled,	CvarChange);
	HookConVarChange(cv_Unbalance,		CvarChange);
	HookConVarChange(cv_Autobalance,	CvarChange);
	HookConVarChange(cv_Scramble,		CvarChange);
	
	RegConsoleCmd("tfbh_debug_showdata", Debug_ShowData, "Outputs player data arrays to the console.", FCVAR_PLUGIN | FCVAR_CHEAT);
	
	if ( GetConVarInt(cv_Debug) > 0 )
	{
		LogMessage("Plugin is starting with debug cvar enabled! Reset this before release!");
	}
	
	#if DEVELOPER == 1
	LogMessage("DEVELOPER flag set! Reset this before release!");
	#endif
	
	// If we're not enabled, don't set anything up.
	if ( g_PluginState & STATE_DISABLED == STATE_DISABLED )
	{
		LogMessage("Plugin starting disabled.");
		return;
	}
	
	// If the server is not yet processing, flag NOT_IN_ROUND and FEW_PLAYERS.
	if ( !IsServerProcessing() )
	{
		g_PluginState |= STATE_NOT_IN_ROUND;
		g_PluginState |= STATE_FEW_PLAYERS;
	}
	
	// Run first start initialisation.
	Cleanup(CLEANUP_FIRSTSTART);
}

public OnPluginEnd()
{
	Cleanup(CLEANUP_ENDALL);
}

/*	Checks which ConVar has changed and performs the relevant actions.	*/
public CvarChange( Handle:convar, const String:oldValue[], const String:newValue[])
{
	if ( convar == cv_PluginEnabled ) PluginEnabledStateChanged(GetConVarBool(cv_PluginEnabled));
	
	if ( convar == cv_Unbalance )
	{
		// Don't change these values if we're enabled.
		if ( g_PluginState & STATE_DISABLED != STATE_DISABLED )
		{
			if ( StringToInt(newValue) != DES_UNBALANCE )
			{
				LogMessage("mp_teams_unbalance_limit changed while plugin is active, blocking change.");
				ServerCommand("mp_teams_unbalance_limit %d", DES_UNBALANCE);
			}
		}
		// If we're not enabled, record the new value for us to return to when the plugin is unloaded.
		else
		{
			cvdef_Unbalance == StringToInt(newValue);
			LogMessage("mp_teams_unbalance_limit changed, value stored: %d", cvdef_Unbalance);
		}
	}
	
	if ( convar == cv_Autobalance )
	{
		// Don't change these values if we're enabled.
		if ( g_PluginState & STATE_DISABLED != STATE_DISABLED )
		{
			if ( StringToInt(newValue) != DES_AUTOBALANCE )
			{
				LogMessage("mp_autoteambalance changed while plugin is active, blocking change.");
				ServerCommand("mp_autoteambalance %d", DES_AUTOBALANCE);
			}
		}
		// If we're not enabled, record the new value for us to return to when the plugin is unloaded.
		else
		{
			cvdef_Autobalance == StringToInt(newValue);
			LogMessage("mp_autoteambalance changed, value stored: %d", cvdef_Autobalance);
		}
	}
	
	if ( convar == cv_Scramble )
	{
		// Don't change these values if we're enabled.
		if ( g_PluginState & STATE_DISABLED != STATE_DISABLED )
		{
			if ( StringToInt(newValue) != DES_SCRAMBLE )
			{
				LogMessage("mp_scrambleteams_auto changed while plugin is active, blocking change.");
				ServerCommand("mp_scrambleteams_auto %d", DES_SCRAMBLE);
			}
		}
		// If we're not enabled, record the new value for us to return to when the plugin is unloaded.
		else
		{
			cvdef_Scramble == StringToInt(newValue);
			LogMessage("mp_scrambleteams_auto changed, value stored: %d", cvdef_Scramble);
		}
	}
}

/*	Sets the enabled/disabled state of the plugin.
	Passing true enables, false disables.	*/
PluginEnabledStateChanged(bool:b_state)
{
	if ( b_state )
	{
		// If we're already enabled, do nothing.
		if ( g_PluginState & STATE_DISABLED != STATE_DISABLED ) return;
			
		g_PluginState &= ~STATE_DISABLED;	// Clear the disabled flag.
		Cleanup(CLEANUP_FIRSTSTART);		// Initialise values.
	}
	else
	{
		// If we're already disabled, do nothing.
		if ( g_PluginState & STATE_DISABLED == STATE_DISABLED ) return;
		
		g_PluginState |= STATE_DISABLED;	// Set the disabled flag.
		Cleanup(CLEANUP_ENDALL);			// Clean up.
	}
}

// =======================================================================================
// ===================================== Event hooks =====================================
// =======================================================================================

/*	Called when a round starts.	*/
public Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	// Clear the NOT_IN_ROUND flag.
	g_PluginState &= ~STATE_NOT_IN_ROUND;
	
	Cleanup(CLEANUP_ROUNDSTART);
	
	// Check whether the player counts are adequate.
	if ( PlayerCountAdequate() ) g_PluginState &= ~STATE_FEW_PLAYERS;
	else g_PluginState |= STATE_FEW_PLAYERS;
	
	if ( (g_PluginState & STATE_DISABLED == STATE_DISABLED) ||
			(g_PluginState & STATE_FEW_PLAYERS == STATE_FEW_PLAYERS) ) return;
	
	// Plugin is enabled.
	
	new cvDebug = GetConVarInt(cv_Debug);
	
	// Set the AWAITING flag.
	g_PluginState |= STATE_AWAITING;
	
	// Allow team changes to Red.
	b_AllowChange = true;
	
	// Move everyone on Blue to the Red team.
	for ( new i = 1; i <= MaxClients; i++ )
	{
		if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Checking client %d...", i);
		
		if ( IsClientConnected(i) )
		{
			if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Client %d (%N) is connected.", i, i);
			
			g_Zombie[DataIndexForUserId(GetClientUserId(i))] = false;	// Mark the player as not being a zombie.
			
			if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Cleared zombie flag for client %N.", i);
			
			if ( IsClientInGame(i) && GetClientTeam(i) == TEAM_BLUE )	// If the player is on Blue:
			{
				if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Changing %N to Red.", i);
				
				ChangeClientTeam(i, TEAM_RED);							// Change the player to Red.
			}
		}
	}
	
	// Finished adding players to the Red team.
	b_AllowChange = false;
}

/*	Called when a round is won.	*/
public Event_RoundWin(Handle:event, const String:name[], bool:dontBroadcast)
{
	Event_RoundEnd();
}

/*	Called when a round is drawn.	*/
public Event_RoundStalemate(Handle:event, const String:name[], bool:dontBroadcast)
{
	Event_RoundEnd();
}

public OnMapStart()
{
	// Set the NOT_IN_ROUND flag.
	g_PluginState |= STATE_NOT_IN_ROUND;
	
	// Set the FEW_PLAYERS flag.
	g_PluginState |= STATE_FEW_PLAYERS;
	
	Cleanup(CLEANUP_MAPSTART);
}

public OnMapEnd()
{
	// Set the NOT_IN_ROUND flag.
	g_PluginState |= STATE_NOT_IN_ROUND;
	
	// Set the FEW_PLAYERS flag.
	g_PluginState |= STATE_FEW_PLAYERS;
	
	Cleanup(CLEANUP_MAPEND);
}

/*	Called when a player disconnects.
	This is called BEFORE TeamsChange below.	*/
public Event_Disconnect(Handle:event, const String:name[], bool:dontBroadcast)
{
	g_Disconnect = GetClientOfUserId(GetEventInt(event, "userid"));
}

public Event_SetupFinished(Handle:event, const String:name[], bool:dontBroadcast)
{
	// If the plugin is disabled, there are not enough players or we are not in a round, return;
	if ( (g_PluginState & STATE_DISABLED == STATE_DISABLED) ||
			(g_PluginState & STATE_FEW_PLAYERS == STATE_FEW_PLAYERS) ||
			(g_PluginState & STATE_NOT_IN_ROUND == STATE_NOT_IN_ROUND)	) return;
	
	new cvDebug = GetConVarInt(cv_Debug);
	
	// A round is currently being played. Infect some people, proportional to the amount we have on the server.
	// Calculate the number of zombies we need. There should be 1 zombie for every group of up to 8 people.
	// Divide the number of players on Red by 8 and round up.
	
	// Find how many players are alive on Red.
	new redTeam;
	for ( new i = 1; i <= MaxClients; i++ )
	{
		if ( IsClientInGame(i) && GetClientTeam(i) == TEAM_RED && IsPlayerAlive(i) ) redTeam++;
	}
	
	// Decide how many zombies should spawn.
	new nZombies = RoundToCeil(Float:redTeam/8);
	
	// Build an array of the Red players.
	decl players[redTeam];
	new pos;
	
	for ( new i = 1; i <= MaxClients; i++ )
	{
		if ( IsClientInGame(i) && GetClientTeam(i) == TEAM_RED && IsPlayerAlive(i) )
		{
			players[pos] = i;
			pos++;
		}
	}
	
	if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE )
	{
		LogMessage("Before sort:");
		
		for ( new i = 0; i < redTeam; i++ )
		{
			LogMessage("Array index %d - %d %N", i, players[i], players[i]);
		}
	}
	
	// Randomise the array.
	SortIntegers(players, redTeam, Sort_Random);
	
	// Due to a SourceMod bug, the first element of the array will always remain unsorted.
	// We correct this here.
	
	new slotToSwap = GetRandomInt(0, redTeam-1);	// Choose a random slot to swap between.
	
	if ( slotToSwap > 0 )	// If the slot is 0, don't bother doing anything else.
	{
		new temp = players[0]							// Make a note of the index in the first element.
		players[0] = players[slotToSwap];				// Put the data from the chosen slot into the first slot.
		players[slotToSwap] = temp;						// Put the value in temp back into the random slot.
	}
	
	if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE )
	{
		LogMessage("After sort:");
		
		for ( new i = 0; i < redTeam; i++ )
		{
			LogMessage("Array index %d - %d %N", i, players[i], players[i]);
		}
	}
	
	// Choose clients from the top of the array.
	for ( new i = 0; i < nZombies; i++ )
	{
		if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Client %N chosen to be zombified.", players[i]);
		
		SetEntProp(players[i], Prop_Send, "m_lifeState", 2);				// Make sure the client won't die when we change their team.
		ChangeClientTeam(players[i], TEAM_BLUE);							// Change them to Blue.
		SetEntProp(players[i], Prop_Send, "m_lifeState", 0);				// Reset the lifestate variable.
		g_Zombie[DataIndexForUserId(GetClientUserId(players[i]))] = true;	// Mark them as a zombie.
		TF2_RemoveWeaponSlot(players[i], 0);								// Remove their primary weapon.
		TF2_RemoveWeaponSlot(players[i], 1);								// Remove their secondary weapon.
	}
	
	// Clear the AWAITING flag. This will ensure that if Blue drops to 0 players Red will win the game.
	g_PluginState &= ~STATE_AWAITING;
}

/*	Called when a player changes team.	*/
public Event_TeamsChange(Handle:event, const String:name[], bool:dontBroadcast)
{
	if ( (g_PluginState & STATE_DISABLED == STATE_DISABLED) ||
			(g_PluginState & STATE_NOT_IN_ROUND == STATE_NOT_IN_ROUND) )
	{
		// Clear g_Disconnect just in case.
		g_Disconnect = 0;
		
		return;
	}
	
	// I've never liked team change hooks.
	
	// If the plugin is disabled or we're not in a round, ignore team changes.
	// If there are not enough players to begin a game, allow team changes but monitor team counts.
	// When the team counts go over the required threshold, end the round.
	
	// After team change is complete, check team numbers. If either Red or Blue has <1 player, declare a win.
	// This means that players can leave Red or Blue to go spec or leave the game, at the expense of their team.
	
	// Using GetTeamClientCount in this hook reports the number of clients as it was BEFORE the change, even with HookMode_Post.
	// To get around this we need to build up what the teams will look like after the change.
	
	new userid = GetEventInt(event, "userid");
	new client = GetClientOfUserId(userid);
	new newTeam = GetEventInt(event, "team");
	new oldTeam = GetEventInt(event, "oldteam");
	new bool:disconnect = GetEventBool(event, "disconnect");
	
	new redTeam = GetTeamClientCount(TEAM_RED);		// These will give us the team counts BEFORE the client has switched.
	new blueTeam = GetTeamClientCount(TEAM_BLUE);
	
	new cvDebug = GetConVarInt(cv_Debug);
	
	if ( disconnect ) 			// If the team change happened because the client was disconnecting:
	{
		if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Client %N is disconnecting.", client);
		
								// Note that, if disconnect == true, the userid will point to the index 0.
								// We fix this here.
		client = g_Disconnect;	// This is retrieved from player_disconnect, which is fired before player_team.
		g_Disconnect = 0;
		
								// If disconnected, this means the team he was on will lose a player and the other teams will stay the same.
		switch (oldTeam)
		{
			case TEAM_RED:
			{
				if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Client %N is leaving team Red.", client);
				redTeam--;
			}
			
			case TEAM_BLUE:
			{
				if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Client %N is leaving team Blue.", client);
				blueTeam--;
			}
		}
	}
	else						// The client is not disconnecting.
	{
		if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Client %N is not disconnecting.", client);
		
								// Decrease the count for the team the client is leaving.
		switch (oldTeam)
		{
			case TEAM_RED:
			{
				if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Client %N is leaving team Red.", client);
				redTeam--;
			}
			
			case TEAM_BLUE:
			{
				if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Client %N is leaving team Blue.", client);
				blueTeam--;
			}
		}
		
								// Increase the count for the team the client is joining.
		switch (newTeam)
		{
			case TEAM_RED:
			{
				if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Client %N is joining team Red.", client);
				redTeam++;
			}
			
			case TEAM_BLUE:
			{
				if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Client %N is joining team Blue.", client);
				blueTeam++;
			}
		}
	}
	
	// Team counts after the change are now held in redTeam and blueTeam.
	new total = redTeam + blueTeam;
	
	if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Team counts after change - Red: %d, Blue: %d, Total: %d", redTeam, blueTeam, total);
	
	// If there were not enough players but we have just broken the threshold, end the round in a stalemate.
	if ( g_PluginState & STATE_FEW_PLAYERS == STATE_FEW_PLAYERS )
	{
		if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Player count was below the threshold.");
		
		if ( total > 1 )
		{
			if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Player count is now above the threshold!");
			
			g_PluginState &= ~STATE_FEW_PLAYERS;	// Clear the FEW_PLAYERS flag.
			RoundWinWithCleanup();
			
			return;
		}
		else
		{
			if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Player count is still below the threshold.");
			
			return;
		}
	}
	// If there were enough players but now there are not, win the round for the team which has the remaining player.
	else if ( (g_PluginState & STATE_FEW_PLAYERS != STATE_FEW_PLAYERS) && total <= 1 )
	{
		if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Player count is now below the threshold.");
		
		if		( redTeam > 0 )		RoundWinWithCleanup(TEAM_RED);
		else if	( blueTeam > 0 )	RoundWinWithCleanup(TEAM_BLUE);
		else						RoundWinWithCleanup();
		
		return;
	}
	
	if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Player count is still above the threshold.");
	
	// If the player is marked as a zombie but is changing to a team that is not Blue, clear the flag.
	// Ignore if the client is disconnecting, since this is dealt with elsewhere.
	if ( !disconnect && g_Zombie[DataIndexForUserId(userid)] && newTeam != TEAM_BLUE ) g_Zombie[DataIndexForUserId(userid)] = false;
	
	// Check whether Red is out of players.
	
	if ( redTeam < 1 )
	{
		if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Red team is out of players.");
		RoundWinWithCleanup(TEAM_BLUE);
	}
	// Check whether Blue is out of players.
	// Make sure the AWAITING flag is not set, otherwise we'll end the round while players are being swapped back to Red.
	else if ( blueTeam < 1 && (g_PluginState & STATE_AWAITING != STATE_AWAITING) )
	{
		if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Blue team is out of players.");
		RoundWinWithCleanup(TEAM_RED);
	}
}

/*	Used to block players changing team when they aren't allowed.
	Possible arguments are red, blue, auto or spectate.
	GetTeamClientCount returns the team values from before the change.*/
public Action:TeamChange(client, const String:command[], argc)
{
	// Don't block team changes if there are any abnormal states.
	if ( (g_PluginState & STATE_DISABLED == STATE_DISABLED) ||
			(g_PluginState & STATE_FEW_PLAYERS == STATE_FEW_PLAYERS) ||
			(g_PluginState & STATE_NOT_IN_ROUND == STATE_NOT_IN_ROUND)	) return Plugin_Continue;
	
	new cvDebug = GetConVarInt(cv_Debug);
	
	if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE )
	{
		decl String:argument[512];
		GetCmdArgString(argument, sizeof(argument));
		LogMessage ("Client %N, command %s, args %s, red %d, blue %d", client, command, argument, GetTeamClientCount(TEAM_RED), GetTeamClientCount(TEAM_BLUE));
	}
	
	// We can't get the player's current team because GetClientTeam returns -1.
	// Therefore we just need to block players from joining Red (or using auto-assign) if a round is in progress
	// and if b_AllowChange is false.
	// We also need to block players changing to Blue if they are not a zombie.
	
	if ( b_AllowChange ) return Plugin_Continue;
	
	new String:arg[16];
	GetCmdArg(1, arg, sizeof(arg));
	if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Arg: %s", arg);
	
	if ( StrContains(arg, "red", false) != -1 || StrContains(arg, "auto", false) != -1 )
	{
		if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Arg contains red or auto, blocking change.");
		return Plugin_Handled;
	}
	else if ( StrContains(arg, "blue", false) != 1 && !g_Zombie[DataIndexForUserId(GetClientUserId(client))] )
	{
		if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Arg contains blue and %N is not a zombie, blocking change.", client);
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

/*	Called when a client connects.	*/
public OnClientConnected(client)
{
	// Give the client a slot in the data arrays.
	new index = FindFreeDataIndex();
	if ( index < 0 )
	{
		LogError("MAJOR ERROR: Cannot find a free data index for client %N (MaxClients %d, MAXPLAYERS %d).", client, MaxClients, MAXPLAYERS);
		return;
	}
	
	g_userIDMap[index] = GetClientUserId(client);	// Register the client's userID.
	ClearAllArrayDataForIndex(index);				// Clear all the other data arrays at the specified index.
	
	// The above will set data to default values and so should be harmless,
	// especially since we want to ensure that if a client is in the server, they will have a slot in the data arrays.
	// Anything further should only occur if the plugin is enabled.
	if ( g_PluginState & STATE_DISABLED == STATE_DISABLED ) return;
	
	
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);	// Hooks when the client takes damage.
}

/*	Called when a client disconnects.	*/
public OnClientDisconnect(client)
{
	// Clear the client's data arrays.
	ClearAllDataForPlayer(GetClientUserId(client));
}

/*	Called when a client is about to connect.	*/
/*public OnClientConnect(client, String:rejectmsg[], maxlen)
{
	// #TODO#: Put code here to reject bots if a ConVar is set.
}*/

/*	Called when a hooked client takes damage.	*/
public Action:OnTakeDamage(client, &attacker, &inflictor, &Float:damage, &damagetype, &weapon, Float:damageForce[3], Float:damagePosition[3])
{
	// Don't bother checking damage values if we're not in a valid round.
	if ( g_PluginState & STATE_DISABLED == STATE_DISABLED ||
			g_PluginState & STATE_NOT_IN_ROUND == STATE_NOT_IN_ROUND ||
			g_PluginState & STATE_FEW_PLAYERS == STATE_FEW_PLAYERS ) return;
	
	// If the client is on Red, the attacker is on Blue and is a zombie, and the damage has killed the client,
	// change the client to Blue and refill their health
	if ( GetClientTeam(client) == TEAM_RED && GetClientTeam(attacker) == TEAM_BLUE && g_Zombie[DataIndexForUserId(GetClientUserId(attacker))] )
}

// =======================================================================================
// =================================== Custom functions ==================================
// =======================================================================================

/*	Keeps all the functions common to RoundWin and RoundStalemate together.	*/
Event_RoundEnd()
{
	// Set the NOT_IN_ROUND flag.
	g_PluginState |= STATE_NOT_IN_ROUND;
	
	Cleanup(CLEANUP_ROUNDEND);
	
	if ( (g_PluginState & STATE_DISABLED) == STATE_DISABLED ) return;
}

/*	Wins the round for the specified team.	*/
stock RoundWin(team = 0)
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

/*	Ends the round and cleans up.	*/
stock RoundWinWithCleanup(team = 0)
{
	RoundWin(team);
	Cleanup(CLEANUP_ROUNDEND);
}

stock FindEntityByClassname2(startEnt, const String:classname[])
{
	/* If startEnt isn't valid shifting it back to the nearest valid one */
	while (startEnt > -1 && !IsValidEntity(startEnt)) startEnt--;
	
	return FindEntityByClassname(startEnt, classname);
}

stock Cleanup(mode)
{
	switch (mode)
	{
		case CLEANUP_ROUNDEND:
		{
			// #TODO#
		}
		
		case CLEANUP_FIRSTSTART:
		{
			if ( g_PluginState & STATE_DISABLED == STATE_DISABLED )	// Don't set up if we're not enabled.
			{
				LogMessage("Warning! CLEANUP_FIRSTSTART called when plugin is disabled!");
				return;
			}
			
			// Store current values for balance cvars
			if ( cv_Unbalance != INVALID_HANDLE )
			{
				cvdef_Unbalance = GetConVarInt(cv_Unbalance);
				LogMessage("Stored value for mp_teams_unbalance_limit: %d", cvdef_Unbalance);
			}
			
			if ( cv_Autobalance != INVALID_HANDLE )
			{
				cvdef_Autobalance = GetConVarInt(cv_Autobalance);
				LogMessage("Stored value for mp_autoteambalance: %d", cvdef_Autobalance);
			}
			
			if ( cv_Scramble != INVALID_HANDLE )
			{
				cvdef_Scramble = GetConVarInt(cv_Scramble);
				LogMessage("Stored value for mp_scrambleteams_auto: %d", cvdef_Scramble);
			}
			
			// Set balance cvars to desired values
			ServerCommand("mp_teams_unbalance_limit %d", DES_UNBALANCE);
			ServerCommand("mp_autoteambalance %d", DES_AUTOBALANCE);
			ServerCommand("mp_scrambleteams_auto %d", DES_SCRAMBLE);
			
			// If a round is currently in progress, end it.
			if ( g_PluginState & STATE_NOT_IN_ROUND != STATE_NOT_IN_ROUND )
			{
				RoundWinWithCleanup();
			}
			
			// Go through each player who is connected and set up their data.
			for ( new i = 1; i <= MaxClients; i++ )
			{
				if ( IsClientConnected(i) )
				{
					// Give the client a slot in the data arrays.
					new index = FindFreeDataIndex();
					if ( index < 0 )
					{
						LogError("MAJOR ERROR: Cannot find a free data index for client %N (MaxClients %d, MAXPLAYERS %d).", i, MaxClients, MAXPLAYERS);
						return;
					}
					
					g_userIDMap[index] = GetClientUserId(i);		// Register the client's userID.
					ClearAllArrayDataForIndex(index);				// Clear all the other data arrays at the specified index.
					SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);	// Hooks when the client takes damage.
				}
			}
			
			// Check player counts.
			if ( PlayerCountAdequate() ) g_PluginState &= ~STATE_FEW_PLAYERS;
			else g_PluginState |= STATE_FEW_PLAYERS;
		}
		
		case CLEANUP_ENDALL:	// Called when the plugin is unloaded or is disabled.
		{
			// Reset balance cvars
			ServerCommand("mp_teams_unbalance_limit %d", cvdef_Unbalance);
			ServerCommand("mp_autoteambalance %d", cvdef_Autobalance);
			ServerCommand("mp_scrambleteams_auto %d", cvdef_Scramble);
			
			// End the current round in progress.
			RoundWin();
		}
		
		case CLEANUP_ROUNDSTART:	// Called even if plugin is disabled, so don't put anything important here.
		{
			// #TODO#
		}
		
		case CLEANUP_MAPSTART:
		{
			// Reset all data arrays.
			for ( new i = 0; i < MAXPLAYERS; i++ )
			{
				ClearAllArrayDataForIndex(i, true);
			}
		}
		
		case CLEANUP_MAPEND:
		{
			// Reset all data arrays.
			for ( new i = 0; i < MAXPLAYERS; i++ )
			{
				ClearAllArrayDataForIndex(i, true);
			}
		}
	}
}

/*	Clears the player data arrays for the player with the specified userID and sets them to their default values.	*/
stock ClearAllDataForPlayer(userid)
{
	new index = DataIndexForUserId(userid);
	if ( index == -1 ) return;
	
	ClearAllArrayDataForIndex(index, true);
}

/*	Clears all the global array data at the specified index to default values.
	if userid is true, also clears the userID array.	*/
stock ClearAllArrayDataForIndex(index, bool:userid = false)
{
	if ( index < 0 || index >= MAXPLAYERS )
	{
		LogError("Cannot clear player data, index %d invalid.", index);
		return;
	}
	
	if ( userid ) g_userIDMap[index] = 0;
	
	g_Zombie[index] = true;
}

/*	Returns true if there are enough players to play a match.
	Own function for convenience.	*/
stock bool:PlayerCountAdequate()
{
	if ( !IsServerProcessing() ) return false;
	else if ( GetTeamClientCount(TEAM_RED) + GetTeamClientCount(TEAM_BLUE) > 1 ) return true;
	else return false;
}

/*	Returns the array index to use in the data arrays for a player with a given userID, or -1 on error.	*/
stock DataIndexForUserId(userid)
{
	if ( GetClientOfUserId(userid) < 1 )
	{
		LogError("UserID %d is invalid!", userid);
		return -1;
	}
	
	// Look through the userID mapping array and return the index number at which the given userID matches.
	for ( new i = 0; i < MAXPLAYERS; i++ )
	{
		if ( g_userIDMap[i] == userid ) return i;
	}
	
	// If no match, return -1;
	return -1;
}

/*	Finds the next free slot in the data arrays. Returns -1 on error.	*/
stock FindFreeDataIndex()
{
	for ( new i = 0; i < MAXPLAYERS; i++ )
	{
		if ( g_userIDMap[i] < 1 ) return i;
	}
	
	return -1;
}

/*	Outputs player data arrays to the console.	*/
public Action:Debug_ShowData(client, args)
{
	if ( client < 0 ) return Plugin_Handled;
	else if ( client > 0 && !IsClientInGame(client) ) return Plugin_Handled;
	
	for (new i = 0; i < MAXPLAYERS; i++ )
	{
		PrintToConsole(client, "%d: UserID %d, zombie %d", i, g_userIDMap[i], g_Zombie[i]);
	}
	
	return Plugin_Handled;
}