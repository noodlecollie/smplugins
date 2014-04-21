/*	=======================================================================
	Arena Modulus Mode Base - [X6] Herbius - 13/10/11 - http://goo.gl/1SmnL
	=======================================================================
*/

#pragma semicolon 1

// ================================
// =========== Includes ===========
// ================================

#include <sourcemod>		// Main SM functionality.
#include <sdktools>		// SDK Tools.
#include <ArenaModulus>	// Arena Modulus main handler.
#include <tf2_Stocks>		// TF2 functions.
#include <TF2Items>		// TF2 Items.

#define TEAM_RED 	2
#define TEAM_BLUE	3

// ================================
// =========== Defines ============
// ================================

// ========== Debug Flags =========
// Different areas of the code can be enabled or disabled for debugging purposes.
// Setting the main DEBUG constant to different flags will allow for different debugging functionality.

#define DEBUG	0

// ========== Variables ===========
new bool:g_bPluginState = false;		// Global state of the plugin. Hooks should only run if this is true. It is set when the handler broadcasts
										// ArenaMod_RoundStart with a matching ID, and reset on ArenaMod_RoundEnd (with a matching ID) and Arenamod_MapEnd
										// (regardless).
new ModeID = -10;						// The ID of the mode. When a round starts, the main handler will call the ArenaMod_RoundStart forward broadcasting
										// the ID of the mode that has been chosen. This ID will be 0 or greater if a mode has been chosen, or -1 if the round
										// is a normal Arena match. Hence, the ModeID should be initialised to -10 (or some arbitrary number less than -1) so
										// as not to match with any other mode ID or the ID for normal Arena.
new bool:AMLibExists = true;			// Set to false if the Arena Modulus handler is not found.
new bool:TF2ILibExists = true;		// Set to false if the TF2Items extension is not found.
 
// ========= Plugin Info ==========
#define PLUGIN_NAME			"Arena Modulus: Stinger"
#define PLUGIN_AUTHOR		"[X6] Herbius"
#define PLUGIN_DESCRIPTION	"Pyros must work together to take the heavies down."
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
 
public OnPluginStart()
{
	LogMessage("===== Arena Modulus - Stinger, Version: %s =====", PLUGIN_VERSION);
	LoadTranslations("arena_modulus/stinger/Stinger.phrases");
	AutoExecConfig(true, "Stinger", "sourcemod/arena_modulus/stinger");
	
	CreateConVar("arenamod_stinger_version", PLUGIN_VERSION, "Mode version.", FCVAR_NOTIFY);
	
	// RoundStart should NOT be hooked here. Use ArenaMod_RoundStart instead, since this will make sure the mode only runs if it's picked.
	
	HookEventEx("teamplay_round_win",		Event_RoundWin,			EventHookMode_Post);
	HookEventEx("teamplay_round_stalemate",	Event_RoundStalemate,	EventHookMode_Post);
	HookEventEx("arena_round_start",			Event_ArenaRoundStart,	EventHookMode_Post);
	//HookEventEx("player_spawn",				Event_PlayerSpawn,		EventHookMode_Post);
}

/*	If valid, we should tell the handler that this mode is unloading so that it will not be chosen again.	*/
public OnPluginEnd()
{
	if ( !AMLibExists ) return;
	if ( ModeID < 0 ) return;	// Only call UnloadMode if we have been registered (ie. if we have a valid Mode ID).
	
	ArenaMod_UnloadMode(ModeID);
}

public OnAllPluginsLoaded()
{
	if ( !LibraryExists("ArenaModulus") )
	{
		LogError("Library ArenaModulus does not exist, custom mode %s will not take effect.", PLUGIN_NAME);
		g_bPluginState = false;
		AMLibExists = false;
	}
	
	if ( !LibraryExists("TF2Items") )
	{
		LogError("Library TF2Items does not exist, custom mode %s will not take effect.", PLUGIN_NAME);
		g_bPluginState = false;
		TF2ILibExists = false;
	}
}

/*	Events hooked as normal should only serve to double-check that all variables are
	reset in case the main handler is not running.	*/
public Event_RoundWin(Handle:event, const String:name[], bool:dontBroadcast)
{
	// Ensure the global state flag is reset.
	g_bPluginState = false;
}

public Event_RoundStalemate(Handle:event, const String:name[], bool:dontBroadcast)
{
	// Ensure the global state flag is reset.
	g_bPluginState = false;
}

public Event_ArenaRoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	// Check team counts here, since we can no longer 100% guarantee there will be enough players on the team
	// (someone could have left in the time between this mode being chosen and the round starting).
	
	if ( !g_bPluginState ) return;
	
	// if ( [player count less than desired level] && modeID >= 0 ) ArenaMod_CancelCurrentRound(modeID);
}

public OnMapEnd()
{
	// Ensure the global state flag is reset.
	g_bPluginState = false;
	
	// Ensure the Mode ID holder is reset.
	ModeID = -10;
}

