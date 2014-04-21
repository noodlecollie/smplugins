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
#include <sdkhooks>
#include <tf2_stocks>

#pragma semicolon 1

#define DONTCOMPILE	0
#define DEVELOPER	1
#define MEZOMBIE	0

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
#define DEBUG_HEALTH		4	// Debugging health calculations.
#define DEBUG_DAMAGE		8	// Debugging OnTakeDamage hook.
#define DEBUG_DATA			16	// Debugging data arrays.
#define DEBUG_CRASHES		32	// Debugging crashes

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

// Building destroy flags
#define BUILD_SENTRY		4
#define BUILD_DISPENSER		2
#define BUILD_TELEPORTER	1

// Weapon slots
#define SLOT_PRIMARY		0
#define SLOT_SECONDARY		1
#define SLOT_MELEE			2
#define SLOT_BUILD			3
#define SLOT_DESTROY		4
#define SLOT_FIVE			5	// This one's currently unknown.

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
new Float:g_MaxHealth[MAXPLAYERS];				// Records a client's max health. Only taken into account if they are flagged as a zombie.
new Float:g_Health[MAXPLAYERS];					// Records a client's health. Only taken into account if they are flagged as a zombie.

// ConVars
new Handle:cv_PluginEnabled = INVALID_HANDLE;	// Enables or disables the plugin.
new Handle:cv_Debug = INVALID_HANDLE;			// Enables or disables debugging using debug flags.
new Handle:cv_Pushback = INVALID_HANDLE;		// General multiplier for zombie pushback.
new Handle:cv_ZHMin = INVALID_HANDLE;			// Minimum zombie health multiplier (against 1 survivor).
new Handle:cv_ZHMax = INVALID_HANDLE;			// Maximum zombie health multiplier (against 24 survivors).
new Handle:cv_ZombieRatio = INVALID_HANDLE;		// At the beginning of a round, the number of zombies that spawn is the quotient of (Red players/this value), rounded up.

