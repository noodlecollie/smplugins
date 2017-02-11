/*
  _______ ______ ___    ____  _       _                            _ 
 |__   __|  ____|__ \  |  _ \(_)     | |                          | |
    | |  | |__     ) | | |_) |_  ___ | |__   __ _ ______ _ _ __ __| |
    | |  |  __|   / /  |  _ <| |/ _ \| '_ \ / _` |_  / _` | '__/ _` |
    | |  | |     / /_  | |_) | | (_) | | | | (_| |/ / (_| | | | (_| |
    |_|  |_|    |____| |____/|_|\___/|_| |_|\__,_/___\__,_|_|  \__,_|
	
	[X6] Herbius, 16th April 2012
*/

/*
Notes:
- m_flMaxSpeed in CBasePlayer defines player speed.
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
#define PLUGIN_NAME			"TF2 Biohazard"
#define PLUGIN_AUTHOR		"[X6] Herbius"
#define PLUGIN_DESCRIPTION	"Hold off the zombies to win the round!"
#define PLUGIN_VERSION		"0.0.0.1"
#define PLUGIN_URL			"http://x6herbius.com/"

// State flags
// Control what aspects of the plugin will run.
#define STATE_DISABLED		16	// Plugin is disabled via convar. No gameplay-modifying activity will occur.
#define STATE_FEW_PLAYERS	8	// There are not enough players to begin a game.
#define STATE_NOT_IN_ROUND	4	// Round has ended or has not yet begun.
#define STATE_AWAITING		1	// A round has started and the Blue team is empty because no-one has yet become a zombie.

// Debug flags
// Used with tfbh_debug to display debug messages to the server console.
#define DEBUG_GENERAL		1	// General debugging.
#define DEBUG_TEAMCHANGE	2	// Debugging team changes.
#define DEBUG_HEALTH		4	// Debugging health calculations.
#define DEBUG_DAMAGE		8	// Debugging OnTakeDamage hook.
#define DEBUG_DATA			16	// Debugging data arrays.
#define DEBUG_CRASHES		32	// Debugging crashes. NOTE: These are probably caused by an outdated SM, so check the latest branch first.
#define DEBUG_ZOMBIFY		64	// Debugging creation of zombies.
#define DEBUG_RAGE			128	// Debugging zombie rage.

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

// Change the following to specify what the plugin should change the balancing CVars to. Must be integers.
#define DES_UNBALANCE		0	// Desired value for mp_teams_unbalance_limit
#define DES_AUTOBALANCE		0	// Desired value for mp_autoteambalance
#define DES_SCRAMBLE		0	// Desired value for mp_scrambleteams_auto

new g_PluginState;		// Holds the global state of the plugin.
new g_Disconnect;		// Sidesteps team count issues by tracking the index of a disconnecting player. See Event_TeamsChange.
new bool:b_AllowChange;	// If true, team changes will not be blocked.
new bool:b_Setup;		// If true, PluginStart has already run. This avoids double loading from OnMapStart when plugin is loaded during a game.
new g_GameRules = -1;	// Index of a tf_gamerules entity.

// Player data
new g_userIDMap[MAXPLAYERS];					// For a userID at index n, this player's data will be found in index n of the rest of the data arrays.
												// If index n < 1, index n in data arrays is free for use.
new bool:g_Zombie[MAXPLAYERS] = {true, ...};	// True if the player is infected, false otherwise. Should start true so that Blue is the team new players join into.
new g_Health[MAXPLAYERS];						// Records a client's health. Only taken into account if they are flagged as a zombie.
new g_MaxHealth[MAXPLAYERS];					// Records a client's max health before it is changed.
new bool:g_StartBoost[MAXPLAYERS];				// If true, player has begun the round as a zombie and should receive crits/speed boost until the end of the round.
new Float:g_Rage[MAXPLAYERS];					// Counter for zombie rage.
new bool:g_Raging[MAXPLAYERS];					// True if zombie is currently in rage state.

// ConVars
new Handle:cv_PluginEnabled = INVALID_HANDLE;		// Enables or disables the plugin.
new Handle:cv_Debug = INVALID_HANDLE;				// Enables or disables debugging using debug flags.
new Handle:cv_DebugRage = INVALID_HANDLE;			// If 1, enables rage charging rate output.
new Handle:cv_Pushback = INVALID_HANDLE;			// General multiplier for zombie pushback.
new Handle:cv_SentryPushback = INVALID_HANDLE;		// Multiplier for sentry pushback.
new Handle:cv_ZHMin = INVALID_HANDLE;				// Minimum zombie health multiplier when against number of players specified in tfbh_zhscale_minplayers.
new Handle:cv_ZHMinPlayers = INVALID_HANDLE;		// When players are <= this value, zombies will be given minimum health.
new Handle:cv_ZHMax = INVALID_HANDLE;				// Maximum zombie health multiplier when against number of players specified in tfbh_zhscale_maxplayers.
new Handle:cv_ZHMaxPlayers = INVALID_HANDLE;		// When players are >= this value, zombies will be given maximum health.
new Handle:cv_ZombieRatio = INVALID_HANDLE;			// At the beginning of a round, the number of zombies that spawn is the quotient of (Red players/this value), rounded up.
new Handle:cv_ZRespawnMin = INVALID_HANDLE;			// Minimum respawn time for zombies, when all survivors are alive.
new Handle:cv_ZRespawnMax = INVALID_HANDLE;			// Maximum respawn time for zombies, when one survivor is left alive.
new Handle:cv_ZRageChargeClose = INVALID_HANDLE;	// The max percentage rate at which a zombie's rage will charge every second when they are close to Red players.
new Handle:cv_ZRageChargeFar = INVALID_HANDLE;		// The min percentage rate at which a zombie's rage will charge every second when they are far from Red players.
new Handle:cv_ZRageCloseDist = INVALID_HANDLE;		// 'Close' distance to Red players, when zombie rage will charge fastest.
new Handle:cv_ZRageFarDist = INVALID_HANDLE;		// 'Far' distance from Red players, when zombie rage will charge slowest.
new Handle:cv_ZRageDuration = INVALID_HANDLE;		// How long a zombie's rage lasts, in seconds.
new Handle:cv_ZRageRadius = INVALID_HANDLE;			// The radius within which other zombies will be granted mini-crits when a zombie rages.
new Handle:cv_ZRageStunRadius = INVALID_HANDLE;		// The radius within which players and sentries will be stunned when a zombie rages.
new Handle:cv_ZRageStunDuration = INVALID_HANDLE;	// Duration to stun players when a zombie rages. Sentries remain stunned for an extra two seconds.

// Timers
new Handle:timer_ZRefresh = INVALID_HANDLE;	// Timer to refresh zombie health.
new Handle:timer_Cond = INVALID_HANDLE;		// Timer to refresh zombie conditions.

 // HUD syncs
new Handle:hs_ZText = INVALID_HANDLE;		// HUD sync for showing zombie info text.

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
										"127",
										"Enables or disables debugging using debug flags.",
										FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_DONTRECORD,
										true,
										0.0);
	
	cv_DebugRage  = CreateConVar("tfbh_debug_rage",
										"0",
										"If 1, enables rage charging rate output.",
										FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_DONTRECORD,
										true,
										0.0,
										true,
										1.0);
	
	cv_Pushback = CreateConVar("tfbh_pushback_scale",
										"2.0",
										"General multiplier for zombie pushback.",
										FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
										true,
										0.0,
										true,
										10.0);
	
	cv_Pushback = CreateConVar("tfbh_sentry_pushback_scale",
										"0.5",
										"Multiplier for sentry pushback.",
										FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
										true,
										0.0,
										true,
										10.0);
	
	cv_ZHMin = CreateConVar("tfbh_zhscale_min",
										"1.0",
										"Minimum zombie health multiplier when against number of players specified in tfbh_zhscale_minplayers.",
										FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
										true,
										1.0);
	
	cv_ZHMinPlayers = CreateConVar("tfbh_zhscale_minplayers",
										"1",
										"When players are <= this value, zombies will be given minimum health.",
										FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
										true,
										1.0);
	
	cv_ZHMax = CreateConVar("tfbh_zhscale_max",
										"16.0",
										"Maximum zombie health multiplier when against number of players specified in tfbh_zhscale_maxplayers.",
										FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
										true,
										1.0);
	
	cv_ZHMaxPlayers = CreateConVar("tfbh_zhscale_maxplayers",
										"24",
										"When players are >= this value, zombies will be given maximum health.",
										FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
										true,
										1.0);
										
	cv_ZombieRatio = CreateConVar("tfbh_zombie_player_ratio",
										"7",
										"At the beginning of a round, the number of zombies that spawn is the quotient of (Red players/this value), rounded up.",
										FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
										true,
										1.0);
	
	cv_ZRespawnMin = CreateConVar("tfbh_zrespawn_min",
										"1",
										"Minimum respawn time for zombies, when all survivors are alive.",
										FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
										true,
										0.0);
	
	cv_ZRespawnMax = CreateConVar("tfbh_zrespawn_max",
										"6",
										"Maximum respawn time for zombies, when one survivor is left alive.",
										FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
										true,
										0.0);
	
	cv_ZRageChargeClose = CreateConVar("tfbh_zrage_maxrate",
										"6",
										"The max percentage rate at which a zombie's rage will charge every second when they are close to Red players.",
										FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
										true,
										0.0,
										true,
										100.0);
	
	cv_ZRageChargeFar = CreateConVar("tfbh_zrage_minrate",
										"0.5",
										"The min percentage rate at which a zombie's rage will charge every second when they are far from Red players.",
										FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
										true,
										0.0,
										true,
										100.0);
	
	cv_ZRageCloseDist = CreateConVar("tfbh_zrage_close",
										"128",
										"'Close' distance to Red players, when zombie rage will charge fastest.",
										FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
										true,
										0.0);
	
	cv_ZRageFarDist = CreateConVar("tfbh_zrage_far",
										"1024",
										"'Far' distance to Red players, when zombie rage will charge slowest.",
										FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
										true,
										0.0);
	
	cv_ZRageDuration = CreateConVar("tfbh_zrage_duration",
										"8",
										"How long a zombie's rage lasts, in seconds.",
										FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
										true,
										0.5);
	
	cv_ZRageRadius = CreateConVar("tfbh_zrage_radius",
										"300",
										"The radius within which other zombies will be granted mini-crits when a zombie rages.",
										FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
										true,
										8.0);
	
	cv_ZRageStunRadius = CreateConVar("tfbh_zrage_stunradius",
										"128",
										"The radius within which players and sentries will be stunned when a zombie rages.",
										FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
										true,
										8.0);
	
	cv_ZRageStunDuration = CreateConVar("tfbh_zrage_stunduration",
										"3",
										"Duration to stun players when a zombie rages.",
										FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
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
	HookEventEx("player_death",				Event_PlayerDeath,		EventHookMode_Post);
	HookEventEx("player_spawn",				Event_PlayerSpawn,		EventHookMode_Post);
	
	AddCommandListener(TeamChange,	"jointeam");	// For blocking team change commands.
	AddCommandListener(DoTaunt,		"taunt");		// Activating zombie rage.
	AddCommandListener(DoTaunt,		"+taunt");
	
	HookConVarChange(cv_PluginEnabled,	CvarChange);
	HookConVarChange(cv_Unbalance,		CvarChange);
	HookConVarChange(cv_Autobalance,	CvarChange);
	HookConVarChange(cv_Scramble,		CvarChange);
	
	RegConsoleCmd("tfbh_debug_showdata", Debug_ShowData, "Outputs player data arrays to the console.", FCVAR_PLUGIN | FCVAR_CHEAT);
	
	decl String:deb[8];
	GetConVarDefault(cv_Debug, deb, sizeof(deb));
	if ( StringToInt(deb) > 0 )
	{
		LogMessage("Debug cvar default is not 0! Reset this before release!");
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
	
	b_Setup = true;
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
	
	// Disable resupply lockers.
	new i = -1;
	while ( (i = FindEntityByClassname(i, "func_regenerate")) != -1 )
	{
		AcceptEntityInput(i, "Disable");
	}
	
	// Allow team changes to Red.
	b_AllowChange = true;
	
	// Move everyone on Blue to the Red team.
	for ( i = 1; i <= MaxClients; i++ )
	{
		if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Checking client %d...", i);
		
		if ( IsClientConnected(i) && !IsClientReplay(i) && !IsClientSourceTV(i) )
		{
			if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Client %d (%N) is connected.", i, i);
			
			if ( IsClientInGame(i) && GetClientTeam(i) == TEAM_BLUE )	// If the player is on Blue:
			{
				if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Cleared zombie flag for client %N.", i);
				g_Zombie[DataIndexForUserId(GetClientUserId(i))] = false;	// Mark the player as not being a zombie.
				
				if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Changing %N to Red.", i);
				ChangeClientTeam(i, TEAM_RED);							// Change the player to Red.
				TF2_RespawnPlayer(i);
			}
		}
	}
	
	// Finished adding players to the Red team.
	b_AllowChange = false;
	
	ModifyRespawnTimes();	// Set up respawn times for the round.
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
	
	// Clear the AWAITING flag. This will ensure that if Blue drops to 0 players from this point on, Red will win the game.
	g_PluginState &= ~STATE_AWAITING;
	
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
		
		MakeClientZombie2(players[i]);											// Make the client into a zombie.
		g_StartBoost[DataIndexForUserId(GetClientUserId(players[i]))] = true;	// Mark them as being roundstart boosted.
	}
}

/*	Called when a player changes team.	*/
public Event_TeamsChange(Handle:event, const String:name[], bool:dontBroadcast)
{
	if ( (g_PluginState & STATE_DISABLED == STATE_DISABLED) )
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
	
	// IGNORE
	// If the player is marked as a zombie but is changing to a team that is not Blue, clear the flag.
	// Ignore if the client is disconnecting, since this is dealt with elsewhere.
	//if ( !disconnect && g_Zombie[DataIndexForUserId(userid)] && newTeam != TEAM_BLUE ) g_Zombie[DataIndexForUserId(userid)] = false;
	
	// If this hook is fired it means the player was allowed through the jointeam command listener.
	// If they are changing to any team which is not Red, set the Zombie flag.
	// This means that they will not be able to rejoin Red until the next round.
	if ( !disconnect )
	{
		if ( newTeam != TEAM_RED ) g_Zombie[DataIndexForUserId(userid)] = true;
		else g_Zombie[DataIndexForUserId(userid)] = false;
	}
	
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
	// If we are still awaiting the first zombie, allow changes to Red from any team,
	// changes to spec from any team and disallow changes to Blue.
	// If the found is fully in progress, disallow changes to Red from any team,
	// allow changes to spec from any team and allow changes to Blue only if the
	// client is a Zombie.
	
	if ( b_AllowChange ) return Plugin_Continue;	// If this flag is true then players are being swapped in round initialisation, don't restrict.
	
	new String:arg[16];
	GetCmdArg(1, arg, sizeof(arg));
	if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Arg: %s", arg);
	
	if ( g_PluginState & STATE_AWAITING == STATE_AWAITING )	// If a zombie has yet to be chosen:
	{
		// Disallow players joining Blue.
		if ( StrContains(arg, "blue", false) != -1 || StrContains(arg, "auto", false) != -1 )
		{
			if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Arg contains blue or auto, overriding to red.");
			FakeClientCommandEx(client, "jointeam red");	// Ex is delayed by 1 frame
			return Plugin_Handled;
		}
	}
	else	// The first zombie has been chosen.
	{
		// Disallow players joining Red if they are marked as a zombie.
		if ( (StrContains(arg, "red", false) != -1 || StrContains(arg, "auto", false) != -1) && g_Zombie[DataIndexForUserId(GetClientUserId(client))] )
		{
			if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Arg contains red or auto, overriding to blue.");
			FakeClientCommandEx(client, "jointeam blue");	// Ex is delayed by 1 frame
			return Plugin_Handled;
		}
		// Disallow players joining Blue if they are not marked as a zombie,
		else if ( (StrContains(arg, "blue", false) != -1 || StrContains(arg, "auto", false) != -1) && !g_Zombie[DataIndexForUserId(GetClientUserId(client))] )
		{
			if ( cvDebug & DEBUG_TEAMCHANGE == DEBUG_TEAMCHANGE ) LogMessage("Arg contains blue or auto, overriding to red.");
			FakeClientCommandEx(client, "jointeam red");	// Ex is delayed by 1 frame
			return Plugin_Handled;
		}
	}
	
	return Plugin_Continue;
}

