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

// Plugin defines
#define PLUGIN_NAME			"TF Biohazard"
#define PLUGIN_AUTHOR		"[X6] Herbius"
#define PLUGIN_DESCRIPTION	"Hold off the zombies to win the round!"
#define PLUGIN_VERSION		"0.0.0.1"
#define PLUGIN_URL			"http://x6herbius.com/"

// State flags
// Control what aspects of the plugin will run.
#define STATE_DISABLED		4	// Plugin is disabled via convar. No gameplay-modifying activity will occur.
#define STATE_FEW_PLAYERS	2	// There are not enough players to begin a game.
#define STATE_NOT_IN_ROUND	1	// Round has ended or has not yet begun.

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

#define MAX_PLAYERS	32	// Hard-coded maximum player define, for where we can't use MaxClients.

// Change the following to specify what the plugin should change the balancing
// CVars to. Must be integers.
#define DES_UNBALANCE		0	// Desired value for mp_teams_unbalance_limit
#define DES_AUTOBALANCE		0	// Desired value for mp_autoteambalance
#define DES_SCRAMBLE		0	// Desired value for mp_scrambleteams_auto

new g_PluginState;	// Holds the global state of the plugin.
new g_Disconnect;	// Sidesteps team count issues by tracking the index of a disconnecting player. See Event_TeamsChange.

// Player data
new g_userIDMap[MAX_PLAYERS] = {-1, ...};	// For a userID at index n, this player's data will be found in index n of the rest of the data arrays.
											// If index n = -1, index n in data arrays is free for use.
new bool:g_Zombie[MAX_PLAYERS];				// True if the plater is infected, false otherwise.

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
										"1",
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
	
	HookConVarChange(cv_PluginEnabled,	CvarChange);
	HookConVarChange(cv_Unbalance,		CvarChange);
	HookConVarChange(cv_Autobalance,	CvarChange);
	HookConVarChange(cv_Scramble,		CvarChange);
	
	if ( GetConVarInt(cv_Debug) > 0 )
	{
		LogMessage("Plugin is starting with debug cvar enabled! Reset this before release!");
	}
	
	// If we're not enabled, don't set anything up.
	if ( g_PluginState & STATE_DISABLED == STATE_DISABLED )
	{
		LogMessage("Plugin starting disabled.");
		return;
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
	
	if ( GetConVarInt(cv_Debug) & DEBUG_GENERAL == DEBUG_GENERAL )
	{
		LogMessage("RoundStart executed. If you see me, remove me!");
	}
	
	// Move everyone on Blue to the Red team.
	for ( new i = 1; i <= MaxClients; i++ )
	{
		if ( IsClientInGame(i) && GetClientTeam(i) == TEAM_BLUE )
		{
			ChangeClientTeam(i, TEAM_RED);
		}
	}
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

/*	Called when a player changes team.	*/
public Event_TeamsChange(Handle:event, const String:name[], bool:dontBroadcast)
{
	if ( (g_PluginState & STATE_DISABLED == STATE_DISABLED) ||
			(g_PluginState & STATE_NOT_IN_ROUND == STATE_NOT_IN_ROUND) ) return;
	
	// I've never liked team change hooks.
	
	// If the plugin is disabled or we're not in a round, ignore team changes.
	// If there are not enough players to begin a game, allow team changes but monitor team counts.
	// When the team counts go over the required threshold, end the round.
	
	// If instead all is clear, we first need to check the team the player is changing from.
	// If they're changing from a team which is not Red or Blue, force them to join Red.
	// If they are changing from Red or Blue, do the following:
		// If from Red, check target team. If team is blue, ensure they are marked as a zombie. If not blue, allow change.
		// If from Blue, check tartget team. If team is Red, ensure they are not marked as a zombie. If not Red, allow change.
	
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
	
	// If there were not enough players but we have just broken the threshold, end the round in a stalemate.
	if ( g_PluginState & STATE_FEW_PLAYERS == STATE_FEW_PLAYERS )
	{
		if ( total > 1 )
		{
			if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Player count is now above the threshold!");
			
			g_PluginState &= ~STATE_FEW_PLAYERS;	// Clear the FEW_PLAYERS flag.
			RoundWinWithCleanup();
			
			return;
		}
		else return;
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
	
	// There are enough players to continue the game.
	// If a player is joining the game (ie. their old team is not Red or Blue), force them to join Red.
	if ( oldTeam != TEAM_RED && oldTeam != TEAM_BLUE )
	{
		
		if ( newTeam == TEAM_BLUE )
		{
			if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Blocking player %N from joining Blue.", client);
			
			ChangeClientTeam(client, TEAM_RED);
		}
	}
	else if ( oldTeam == TEAM_RED )	// If Red->Blue, check whether the client is a zombie.
	{
		if ( newTeam == TEAM_BLUE )
		{
			new dataIndex = DataIndexForUserId(userid);
			if ( dataIndex == -1 ) return;
			
			if ( !g_Zombie[dataIndex] )	// If they are not a zombie, prohibit the change. #NOTE#: A better way to do this would be to block the command itself.
			{
				if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Blocking non-zombie player %N from joining Blue.", client);
				
				ChangeClientTeam(client, TEAM_RED);
			}
		}
	}
	else if ( oldTeam == TEAM_BLUE )	// If Blue->Red, check whether the client is a zombie.
	{
		if ( newTeam == TEAM_RED )
		{
			new dataIndex = DataIndexForUserId(userid);
			if ( dataIndex == -1 ) return;
			
			if ( g_Zombie[dataIndex] )	// If they are a zombie, prohibit the change.
			{
				if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Blocking zombie player %N from joining Red.", client);
				
				ChangeClientTeam(client, TEAM_BLUE);
			}
		}
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
			// #TODO#
		}
		
		case CLEANUP_MAPEND:
		{
			// #TODO#
		}
	}
}

/*	Clears the player data arrays for the player with the specified userID.	*/
stock ClearDataForPlayer(userid)
{
	new index = DataIndexForUserId(userid);
	if index == -1 return;
	
	g_Zombie[index] = false;
	
	g_userIDMap[index] = -1;
}

/*	Returns true if there are enough players to play a match.
	Own function for convenience.	*/
stock bool:PlayerCountAdequate()
{
	if ( GetTeamClientCount(TEAM_RED) + GetTeamClientCount(TEAM_BLUE) > 1 ) return true;
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
	for ( new i = 0; i < MAX_PLAYERS; i++ )
	{
		if ( g_userIDMap[i] == userid ) return i;
	}
	
	// If no match, return -1;
	return -1;
}