/*	This forward is called when the main handler is searching for modes to register.
	Each custom mode should specify its name and description (translated into LANG_SERVER),
	the minimum required players for Red and Blue (0 by default) and whether these player counts
	should be checked against each team (team independent being passed as 0) or whether they just
	specify the maximum number of players in the game regardless of teams (team independant then
	being passed as 1). If team independent is 1, the handler will add the minimum Red value to the
	minimum Blue value and check this total against the total number of players on both Red and Blue
	to determine whether the mode can be played.	*/
public ArenaMod_SearchForModes()
{
	if ( !AMLibExists )
	{
		LogMessage("Arena Modulus main handler not found.");	// This is probably impossible, but here for safety's sake.
		return;
	}
	
	if ( !TF2ILibExists )	// If the TF2Items extension does not exist, don't register in.
	{
		LogMessage("TF2Items extension does not exist, %s will not register into Arena Modulus.", PLUGIN_NAME);
		return;
	}
	
	decl String:ModeName[65], String:ModeDesc[129], String:ModeTagline[65];
	
	Format(ModeName, sizeof(ModeName), "%T", "am_stinger_name", LANG_SERVER);
	Format(ModeDesc, sizeof(ModeDesc), "%T", "am_stinger_description", LANG_SERVER);
	Format(ModeTagline, sizeof(ModeTagline), "%T", "am_stinger_tagline", LANG_SERVER);
	
	// Get our Mode ID and register our details.
	ModeID = ArenaMod_RegisterMode(ModeName,			/* Our name translated.								*/
											ModeTagline,/* Our tagline, translated.							*/
											ModeDesc,	/* Our description translated.						*/
											1,			/* There must be at least two people playing.		*/
											1,			/* Both these counts wil be added together, because	*/
											1);			/* Minimum counts are independent of teams.			*/
}

/*	Called when the main handler has chosen a mode to play.
	The physical Arena match has not yet started.	*/
public Action:ArenaMod_RoundStart(chosen_mode)
{
	if ( chosen_mode != ModeID || !AMLibExists || !TF2ILibExists )
	{
		g_bPluginState = false;
		
		return Plugin_Continue;
	}
	
	g_bPluginState = true;
	
	// Count how many valid players we have.
	new TotalValidPlayers = 0;
	
	for ( new i = 1; i <= MaxClients; i++ )
	{
		if ( IsClientInGame(i) && IsPlayerOnValidTeam(i) ) TotalValidPlayers++;
	}
	
	if TotalValidPlayers <= 0 return;
	
	// Make an array to hold the indices.
	new PlayerList[TotalValidPlayers];
	new Index = 0;
	
	for ( new i = 1; i <= MaxClients; i++ )
	{
		// If player index is valid, add it to the array.
		if ( IsClientInGame(i) && IsPlayerOnValidTeam(i) )
		{
			PlayerList[Index] = i;
			Index++;
		}
	}
	
	// Randomise the array.
	SortIntegers(PlayerList, sizeof(PlayerList), Sort_Random);
	
	// Run through the list and assign the player to either Red or Blue.
	for ( new i = 0; i < Index; i++ )
	{
		SortPlayerToTeam(PlayerList[i]);
	}
	
	return Plugin_Handled;
}

/*	If the mode ID matches here, it means that the round concerning this custom mode has ended.
	The mode should then clean up anything it needs to.	*/
public Action:ArenaMod_RoundEnd(mode, winning_team)
{
	if ( mode != ModeID )
	{
		g_bPluginState = false;
		return Plugin_Continue;
	}
	
	g_bPluginState = false;
	return Plugin_Handled;	// return Plugin_Handled to let the handler know this was successful.
}

/*	This means that the map has ended and all modes should clean up their resources.	*/
public ArenaMod_MapEnd()
{
	g_bPluginState = false;
	ModeID = -10;
}

/*	The main handler has loaded. Don't do custom setup here, just update the AMLibExists flag.	*/
public ArenaMod_HandlerLoad()
{
	AMLibExists = true;
}

/*	This means that the handler has unloaded and all modes should clean up their resources.	*/
public ArenaMod_HandlerUnload()
{
	g_bPluginState = false;
	ModeID = -10;
	AMLibExists = false;
}

bool IsPlayerOnValidTeam(client)
{
	if ( GetClientTeam(client) == TEAM_RED || GetClientTeam(client) == TEAM_BLUE ) return true;
	else return false;
}

/*	Handles the necessary admin for setting up players on teams.	*/
stock SortPlayerToTeam(client)
{
	static LastTeam = TEAM_RED;
	
	if ( LastTeam == TEAM_RED )
	{
		ChangeClientTeam(client, TEAM_BLUE);
		LastTeam = TEAM_BLUE;
	}
	else if ( LastTeam == TEAM_BLUE )
	{
		ChangeClientTeam(client, TEAM_RED);
		LastTeam = TEAM_RED;
	}
}