// Timers
new Handle:timer_ZRefresh = INVALID_HANDLE;		// Timer to refresh zombie health.

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
										"63",
										"Enables or disables debugging using debug flags.",
										FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_DONTRECORD,
										true,
										0.0);
	
	cv_Pushback = CreateConVar("tfbh_pushback_scale",
										"2.0",
										"General multiplier for zombie pushback",
										FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
										true,
										0.0,
										true,
										10.0);
	
	cv_ZHMin = CreateConVar("tfbh_zhscale_min",
										"1.0",
										"Minimum zombie health multiplier (against 1 survivor).",
										FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
										true,
										1.0);
	
	cv_ZHMax = CreateConVar("tfbh_zhscale_max",
										"8.0",
										"Maximum zombie health multiplier (against 24 survivors).",
										FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
										true,
										1.0);
										
	cv_ZombieRatio = CreateConVar("tfbh_zombie_player_ratio",
										"7",
										"At the beginning of a round, the number of zombies that spawn is the quotient of (Red players/this value), rounded up.",
										FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
										true,
										1.0);
	
	cv_Unbalance = FindConVar("mp_teams_unbalance_limit");
	cv_Autobalance = FindConVar("mp_autoteambalance");
	cv_Scramble = FindConVar("mp_scrambleteams_auto");
	
	HookEventEx("teamplay_round_start",		Event_RoundStart,		EventHookMode_Post);
	HookEventEx("teamplay_round_win",		Event_RoundWin,			EventHookMode_Post);
	HookEventEx("teamplay_round_stalemate",	Event_RoundStalemate,	EventHookMode_Post);
	HookEventEx("player_team",				Event_TeamsChange,		EventHookMode_Post);
	HookEventEx("teamplay_setup_finished",	Event_SetupFinished,	EventHookMode_Post);
	HookEventEx("player_death",				Event_PlayerDeath,		EventHookMode_Post);
	HookEventEx("player_spawn",				Event_PlayerSpawn,		EventHookMode_Post);
	HookEventEx("item_pickup",				Event_ItemPickup,		EventHookMode_Post);
	
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
	
	#if MEZOMBIE == 1
	LogMessage("MEZOMBIE flag set! Reset this before release!");
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
	// Note that this can be called if the "map" command is entered from the server console (I think)!
	// Make sure our flags are reset!
	
	g_PluginState |= STATE_NOT_IN_ROUND;
	g_PluginState |= STATE_FEW_PLAYERS;
	
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
				TF2_RespawnPlayer(i);
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
	
	new Float:fRedTeam = float(redTeam);
	
	// Decide how many zombies should spawn.
	new Float:n = GetConVarFloat(cv_ZombieRatio);
	new nZombies = RoundToCeil(fRedTeam/n);
	
	if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE )
	{
		LogMessage("redTeam: %d. n: %f. Before rounding: %f", redTeam, n, fRedTeam/n);
		LogMessage("Number of zombies to spawn: %d", nZombies);
	}
	
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
	
	// Added this preproc to allow the first person connected (ie. me) to always be a zombie when testing. Bug utilisation!
	#if MEZOMBIE != 1
	new slotToSwap = GetRandomInt(0, redTeam-1);	// Choose a random slot to swap between.
	
	if ( slotToSwap > 0 )	// If the slot is 0, don't bother doing anything else.
	{
		new temp = players[0];							// Make a note of the index in the first element.
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
	#endif
	
	// Choose clients from the top of the array.
	for ( new i = 0; i < nZombies; i++ )
	{
		if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Client %N chosen to be zombified.", players[i]);
		
		MakeClientZombie(players[i]);	// Make the client into a zombie.
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
	
	// Check whether Red is out of alive players.
	
	/*new redCount;
	
	for ( new i = 1; i <= MaxClients; i++ )
	{
		if ( IsClientInGame(i) && GetClientTeam(i) == TEAM_RED && IsPlayerAlive(i) ) redCount++;
	}*/
	
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
	
	CreateTimer(0.1, Timer_CheckTeams);
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
}

/*	Called when a client disconnects.	*/
public OnClientDisconnect(client)
{
	// Clear the client's data arrays.
	ClearAllDataForPlayer(GetClientUserId(client));
}

public OnClientPutInServer(client)
{
	if ( g_PluginState & STATE_DISABLED == STATE_DISABLED ) return;
	
	SDKHook(client, SDKHook_OnTakeDamage,		OnTakeDamage);		// Hooks when the client takes damage.
	SDKHook(client, SDKHook_OnTakeDamagePost,	OnTakeDamagePost);
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
			g_PluginState & STATE_FEW_PLAYERS == STATE_FEW_PLAYERS ) return Plugin_Continue;
	
	new cvDebug = GetConVarInt(cv_Debug);
	if ( cvDebug & DEBUG_CRASHES == DEBUG_CRASHES ) LogMessage("OnTakeDamage fired");
		
	new userid = GetClientUserId(client);
	new index = DataIndexForUserId(userid);
	
	// If the player is on Blue and a zombie, and the attacker is on Red and not a zombie, increase the pushback.
	if ( GetClientTeam(client) == TEAM_BLUE && g_Zombie[index] &&
			attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker) &&
			GetClientTeam(attacker) == TEAM_RED && !g_Zombie[DataIndexForUserId(GetClientUserId(attacker))] )
	{
		/*if ( cvDebug & DEBUG_DAMAGE == DEBUG_DAMAGE ) LogMessage("Modifying zombie pushback.");
		new Float:mx = GetConVarFloat(cv_Pushback);	// Get the pushback multiplier.
		
		damageForce[0] = damageForce[0] * mx;
		damageForce[1] = damageForce[1] * mx;
		damageForce[2] = damageForce[2] * mx;*/
		ScaleVector(damageForce, GetConVarFloat(cv_Pushback));
		
		return Plugin_Changed;
	}
	
	// If the client is a zombie:
	if ( GetClientTeam(client) == TEAM_BLUE && g_Zombie[index] )
	{
		// If the client's internal health value will be <= 0 but g_Health will not, override the internal health.
		new health = GetEntProp(client, Prop_Send, "m_iHealth");
		if ( (float(health) - damage) <= 0 && (g_Health[index] - damage) > 0.0 )
		{
			SetHealthFix(client, RoundToCeil(g_Health[index]));	// <- Since SetHealthFix always sets the health to >= its given parameter, this is safe to do.
			return Plugin_Continue;
		}
	}
	
	return Plugin_Continue;
}