/*	For checking zombies to activate rage.	*/
public Action:DoTaunt(client, const String:command[], argc)
{
	// Don't check unless the round has fully started.
	if ( g_PluginState > 0	) return Plugin_Continue;
	
	// Check to see if the client is a zombie with full rage.
	if ( !IsClientInGame(client) || GetClientTeam(client) != TEAM_BLUE || !IsPlayerAlive(client) ) return Plugin_Continue;
	
	new index = DataIndexForUserId(GetClientUserId(client));
	if ( !g_Zombie[index] || g_Rage[index] < 100.0 || g_Raging[client] ) return Plugin_Continue;
	
	// Rage should be activated. Set the raging flag (decrease of rage meter is handled elsewhere).
	g_Raging[index] = true;
	
	// Stun any players within the specified radius.
	new Float:cOrigin[3];
	GetClientAbsOrigin(client, cOrigin);
	
	for ( new i = 1; i <= MaxClients; i++ )
	{
		if ( IsClientInGame(i) && GetClientTeam(i) == TEAM_RED && IsPlayerAlive(i) )
		{
			new Float:tOrigin[3];
			GetClientAbsOrigin(i, tOrigin);
			if ( GetConVarInt(cv_Debug) & DEBUG_RAGE == DEBUG_RAGE ) LogMessage("Getting origin of %N.", i);
			
			if ( !TF2_IsPlayerInCondition(i, TFCond_Ubercharged) && GetVectorDistance(cOrigin, tOrigin) <= GetConVarFloat(cv_ZRageStunRadius) )
			{
				TF2_StunPlayer(i, GetConVarFloat(cv_ZRageStunDuration), 0.0, TF_STUNFLAGS_GHOSTSCARE, client);
				if ( GetConVarInt(cv_Debug) & DEBUG_RAGE == DEBUG_RAGE ) LogMessage("Player %N stunned by zombie %N.", i, client);
			}
		}
	}
	
	// Stun any sentries within the specified radius.
	new ent = -1;
	while ( (ent = FindEntityByClassname(ent, "obj_sentrygun")) != -1 )
	{
		new Float:tOrigin[3];
		GetEntPropVector(ent, Prop_Send, "m_vecOrigin", tOrigin);
		
		if ( GetVectorDistance(cOrigin, tOrigin) <= GetConVarFloat(cv_ZRageStunRadius) )
		{
			SetEntProp(ent, Prop_Send, "m_bDisabled", 1);
			new particle = AttachParticle(ent, "yikes_fx", 75.0);
			
			new Handle:pack = CreateDataPack();
			WritePackCell(pack, EntIndexToEntRef(ent));			// Record the sentry.
			WritePackCell(pack, EntIndexToEntRef(particle));	// Record the particle.
			
			CreateTimer(GetConVarFloat(cv_ZRageDuration) + 2.0, Timer_EnableStunnedSentry, pack);
		}
	}
	
	return Plugin_Handled;
}

