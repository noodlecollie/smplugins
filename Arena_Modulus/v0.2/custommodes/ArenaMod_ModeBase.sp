/*	=======================================================================
	Arena Modulus Mode Base - [X6] Herbius - 31/08/11 - http://goo.gl/1SmnL
	=======================================================================
	
	This is the basic shell for a custom Arena Modulus mode.
*/

#pragma semicolon 1

// ================================
// =========== Includes ===========
// ================================

#include <sourcemod>		// Main SM functionality.
#include <sdktools>		// SDK Tools.
#include <ArenaModulus>	// Arena Modulus main handler.

// ================================
// =========== Defines ============
// ================================

// ========== Debug Flags =========
// Different areas of the code can be enabled or disabled for debugging purposes.
// Setting the main DEBUG constant to different flags will allow for different debugging functionality.

#define DEBUG_NONE		0	// No debugging.
#define DEBUG_GENERAL	1	// General debugging.

#define DEBUG				1023

// ========== Variables ===========
new bool:g_bPluginState = false;	// Global state of the plugin. Hooks should only run if this is true. It is set when the handler broadcasts
									// ArenaMod_RoundStart with a matching ID, and reset on ArenaMod_RoundEnd (with a matching ID) and Arenamod_MapEnd
									// (regardless).
new ModeID = -10;					// The ID of the mode. When a round starts, the main handler will call the ArenaMod_RoundStart forward broadcasting
									// the ID of the mode that has been chosen. This ID will be 0 or greater if a mode has been chosen, or -1 if the round
									// is a normal Arena match. Hence, the ModeID should be initialised to -10 (or some arbitrary number less than -1) so
									// as not to match with any other mode ID or the ID for normal Arena.
new bool:AMLibExists = true;		// Set to false if the Arena Modulus handler is not found.
 
// ========= Plugin Info ==========
#define PLUGIN_NAME			"Arena Modulus: Mode Base"
#define PLUGIN_AUTHOR		"[X6] Herbius"
#define PLUGIN_DESCRIPTION	"Basic shell for an Arena Modulus custom mode."
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
 
public OnPluginStart()
{
	LogMessage("===== Arena Modulus Mode Base, Version: %s =====", PLUGIN_VERSION);
	LoadTranslations("arena_modulus/basemode/ArenaModBaseMode.phrases");
	AutoExecConfig(true, "ArenaModBaseMode", "sourcemod/arena_modulus/basemode");
	
	CreateConVar("arenamod_basemode_version", PLUGIN_VERSION, "Mode version.", FCVAR_NOTIFY);
	
	// RoundStart should NOT be hooked here. Use ArenaMod_RoundStart instead, since this will make sure the mode only runs if it's picked.
	
	HookEventEx("player_hurt",				Event_PlayerHurt,		EventHookMode_Post);	// Our demonstration hook.
	HookEventEx("teamplay_round_win",		Event_RoundWin,			EventHookMode_Post);
	HookEventEx("teamplay_round_stalemate",	Event_RoundStalemate,	EventHookMode_Post);
	HookEventEx("arena_round_start",			Event_ArenaRoundStart,	EventHookMode_Post);
}

public OnPluginEnd()
{
	if ( !AMLibExists ) return;
	if ( ModeID < 0 ) return;
	
	LogMessage("Base mode unloading, notifying the handler.");
	
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
}

/*	This is our example hook. The code here will run if the global state flag is set to true.
	This happens if the mode ID for the current round matches this mode.	*/
public Event_PlayerHurt(Handle:event, const String:name[], bool:dontBroadcast)
{
	// Don't run our functionality if the mode is not enabled.
	if ( !g_bPluginState ) return;
	
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	PrintToChatAll("Client %N was hurt.", client);
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
	LogMessage("Base mode received SearchForModes notification.");
	
	if ( !AMLibExists )
	{
		LogMessage("Arena Modulus main handler not found.");
		return;
	}
	
	decl String:ModeName[65], String:ModeTagline[65], String:ModeDesc[129];
	
	Format(ModeName, sizeof(ModeName), "%T", "am_base_name", LANG_SERVER);
	Format(ModeTagline, sizeof(ModeTagline), "%T", "am_base_tagline", LANG_SERVER);
	Format(ModeDesc, sizeof(ModeDesc), "%T", "am_base_description", LANG_SERVER);
	
	// Get our Mode ID and register our details.
	ModeID = ArenaMod_RegisterMode(ModeName,			/* Our name translated. */
											ModeTagline,/* Our tagline translated. */
											ModeDesc,	/* Our description translated. */
											0,			/* No minimum player count for Red. */
											0,			/* No minimum player count for Blue. */
											0);			/* Minimum counts aren't independent of teams. */
	LogMessage("Arena Modulus Base Mode ID is %d.", ModeID);
}

/*	Called when the main handler has chosen a mode to play.
	If the chosen mode matches our ID, we should enable.
	Changing teams/classes can be done here, until arena_round_start is fired.	*/
public Action:ArenaMod_RoundStart(chosen_mode)
{
	LogMessage("Base mode round start, chosen mode is %d, mode ID is %d.", chosen_mode, ModeID);
	
	if ( chosen_mode == ModeID )
	{
		LogMessage("Success! Base mode enabled.");
		
		g_bPluginState = true;
		
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

/*	If the mode ID matches here, it means that the round concerning this custom mode has ended.
	The mode should then clean up anything it needs to.	*/
public Action:ArenaMod_RoundEnd(mode, winning_team)
{
	LogMessage("Base mode round end, chosen mode is %d, mode ID is %d.", mode, ModeID);
	
	if ( mode == ModeID )
	{
		PrintToChatAll("End of round for the base mode, cleanup functions will happen here.");
		
		g_bPluginState = false;
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

/*	This means that the map has ended and all modes should clean up their resources.	*/
public ArenaMod_MapEnd()
{
	LogMessage("Map end detected, base mode will clean up resources here.");
		
	g_bPluginState = false;
	ModeID = -10;
}

/*	The main handler has loaded. Don't do custom setup here, just update the AMLibExists flag.	*/
public ArenaMod_HandlerLoad()
{
	LogMessage("Handler load detected.");
	AMLibExists = true;
}

/*	This means that the handler has unloaded and all modes should clean up their resources.	*/
public ArenaMod_HandlerUnload()
{
	LogMessage("Handler unload detected, base mode will clean up resources here.");
	
	g_bPluginState = false;
	ModeID = -10;
	AMLibExists = false;
}