public Action:OnTakeDamagePost(client, &attacker, &inflictor, &Float:damage, &damagetype, &weapon, Float:damageForce[3], Float:damagePosition[3])
{
	// Don't bother checking damage values if we're not in a valid round.
	if ( g_PluginState & STATE_DISABLED == STATE_DISABLED ||
			g_PluginState & STATE_NOT_IN_ROUND == STATE_NOT_IN_ROUND ||
			g_PluginState & STATE_FEW_PLAYERS == STATE_FEW_PLAYERS ) return Plugin_Continue;
	
	new cvDebug = GetConVarInt(cv_Debug);
	if ( cvDebug & DEBUG_CRASHES == DEBUG_CRASHES ) LogMessage("OnTakeDamagePost fired");
	
	new userid = GetClientUserId(client);
	new index = DataIndexForUserId(userid);
	
	// If a zombie was hurt, decrease their recorded health by the damage amount.
	if ( GetClientTeam(client) == TEAM_BLUE && g_Zombie[index] )
	{
		// If damage taken causes g_Health to be <= 0 but not client's internal health,
		// deal with this below.
		
		if ( cvDebug & DEBUG_CRASHES == DEBUG_CRASHES ) LogMessage("OnTakeDamagePost getting EntProp...");
		new health = GetEntProp(client, Prop_Send, "m_iHealth");
		if ( cvDebug & DEBUG_CRASHES == DEBUG_CRASHES ) LogMessage("OnTakeDamagePost getting EntProp succeeded. (%d) (%f) (%f)", health, g_Health[index], damage);
		
		if ( (g_Health[index] - damage) <= 0.0 && health > 0 )	// The internal health has already been modified by this time, but not g_Health.
		{
			if ( cvDebug & DEBUG_CRASHES == DEBUG_CRASHES ) LogMessage("OnTakeDamagePost started 2");
			
			g_Health[index] = 0.0;
			SetHealthFix(client, 0);
			
			if ( cvDebug & DEBUG_CRASHES == DEBUG_CRASHES ) LogMessage("OnTakeDamagePost ended 2");
			return Plugin_Continue;
		}
		
		// We always want to rely on the data array health entry rather than the client's own internal health,
		// since we're modifying this health to avoid the player's camera going into dead mode and so it's unreliable.
		// We've made sure in OnTakeDamage (pre) that the client's internal health will be able to take the
		// amount of damage that has been dealt, so we should always turn up with a positive internal health
		// value here if g_Health is also positive.
		
		if ( cvDebug & DEBUG_CRASHES == DEBUG_CRASHES ) LogMessage("OnTakeDamagePost taking damage from g_Health...");
		g_Health[index] -= damage;								// Take the damage done from the health entry.
		if ( cvDebug & DEBUG_CRASHES == DEBUG_CRASHES ) LogMessage("OnTakeDamagePost setting health...");
		g_Health[index] = float(RoundToCeil(g_Health[index]));	// Make it a round number.
		SetHealthFix(client, RoundToCeil(g_Health[index]));		// Set the health.
	}
	
	if ( cvDebug & DEBUG_CRASHES == DEBUG_CRASHES ) LogMessage("OnTakeDamagePost ended");
	return Plugin_Continue;
}