/*	Called when a client connects.	*/
public OnClientConnected(client)
{
	// Don't set up things for Replay or Source TV.
	if ( IsClientReplay(client) || IsClientSourceTV(client) ) return;
	
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
	// Don't set up things for Replay or Source TV.
	if ( IsClientReplay(client) || IsClientSourceTV(client) ) return;
	
	// Clear the client's data arrays.
	ClearAllDataForPlayer(GetClientUserId(client));
	
	if ( g_PluginState & STATE_DISABLED == STATE_DISABLED ) return;
	
	SDKUnhook(client, SDKHook_OnTakeDamage,		OnTakeDamage);
	SDKUnhook(client, SDKHook_OnTakeDamagePost,	OnTakeDamagePost);
}

public OnClientPutInServer(client)
{
	if ( g_PluginState & STATE_DISABLED == STATE_DISABLED ) return;
	
	// Don't set up things for Replay or Source TV.
	if ( IsClientReplay(client) || IsClientSourceTV(client) ) return;
	
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
	
	new userid = GetClientUserId(client);
	new index = DataIndexForUserId(userid);
	new cvDebug = GetConVarInt(cv_Debug);
	
	// If the player is on Red and not a zombie, the attacker is on Blue and is a zombie and the damage will kill the player, convert Red player to zombie.
	// This jumps in before the player actually dies, since it's nigh impossible to respawn the player instantly in the
	// same place using the death hook.
	
	// #BUG#: Sometimes this hook returns the damage dealt as less than the client's health, yet the client still dies.
	// This could be due to a damage flag I'm not checking for (I hope), or the damage/health values are inaccurate (bad).
	
	//if ( cvDebug & DEBUG_ZOMBIFY == DEBUG_ZOMBIFY ) LogMessage("Team %d, damage %f, health %d, attacker %d, attacker team %d, g_Zombie %d", GetClientTeam(client), damage, GetEntProp(client, Prop_Send, "m_iHealth"), attacker, GetClientTeam(attacker), g_Zombie[DataIndexForUserId(GetClientUserId(attacker))]);
	
	if ( GetClientTeam(client) == TEAM_RED && attacker > 0 && attacker <= MaxClients && GetClientTeam(attacker) == TEAM_BLUE && g_Zombie[DataIndexForUserId(GetClientUserId(attacker))] )	// Must use the player health property here, since g_Health doesn't update until the post hook.
	{
		// Apparently damage contains only the base damage, meaning if the attack was a crit/mini-crit and would kill the player
		// the damage value wouldn't necessarily be greater than the player's health in this hook, and so the player would die normally.
		// We need to check whether the attack is a crit/mini-crit and if so, check the correct multiple of the damage dealt.
		
		if ( cvDebug & DEBUG_ZOMBIFY == DEBUG_ZOMBIFY )
		{
			LogMessage("Client %N hurt by zombie %N", client, attacker);
			
			if ( damagetype & DMG_CRIT == DMG_CRIT )
			{
				LogMessage("Damage CRIT, damage %f, x3 = %f, health %f", damage, damage * 3.0, float(GetEntProp(client, Prop_Send, "m_iHealth")));
			}
			// NOTE
			else if ( damagetype & DMG_ACID == DMG_ACID )
			{
				LogMessage("Damage ACID (mini-crit), damage %f, x1.35 = %f, health %f", damage, damage * 1.35, float(GetEntProp(client, Prop_Send, "m_iHealth")));
			}
			else
			{
				LogMessage("Damage normal, damage %f, type %d health %f", damage, damagetype, float(GetEntProp(client, Prop_Send, "m_iHealth")));
			}
		}
		
		if ( damage >= float(GetEntProp(client, Prop_Send, "m_iHealth")) || (damagetype & DMG_CRIT == DMG_CRIT && damage * 3.0 >= float(GetEntProp(client, Prop_Send, "m_iHealth"))) || (damagetype & DMG_ACID == DMG_ACID && damage * 1.35 >= float(GetEntProp(client, Prop_Send, "m_iHealth"))) )
		{
			if ( cvDebug & DEBUG_ZOMBIFY == DEBUG_ZOMBIFY ) LogMessage("Client %N killed by zombie %N", client, attacker);
			damage = 0.0;															// Negate the damage.
			MakeClientZombie2(client);												// Make the client a zombie.
			BuildZombieMessage(client, attacker, inflictor, damagetype, weapon);	// Build and fire the death message.
			return Plugin_Changed;
		}
		else if ( cvDebug & DEBUG_ZOMBIFY == DEBUG_ZOMBIFY ) LogMessage("Damage not enough to kill player.");
	}
	
	// If the player is on Blue and a zombie, and the attacker is on Red and not a zombie, increase the pushback.
	else if ( GetClientTeam(client) == TEAM_BLUE && g_Zombie[index] &&
			attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker) &&
			GetClientTeam(attacker) == TEAM_RED && !g_Zombie[DataIndexForUserId(GetClientUserId(attacker))] )
	{
		new Float:mx;
		if ( IsValidEntity(inflictor) )
		{
			new String:classname[64];
			GetEntityClassname(inflictor, classname, sizeof(classname));
			
			if ( StrEqual(classname, "obj_sentrygun") ) mx = GetConVarFloat(cv_SentryPushback);
			else mx = GetConVarFloat(cv_Pushback);
		}
		else mx = GetConVarFloat(cv_Pushback);
		
		damageForce[0] = damageForce[0] * mx;	// This method seems to work better...?
		damageForce[1] = damageForce[1] * mx;
		damageForce[2] = damageForce[2] * mx;
		//ScaleVector(damageForce, GetConVarFloat(cv_Pushback));
		
		return Plugin_Changed;
	}
	
	return Plugin_Continue;
}

