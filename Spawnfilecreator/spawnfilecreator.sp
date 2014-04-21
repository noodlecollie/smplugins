
#include <sourcemod>
#include <keyvalues>
#include <sdktools>
#include <tf2>

#define DEBUG		1
#pragma semicolon	1

// Debug flags
#define DBG_REMOVEALL	1

#define PLUGIN_NAME 			"Deathmatch Spawn File Creator"
#define PLUGIN_AUTHOR		"[X6] Herbius"
#define PLUGIN_DESCRIPTION	"Creates and handles custom deathmatch spawns for Team Fortress 2."
#define PLUGIN_VERSION		"1.2.0.0"

#define MAX_SPAWN_POINTS	64

// Teams
#define TEAM_INVALID		-1
#define TEAM_UNASSIGNED	0
#define TEAM_SPECTATOR	1
#define TEAM_RED			2
#define TEAM_BLUE			3

// Ent remove types:
#define KILL_RESUPPLY	1
#define KILL_RESPAWN		2
#define KILL_FILTERS		4

// Plugin states:
#define STATE_NO_ACTIVITY	8	// Plugin is loaded while the server is running.
#define STATE_DISABLED		4	// Plugin is disabled. No activity will occur.
#define STATE_EDIT_MODE		2	// Plugin is in spawn editing mode.
#define STATE_NOT_IN_ROUND	1	// Not currently in a round.

// Sounds
#define SOUND_EDIT_MODE			"vo/sniper_go02.wav"
#define SOUND_LOAD_SPAWNS		"vo/sniper_goodjob03.wav"
#define SOUND_ADD_SPAWN_01		"vo/sniper_cheers02.wav"
#define SOUND_ADD_SPAWN_02		"vo/sniper_cheers03.wav"
#define SOUND_ADD_SPAWN_03		"vo/sniper_award04.wav"
#define SOUND_ADD_SPAWN_04		"vo/sniper_meleedare02.wav"
#define SOUND_REMOVE_SPAWN_01	"vo/sniper_paincriticaldeath01.wav"
#define SOUND_REMOVE_SPAWN_02	"vo/sniper_paincriticaldeath02.wav"
#define SOUND_REMOVE_SPAWN_03	"vo/sniper_paincriticaldeath03.wav"
#define SOUND_REMOVE_SPAWN_04	"vo/sniper_paincriticaldeath04.wav"
#define SOUND_FINISH_SPAWNS	"vo/sniper_positivevocalization04.wav"
#define SOUND_CANCEL_SPAWNS	"vo/sniper_jeers01.wav"

// Variable declarations:
new g_PluginState;						// Holds the flags for the global plugin state.

// ConVars:
new Handle:cv_PluginEnabled = INVALID_HANDLE;	// Enables or disables the plugin. Changing this while in-game will restart the map.

public Plugin:myinfo = 
{
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = "https://forums.alliedmods.net/showthread.php?p=1535887"
}

public OnPluginStart()
{
	LogMessage("== Deathmatch Spawn File Creator active, v%s ==", PLUGIN_VERSION);
	LoadTranslations("dmspawn/dmspawn_phrases");
	AutoExecConfig(true, "dmspawn", "sourcemod/dmspawn");
	
	CreateConVar("dmspawn_version", PLUGIN_VERSION, "Plugin version.", FCVAR_PLUGIN | FCVAR_NOTIFY);
	
	cv_PluginEnabled  = CreateConVar("dmspawn_enabled",
												"1",
												"Enables or disables the plugin. Changing this while in-game will restart the map.",
												FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
												true,
												0.0,
												true,
												1.0);
	
	HookConVarChange(cv_PluginEnabled,	CvarChange);
	
	HookEventEx("teamplay_round_start",		Event_RoundStart,	EventHookMode_Post);
	HookEventEx("player_spawn",				Event_Spawn,			EventHookMode_Post);
	
	if ( IsServerProcessing() )
	{
		g_PluginState |= STATE_NO_ACTIVITY;
		LogMessage("[DMS] Plugin loaded while round is active. Plugin will be activated on map change.");
		PrintToChatAll("[DMS] %t", "dms_pluginloadnextmapchange");
		
		return;
	}
}

/*	========== Begin Event Hook Functions ==========	*/

/*	Checks which ConVar has changed and does the relevant things.	*/
public CvarChange( Handle:convar, const String:oldValue[], const String:newValue[] )
{
	// If the enabled/disabled convar has changed, run PluginStateChanged
	if ( convar == cv_PluginEnabled ) PluginEnabledStateChanged(GetConVarBool(cv_PluginEnabled));
}

/*	Called on map start.	*/
public OnMapStart()
{
	// Clear the NO_ACTIVITY flag.
	g_PluginState &= ~STATE_NO_ACTIVITY;
	
	// If disabled, return.
	if ( (g_PluginState & STATE_DISABLED) == STATE_DISABLED ) return;
}

public OnMapEnd()
{
	// Regardless of what state is set, clear the editing state flag.
	g_PluginState &= ~STATE_EDIT_MODE;
}

/*	Called when a new round begins.	*/
public Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	g_PluginState &= ~STATE_NOT_IN_ROUND;
	
	if ( g_PluginState >= STATE_DISABLED ) return;
}

/*	Called when a player spawns.	*/
public Event_Spawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	if ( g_PluginState > 0 ) return;
}

/*	=========== End Event Hook Functions ===========	*/

/*	========== Begin Custom Functions ==========	*/

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
	
	LogMessage("[DMS] Plugin state changed. Restarting map (%s)...", mapname);
	
	// Restart the map
	ServerCommand( "changelevel %s", mapname);
}

/*	Removes all entities with the specified classname.	*/
stock RemoveAll(String:classname)
{
	new i = -1;
	while ( (i = FindEntityByClassname(i, classname)) != -1 )
	{
		AcceptEntityInput(i, "Kill");
		
		#if ( DEBUG & DBG_REMOVEALL == DBG_REMOVEALL )
		LogMessage("%s at index %d was removed.", classname, i);
		#endif
	}
}