/*	Called when a player dies.	*/
public Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	if ( g_PluginState & STATE_DISABLED == STATE_DISABLED ||
			g_PluginState & STATE_NOT_IN_ROUND == STATE_NOT_IN_ROUND ||
			g_PluginState & STATE_FEW_PLAYERS == STATE_FEW_PLAYERS ) return;
	
	new cvDebug = GetConVarInt(cv_Debug);
	if ( cvDebug & DEBUG_CRASHES == DEBUG_CRASHES ) LogMessage("player_death fired");
	
	new userid = GetEventInt(event, "userid");
	new client = GetClientOfUserId(userid);
	new atuserid = GetEventInt(event, "attacker");
	new attacker = GetClientOfUserId(atuserid);
	new deathFlags = GetEventInt(event, "death_flags");
	
	// If the player is a Red Engineer, destroy their sentry.
	if ( GetClientTeam(client) == TEAM_RED && TF2_GetPlayerClass(client) == TFClass_Engineer )
	{
		if ( cvDebug & DEBUG_GENERAL == DEBUG_GENERAL ) LogMessage("Client %N is a Red Engineer, killing any sentries.", client);
		KillBuildings(client, BUILD_SENTRY);
	}
	
	// If the player was a zombie and didn't DR, clear out their health values to be safe.
	
	// If the player was on Red and not a zombie, and the killer was on Blue and was a zombie, and the player didn't DR,
	// change them into a zombie.
	if ( GetClientTeam(client) == TEAM_RED && !g_Zombie[DataIndexForUserId(userid)] &&
			attacker > 0 && attacker <= MaxClients && GetClientTeam(attacker) == TEAM_BLUE && g_Zombie[DataIndexForUserId(atuserid)] &&
			deathFlags & 32 != 32 )
	{
		if ( cvDebug & DEBUG_GENERAL == DEBUG_GENERAL ) LogMessage("%N killed by zombie %N.", client, attacker);
		
		// Note the client's position.
		new Float:clientPos[3], Float:clientAng[3];
		GetClientAbsAngles(client, clientAng);
		GetClientAbsOrigin(client, clientPos);
		
		MakeClientZombie(client, true);
		
		new Handle:pack = CreateDataPack();
		WritePackCell(pack, userid);
		WritePackFloat(pack, clientPos[0]);
		WritePackFloat(pack, clientPos[1]);
		WritePackFloat(pack, clientPos[2]);
		WritePackFloat(pack, clientAng[0]);
		WritePackFloat(pack, clientAng[1]);
		WritePackFloat(pack, clientAng[2]);
		CreateTimer(0.1, Timer_RespawnTelePlayer, pack);
		
	}
}

/*	Called when a player spawns.	*/
public Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	if ( g_PluginState & STATE_DISABLED == STATE_DISABLED ||
			/*g_PluginState & STATE_NOT_IN_ROUND == STATE_NOT_IN_ROUND ||*/
			g_PluginState & STATE_FEW_PLAYERS == STATE_FEW_PLAYERS ) return;
	
	new userid = GetEventInt(event, "userid");
	new client = GetClientOfUserId(userid);
	new index = DataIndexForUserId(userid);
	
	// If the player is on Blue and is a zombie, remove slots 0 and 1.
	if ( GetClientTeam(client) == TEAM_BLUE && g_Zombie[DataIndexForUserId(userid)] )
	{
		new Float:maxHealth = float(GetEntProp(client, Prop_Data, "m_iMaxHealth"));	// Get the client's current max health.
		new newHealth = RoundToCeil(maxHealth * CalculateZombieHealthMultiplier());	// Calculate the new max health.
		
		if ( GetConVarInt(cv_Debug) & DEBUG_HEALTH == DEBUG_HEALTH ) LogMessage("%N's max health: %d", client, newHealth);
		
		g_MaxHealth[index] = float(newHealth);								// Update health entries.
		g_Health[index] = float(newHealth);									// These must always change first; real health will be modified after this.
		
		SetEntProp(client, Prop_Data, "m_iMaxHealth", RoundToCeil(g_MaxHealth[index]));	// Update the client's max health value.
		SetHealthFix(client, RoundToCeil(g_Health[index]));								// Update the client's health.
		
		TF2_RemoveWeaponSlot(client, SLOT_PRIMARY);
		TF2_RemoveWeaponSlot(client, SLOT_SECONDARY);
		EquipSlot(client, SLOT_MELEE);
	}
	
	if ( g_PluginState & STATE_NOT_IN_ROUND == STATE_NOT_IN_ROUND ) return;
}

/*	Check if a player has picked up a health kit.
	In reality zombies won't be able to pick up health kits,
	but for safety's sake this is here.	*/