public Action:OnTakeDamagePost(client, &attacker, &inflictor, &Float:damage, &damagetype, &weapon, Float:damageForce[3], Float:damagePosition[3])
{
	// Don't bother checking damage values if we're not in a valid round.
	if ( g_PluginState & STATE_DISABLED == STATE_DISABLED ||
			g_PluginState & STATE_NOT_IN_ROUND == STATE_NOT_IN_ROUND ||
			g_PluginState & STATE_FEW_PLAYERS == STATE_FEW_PLAYERS ) return Plugin_Continue;
	
	new userid = GetClientUserId(client);
	new index = DataIndexForUserId(userid);
	
	if ( GetConVarInt(cv_Debug) & DEBUG_ZOMBIFY == DEBUG_ZOMBIFY ) LogMessage("Client %N's health is now %d", client, GetEntProp(client, Prop_Send, "m_iHealth"));
	
	// If a zombie was hurt, update their recorded health.
	if ( GetClientTeam(client) == TEAM_BLUE && g_Zombie[index] )
	{
		g_Health[index] = GetEntProp(client, Prop_Send, "m_iHealth");
	}

	return Plugin_Continue;
}

/*	Called when a player dies.	*/
public Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	if ( g_PluginState & STATE_DISABLED == STATE_DISABLED ||
			g_PluginState & STATE_NOT_IN_ROUND == STATE_NOT_IN_ROUND ||
			g_PluginState & STATE_FEW_PLAYERS == STATE_FEW_PLAYERS ) return;
	
	new cvDebug = GetConVarInt(cv_Debug);
	
	new userid = GetEventInt(event, "userid");
	new client = GetClientOfUserId(userid);
	//new atuserid = GetEventInt(event, "attacker");
	//new attacker = GetClientOfUserId(atuserid);
	//new deathFlags = GetEventInt(event, "death_flags");
	
	// If the player is a Red Engineer, destroy their sentry.
	if ( GetClientTeam(client) == TEAM_RED && TF2_GetPlayerClass(client) == TFClass_Engineer )
	{
		if ( cvDebug & DEBUG_GENERAL == DEBUG_GENERAL ) LogMessage("Client %N is a Red Engineer, killing any sentries.", client);
		KillBuildings(client, BUILD_SENTRY);
	}
	
	// VV REDUNDANT: Handled in damage pre-hook instead. VV
	// If the player was on Red and not a zombie, and the killer was on Blue and was a zombie, and the player didn't DR,
	// change them into a zombie.
	/*if ( GetClientTeam(client) == TEAM_RED && !g_Zombie[DataIndexForUserId(userid)] &&
			attacker > 0 && attacker <= MaxClients && GetClientTeam(attacker) == TEAM_BLUE && g_Zombie[DataIndexForUserId(atuserid)] &&
			deathFlags & 32 != 32 )
	{
		if ( cvDebug & DEBUG_GENERAL == DEBUG_GENERAL ) LogMessage("%N killed by zombie %N.", client, attacker);
		MakeClientZombie(client, true);
		
	}*/
	
	CreateTimer(0.1, Timer_CheckTeams);
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
	
	// If the player is on Blue and is a zombie, remove unwanted weapon slots.
	if ( GetClientTeam(client) == TEAM_BLUE && g_Zombie[index] )
	{
		SetLargeHealth(client);
		
		ManageZombieWeapons(client);
		EquipSlot(client, SLOT_MELEE);
		g_Rage[index] = 0.0;
		g_Raging[index] = false;
	}
	
	if ( g_PluginState & STATE_NOT_IN_ROUND == STATE_NOT_IN_ROUND ) return;
}