public Event_ItemPickup(Handle:event, const String:name[], bool:dontBroadcast)
{
	if ( g_PluginState & STATE_DISABLED == STATE_DISABLED ||
			g_PluginState & STATE_NOT_IN_ROUND == STATE_NOT_IN_ROUND ||
			g_PluginState & STATE_FEW_PLAYERS == STATE_FEW_PLAYERS ) return;
	
	new userid = GetEventInt(event, "userid");
	new client = GetClientOfUserId(userid);
	new index = DataIndexForUserId(userid);
	
	if ( GetClientTeam(client) == TEAM_BLUE && g_Zombie[index] )
	{
		// Find out what type of pickup it was.
		decl String:item[65];
		GetEventString(event, "item", item, sizeof(item));
		
		if ( StrEqual(item, "item_healthkit_small", false) )	// Small health kits heal 20.5% health.
		{
			g_Health[index] += (0.205 * g_MaxHealth[index]);
		}
		else if ( StrEqual(item, "item_healthkit_medium", false) )	// Medium health kits heal 50% health. )
		{
			g_Health[index] += (0.5 * g_MaxHealth[index]);
		}
		else if ( StrEqual(item, "item_healthkit_full", false) )	// Medium health kits heal all health. )
		{
			g_Health[index] = g_MaxHealth[index];
		}
		
		SetHealthFix(client, RoundToCeil(g_Health[index]));
	}
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
	new cvDebug = GetConVarInt(cv_Debug);
	
	switch (mode)
	{
		case CLEANUP_ROUNDEND:
		{
			if ( g_PluginState & STATE_DISABLED == STATE_DISABLED ) return;
			
			for ( new i = 0; i < MAXPLAYERS; i++ )
			{
				g_Health[i] = 0.0;
				g_MaxHealth[i] = 0.0;
			}
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
			
			if ( timer_ZRefresh == INVALID_HANDLE )
			{
				timer_ZRefresh = CreateTimer(0.2, Timer_ZombieHealthRefresh, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
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
					if ( cvDebug & DEBUG_DATA == DEBUG_DATA ) LogMessage("Client %N is connected.", i);
					
					// Give the client a slot in the data arrays.
					new index = FindFreeDataIndex();
					if ( index < 0 )
					{
						LogError("MAJOR ERROR: Cannot find a free data index for client %N (MaxClients %d, MAXPLAYERS %d).", i, MaxClients, MAXPLAYERS);
						return;
					}
					
					if ( cvDebug & DEBUG_DATA == DEBUG_DATA ) LogMessage("Client %N has user ID %d and data index %d.", i, GetClientUserId(i), index);
					
					g_userIDMap[index] = GetClientUserId(i);				// Register the client's userID.
					ClearAllArrayDataForIndex(index);						// Clear all the other data arrays at the specified index.
					SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);			// Hooks when the client takes damage.
					SDKHook(i, SDKHook_OnTakeDamagePost, OnTakeDamagePost);
					
					if ( cvDebug & DEBUG_DATA == DEBUG_DATA ) LogMessage("Data at index %d: user ID %d, zombie %d.", index, g_userIDMap[index], g_Zombie[index]);
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
			
			for ( new i = 0; i < MAXPLAYERS; i++ )
			{
				ClearAllArrayDataForIndex(i, true);
			}
			
			if ( timer_ZRefresh != INVALID_HANDLE )
			{
				KillTimer(timer_ZRefresh);
				timer_ZRefresh = INVALID_HANDLE;
			}
		}
		
		case CLEANUP_ROUNDSTART:	// Called even if plugin is disabled, so don't put anything important here.
		{
			// Reset all stored health values.
			for ( new i = 0; i < MAXPLAYERS; i++ )
			{
				g_Health[i] = 0.0;
				g_MaxHealth[i] = 0.0;
			}
		}
		
		case CLEANUP_MAPSTART:
		{
			// MapStart gets called when the plugin is loaded, so if we are already processing don't do this,
			// otherwise all the data arrays will get reset.
			if ( IsServerProcessing() ) return;
			
			if ( timer_ZRefresh == INVALID_HANDLE )
			{
				timer_ZRefresh = CreateTimer(0.2, Timer_ZombieHealthRefresh, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
			}
			
			// Reset all data arrays.
			// #NOTE#: Is this needed?
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
			
			if ( timer_ZRefresh != INVALID_HANDLE )
			{
				KillTimer(timer_ZRefresh);
				timer_ZRefresh = INVALID_HANDLE;
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
	
	if ( userid )
	{
		if ( GetConVarInt(cv_Debug) & DEBUG_DATA == DEBUG_DATA ) LogMessage("UserID for index %d is being reset.", index);
		g_userIDMap[index] = 0;
	}
	
	g_Zombie[index] = true;
	g_MaxHealth[index] = 0.0;
	g_Health[index] = 0.0;
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

/*	Sets up a client as a zombie.	*/
stock MakeClientZombie(client, bool:death = false)
{
	KillBuildings(client, BUILD_SENTRY | BUILD_DISPENSER | BUILD_TELEPORTER);	// Kill the client's buildings (class is checked in function).
	if ( !death ) SetEntProp(client, Prop_Send, "m_lifeState", 2);				// Make sure the client won't die when we change their team.
	ChangeClientTeam(client, TEAM_BLUE);										// Change them to Blue.
	if ( !death ) SetEntProp(client, Prop_Send, "m_lifeState", 0);				// Reset the lifestate variable.
	g_Zombie[DataIndexForUserId(GetClientUserId(client))] = true;				// Mark them as a zombie.
	if ( death ) TF2_RespawnPlayer(client);
	
	new Float:maxHealth = float(GetEntProp(client, Prop_Data, "m_iMaxHealth"));	// Get the client's current max health.
	new newHealth = RoundToCeil(maxHealth * CalculateZombieHealthMultiplier());	// Calculate the new max health.
	
	if ( GetConVarInt(cv_Debug) & DEBUG_HEALTH == DEBUG_HEALTH ) LogMessage("%N's max health: %d", client, newHealth);
	
	new index = DataIndexForUserId(GetClientUserId(client));
	g_MaxHealth[index] = float(newHealth);
	g_Health[index] = float(newHealth);
	
	SetEntProp(client, Prop_Data, "m_iMaxHealth", RoundToCeil(g_MaxHealth[index]));		// Update the client's max health value.
	SetHealthFix(client, RoundToCeil(g_Health[index]));
	
	TF2_RemoveWeaponSlot(client, SLOT_PRIMARY);											// Remove their primary weapon.
	TF2_RemoveWeaponSlot(client, SLOT_SECONDARY);										// Remove their secondary weapon.
	EquipSlot(client, SLOT_MELEE);														// Equip melee.
}

/*	Kills the specified buildings owned by a client.	*/
stock KillBuildings(client, flags)
{
	if ( client < 1 || client > MaxClients || !IsClientInGame(client) || TF2_GetPlayerClass(client) != TFClass_Engineer ) return;
	
	// Sentries:
	if ( (flags & BUILD_SENTRY) == BUILD_SENTRY )
	{
		new ent = -1;
		while ( (ent = FindEntityByClassname(ent, "obj_sentrygun")) != -1 )
		{
			if ( IsValidEntity(ent) && GetEntPropEnt(ent, Prop_Send, "m_hBuilder") == client )
			{
				SetVariantInt( GetEntProp(ent, Prop_Send, "m_iMaxHealth") + 1 );
				AcceptEntityInput(ent, "RemoveHealth");
				AcceptEntityInput(ent, "Kill");
			}
		}
	}
	
	// Dispensers:
	if ( (flags & BUILD_DISPENSER) == BUILD_DISPENSER )
	{
		new ent = -1;
		while ( (ent = FindEntityByClassname(ent, "obj_dispenser")) != -1 )
		{
			if ( IsValidEntity(ent) && GetEntPropEnt(ent, Prop_Send, "m_hBuilder") == client )
			{
				SetVariantInt( GetEntProp(ent, Prop_Send, "m_iMaxHealth") + 1 );
				AcceptEntityInput(ent, "RemoveHealth");
				AcceptEntityInput(ent, "Kill");
			}
		}
	}
	
	// Teleporters
	if ( (flags & BUILD_DISPENSER) == BUILD_DISPENSER )
	{
		new ent = -1;
		while ( (ent = FindEntityByClassname(ent, "obj_teleporter")) != -1 )
		{
			if ( IsValidEntity(ent) && GetEntPropEnt(ent, Prop_Send, "m_hBuilder") == client )
			{
				SetVariantInt( GetEntProp(ent, Prop_Send, "m_iMaxHealth") + 1 );
				AcceptEntityInput(ent, "RemoveHealth");
				AcceptEntityInput(ent, "Kill");
			}
		}
	}
}

/*	Calculates what multiple of normal health a zombie should have.	*/
stock Float:CalculateZombieHealthMultiplier()
{
	new Float:zMin = GetConVarFloat(cv_ZHMin);
	new Float:zMax = GetConVarFloat(cv_ZHMax);
	new cvDebug = GetConVarInt(cv_Debug);
	new Float:m, Float:c;
	
	// Health is determined on a per-spawn basis, linearly interpolated between a minimum and maximum health multiplier.
	// Minimum health is given when there is 1 opponent on Red, and maximum given when there are 24 or greater.
	// We use a y=mx+c format to calculate the health (y) to give for (x) players.
	
	// Firstly, clamp the health proportion values. Min should not be greater than max.
	if ( zMin > zMax )
	{
		if ( cvDebug & DEBUG_HEALTH == DEBUG_HEALTH ) LogMessage("Minimum health value %f larger than maximum health value %f.", zMin, zMax);
		
		zMax = zMin;	// Set max health to match min health.
	}
	
	// If I were doing this on paper I would write (zMax-zMin) = m(24-1).
	// This means to calculate m we need to do (zMax-zMin)/23.
	m = (zMax-zMin)/23;
	
	if ( cvDebug & DEBUG_HEALTH == DEBUG_HEALTH ) LogMessage("Gradient %f", m);
	
	// I would then do y=mx+c, or for example zMin = m(1)+c
	// This means to calculate c we need to do zMin-m (since the minimum player count in this instance,
	// conveniently, is 1).
	
	c = zMin-m;
	
	if ( cvDebug & DEBUG_HEALTH == DEBUG_HEALTH ) LogMessage("Intercept %f", c);
	
	// Get the number of live players on Red.
	new redCount;
	
	for ( new i = 1; i <= MaxClients; i++ )
	{
		if ( IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == TEAM_RED ) redCount++;
	}
	
	if ( cvDebug & DEBUG_HEALTH == DEBUG_HEALTH ) LogMessage("%d players alive on Red.", redCount);
	
	// Calculate the raw multiplier value (y).
	new Float:multiplier = (m * redCount) + c;
	
	if ( cvDebug & DEBUG_HEALTH == DEBUG_HEALTH ) LogMessage("Raw multiplier: %f", multiplier);
	
	// Clamp the multiplier value to fall within our limits.
	if ( multiplier < zMin )
	{
		if ( cvDebug & DEBUG_HEALTH == DEBUG_HEALTH ) LogMessage("Multiplier %f < %f, clamping.", multiplier, zMin);
		multiplier = zMin;
	}
	else if ( multiplier > zMax )
	{
		if ( cvDebug & DEBUG_HEALTH == DEBUG_HEALTH ) LogMessage("Multiplier %f > %f, clamping.", multiplier, zMax);
		multiplier = zMax;
	}
	else if ( multiplier <= 0.0 )	// If the multiplier is <= 0, return 1.
	{
		if ( cvDebug & DEBUG_HEALTH == DEBUG_HEALTH ) LogMessage("Multiplier <= 0, clamping to 1.0.");
		multiplier = 1.0;
	}
	
	return multiplier;
}

/*	Equips a weapon given a slot.	*/
stock EquipSlot(client, slot)
{
	if ( client < 0 || client > MaxClients || !IsClientInGame(client) || !IsPlayerAlive(client) ||
			GetClientTeam(client) > TEAM_BLUE || GetClientTeam(client) < TEAM_RED ) return;
	
	new weapon = GetPlayerWeaponSlot(client, slot);
	if ( weapon == -1 || !IsValidEntity(weapon) ) return;
	
	EquipPlayerWeapon(client, weapon);
}

/*	Fixes health issues with health values over 1024.
	Thanks to FlaminSarge for figuring this all out in VSH.
	Client health set will always be >= health parameter.	*/
stock SetHealthFix(client, health)
{
	new modHealth = health;										// Copy the health value we have been given.
	if (modHealth < 1024)										// If health is less than 1024:
	{
		SetEntProp(client, Prop_Send, "m_iHealth", modHealth);	// Give health as normal.
		return;
	}
	
	health = health % 2048;										// Find the remainder when the health value is divided by 2048.
	
	if (health < 1024)											// If this remainder is less than 1024:
	{
		if (health < 5) modHealth += 30;						// If less than 5, increase by 30.
	}
	if (health >= 1024)											// If greater than or equal to 1024:
	{
		modHealth += 1024;										// Increase by 1024.
	}
	
	SetEntProp(client, Prop_Send, "m_iHealth", modHealth);
}

public Action:Timer_EnsurePlayerAlive(Handle:timer, Handle:pack)
{
	ResetPack(pack);
	new userid = ReadPackCell(pack);
	if ( userid < 1 ) return;
	
	new client = GetClientOfUserId(userid);
	if ( client < 1 || client > MaxClients || !IsClientInGame(client) ) return;
	if ( GetClientTeam(client) == TEAM_BLUE ) ChangeClientTeam(client, TEAM_RED);
	if ( !IsPlayerAlive(client) ) TF2_RespawnPlayer(client);
}

public Action:Timer_CheckTeams(Handle:timer)
{
	if ( g_PluginState & STATE_DISABLED == STATE_DISABLED ||
			g_PluginState & STATE_NOT_IN_ROUND == STATE_NOT_IN_ROUND ||
			g_PluginState & STATE_FEW_PLAYERS == STATE_FEW_PLAYERS ) return;
	
	new redCount;
	new cvDebug = GetConVarInt(cv_Debug);
	
	for ( new i = 1; i <= MaxClients; i++ )
	{
		if ( IsClientInGame(i) && GetClientTeam(i) == TEAM_RED && IsPlayerAlive(i) ) redCount++;
	}
	
	if ( redCount < 1 )
	{
		if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Red team is out of players.");
		RoundWinWithCleanup(TEAM_BLUE);
	}
}

public Action:Timer_RespawnTelePlayer(Handle:timer, Handle:pack)
{
	ResetPack(pack);
	new userid = ReadPackCell(pack);
	new Float:clientPos[3], Float:clientAng[3];
	
	clientPos[0] = ReadPackFloat(pack);
	clientPos[1] = ReadPackFloat(pack);
	clientPos[2] = ReadPackFloat(pack);
	clientAng[0] = ReadPackFloat(pack);
	clientAng[1] = ReadPackFloat(pack);
	clientAng[2] = ReadPackFloat(pack);
	
	if ( userid < 1 ) return;
	
	new client = GetClientOfUserId(userid);
	if ( client < 1 || client > MaxClients || !IsClientInGame(client) ) return;
	TF2_RespawnPlayer(client);
	TeleportEntity(client, clientPos, clientAng, NULL_VECTOR);
}

public Action:Timer_ZombieHealthRefresh(Handle:timer, Handle:pack)
{
	if ( g_PluginState & STATE_DISABLED == STATE_DISABLED ||
			g_PluginState & STATE_NOT_IN_ROUND == STATE_NOT_IN_ROUND ||
			g_PluginState & STATE_FEW_PLAYERS == STATE_FEW_PLAYERS ) return Plugin_Handled;
	
	for ( new i = 1; i < MaxClients; i++ )
	{
		if ( IsClientInGame(i) )
		{
			new index = DataIndexForUserId(GetClientUserId(i));
			
			if ( GetClientTeam(i) == TEAM_BLUE && IsPlayerAlive(i) && g_Zombie[index] )
			{
				SetHealthFix(i, RoundToCeil(g_Health[index]));
				SetHudTextParams(-1.0,
									0.85,
									0.21,
									255,
									255,
									255,
									255,
									0,
									0.0,
									0.0,
									0.0);
				
				ShowHudText(i, 0, "[FIXME] Health: %d", RoundToCeil(g_Health[index]));
			}
		}
	}
	
	return Plugin_Handled;
}

/*	Outputs player data arrays to the console.	*/
public Action:Debug_ShowData(client, args)
{
	if ( client < 0 ) return Plugin_Handled;
	else if ( client > 0 && !IsClientInGame(client) ) return Plugin_Handled;
	
	if ( GetCmdArgs() > 0 )
	{
		new String:arg[16];
		GetCmdArg(1, arg, sizeof(arg));
		new i = StringToInt(arg);
		
		if ( i < 0 || i >= MAXPLAYERS )
		{
			ReplyToCommand(client, "Index must be between 0 and %d inclusive!", MAXPLAYERS-1);
			return Plugin_Handled;
		}
		
		PrintToConsole(client, "%d: UserID %d, zombie %d, health %f, maxhealth %f", i, g_userIDMap[i], g_Zombie[i], g_Health[i], g_MaxHealth[i]);
	}
	
	for (new i = 0; i < MAXPLAYERS; i++ )
	{
		PrintToConsole(client, "%d: UserID %d, zombie %d, health %f, maxhealth %f", i, g_userIDMap[i], g_Zombie[i], g_Health[i], g_MaxHealth[i]);
	}
	
	return Plugin_Handled;
}