/*	To prevent zombies from picking up health.	*/
public Action:OnHealthPackTouch(entity, other) 
{ 
    if (other > 0 && other <= MaxClients && g_Zombie[DataIndexForUserId(GetClientUserId(other))]) return Plugin_Handled; 
    return Plugin_Continue; 
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
	new ent = FindEntityByClassname(-1, "team_control_point_master");
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
				g_Health[i] = 0;
				g_MaxHealth[i] = 0;
				g_StartBoost[i] = false;
				g_Rage[i] = 0.0;
				g_Raging[i] = false;
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
			
			if ( timer_Cond == INVALID_HANDLE )
			{
				timer_Cond = CreateTimer(1.0, Timer_CondRefresh, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
			}
			
			if ( hs_ZText == INVALID_HANDLE )
			{
				hs_ZText = CreateHudSynchronizer();
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
				if ( IsClientConnected(i) && !IsClientReplay(i) && !IsClientSourceTV(i) )
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
			
			if ( timer_Cond != INVALID_HANDLE )
			{
				KillTimer(timer_Cond);
				timer_Cond = INVALID_HANDLE;
			}
			
			if ( hs_ZText != INVALID_HANDLE )
			{
				CloseHandle(hs_ZText);
				hs_ZText = INVALID_HANDLE;
			}
		}
		
		case CLEANUP_ROUNDSTART:	// Called even if plugin is disabled, so don't put anything important here.
		{
			// Reset all stored health values.
			for ( new i = 0; i < MAXPLAYERS; i++ )
			{
				g_Health[i] = 0;
				g_MaxHealth[i] = 0;
				g_Rage[i] = 0.0;
				g_Raging[i] = false;
			}
		}
		
		case CLEANUP_MAPSTART:
		{
			// MapStart gets called when the plugin is loaded as well as OnPluginStart.
			// If PluginStart has already run, reset the flag and exit.
			// This is to make sure the data indices don't get cleared multiple times.
			if ( b_Setup )
			{
				b_Setup = false;
				return;
			}
			
			if ( timer_ZRefresh == INVALID_HANDLE )
			{
				timer_ZRefresh = CreateTimer(0.2, Timer_ZombieHealthRefresh, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
			}
			
			if ( timer_Cond == INVALID_HANDLE )
			{
				timer_Cond = CreateTimer(1.0, Timer_CondRefresh, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
			}
			
			if ( hs_ZText == INVALID_HANDLE )
			{
				hs_ZText = CreateHudSynchronizer();
			}
			
			// Reset all data arrays.
			// Is this needed?
			for ( new i = 0; i < MAXPLAYERS; i++ )
			{
				ClearAllArrayDataForIndex(i, true);
			}
			
			g_GameRules = FindEntityByClassname(-1, "tf_gamerules");
			
			if ( g_GameRules < 1 )
			{
				g_GameRules = CreateEntityByName("tf_gamerules");
				
				if ( g_GameRules < 1 )
				{
					LogError("ERROR: tf_gamerules unable to be found or created!");
					return;
				}
				
				DispatchKeyValue(g_GameRules, "targetname", "tf_gamerules");
				
				if ( !DispatchSpawn(g_GameRules) )
				{
					LogError("ERROR: tf_gamerules unable to be found or created!");
					return;
				}
			}
			
			// Hook health packs.
			new i = -1;
			while ( (i = FindEntityByClassname(i, "item_healthkit_small")) != -1 )
			{
				SDKHook(i, SDKHook_Touch, OnHealthPackTouch);
			}
			
			i = -1;
			while ( (i = FindEntityByClassname(i, "item_healthkit_medium")) != -1 )
			{
				SDKHook(i, SDKHook_Touch, OnHealthPackTouch);
			}
			
			i = -1;
			while ( (i = FindEntityByClassname(i, "item_healthkit_full")) != -1 )
			{
				SDKHook(i, SDKHook_Touch, OnHealthPackTouch);
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
			
			if ( timer_Cond != INVALID_HANDLE )
			{
				KillTimer(timer_Cond);
				timer_Cond = INVALID_HANDLE;
			}
			
			if ( hs_ZText != INVALID_HANDLE )
			{
				CloseHandle(hs_ZText);
				hs_ZText = INVALID_HANDLE;
			}
			
			g_GameRules = -1;
			
			// Unook health packs.
			new i = -1;
			while ( (i = FindEntityByClassname(i, "item_healthkit_small")) != -1 )
			{
				SDKUnhook(i, SDKHook_Touch, OnHealthPackTouch);
			}
			
			i = -1;
			while ( (i = FindEntityByClassname(i, "item_healthkit_medium")) != -1 )
			{
				SDKUnhook(i, SDKHook_Touch, OnHealthPackTouch);
			}
			
			i = -1;
			while ( (i = FindEntityByClassname(i, "item_healthkit_full")) != -1 )
			{
				SDKUnhook(i, SDKHook_Touch, OnHealthPackTouch);
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
	g_Health[index] = 0;
	g_MaxHealth[index] = 0;
	g_StartBoost[index] = false;
	g_Rage[index] = 0.0;
	g_Raging[index] = false;
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

/*	Sets up a client as a zombie.
	NOTE: Deprecated, use MakeClientZombie2.	*/
stock MakeClientZombie(client, bool:death = false)
{
	KillBuildings(client, BUILD_SENTRY | BUILD_DISPENSER | BUILD_TELEPORTER);	// Kill the client's buildings (class is checked in function).
	
	if ( !death ) SetEntProp(client, Prop_Send, "m_lifeState", 2);				// Make sure the client won't die when we change their team.
	ChangeClientTeam(client, TEAM_BLUE);										// Change them to Blue.
	if ( !death ) SetEntProp(client, Prop_Send, "m_lifeState", 0);				// Reset the lifestate variable.
	
	g_Zombie[DataIndexForUserId(GetClientUserId(client))] = true;				// Mark them as a zombie.
	
	if ( death )
	{
		new Float:clientPos[3], Float:clientAng[3];
		GetClientAbsAngles(client, clientAng);
		GetClientAbsOrigin(client, clientPos);
		
		new Handle:pack = CreateDataPack();
		WritePackCell(pack, GetClientUserId(client));
		WritePackFloat(pack, clientPos[0]);
		WritePackFloat(pack, clientPos[1]);
		WritePackFloat(pack, clientPos[2]);
		WritePackFloat(pack, clientAng[0]);
		WritePackFloat(pack, clientAng[1]);
		WritePackFloat(pack, clientAng[2]);
		CreateTimer(0.0, Timer_RespawnTelePlayer, pack);
		
		return;
	}
	
	if ( GetConVarInt(cv_Debug) & DEBUG_HEALTH == DEBUG_HEALTH ) LogMessage("%N's class : %d", client, TF2_GetPlayerClass(client));
	
	SetLargeHealth(client);
	
	TF2_RemoveWeaponSlot(client, SLOT_PRIMARY);						// Remove their primary weapon.
	TF2_RemoveWeaponSlot(client, SLOT_SECONDARY);					// Remove their secslot weapon.
	EquipSlot(client, SLOT_MELEE);									// Equip melee.
}

/*	Steps to make a client a zombie:
	- Kill their buildings
	- Change their team
	- Mark them as a zombie in the data arrays
	- Resupply them
	- Set their health multiplier
	- Take away any disallowed weapons
	- Equip melee	*/
stock MakeClientZombie2(client)
{
	KillBuildings(client, BUILD_SENTRY | BUILD_DISPENSER | BUILD_TELEPORTER);	// Kill the client's buildings (class is checked in function).
	//DissociateBuildings(client, BUILD_DISPENSER | BUILD_TELEPORTER);			// Dissociate the dispenser and teleporter so that they still work when the team is switched.
	
	new index = DataIndexForUserId(GetClientUserId(client));
	
	TF2_RemoveCondition(client, TFCond_Taunting);		// Zombification while taunting can cause issues.
	g_Zombie[index] = true;								// Mark the client as a zombie.
	g_Rage[index] = 0.0;								// Reset their rage.
	SetEntProp(client, Prop_Send, "m_lifeState", 2);	// Make sure the client won't die when we change their team.
	ChangeClientTeam(client, TEAM_BLUE);				// Change them to Blue.
	SetEntProp(client, Prop_Send, "m_lifeState", 0);	// Reset the lifestate variable.
	TF2_RegeneratePlayer(client);						// Resupply.
	
	if ( GetConVarInt(cv_Debug) & DEBUG_HEALTH == DEBUG_HEALTH ) LogMessage("%N's class : %d", client, TF2_GetPlayerClass(client));
	SetLargeHealth(client);
	
	ManageZombieWeapons(client);												// Remove appropriate weapons.
	EquipSlot(client, SLOT_MELEE);												// Equip melee.
}

/*	Removes a client's weapons that are disallowed when they are a zombie.	*/
stock ManageZombieWeapons(client)
{
	switch (TF2_GetPlayerClass(client))
	{
		case TFClass_Scout:
		{
			TF2_RemoveWeaponSlot(client, SLOT_PRIMARY);						// No primary weapons allowed.
			
			new secslot = GetPlayerWeaponSlot(client, SLOT_SECONDARY);	// Some secondaries allowed.
			if ( IsValidEntity(secslot) )									// If the player has a secslot weapon:
			{
				decl String:classname[64];
				if ( GetEntityClassname(secslot, classname, sizeof(classname)) && StrContains(classname, "tf_weapon", false) != -1 )
				{
					switch (GetEntProp(secslot, Prop_Send, "m_iItemDefinitionIndex"))
					{
						case 46, 163, 222: {}									// Bonk, Crit-a-Cola, Mad Milk are allowed, do nothing.
						default: TF2_RemoveWeaponSlot(client, SLOT_SECONDARY);	// Otherwise remove the weapon.
					}
				}
				else TF2_RemoveWeaponSlot(client, SLOT_SECONDARY);
			}
			else TF2_RemoveWeaponSlot(client, SLOT_SECONDARY);
			
			// Melee weapons are always allowed.
		}
		
		case TFClass_Sniper:
		{
			TF2_RemoveWeaponSlot(client, SLOT_PRIMARY);						// No primary weapons allowed.
			
			new secslot = GetPlayerWeaponSlot(client, SLOT_SECONDARY);	// Some secondaries allowed.
			if ( IsValidEntity(secslot) )									// If the player has a secslot weapon:
			{
				decl String:classname[64];
				if ( GetEntityClassname(secslot, classname, sizeof(classname)) && StrContains(classname, "tf_weapon", false) != -1 )
				{
					switch (GetEntProp(secslot, Prop_Send, "m_iItemDefinitionIndex"))
					{
						case 58: {}												// Jarate is allowed, do nothing.
						default: TF2_RemoveWeaponSlot(client, SLOT_SECONDARY);	// Otherwise remove the weapon.
					}
				}
				else TF2_RemoveWeaponSlot(client, SLOT_SECONDARY);
			}
			else TF2_RemoveWeaponSlot(client, SLOT_SECONDARY);
			
			// Melee weapons are always allowed.
		}
		
		case TFClass_Soldier:
		{
			TF2_RemoveWeaponSlot(client, SLOT_PRIMARY);		// No primary weapons allowed.
			TF2_RemoveWeaponSlot(client, SLOT_SECONDARY);	// No secslot weapons allowed.
															// Melee weapons are always allowed.
		}
		
		case TFClass_DemoMan:
		{
			TF2_RemoveWeaponSlot(client, SLOT_PRIMARY);		// No primary weapons allowed (booties are useless here anyway).
			
			new secslot = GetPlayerWeaponSlot(client, SLOT_SECONDARY);	// Some secondaries allowed.
			if ( IsValidEntity(secslot) )									// If the player has a secslot weapon:
			{
				decl String:classname[64];
				if ( GetEntityClassname(secslot, classname, sizeof(classname)) && StrContains(classname, "tf_weapon", false) != -1 )
				{
					switch (GetEntProp(secslot, Prop_Send, "m_iItemDefinitionIndex"))
					{
						case 131: {}											// Targe is allowed (NOT the Screen, Jesus Christ, let's add a little skill here).
						default: TF2_RemoveWeaponSlot(client, SLOT_SECONDARY);	// Otherwise remove the weapon.
					}
				}
				else TF2_RemoveWeaponSlot(client, SLOT_SECONDARY);
			}
			else TF2_RemoveWeaponSlot(client, SLOT_SECONDARY);
			
			// TODO: remove the Persian Persuader.
		}
		
		case TFClass_Medic:
		{
			TF2_RemoveWeaponSlot(client, SLOT_PRIMARY);		// No primary weapons allowed.
			TF2_RemoveWeaponSlot(client, SLOT_SECONDARY);	// No secslot weapons allowed.
			// All melee weapons allowed.
		}
		
		case TFClass_Heavy:
		{
			TF2_RemoveWeaponSlot(client, SLOT_PRIMARY);		// No primary weapons allowed.
			TF2_RemoveWeaponSlot(client, SLOT_SECONDARY);	// No secslot weapons allowed (with overheals Sandvich etc. would be useless).
			// All melee weapons allowed.
		}
		
		case TFClass_Pyro:
		{
			TF2_RemoveWeaponSlot(client, SLOT_PRIMARY);		// No primary weapons allowed.
			TF2_RemoveWeaponSlot(client, SLOT_SECONDARY);	// No secslot weapons allowed.
			// All melee weapons allowed.
		}
		
		case TFClass_Spy:
		{
			TF2_RemoveWeaponSlot(client, SLOT_PRIMARY);		// No primary weapons allowed.
			// Sappers, disguise kit and cloak watches are allowed.
			// Melee is allowed.
		}
		
		case TFClass_Engineer:
		{
			TF2_RemoveWeaponSlot(client, SLOT_PRIMARY);		// No primary weapons allowed.
			TF2_RemoveWeaponSlot(client, SLOT_SECONDARY);	// No secslot weapons allowed.
			// Melee is allowed.
			TF2_RemoveWeaponSlot(client, 3);	// Remove all PDA-related slots.
			TF2_RemoveWeaponSlot(client, 4);
			TF2_RemoveWeaponSlot(client, 5);
		}
	}
}

/*	Removes the client's owner reference from the specified buildings.
	NOTE: Non-effective in that a client's buildings will always change team when the client does.	*/
stock DissociateBuildings(client, flags)
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
				//if ( GetConVarInt(cv_Debug) & DEBUG_CRASHES == DEBUG_CRASHES ) LogMessage("SetEntProp ID 5: m_hBuilder and m_hOwnerEntity on sentry %d about to be performed.", ent);
				SetEntPropEnt(ent, Prop_Send, "m_hBuilder", -1);
				SetEntPropEnt(ent, Prop_Send, "m_hOwnerEntity", -1);
				//if ( GetConVarInt(cv_Debug) & DEBUG_CRASHES == DEBUG_CRASHES ) LogMessage("SetEntProp ID 5: m_hBuilder and m_hOwnerEntity on sentry %d complete.", ent);
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
				//if ( GetConVarInt(cv_Debug) & DEBUG_CRASHES == DEBUG_CRASHES ) LogMessage("SetEntProp ID 6: m_hBuilder and m_hOwnerEntity on dispenser %d about to be performed.", ent);
				SetEntPropEnt(ent, Prop_Send, "m_hBuilder", -1);
				SetEntPropEnt(ent, Prop_Send, "m_hOwnerEntity", -1);
				//if ( GetConVarInt(cv_Debug) & DEBUG_CRASHES == DEBUG_CRASHES ) LogMessage("SetEntProp ID 6: m_hBuilder and m_hOwnerEntity on dispenser %d complete.", ent);
			}
		}
	}
	
	// Teleporters:
	if ( (flags & BUILD_TELEPORTER) == BUILD_TELEPORTER )
	{
		new ent = -1;
		while ( (ent = FindEntityByClassname(ent, "obj_teleporter")) != -1 )
		{
			if ( IsValidEntity(ent) && GetEntPropEnt(ent, Prop_Send, "m_hBuilder") == client )
			{
				//if ( GetConVarInt(cv_Debug) & DEBUG_CRASHES == DEBUG_CRASHES ) LogMessage("SetEntProp ID 7: m_hBuilder and m_hOwnerEntity on teleporter %d about to be performed.", ent);
				SetEntPropEnt(ent, Prop_Send, "m_hBuilder", -1);
				SetEntPropEnt(ent, Prop_Send, "m_hOwnerEntity", -1);
				//if ( GetConVarInt(cv_Debug) & DEBUG_CRASHES == DEBUG_CRASHES ) LogMessage("SetEntProp ID 7: m_hBuilder and m_hOwnerEntity on teleporter %d complete.", ent);
			}
		}
	}
}

/*	Deals with setting a client's health.	*/
stock SetLargeHealth(client)
{
	new i_maxHealth = GetEntProp(client, Prop_Data, "m_iMaxHealth");
	new Float:maxHealth = float(i_maxHealth);									// Get the client's current max health.
	new newHealth = RoundToCeil(maxHealth * CalculateZombieHealthMultiplier());	// Calculate the new max health.
	
	if ( GetConVarInt(cv_Debug) & DEBUG_HEALTH == DEBUG_HEALTH ) LogMessage("%N's max health: %d", client, newHealth);
	
	//if ( GetConVarInt(cv_Debug) & DEBUG_CRASHES == DEBUG_CRASHES ) LogMessage("SetEntProp ID 8: m_iMaxHealth and m_iHealth on client %N about to be performed.", client);
	SetEntProp(client, Prop_Data, "m_iMaxHealth", newHealth);	// Update the client's max health value.
	SetEntProp(client, Prop_Send, "m_iHealth", newHealth);
	//if ( GetConVarInt(cv_Debug) & DEBUG_CRASHES == DEBUG_CRASHES ) LogMessage("SetEntProp ID 8: m_iMaxHealth and m_iHealth on client %N complete.", client);
	
	new index = DataIndexForUserId(GetClientUserId(client));
	g_Health[index] = newHealth;
	g_MaxHealth[index] = i_maxHealth;
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
	if ( (flags & BUILD_TELEPORTER) == BUILD_TELEPORTER )
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
	new Float:zMinPl = GetConVarFloat(cv_ZHMinPlayers);
	new Float:zMaxPl = GetConVarFloat(cv_ZHMaxPlayers);
	new cvDebug = GetConVarInt(cv_Debug);
	
	// Health is determined on a per-spawn basis, linearly interpolated between a minimum and maximum health multiplier.
	// Minimum health is given when there are 'zMinPl' opponents on Red, and maximum given when there are 'zMaxPl' or greater.
	
	// Firstly, clamp the health proportion values. Min should not be greater than max.
	if ( zMin > zMax )
	{
		LogMessage("tfbh_zhscale_min %f larger than tfbh_zhscale_max %f.", zMin, zMax);
		
		zMax = zMin;	// Set max health to match min health.
	}
	
	if ( zMinPl > zMaxPl )
	{
		LogMessage("tfbh_zhscale_minplayers %d larger than tfbh_zhscale_maxplayers %d.", zMinPl, zMaxPl);
		
		zMaxPl = zMinPl;	// Set max to match min.
	}
	
	// Value = number of players left alive on Red.
	// A = min players
	// B = max players
	// X = min health multiplier
	// Y = max health multiplier
	// As number of players alive grows smaller, health multiplier gets smaller.
	
	// Get the number of live players on Red.
	new redCount;
	
	for ( new i = 1; i <= MaxClients; i++ )
	{
		if ( IsClientInGame(i) && GetClientTeam(i) == TEAM_RED && IsPlayerAlive(i) ) redCount++;
	}
	
	if ( cvDebug & DEBUG_HEALTH == DEBUG_HEALTH ) LogMessage("%d players alive on Red.", redCount);
	
	// Calculate the raw multiplier value.
	new Float:multiplier = Remap(float(redCount), zMinPl, zMaxPl, zMin, zMax);
	
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

/*	Tints a zombie depending on their health.	*/
stock TintZombie(client)
{
	// RGB of colour we want to tint at full intensity: 41 138 30
	// If the health level is at normal class level or below, tint with 255 255 255
	// If the health level is normal class level * tfbh_zhscale_max (or above), tint with 41 138 30
	
	if ( client < 1 || client > MaxClients || !IsClientInGame(client) || !IsPlayerAlive(client) || GetClientTeam(client) != TEAM_BLUE ) return;
	
	new userid = GetClientUserId(client);
	new index = DataIndexForUserId(userid);
	new R = 255, G = 255, B = 255;
	new Float:classmax;
	new Float:zMax = GetConVarFloat(cv_ZHMax);	// tfbh_zhscale_max can never be below 1.0, so no trouble with inverse relationships here.
	
	// Value = g_Health[index]
	// A = normal class level
	// B = normal class level * tfbh_zhscale_max
	// X = 255
	// Y = max tint
	
	switch (TF2_GetPlayerClass(client))
	{
		case TFClass_Scout:		classmax = 125.0;
		case TFClass_Sniper:	classmax = 125.0;
		case TFClass_Soldier:	classmax = 200.0;
		case TFClass_DemoMan:	classmax = 175.0;
		case TFClass_Heavy:		classmax = 300.0;
		case TFClass_Medic:		classmax = 150.0;
		case TFClass_Pyro:		classmax = 175.0;
		case TFClass_Spy:		classmax = 125.0;
		case TFClass_Engineer:	classmax = 125.0;
		default:				classmax = 125.0;
	}
	
	R = RoundFloat(Remap(float(g_Health[index]), classmax, classmax * zMax, 255.0, 41.0));	
	if ( R < 41 ) R = 41;																	// Clamp value, eg. if health is less than normal class max.
	else if ( R > 255 ) R = 255;
	
	G = RoundFloat(Remap(float(g_Health[index]), classmax, classmax * zMax, 255.0, 138.0));
	if ( G < 138 ) G = 138;
	else if ( G > 255 ) G = 255;
	
	B = RoundFloat(Remap(float(g_Health[index]), classmax, classmax * zMax, 255.0, 30.0));
	if ( B < 30 ) B = 30;
	else if ( B > 255 ) B = 255;
	
	SetEntityRenderColor(client, R, G, B, 255);	// Set the client's colour.
}

/*	Remaps value on a scale of a-b to a scale of x-y.
	As value approaches a, return approaches x.
	As value approaches b, return approaches y.
	For inverse relationships, make b larger than a (where x and y remain the same).
	
	|----------|----|
	a          v    b
	           |
	|----------+----|
	x          |    y
	        return
	*/
stock Float:Remap(Float:value, Float:a, Float:b, Float:x, Float:y) { return x + (((value-a)/(b-a)) * (y-x)); }

stock ModifyRespawnTimes()
{
	if ( !IsValidEntity(g_GameRules) ) return;
	
	new min = GetConVarInt(cv_ZRespawnMin);
	new max = GetConVarInt(cv_ZRespawnMax);
	new totalPlayers = GetTeamClientCount(TEAM_RED) + GetTeamClientCount(TEAM_BLUE);
	new redPlayers;
	
	for ( new i = 1; i <= MaxClients; i++ )
	{
		if ( IsClientInGame(i) && GetClientTeam(i) == TEAM_RED && IsPlayerAlive(i) ) redPlayers++;
	}
	
	// Value: Number of players alive on Red
	// A: Total players on Red and Blue
	// B: 1 player
	// X: min
	// Y: max
	
	new respawnWave = RoundFloat(Remap(float(redPlayers), float(totalPlayers), 1.0, float(min), float(max)));
	if ( respawnWave > max) respawnWave = max;
	else if ( respawnWave < min ) respawnWave = min;
	
	SetVariantInt(respawnWave);
	AcceptEntityInput(g_GameRules, "SetBlueTeamRespawnWaveTime");
}

/*	Builds and fires a death message when a zombie kills a human.	*/
stock bool:BuildZombieMessage(client, attacker, inflictor, damagetype, weapon)
{
	// From what I can see of Saxton Hale, the "weapon" string in the death event defines what icon will be displayed.
	// "unarmed_combat" for the Unarmed Combat weapon.
	
	new Handle:event = CreateEvent("player_death", true);
	if ( event == INVALID_HANDLE ) return false;
	
	SetEventInt(event, "userid", GetClientUserId(client));
	SetEventInt(event, "victim_entindex", client);
	SetEventInt(event, "inflictor_entindex", inflictor);
	SetEventInt(event, "attacker", GetClientUserId(attacker));
	SetEventInt(event, "damagebits", damagetype);
	
	SetEventString(event, "weapon", "unarmed_combat");
	SetEventString(event, "weapon_logclassname", "unarmed_combat");
	SetEventInt(event, "weaponid", TF_WEAPON_BAT);
	
	SetEventInt(event, "customkill", 0);
	SetEventInt(event, "assister", -1);
	SetEventInt(event, "stun_flags", 0);
	SetEventInt(event, "death_flags", 0);
	SetEventBool(event, "silent_kill", false);
	SetEventInt(event, "playerpenetratecount", 0);
	SetEventString(event, "assister_fallback", "");
	
	FireEvent(event);
	return true;
}

/*	Calculates the average distance from a client to nearest players.
	Specify the team to check (pass TEAM_INVALID to ignore) and the number of players.
	Returns -1.0 on failure.	*/
stock Float:CalcAvgDistance(client, team, number)
{
	if ( client < 1 || client > MaxClients || !IsClientInGame(client) || !IsPlayerAlive(client) ) return -1.0;
	
	new Float:cOrigin[3];
	GetClientAbsOrigin(client, cOrigin);
	
	// Build a list of distances.
	new teamcount, Float:distances[MaxClients];
	
	for ( new i = 1; i <= MaxClients; i++ )
	{
		// If the player is alive and on the correct team, insert their distance into the array.
		if ( IsClientInGame(i) && IsPlayerAlive(i) )
		{
			if ( team != TEAM_INVALID && GetClientTeam(i) != team ) continue;
			
			new Float:iOrigin[3];
			GetClientAbsOrigin(i, iOrigin);
			distances[teamcount] = GetVectorDistance(cOrigin, iOrigin);
			
			teamcount++;
		}
	}
	
	if ( teamcount < 1 ) return -1.0;
	
	// Array has been built and there is at least one entry.
	// Sort the array into ascending order.
	SortFloats(distances, teamcount);
	
	// Take the average of the number of nearest players specified.
	new Float:average;
	if ( number > teamcount ) number = teamcount;	// Make sure we don't try and average more than the number of players we found.
	
	for ( new i = 0; i < number; i++ )
	{
		average += distances[i];
	}
	
	return average / float(number);
}

/*	Thanks SaxtonHale.	*/
stock AttachParticle(ent, String:particleType[], Float:offset = 0.0, bool:battach = true)
{
	new particle = CreateEntityByName("info_particle_system");
	
	decl String:tName[32];
	new Float:pos[3];
	GetEntPropVector(ent, Prop_Send, "m_vecOrigin", pos);
	pos[2] += offset;
	TeleportEntity(particle, pos, NULL_VECTOR, NULL_VECTOR);
	
	Format(tName, sizeof(tName), "target%i", ent);
	DispatchKeyValue(ent, "targetname", tName);
	DispatchKeyValue(particle, "targetname", "tf2particle");
	DispatchKeyValue(particle, "parentname", tName);
	DispatchKeyValue(particle, "effect_name", particleType);
	DispatchSpawn(particle);
	
	if (battach)
	{
		SetVariantString(tName);
		AcceptEntityInput(particle, "SetParent", particle, particle, 0);
		SetEntPropEnt(particle, Prop_Send, "m_hOwnerEntity", ent);
	}
	
	ActivateEntity(particle);
	AcceptEntityInput(particle, "start");
	return particle;
}

public Action:Timer_EnableStunnedSentry(Handle:timer, Handle:pack)
{
	// Unpack the data.
	SetPackPosition(pack, 0);
	new sentry = EntRefToEntIndex(ReadPackCell(pack));
	new particle = EntRefToEntIndex(ReadPackCell(pack));
	CloseHandle(pack);
	
	if ( IsValidEntity(sentry) )
	{
		decl String:classname[64];
		GetEntityClassname(sentry, classname, sizeof(classname));
		
		if ( StrEqual(classname, "obj_sentrygun") ) SetEntProp(sentry, Prop_Send, "m_bDisabled", 0);
	}
	
	if ( IsValidEntity(particle) )
	{
		decl String:classname[64];
		GetEntityClassname(particle, classname, sizeof(classname));
		
		if ( StrEqual(classname, "info_particle_system") ) AcceptEntityInput(particle, "Kill");
	}
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
		return;
	}
	
	ModifyRespawnTimes();
}

public Action:Timer_RespawnTelePlayer(Handle:timer, Handle:pack)
{
	//new cvDebug = GetConVarInt(cv_Debug);
	
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

/*	Periodically resets m_iHealth on zombies to their health value stored in g_Health.
	This is to negate the overheal effect when setting large values of health.
	NEW: Rage and other things are calculated here.	*/
public Action:Timer_ZombieHealthRefresh(Handle:timer, Handle:pack)
{
	if ( g_PluginState & STATE_DISABLED == STATE_DISABLED ||
			g_PluginState & STATE_NOT_IN_ROUND == STATE_NOT_IN_ROUND ||
			g_PluginState & STATE_FEW_PLAYERS == STATE_FEW_PLAYERS ) return Plugin_Handled;
	
	for ( new i = 1; i < MaxClients; i++ )
	{
		if ( IsClientInGame(i) && !IsClientReplay(i) && !IsClientSourceTV(i) )
		{
			new index = DataIndexForUserId(GetClientUserId(i));
			
			if ( GetClientTeam(i) == TEAM_BLUE && IsPlayerAlive(i) && g_Zombie[index] )
			{
				// Check whether the zombie's health is above what we last recorded. If it is, update.
				// Since health only drops over time, if we have more than last time then that's fine.
				new health = GetEntProp(i, Prop_Send, "m_iHealth");
				
				if ( health > g_Health[index] ) g_Health[index] = health;
				else
				{
					SetEntProp(i, Prop_Send, "m_iHealth", g_Health[index]);
				}
				
				// Tint the zombie depending on his health level.
				TintZombie(i);
				
				new Float:debug_dist, Float:debug_rage;
				
				// Update the client's rage level.
				if ( !g_Raging[index] )	// If not currently raging:
				{
					new Float:dist = CalcAvgDistance(i, TEAM_RED, 3);	// Check the nearest 3 players on Red.
					if ( GetConVarBool(cv_DebugRage) ) debug_dist = dist;
					
					// Remap: when a zombie is on average 128 units or closer to players, rage fills at 10% per second.
					// When a zombie is on average 1024 units or further from players, rage fills at 1% per second.
					// Timer is refired every 0.2 seconds, so rage should fill at 2% and 0.2% respectively each refire.
					
					// Value: avg dist
					// A: near dist
					// B: far dist
					// X: high charge
					// Y: low charge
					new Float:mincharge = GetConVarFloat(cv_ZRageChargeFar)/5.0, Float:maxcharge = GetConVarFloat(cv_ZRageChargeClose)/5.0;			// Convar is % per sec, divide by 5 to get % per 0.2 sec.
					new Float:rage = Remap(dist, GetConVarFloat(cv_ZRageCloseDist), GetConVarFloat(cv_ZRageFarDist), maxcharge, mincharge);
					
					// Clamp the rage value.
					if ( rage < mincharge ) rage = mincharge;
					else if ( rage > maxcharge ) rage = maxcharge;
					
					if ( GetConVarBool(cv_DebugRage) ) debug_rage = rage;
					
					// Update the zombie's rage.
					g_Rage[index] += rage;
					if ( g_Rage[index] > 100.0 ) g_Rage[index] = 100.0;
					else if ( g_Rage[index] < 0.0 ) g_Rage[index] = 0.0;
				}
				else	// If raging:
				{
					// Work out how many points to deduct from the meter depending on the duration convar.
					new Float:deduct = 20.0/GetConVarFloat(cv_ZRageDuration);	// 100/5 since we're refiring every 0.2 secs.
					g_Rage[index] -= deduct;
					
					// If we have now reached zero, clamp and disable rage.
					if ( g_Rage[index] <= 0.0 )
					{
						g_Rage[index] = 0.0;
						g_Raging[index] = false;
					}
					else	// We're not at zero yet, apply effects that happen during duration of rage (stuns are handled in taunt hook).
					{
						// Apply crits to the raging player.
						TF2_AddCondition(i, TFCond_HalloweenCritCandy, 0.25);
						
						// Apply mini-crits to players in the specified radius, as long as they do not already have crits.
						new Float:cOrigin[3];
						GetClientAbsOrigin(i, cOrigin);
						
						for ( new j = 1; j <= MaxClients; j++ )
						{
							if ( j != i && IsClientInGame(j) && GetClientTeam(j) == TEAM_BLUE && IsPlayerAlive(j) && g_Zombie[DataIndexForUserId(GetClientUserId(j))]
							&& !TF2_IsPlayerInCondition(j, TFCond_HalloweenCritCandy) && !TF2_IsPlayerInCondition(j, TFCond_Kritzkrieged) )
							{
								new Float:tOrigin[3];
								GetClientAbsOrigin(j, tOrigin);
								
								if ( GetVectorDistance(cOrigin, tOrigin) <= GetConVarFloat(cv_ZRageRadius) )
								{
									TF2_AddCondition(j, TFCond_Buffed, 0.25);
								}
							}
						}
					}
				}
				
				// Update the HUD text.
				if ( g_Raging[index] || g_Rage[index] >= 100.0 )	// If currently raging or meter is full, print in red.
				{
					SetHudTextParams(-1.0,
									0.84,
									0.21,
									255,
									79,
									79,
									255,
									0,
									0.0,
									0.0,
									0.0);
				}
				else
				{
					SetHudTextParams(-1.0,
									0.84,
									0.21,
									255,
									255,
									255,
									255,
									0,
									0.0,
									0.0,
									0.0);
				}
				
				decl String:buffer[128];
				if ( GetConVarBool(cv_DebugRage) ) Format(buffer, sizeof(buffer), "%T: %d\n%T: %d\% Dist %f Rate %f", "Health", i, GetEntProp(i, Prop_Send, "m_iHealth"), "Rage", i, RoundToFloor(g_Rage[index]), debug_dist, debug_rage * 5 );
				else Format(buffer, sizeof(buffer), "%T: %d\n%T: %d\%", "Health", i, GetEntProp(i, Prop_Send, "m_iHealth"), "Rage", i, RoundToFloor(g_Rage[index]));
				
				ShowSyncHudText(i, hs_ZText, buffer);
			}
		}
	}
	
	return Plugin_Handled;
}

public Action:Timer_CondRefresh(Handle:timer, Handle:pack)
{
	if ( g_PluginState & STATE_DISABLED == STATE_DISABLED ||
			g_PluginState & STATE_NOT_IN_ROUND == STATE_NOT_IN_ROUND ||
			g_PluginState & STATE_FEW_PLAYERS == STATE_FEW_PLAYERS ) return Plugin_Handled;
	
	// Search through the g_StartBoost array to find zombies who should be boosted.
	for ( new i = 0; i < MAXPLAYERS; i++ )
	{
		if ( g_StartBoost[i] == true )	// If zombie should be boosted:
		{
			// Check client is valid.
			new client = GetClientOfUserId(g_userIDMap[i]);
			if ( client < 1 ) continue;
			
			// If using the Holiday Punch, critical hits just cause players to laugh and do no physical damage.
			// This means that if there's only one zombie alive at the start of the round and they're crit boosted
			// with the HP, they won't be able to deal any damage.
			// We need to check whether the client is using the HP before we crit boost them.
			new bool:hp = false;
			if ( TF2_GetPlayerClass(client) == TFClass_Heavy )
			{
				new weapon = GetPlayerWeaponSlot(client, SLOT_MELEE);
				if ( weapon > MaxClients )
				{
					if ( GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 656 ) hp = true;
				}
			}
			
			if ( !hp ) TF2_AddCondition(client, TFCond_HalloweenCritCandy, 1.05);	// Crits
			TF2_AddCondition(client, TFCond_SpeedBuffAlly, 1.05);					// Speed boost
		}
	}
	
	// Count the number of players left alive on Red and give the last couple mini-crits.
	new playercount, players[2];
	
	for ( new i = 1; i <= MaxClients; i++ )
	{
		if ( IsClientInGame(i) && GetClientTeam(i) == TEAM_RED && IsPlayerAlive(i) )
		{
			// If playercount is 0 or 1, add the player to the array.
			if ( playercount < 2 ) players[playercount] = i;
			
			// Increment the player count.
			playercount++;
		}
	}
	
	if ( playercount == 2 )	// If two players left, give both mini-crits.
	{
		// The players' client indices will be at players[0] and players[1].
		TF2_AddCondition(players[0], TFCond_Buffed, 1.05);
		TF2_AddCondition(players[1], TFCond_Buffed, 1.05);
	}
	else if ( playercount == 1 )	// If one player left, give mini-crits and a boost.
	{
		// The single player's client index will be at players[0].
		TF2_AddCondition(players[0], TFCond_Buffed, 1.05);
		TF2_AddCondition(players[0], TFCond_SpeedBuffAlly, 1.05);
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
		
		PrintToConsole(client, "%d: UserID %d\tzombie %d\thealth %d\tmaxhealth %d\tstartboost %d\trage %f\traging %d", i, g_userIDMap[i], g_Zombie[i], g_Health[i], g_MaxHealth[i], g_StartBoost[i], g_Rage[i], g_Raging[i]);
	}
	
	for (new i = 0; i < MAXPLAYERS; i++ )
	{
		PrintToConsole(client, "%d: UserID %d\tzombie %d\thealth %d\tmaxhealth %d\tstartboost %d\trage %f\traging %d", i, g_userIDMap[i], g_Zombie[i], g_Health[i], g_MaxHealth[i], g_StartBoost[i], g_Rage[i], g_Raging[i]);
	}
	
	return Plugin_Handled;
}