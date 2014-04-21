// Nightfire Assassination by [X6] Herbius
// Fifth re-write (this is getting ridiculous) started on 23/10/11

/*
	Recent changes:
	- Re-worked the plugin to be in all-vs-1 format instead of in teams.
	
	duel_blue, duel_red
*/

#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <tf2_stocks>

#define DEBUGFLAG_GENERAL			1
#define DEBUGFLAG_INDICES			2		// Logging when the global indices change.
#define DEBUGFLAG_TEAMCHANGE		4		// Logging when a player changes team.
#define DEBUGFLAG_OBJECTIVES		8		// Logging disabling of objectives.
#define DEBUGFLAG_CONDITION		16		// Logging condition timer activity.
#define DEBUGFLAG_DEATH				32		// Logging death events.
#define DEBUGFLAG_HURT				64		// Logging assassin hhurt events.

#define DEBUGFLAG_MAX				64
#define DEBUGFLAG_MAX_FL			64.0

// Plugin states
#define STATE_DISABLED		2	// Plugin is disabled and no functionality should occur.
#define STATE_NOT_IN_ROUND	1	// A round is not currently being played.

// Plugin metadata defines
#define PLUGIN_NAME			"Nightfire: Assassination"
#define PLUGIN_AUTHOR		"[X6] Herbius"
#define PLUGIN_DESCRIPTION	"The assassin must eliminate the target to gain points."
#define PLUGIN_VERSION		"2.0.0.50"	// Note: build version is a rough estimate. I don't update this religiously.
#define PLUGIN_URL			"http://forums.alliedmods.net/showthread.php?p=1531506"

// Team integers
#define TEAM_INVALID		-1
#define TEAM_UNASSIGNED	0
#define TEAM_SPECTATOR	1
#define TEAM_RED			2
#define TEAM_BLUE			3

// Death flags
#define DEATHFLAG_FEIGNDEATH	(1 << 5)

// Building flags for destroying buildings
#define BUILDING_SENTRY			1
#define BUILDING_DISPENSER		2
#define BUILDING_TELEPORTER	4

#define CLEANUP_MAPSTART	1
#define CLEANUP_MAPEND		2
#define CLEANUP_ROUNDSTART	3
#define CLEANUP_ROUNDEND	4
#define CLEANUP_PLAYERSPAWN	5

#define CONDITION_REFRESH	0.5		// The amount of time, in seconds, as a float, that the assassin condition timer will refresh at. Conditions will individually last for this value + 0.05s.

// Sounds
#define SND_ASSASSIN_KILLED				"assassination/assassin_killed.mp3"				// Assassin dies.
#define SND_ASSASSIN_KILLED_BY_TARGET	"assassination/assassin_killed_by_target.mp3"	// Assassin is killed by target.
#define SND_ASSASSIN_SCORE					"assassination/assassin_score.mp3"				// Assassin kills target.
#define SND_TARGET_KILLED					"assassination/target_killed.mp3"				// Target dies.

// Particle effect strings:
#define TARGET_BLUE	"duel_blue"
#define TARGET_RED	"duel_red"
#define PARTICLE_OFFSET		75.0

// Global variables
new g_PluginState;			// Holds the global state of the plugin.
new DisconnectIndex;		// If a player disconnects, this will hold their index for use in TeamsChange.
new g_Assassin = 0;			// Holds the user ID of the assassin. This is checked whenever a player spawns on Red.
new g_Target = 0;				// Holds the user ID of the target.
new g_Scores[MAXPLAYERS];		// Holds each player's score. Individual score values are cleared whenever a player joins or leaves the game.

// ConVar declarations
new Handle:cv_PluginEnabled = INVALID_HANDLE;	// Enables or disables the plugin. Changing this while in-game restarts the map.
new Handle:cv_Debug = INVALID_HANDLE;				// Holds the bitflag value for debug messages that should be output to the server console. See nfas_showdebugflags for more information.
new Handle:cv_KillSentries = INVALID_HANDLE;	// If 1, Engineer sentries will be destroyed when the Engineer dies.
new Handle:cv_MaxScore = INVALID_HANDLE;			// When this score is reached, the round will end.
new Handle:cv_DamageFraction = INVALID_HANDLE;	// The fraction of damage the assassin will be protected from on a full server. Scales with number of opponents.

// Stock ConVars and values.
new Handle:cv_Unbalance = INVALID_HANDLE;		// Handle to mp_teams_unbalance_limit.
new Handle:cv_Autobalance = INVALID_HANDLE;		// Handle to mp_autoteambalance.
new Handle:cv_Scramble = INVALID_HANDLE;			// Handle to mp_scrambleteams_auto.
new cvd_Unbalance = 1;							// Original value of mp_teams_unbalance_limit.
new cvd_Autobalance = 1;						// Original value of mp_autoteambalance.
new cvd_Scramble = 1;							// Original value of mp_scrambleteams_auto.

// Timer handle declarations
new Handle:timer_AssassinCondition = INVALID_HANDLE;	// Handle to our timer that refreshes the buffed state on the assassin. Created on MapStart/PluginStart and killed on MapEnd.
new Handle:timer_HUDMessageRefresh = INVALID_HANDLE;	// Handle to our HUD refresh timer.
new Handle:timer_HUDInfoRefresh = INVALID_HANDLE;		// Handle to our HUD info refresh timer.

// Hud syncs
new Handle:hs_Assassin = INVALID_HANDLE;				// Handle to our HUD synchroniser for displaying who is the assassin.
new Handle:hs_Target = INVALID_HANDLE;				// Handle to our HUD synchroniser for displaying who is the target.
new Handle:hs_Info = INVALID_HANDLE;					// Handle to our HUD synchroniser for displaying scores and info.

public Plugin:myinfo =
{
	name			= PLUGIN_NAME,
	author			= PLUGIN_AUTHOR,
	description	= PLUGIN_DESCRIPTION,
	version		= PLUGIN_VERSION,
	url			= PLUGIN_URL
};

public OnPluginStart()
{
	LogMessage("=== Nightfire: Assassination, Version %s ===", PLUGIN_VERSION);
	LogMessage("Put desired debug flag values into nfas_debug for debug output.");
	
	LoadTranslations("assassination/assassination_phrases");
	LoadTranslations("common.phrases");
	LoadTranslations("core.phrases");
	AutoExecConfig(true, "assassination", "sourcemod/assassination");
	
	cv_Unbalance = FindConVar("mp_teams_unbalance_limit");
	cv_Autobalance = FindConVar("mp_autoteambalance");
	cv_Scramble = FindConVar("mp_scrambleteams_auto");
	
	if ( cv_Unbalance != INVALID_HANDLE )
	{
		cvd_Unbalance = GetConVarInt(cv_Unbalance);
		LogMessage("Stored value for mp_teams_unbalance_limit: %d", cvd_Unbalance);
	}
	
	if ( cv_Autobalance != INVALID_HANDLE )
	{
		cvd_Autobalance = GetConVarInt(cv_Autobalance);
		LogMessage("Stored value for mp_autoteambalance: %d", cvd_Autobalance);
	}
	
	if ( cv_Scramble != INVALID_HANDLE )
	{
		cvd_Scramble = GetConVarInt(cv_Scramble);
		LogMessage("Stored value for mp_scrambleteams_auto: %d", cvd_Scramble);
	}
	
	CreateConVar("nfas_version", PLUGIN_VERSION, "Plugin version.", FCVAR_PLUGIN | FCVAR_NOTIFY);
	
	cv_PluginEnabled  = CreateConVar("nfas_enabled",
												"1",
												"Enables or disables the plugin. Changing this while in-game will restart the map.",
												FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
												true,
												0.0,
												true,
												1.0);
	
	cv_Debug  = CreateConVar("nfas_debug",
												"0",
												"Holds the bitflag value for debug messages that should be output to the server console. See nfas_debugflags for more information.",
												FCVAR_PLUGIN | FCVAR_NOTIFY,
												true,
												0.0);
	
	cv_KillSentries  = CreateConVar("nfas_killsentries",
												"1",
												"If 1, Engineer sentries will be destroyed when the Engineer dies.",
												FCVAR_PLUGIN | FCVAR_NOTIFY,
												true,
												0.0,
												true,
												1.0);
	
	cv_MaxScore  = CreateConVar("nfas_score_max",
												"50",
												"When this score is reached, the round will end.",
												FCVAR_PLUGIN | FCVAR_NOTIFY,
												true,
												0.0);
	
	cv_DamageFraction  = CreateConVar("nfas_assassin_damage_protection",
												"0.75",
												"The fraction of damage the assassin will be protected from on a full server. Scales with number of opponents.",
												FCVAR_PLUGIN | FCVAR_NOTIFY,
												true,
												0.0,
												true,
												0.9);
	
	HookConVarChange(cv_PluginEnabled,	CvarChange);
	
	HookEventEx("player_spawn",				Event_PlayerSpawn,		EventHookMode_Post);
	HookEventEx("teamplay_round_start",		Event_RoundStart,		EventHookMode_Post);
	HookEventEx("teamplay_round_win",		Event_RoundWin,			EventHookMode_Post);
	HookEventEx("teamplay_round_stalemate",	Event_RoundStalemate,	EventHookMode_Post);
	HookEventEx("player_disconnect",		Event_Disconnect,		EventHookMode_Post);
	HookEventEx("player_team",				Event_TeamsChange,		EventHookMode_Post);
	HookEventEx("player_death",				Event_PlayerDeath,		EventHookMode_Post);
	HookEventEx("player_hurt",				Event_PlayerHurt,		EventHookMode_Post);
	
	RegConsoleCmd("nfas_showindices",	Cmd_ShowIndices,	"Outputs the assassin and target to the console.");
	RegConsoleCmd("nfas_showscores",	Cmd_ShowScores,		"Outputs scores to the console.");
	RegConsoleCmd("nfas_players",		Cmd_Players,		"Outputs player info to the console; for debugging players getting stuck in limbo.");
	
	// Only continue from this point if the game is already being played.
	if ( !IsServerProcessing() ) return;
	
	// End the round.
	RoundWin();
	
	Cleanup(CLEANUP_MAPSTART);
}

public OnPluginEnd()
{
	ServerCommand("mp_teams_unbalance_limit %d", cvd_Unbalance);
	ServerCommand("mp_autoteambalance %d", cvd_Autobalance);
	ServerCommand("mp_scrambleteams_auto %d", cvd_Scramble);
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

stock FindEntityByClassname2(startEnt, const String:classname[])
{
	/* If startEnt isn't valid shifting it back to the nearest valid one */
	while (startEnt > -1 && !IsValidEntity(startEnt)) startEnt--;
	
	return FindEntityByClassname(startEnt, classname);
}  

/*	Deals with variables/functions that must be cleaned up.	*/
stock Cleanup(mode = 0)
{
	/*On RoundStart:
	* 	Zero scores;
	*	Reset team balance ConVars;
	* On RoundWin:
	* 	Reset assassin and target indices to 0;
	* On MapStart:
	*	Reset team balance ConVars;
	* 	Reset assassin and target indices to 0;
	*	Create the assassin condition timer;
	*	Zero scores;
	* On MapEnd:
	* 	Reset assassin and target indices to 0;
	*	Kill the assassin condition timer;
	*	Zero scores;
	* On PlayerSpawn:
	*	Reset assassin and target indices to 0;
	*/
	
	switch (mode)
	{
		case CLEANUP_ROUNDSTART:	// RoundStart
		{
			if ( (g_PluginState & STATE_DISABLED) != STATE_DISABLED )
			{
				//SetConVarInt(cv_Unbalance, 0);
				ServerCommand("mp_teams_unbalance_limit 0");
				//SetConVarBool(cv_Autobalance, false);
				ServerCommand("mp_autoteambalance 0");
				ServerCommand("mp_scrambleteams_auto 0");
			}
			
			new Zero[MAXPLAYERS];
			g_Scores = Zero;
		}
		
		case CLEANUP_ROUNDEND:	// RoundWin:
		{
			g_Assassin = 0;
			g_Target = 0;
		}
		
		case CLEANUP_MAPSTART:	// MapStart
		{
			g_Assassin = 0;
			g_Target = 0;
			
			if ( (g_PluginState & STATE_DISABLED) != STATE_DISABLED )
			{
				//SetConVarInt(cv_Unbalance, 0);
				ServerCommand("mp_teams_unbalance_limit 0");
				//SetConVarBool(cv_Autobalance, false);
				ServerCommand("mp_autoteambalance 0");
				ServerCommand("mp_scrambleteams_auto 0");
			}
			
			new Zero[MAXPLAYERS];
			g_Scores = Zero;

			// We only want to do these bits if we're enabled.
			if ( (g_PluginState & STATE_DISABLED) != STATE_DISABLED )
			{
				if ( timer_AssassinCondition == INVALID_HANDLE )
				{
					timer_AssassinCondition = CreateTimer(CONDITION_REFRESH, TimerAssassinCondition, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
				}
				
				if ( hs_Assassin == INVALID_HANDLE )
				{
					hs_Assassin = CreateHudSynchronizer();
				}
				
				if ( hs_Target == INVALID_HANDLE )
				{
					hs_Target = CreateHudSynchronizer();
				}
				
				if ( hs_Info == INVALID_HANDLE )
				{
					hs_Info = CreateHudSynchronizer();
				}
				
				if ( hs_Assassin != INVALID_HANDLE && hs_Target != INVALID_HANDLE )	// If the above was successful:
				{
					UpdateHUDMessages(g_Assassin, g_Target);	// Update the HUD
					timer_HUDMessageRefresh = CreateTimer(1.0, TimerHUDRefresh, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);	// Set up the timer to next update the HUD.
				}
				
				if ( hs_Info != INVALID_HANDLE )
				{
					UpdateHUDInfo(g_Scores);
					timer_HUDInfoRefresh = CreateTimer(1.0, TimerHUDInfoRefresh, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
				}
			}
		}
		
		case CLEANUP_MAPEND:	// MapEnd
		{
			g_Assassin = 0;
			g_Target = 0;
			
			new Zero[MAXPLAYERS];
			g_Scores = Zero;

			if ( timer_AssassinCondition != INVALID_HANDLE )
			{
				KillTimer(timer_AssassinCondition);
				timer_AssassinCondition = INVALID_HANDLE;
			}
			
			if ( hs_Assassin != INVALID_HANDLE )
			{
				CloseHandle(hs_Assassin);	// If the assassin hud snyc isn't invalid, close it.
				hs_Assassin = INVALID_HANDLE;
			}
			
			if ( hs_Target != INVALID_HANDLE )
			{
				CloseHandle(hs_Target);		// If the target hud snyc isn't invalid, close it.
				hs_Target = INVALID_HANDLE;
			}
			
			if ( hs_Info != INVALID_HANDLE )
			{
				CloseHandle(hs_Info);
				hs_Info = INVALID_HANDLE;
			}
			
			if ( timer_HUDMessageRefresh != INVALID_HANDLE )
			{
				KillTimer(timer_HUDMessageRefresh);
				timer_HUDMessageRefresh = INVALID_HANDLE;
			}
			
			if ( timer_HUDInfoRefresh != INVALID_HANDLE )
			{
				KillTimer(timer_HUDInfoRefresh);
				timer_HUDInfoRefresh = INVALID_HANDLE;
			}
		}
		
		case CLEANUP_PLAYERSPAWN:	// PlayerSpawn
		{
			g_Assassin = 0;
			g_Target = 0;
		}
	}
	
	return;
}

// Enabling/Disabling

/*	Checks which ConVar has changed and performs the relevant actions.	*/
public CvarChange( Handle:convar, const String:oldValue[], const String:newValue[])
{
	if ( convar == cv_PluginEnabled ) PluginEnabledStateChanged(GetConVarBool(cv_PluginEnabled));
}

/*	Sets the enabled/disabled state of the plugin and restarts the map.
	Passing true enables, false disables.	*/
PluginEnabledStateChanged(bool:b_state)
{
	if ( b_state )
	{
		g_PluginState &= ~STATE_DISABLED;	// Clear the disabled flag.
		
		// Set our team balance cvars.
		ServerCommand("mp_teams_unbalance_limit 0");
		ServerCommand("mp_autoteambalance 0");
	}
	else
	{
		g_PluginState |= STATE_DISABLED;	// Set the disabled flag.
		
		// Reset our team balance cvars.
		ServerCommand("mp_teams_unbalance_limit %d", cvd_Unbalance);
		ServerCommand("mp_autoteambalance %d", cvd_Autobalance);
	}
	
	// Get the current map name
	decl String:mapname[65];
	GetCurrentMap(mapname, sizeof(mapname));
	LogMessage("[AS] Plugin state changed. Enabled: %d. Restarting map %s...", b_state, mapname);
	
	// Restart the map
	ForceChangeLevel(mapname, "Nightfire: Assassination enabled state changed, map restart required.");
}

/*	Called when a client has fully connected.	*/
public OnClientConnected(client)
{
	g_Scores[client-1] = 0;	// Zero the score of the index we will use.
	CheckScoresAgainstMax();
}

/*	Called when a player disconnects.
	This is called BEFORE TeamsChange below.	*/
public Event_Disconnect(Handle:event, const String:name[], bool:dontBroadcast)
{
	DisconnectIndex = GetClientOfUserId(GetEventInt(event, "userid"));
	g_Scores[DisconnectIndex-1] = 0;
	CheckScoresAgainstMax();
}

/*	Called when a player is hurt.	*/
public Event_PlayerHurt(Handle:event, const String:name[], bool:dontBroadcast)
{
	if ( g_PluginState > 0 ) return;
	if ( g_Assassin < 1 || GetClientOfUserId(g_Assassin) < 1 ) return;
	
	new ph_ClientID = GetEventInt(event, "userid");
	new ph_ClientIndex = GetClientOfUserId(ph_ClientID);			// Index of the client who was hurt.
	new ph_AttackerID = GetEventInt(event, "attacker");
	new ph_AttackerIndex = GetClientOfUserId(ph_AttackerID);		// Index of the client who fired the shot.
	new ph_ClientHealth = GetEventInt(event, "health");				// How much health the injured player now has.
	new ph_ClientDamage = GetEventInt(event, "damageamount");		// The amount of damage the injured player took.
	
	// If the assassin was hurt and didn't die, give them back a fraction of the damage done. This fraction depends on the server population.
	// The number of players (not including the assassin) is compared to the maximum possible number of players on the server bar one, and this fraction is used to remap
	// how much of the damage taken is consequently given back to the assassin. If there is only one other person apart from the assassin, the assassin will
	// take full damage. If the server is full, the assassin will only take 20% of the received damage (or whatever the mutliplier constant is).
	
	new count = (GetTeamClientCount(TEAM_RED) + GetTeamClientCount(TEAM_BLUE));
	new Float:f_dmg_frac = GetConVarFloat(cv_DamageFraction);
	
	// Don't modify health if there is only one person bar the assassin.
	if ( ph_ClientID == g_Assassin && ph_ClientHealth > 0 && ph_AttackerIndex != ph_ClientIndex && ph_AttackerIndex > 0 && ph_AttackerIndex <= MaxClients && count > 2 )
	{
		new Float:f_damagereturn = ((count-1)/(MaxClients-1)) * f_dmg_frac * float(ph_ClientDamage);
		new Float:f_healthtoset = float(ph_ClientHealth) + f_damagereturn;
		
		if ( (GetConVarInt(cv_Debug) & DEBUGFLAG_HURT) == DEBUGFLAG_HURT )
		{
			LogMessage("Health: %d. Damage fraction: %f. Return: %d/%d x %f x %d = %f. Health to set: %d.",
							ph_ClientHealth, f_dmg_frac, count-1, MaxClients-1, f_dmg_frac, ph_ClientDamage, f_damagereturn, RoundToFloor(f_healthtoset));
		}
		
		SetEntProp(ph_ClientIndex, Prop_Data, "m_iHealth", RoundToFloor(f_healthtoset));
		
		// Immediately mark the health value as changed.
		ChangeEdictState(ph_ClientIndex, GetEntSendPropOffs(ph_ClientIndex, "m_iHealth"));
	}
}

/*	Called when a player changes team.	*/
public Event_TeamsChange(Handle:event, const String:name[], bool:dontBroadcast)
{
	
	// Player spawn will deal with assigning the assassin or target.
	// Here we need to check whether the player who is changing team is the assassin or target.
	
	if ( g_PluginState > 0 )	return;	// Leave the rest of this if there are any abnormal states.
	
	new tc_ClientID = GetEventInt(event, "userid");
	new tc_ClientIndex = GetClientOfUserId(tc_ClientID);
	//new tc_Assassin = GetClientOfUserId(g_Assassin);
	//new tc_Target = GetClientOfUserId(g_Target);
	new tc_NewTeamID = GetEventInt(event, "team");
	new tc_OldTeamID = GetEventInt(event, "oldteam");
	new bool:tc_Disconnect = GetEventBool(event, "disconnect");
	
	new tc_RedTeamCount = GetTeamClientCount(TEAM_RED);		// These will give us the team counts BEFORE the client has switched.
	new tc_BlueTeamCount = GetTeamClientCount(TEAM_BLUE);
	
	new g_debug = GetConVarInt(cv_Debug);
	
	// Since the team change event is ALWAYS called like a pre (thanks, Valve), we need to build up a picture of what
	// the teams will look like after the switch.
	
	if ( tc_Disconnect ) 	// If the team change happened because the client was disconnecting:
	{
		// Note that, if disconnect == true, the userid will point to the index 0.
		// We fix this here.
		tc_ClientIndex = DisconnectIndex;	// This is retrieved from player_disconnect, which is fired before player_team.
		DisconnectIndex = 0;
		
		if ( (g_debug & DEBUGFLAG_TEAMCHANGE) == DEBUGFLAG_TEAMCHANGE )
		{
			LogMessage("TC: Player %d is disconnecting.", tc_ClientIndex);
		}
		
		// If disconnected, this means the team he was on will lose a player and the other teams will stay the same.
		switch (tc_OldTeamID)	// Find out which team the client left.
		{
			case TEAM_RED:
			{
				tc_RedTeamCount--;	// Decrement our counter for the team.
			}
			
			case TEAM_BLUE:
			{
				tc_BlueTeamCount--;	// Decrement our counter for the team.
			}
			
			// If the old team was spectator, we're not counting spec players so don't do anything.
		}
	}
	else	// If the client hasn't disconnected, this means they're changing teams.
	{
		if ( (g_debug & DEBUGFLAG_TEAMCHANGE) == DEBUGFLAG_TEAMCHANGE )
		{
			LogMessage("TC: Player %N is not disconnecting.", tc_ClientIndex);
		}
		
		// The client's old team will lose a player and their new team will gain a player.
		switch (tc_OldTeamID)
		{
			case TEAM_RED:
			{
				tc_RedTeamCount--;	// Decrement the old team's counter.
			}
			
			
			case TEAM_BLUE:
			{
				tc_BlueTeamCount--;	// Decrement the old team's counter.
			}
			
			// If the old team was spectator, we're not counting spec players so don't do anything.
		}
		
		switch (tc_NewTeamID)
		{
			case TEAM_RED:
			{
				tc_RedTeamCount++;	// Increment the new team's counter.
			}
			
			case TEAM_BLUE:
			{
				tc_BlueTeamCount++;	// Increment the new team's counter.
			}
			
			// If the new team is spectator, we're not counting spec players so don't do anything.
		}
	}
	
	// --------------------------
	// - Team counts are built. -
	// --- Functions go below. --
	// --------------------------
	
	// A player is joining the active game.
	if ( tc_OldTeamID < TEAM_RED && tc_NewTeamID >= TEAM_RED )
	{
		if ( (g_debug & DEBUGFLAG_TEAMCHANGE) == DEBUGFLAG_TEAMCHANGE )
		{
			LogMessage("TC: Player %N is joining the active game.", tc_ClientIndex);
		}
		
		// Check player counts.
		if ( (tc_RedTeamCount + tc_BlueTeamCount) < 2 )
		{
			if ( (g_debug & DEBUGFLAG_TEAMCHANGE) == DEBUGFLAG_TEAMCHANGE )
			{
				LogMessage("TC: Team counts not adequate, disabling indices.");
			}
			
			g_Assassin = 0;
			g_Target = 0;
			
			new Zero[MAXPLAYERS];
			g_Scores = Zero;
		}
		else
		{
			if ( g_Assassin > 0 && GetClientOfUserId(g_Assassin) > 0 )	// If the assassin is valid:
			{
				if ( tc_ClientID != g_Assassin && tc_NewTeamID == TEAM_RED )
				{
					if ( (g_debug & DEBUGFLAG_TEAMCHANGE) == DEBUGFLAG_TEAMCHANGE )
					{
						LogMessage("TC: Non-assassin player %N attempting to change to Red, prohibiting.", tc_ClientIndex);
					}
					ChangeClientTeam(tc_ClientIndex, TEAM_BLUE);
					CheckPlayersOnRed();
				}
			}
			else	// If not, set the joining player as the assassin.
			{
				if ( (g_debug & DEBUGFLAG_TEAMCHANGE) == DEBUGFLAG_TEAMCHANGE )
				{
					LogMessage("TC: No assassin assigned but player counts are OK, assigning player %N...", tc_ClientIndex);
				}
				
				g_Assassin = tc_ClientID;
				if ( tc_NewTeamID != TEAM_RED ) ChangeClientTeamPersistent(tc_ClientIndex, TEAM_RED);
				CheckPlayersOnRed();
				
				if ( GetTeamClientCount(TEAM_BLUE) > 0 ) g_Target = GetClientUserId(RandomPlayerFromTeam(TEAM_BLUE));
			}
		}
	}
	// A player is leaving the active game.
	else if ( tc_NewTeamID < TEAM_RED && tc_OldTeamID >= TEAM_RED )
	{
		if ( (g_debug & DEBUGFLAG_TEAMCHANGE) == DEBUGFLAG_TEAMCHANGE )
		{
			LogMessage("TC: Player %d is leaving the active game.", tc_ClientIndex);
		}
		
		// Check player counts.
		if ( (tc_RedTeamCount + tc_BlueTeamCount) < 2 )
		{
			if ( (g_debug & DEBUGFLAG_TEAMCHANGE) == DEBUGFLAG_TEAMCHANGE )
			{
				LogMessage("TC: Team counts not adequate, disabling indices.");
			}
		
			g_Assassin = 0;
			g_Target = 0;
			
			new Zero[MAXPLAYERS];
			g_Scores = Zero;
		}
		else	// Player counts are adequate.
		{
			if ( g_Assassin > 0 && tc_ClientID == g_Assassin )	// If the assassin is leaving:
			{
				if ( (g_debug & DEBUGFLAG_TEAMCHANGE) == DEBUGFLAG_TEAMCHANGE )
				{
					LogMessage("TC: Assassin %d is leaving the active game, choosing new assassin...", tc_ClientIndex);
				}
				
				new assassin_index = RandomPlayerFromTeam(TEAM_BLUE);
				if ( assassin_index < 1 ) assassin_index = RandomPlayerFromTeam(TEAM_RED);
				
				if ( assassin_index > 0 && assassin_index <= MaxClients )
				{
					g_Assassin = GetClientUserId(assassin_index);
					if ( GetClientTeam(assassin_index) == TEAM_BLUE ) ChangeClientTeamPersistent(assassin_index, TEAM_RED);
					CheckPlayersOnRed();
					
					g_Target = GetClientUserId(RandomPlayerFromTeam(TEAM_BLUE));
				}
			}
			else if ( g_Target > 0 && tc_ClientID == g_Target )	// If the target is leaving:
			{
				if ( (g_debug & DEBUGFLAG_TEAMCHANGE) == DEBUGFLAG_TEAMCHANGE )
				{
					LogMessage("TC: Target %d is leaving the active game, choosing new target...", tc_ClientIndex);
				}
				
				CheckPlayersOnRed();										// Make sure only the Assassin is on Red.
				new target_index = RandomPlayerFromTeam(TEAM_BLUE);	// Choose a target from Blue.
				if ( target_index > 0 && target_index <= MaxClients ) g_Target = GetClientUserId(target_index);
			}
		}
	}
	// A player is switching between teams in the game.
	else if ( tc_OldTeamID >= TEAM_RED && tc_NewTeamID >= TEAM_RED )
	{
		if ( (g_debug & DEBUGFLAG_TEAMCHANGE) == DEBUGFLAG_TEAMCHANGE )
		{
			LogMessage("TC: Player %N is switching between Red and Blue.", tc_ClientIndex);
		}
		
		// If the player is the assassin and is changing to Blue, prevent the change.
		// If the player is not the assassin and is changing to Red, prevent the change.
		if ( (tc_ClientID == g_Assassin && tc_NewTeamID == TEAM_BLUE) || (tc_ClientID != g_Assassin && tc_NewTeamID == TEAM_RED) )
		{
			if ( (g_debug & DEBUGFLAG_TEAMCHANGE) == DEBUGFLAG_TEAMCHANGE )
			{
				LogMessage("TC: Player %N is not allowed to switch to team %d, prohibiting change.", tc_ClientIndex, tc_NewTeamID);
			}
			
			ChangeClientTeam(tc_ClientIndex, tc_OldTeamID);
		}
	}
}

/*	Called when a player changes team.	*/
public Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	// If there are ANY abnormal states, don't go through all the crap below.
	if ( g_PluginState > 0 ) return;
	
	decl DeathEvents[11];
	
	DeathEvents[0] = GetEventInt(event, "userid");					// This is the user ID of the player who died.
	DeathEvents[1] = GetEventInt(event, "victim_entindex");			// ???
	DeathEvents[2] = GetEventInt(event, "inflictor_entindex");		// Entindex of the inflictor. This could be a weapon, sentry, projectile, etc.
	DeathEvents[3] = GetEventInt(event, "attacker");					// User ID of the attacker.
	DeathEvents[4] = GetEventInt(event, "weaponid");					// Weapon ID the attacker used.
	DeathEvents[5] = GetEventInt(event, "damagebits");				// Bitflags of the damage dealt.
	DeathEvents[6] = GetEventInt(event, "customkill");				// Custom kill value (headshot, etc.).
	DeathEvents[7] = GetEventInt(event, "assister");					// User ID of the assister.
	DeathEvents[8] = GetEventInt(event, "stun_flags");				// Bitflags of the user's stunned state before death.
	DeathEvents[9] = GetEventInt(event, "death_flags");				// Bitflags describing the type of death.
	DeathEvents[10] = GetEventInt(event, "playerpenetratecount");	// ??? To do with new penetration weapons?
	
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if ( client < 1 ) return;
	
	if ( TF2_GetPlayerClass(client) == TFClass_Engineer && GetConVarBool(cv_KillSentries) )	// If the player who died was an Engineer, kill their sentry if we're allowed.
	{
		KillBuildings(client, BUILDING_SENTRY);
	}
	
	// The assassin has died.
	if ( DeathEvents[0] == g_Assassin && (DeathEvents[9] & DEATHFLAG_FEIGNDEATH) != DEATHFLAG_FEIGNDEATH )
	{
		OnAssassinDeath(DeathEvents);
	}
	
	// The target has died.
	else if ( DeathEvents[0] == g_Target && (DeathEvents[9] & DEATHFLAG_FEIGNDEATH) != DEATHFLAG_FEIGNDEATH )
	{
		OnTargetDeath(DeathEvents);
	}
}

/*	Called when the target has died.	*/
OnAssassinDeath(DeathEvents[])
{
	new g_debug = GetConVarInt(cv_Debug);
	
	if ( (g_debug & DEBUGFLAG_DEATH) == DEBUGFLAG_DEATH )
	{
		LogMessage("Assassin %N has died.", GetClientOfUserId(DeathEvents[0]));
	}
	
	// If there are not enough players, reset both the indices.
	if ( (GetTeamClientCount(TEAM_RED) + GetTeamClientCount(TEAM_BLUE)) < 2 )
	{
		g_Assassin = 0;
		g_Target = 0;
		
		new Zero[MAXPLAYERS];
		g_Scores = Zero;
		
		return;
	}
	
	// Determine what has happened in this instance.
	// Suicide, team kill, world kill must be handled separately.
	// Environmental kills (falling to death, trigger_hurt, etc.) have an attacker ID of 0.
	// Suicide has an attacker ID that is the same as the user ID.
	// Team kill means the user ID team will be the same as the attacker ID team.
	
	new client = GetClientOfUserId(DeathEvents[0]);
	new team = GetClientTeam(client);
	new attacker = GetClientOfUserId(DeathEvents[3]);
	
	// The assassin has killed themselves somehow.
	if ( DeathEvents[0] == DeathEvents[3] || DeathEvents[3] < 1 )
	{
		if ( (g_debug & DEBUGFLAG_DEATH) == DEBUGFLAG_DEATH )
		{
			LogMessage("Assassin %N has killed themselves.", client);
		}
		
		// Play the Assassin Killed music.
		//EmitSoundToAll(SND_ASSASSIN_KILLED, _, SNDCHAN_AUTO, SNDLEVEL_TRAFFIC, SND_NOFLAGS, SNDVOL_NORMAL, 100, client, _, NULL_VECTOR, false, 0.0);
		EmitSoundToAll(SND_ASSASSIN_KILLED, _, _, SNDLEVEL_TRAFFIC, _, _, _, client);
		
		// No points should be awarded.
		
		// Assign a new assassin and target.
		new new_assassin = RandomPlayerFromTeam(TEAM_BLUE);			// Get a new assassin from the players on Blue.
		g_Assassin = GetClientUserId(new_assassin);					// Make a note of their ID.
		ChangeClientTeamPersistent(new_assassin, TEAM_RED);			// Move them to Red.
		ChangeClientTeamPersistent(client, TEAM_BLUE);				// Move the former assassin to Blue.
		new new_target = RandomPlayerFromTeam(TEAM_BLUE, client);	// Choose a new target from Blue, excluding the former assassin.
		if ( new_target < 1 ) new_target = client;						// If that didn't work then the former assassin must be the only Blue player, so make him the target.
		g_Target = GetClientUserId(new_target);							// Make a note of their ID.
		CheckPlayersOnRed();												// Make sure the assassin is the only player on Red.
	}
	
	// The assassin was killed by a player from the same team (unlikely but possible).
	else if ( attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker) && team == GetClientTeam(attacker) )
	{
		// Don't do anything. Keep the assassin as the same player.
		if ( (g_debug & DEBUGFLAG_DEATH) == DEBUGFLAG_DEATH )
		{
			LogMessage("Assassin %N was team killed by %N.", client, attacker);
		}
	}
	// The assassin was killed by an enemy player.
	else if ( attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker) )
	{
		// If this wasn't the target:
		if ( DeathEvents[3] != g_Target )
		{
			if ( (g_debug & DEBUGFLAG_DEATH) == DEBUGFLAG_DEATH )
			{
				LogMessage("Assassin %N was killed by non-target %N.", client, attacker);
			}
		
			// Play the Assassin Killed music.
			//EmitSoundToAll(SND_ASSASSIN_KILLED, _, SNDCHAN_AUTO, SNDLEVEL_TRAFFIC, SND_NOFLAGS, SNDVOL_NORMAL, 100, client, _, NULL_VECTOR, false, 0.0);
			EmitSoundToAll(SND_ASSASSIN_KILLED, _, _, SNDLEVEL_TRAFFIC, _, _, _, client);
			
			g_Assassin = DeathEvents[3];							// Note the attacker's ID.
			ChangeClientTeamPersistent(attacker, TEAM_RED);	// Move them to Red.
			ChangeClientTeamPersistent(client, TEAM_BLUE);	// Move the former assassin to Blue.
			new new_target = RandomPlayerFromTeam(TEAM_BLUE);	// Choose a new target from Blue.
			g_Target = GetClientUserId(new_target);				// Make a note of their ID.
			CheckPlayersOnRed();									// Make sure the assassin is the only player on Red.
		}
		
		// If it was the target:
		else
		{
			if ( (g_debug & DEBUGFLAG_DEATH) == DEBUGFLAG_DEATH )
			{
				LogMessage("Assassin %N was killed by target %N.", client, attacker);
			}
			
			// Play Assassin Killed by Target music.
			//EmitSoundToAll(SND_ASSASSIN_KILLED_BY_TARGET, _, SNDCHAN_AUTO, SNDLEVEL_TRAFFIC, SND_NOFLAGS, SNDVOL_NORMAL, 100, client, _, NULL_VECTOR, false, 0.0);
			EmitSoundToAll(SND_ASSASSIN_KILLED_BY_TARGET, _, _, SNDLEVEL_TRAFFIC, _, _, _, client);
			
			// Award the target 3 points.
			g_Scores[attacker-1] += 3;
			
			g_Assassin = DeathEvents[3];							// Note the attacker's ID.
			ChangeClientTeamPersistent(attacker, TEAM_RED);	// Move them to Red.
			ChangeClientTeamPersistent(client, TEAM_BLUE);	// Move the former assassin to Blue.
			new new_target = RandomPlayerFromTeam(TEAM_BLUE);	// Choose a new target from Blue.
			g_Target = GetClientUserId(new_target);				// Make a note of their ID.
			CheckPlayersOnRed();									// Make sure the assassin is the only player on Red.
			CheckScoresAgainstMax();								// Check to see if any of the scores have reached the max limit.
		}
	}
}

/*	Called when the target has died.	*/
OnTargetDeath(DeathEvents[])
{
	new g_debug = GetConVarInt(cv_Debug);
	
	if ( (g_debug & DEBUGFLAG_DEATH) == DEBUGFLAG_DEATH )
	{
		LogMessage("Target %N has died.", GetClientOfUserId(DeathEvents[0]));
	}
	
	// If either team has no players, reset both the indices.
	if ( GetTeamClientCount(TEAM_RED) < 1 || GetTeamClientCount(TEAM_BLUE) < 1 )
	{
		g_Assassin = 0;
		g_Target = 0;
		
		new Zero[MAXPLAYERS];
		g_Scores = Zero;
		
		return;
	}
	
	new client = GetClientOfUserId(DeathEvents[0]);
	new team = GetClientTeam(client);
	new attacker = GetClientOfUserId(DeathEvents[3]);
	
	// Determine what has happened in this instance.
	// Suicide, team kill, world kill must be handled separately.
	// Environmental kills (falling to death, trigger_hurt, etc.) have an attacker ID of 0.
	// Suicide has an attacker ID that is the same as the user ID.
	// Team kill means the user ID team will be the same as the attacker ID team.
	
	// The target killed themselves somehow.
	if ( DeathEvents[0] == DeathEvents[3] || DeathEvents[3] < 1 )
	{
		if ( (g_debug & DEBUGFLAG_DEATH) == DEBUGFLAG_DEATH )
		{
			LogMessage("Target %N killed themselves.", client);
		}
		
		// Play the Target Killed music.
		//EmitSoundToAll(SND_TARGET_KILLED, _, SNDCHAN_AUTO, SNDLEVEL_TRAFFIC, SND_NOFLAGS, SNDVOL_NORMAL, 100, client, _, NULL_VECTOR, false, 0.0);
		EmitSoundToAll(SND_TARGET_KILLED, _, _, SNDLEVEL_TRAFFIC, _, _, _, client);
		
		// No points should be awarded.
		
		if ( team == TEAM_RED ) ChangeClientTeamPersistent(client, TEAM_BLUE);
		new new_target = RandomPlayerFromTeam(TEAM_BLUE, client);				// Assign a new player from the Blue to be the target, excluding the player who died.
		if ( new_target < 1 ) new_target = client;									// If this doesn't work then the target must be the only player on his team, so choose him instead.
		g_Target = GetClientUserId(new_target);										// Make a note of their ID.
		CheckPlayersOnRed();															// Make sure the assassin is the only player on Red.
	}
	// The target was killed by someone on the same team.
	else if ( attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker) && team == GetClientTeam(attacker) )
	{
		// Don't do anything. Keep the target as the same player.
		if ( (g_debug & DEBUGFLAG_DEATH) == DEBUGFLAG_DEATH )
		{
			LogMessage("Target %N was team killed by %N.", client, attacker);
		}
	}
	// The target was killed by an enemy player.
	else if ( attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker) )
	{
		// If this wasn't the assassin:
		if ( DeathEvents[3] != g_Assassin )
		{
			if ( (g_debug & DEBUGFLAG_DEATH) == DEBUGFLAG_DEATH )
			{
				LogMessage("Target %N was killed by non-assassin %N.", client, attacker);
			}
			
			// Play the Target Killed music.
			//EmitSoundToAll(SND_TARGET_KILLED, _, SNDCHAN_AUTO, SNDLEVEL_TRAFFIC, SND_NOFLAGS, SNDVOL_NORMAL, 100, client, _, NULL_VECTOR, false, 0.0);
			EmitSoundToAll(SND_TARGET_KILLED, _, _, SNDLEVEL_TRAFFIC, _, _, _, client);
			
			// Choose a target from the same team.
			if ( team == TEAM_RED ) ChangeClientTeamPersistent(client, TEAM_BLUE);
			new new_target = RandomPlayerFromTeam(TEAM_BLUE);							// Assign a new player from the Blue to be the target.
			g_Target = GetClientUserId(new_target);										// Make a note of their ID.
			CheckPlayersOnRed();															// Make sure the assassin is the only player on Red.
		}
		// If it was the assassin:
		else if ( attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker) && DeathEvents[3] == g_Assassin )
		{
			if ( (g_debug & DEBUGFLAG_DEATH) == DEBUGFLAG_DEATH )
			{
				LogMessage("Target %N was killed by assassin %N.", client, attacker);
			}
			
			// Play the Assassin Score music.
			//EmitSoundToAll(SND_ASSASSIN_SCORE, _, SNDCHAN_AUTO, SNDLEVEL_TRAFFIC, SND_NOFLAGS, SNDVOL_NORMAL, 100, client, _, NULL_VECTOR, false, 0.0);
			EmitSoundToAll(SND_ASSASSIN_SCORE, _, _, SNDLEVEL_TRAFFIC, _, _, _, client);
			
			// Award the assassin 5 points.
			g_Scores[attacker-1] += 5;
			
			// Choose a target from the same team.
			if ( team == TEAM_RED ) ChangeClientTeamPersistent(client, TEAM_BLUE);
			new new_target = RandomPlayerFromTeam(TEAM_BLUE);							// Assign a new player from the Blue to be the target.
			g_Target = GetClientUserId(new_target);										// Make a note of their ID.
			CheckPlayersOnRed();															// Make sure the assassin is the only player on Red.
			CheckScoresAgainstMax();														// Check to see if any of the scores have reached the max limit.
		}
	}
}

public OnMapStart()
{
	// Set the NOT_IN_ROUND flag.
	g_PluginState |= STATE_NOT_IN_ROUND;
	
	Cleanup(CLEANUP_MAPSTART);
	
	//if ( (g_PluginState & STATE_DISABLED) == STATE_DISABLED ) return;
	
	// Start precaching here.
	decl String:SoundBuffer[128];	// Precache the sounds and add them to the download table.
	
	Format(SoundBuffer, sizeof(SoundBuffer), "sound/%s", SND_ASSASSIN_KILLED);
	AddFileToDownloadsTable(SoundBuffer);
	PrecacheSound(SND_ASSASSIN_KILLED, true);
	
	Format(SoundBuffer, sizeof(SoundBuffer), "sound/%s", SND_ASSASSIN_KILLED_BY_TARGET);
	AddFileToDownloadsTable(SoundBuffer);
	PrecacheSound(SND_ASSASSIN_KILLED_BY_TARGET, true);
	
	Format(SoundBuffer, sizeof(SoundBuffer), "sound/%s", SND_ASSASSIN_SCORE);
	AddFileToDownloadsTable(SoundBuffer);
	PrecacheSound(SND_ASSASSIN_SCORE, true);
	
	Format(SoundBuffer, sizeof(SoundBuffer), "sound/%s", SND_TARGET_KILLED);
	AddFileToDownloadsTable(SoundBuffer);
	PrecacheSound(SND_TARGET_KILLED, true);
}

public OnMapEnd()
{
	// Set the NOT_IN_ROUND flag.
	g_PluginState |= STATE_NOT_IN_ROUND;
	
	Cleanup(CLEANUP_MAPEND);
	
	if ( (g_PluginState & STATE_DISABLED) == STATE_DISABLED ) return;
}

/*	Called when a round starts.	*/
public Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	// Player_spawn is called before teamplay_round_start!
	
	// Clear the NOT_IN_ROUND flag.
	g_PluginState &= ~STATE_NOT_IN_ROUND;
	
	Cleanup(CLEANUP_ROUNDSTART);
	
	if ( (g_PluginState & STATE_DISABLED) == STATE_DISABLED ) return;
	
	DisableObjectives();
	
	if ( (GetTeamClientCount(TEAM_RED) + GetTeamClientCount(TEAM_BLUE)) < 2 ) return;
	
	new assassin = RandomPlayerFromTeam(TEAM_RED);
	if ( assassin < 1 ) assassin = RandomPlayerFromTeam(TEAM_BLUE);
	g_Assassin = GetClientUserId(assassin);
	
	if ( GetClientTeam(assassin) != TEAM_RED ) ChangeClientTeamPersistent(assassin, TEAM_RED);
	CheckPlayersOnRed();
	g_Target = GetClientUserId(RandomPlayerFromTeam(TEAM_BLUE));
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

/*	Keeps all the functions common to RoundWin and RoundStalemate together.	*/
Event_RoundEnd()
{
	// Set the NOT_IN_ROUND flag.
	g_PluginState |= STATE_NOT_IN_ROUND;
	
	Cleanup(CLEANUP_ROUNDEND);
	
	if ( (g_PluginState & STATE_DISABLED) == STATE_DISABLED ) return;
}

/*	Called when a player spawns.	*/
public Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (	(g_PluginState & STATE_DISABLED)		== STATE_DISABLED		||
			(g_PluginState & STATE_NOT_IN_ROUND)	== STATE_NOT_IN_ROUND  )
	{
		Cleanup(CLEANUP_PLAYERSPAWN);
		
		if ( (GetConVarInt(cv_Debug) & DEBUGFLAG_INDICES) == DEBUGFLAG_INDICES )
		{
			LogMessage("Spawn: Reset indices to 0; plugin disabled or not in round.");
		}
		
		return;
	}
	
	new g_Debug = GetConVarInt(cv_Debug);
	new client_id = GetEventInt(event, "userid");
	new client = GetClientOfUserId(client_id);
	
	if ( (GetTeamClientCount(TEAM_RED) + GetTeamClientCount(TEAM_BLUE)) < 2 )
	{
		Cleanup(CLEANUP_PLAYERSPAWN);
		
		if ( (g_Debug & DEBUGFLAG_INDICES) == DEBUGFLAG_INDICES )
		{
			LogMessage("Spawn: Reset indices to 0; plugin disabled or not in round.");
		}
	}
	else	// There are enough players on a team.
	{
		if ( g_Assassin > 0 && GetClientOfUserId(g_Assassin) > 0 )	// If the assassin is valid:
		{
			new team = GetClientTeam(client);
			
			if ( client_id == g_Assassin && team == TEAM_BLUE )
			{
				ChangeClientTeamPersistent(client, TEAM_RED);
				CheckPlayersOnRed();
			}
			else if ( client_id != g_Assassin && team == TEAM_RED )
			{
				ChangeClientTeamPersistent(client, TEAM_BLUE);
				CheckPlayersOnRed();
			}
		}
		else
		{
			new assassin_index = RandomPlayerFromTeam(TEAM_RED);
			if ( assassin_index < 1 ) assassin_index = RandomPlayerFromTeam(TEAM_BLUE);
			
			if ( assassin_index > 0 && assassin_index <= MaxClients )
			{
				g_Assassin = GetClientUserId(assassin_index);
				if ( GetClientTeam(assassin_index) == TEAM_BLUE )	ChangeClientTeamPersistent(assassin_index, TEAM_RED);
				CheckPlayersOnRed();
				
				g_Target = GetClientUserId(RandomPlayerFromTeam(TEAM_BLUE));
			}
		}
	}
}

/*	Changes the team of any Red players who are not the assassin.	*/
stock CheckPlayersOnRed(bool:check = true)
{
	if ( g_Assassin < 1 ) return;
	
	new g_Debug = GetConVarInt(cv_Debug);
	
	if ( GetTeamClientCount(TEAM_RED) > 0 )
	{
		for ( new i = 1; i <= MaxClients; i++ )
		{
			if ( IsClientInGame(i) && GetClientTeam(i) == TEAM_RED )
			{
				new id = GetClientUserId(i);
				
				if ( (g_Debug & DEBUGFLAG_INDICES) == DEBUGFLAG_INDICES )
				{
					LogMessage("CheckPlayersOnRed: checking player ID %d...", id);
				}
				
				if ( id != g_Assassin )
				{
					if ( (g_Debug & DEBUGFLAG_INDICES) == DEBUGFLAG_INDICES )
					{
						LogMessage("Player ID %d is not the assassin but is on Red, moving to Blue...", id);
					}
					
					ChangeClientTeamPersistent(i, TEAM_BLUE);
				}
			}
		}
	}
	
	// Now that we've booted anyone who's not the assassin, check to make sure that Red actually has players.
	if ( check )
	{
		if ( GetTeamClientCount(TEAM_RED) < 1 && GetTeamClientCount(TEAM_BLUE) > 1 )
		{
			new assassin = RandomPlayerFromTeam(TEAM_BLUE);
			g_Assassin = GetClientUserId(assassin);
			ChangeClientTeamPersistent(assassin, TEAM_RED);
		}
	}
}

/*	Returns a random player from the chosen team, or 0 on error.
	If exclude is specified, the client with this index will be excluded from the search.	*/
stock RandomPlayerFromTeam(team, exclude = 0)
{
	if ( team < 0 ) return 0;	// Make sure our team input value is valid.
	
	new playersfound[MaxClients];
	new n_playersfound = 0;
	
	// Check each client index.
	for (new i = 1; i <= MaxClients; i++)
	{
		if ( IsClientInGame(i) && i != exclude )	// If the client we've chosen is in the game and not excluded:
		{
			if ( GetClientTeam(i) == team )	// If they're on the right team:
			{
				playersfound[n_playersfound] = i;	// Put our client index (i) into the array.
				n_playersfound++;					// Increment our "players found" count and loop back.
			}
		}
	}
	
	if ( n_playersfound < 1 ) return 0;	// If we didn't find any players, return 0.
	
	// By this point we will have the number of players found stored in n_playersfound, and their indices in playersfound[].
	// The max index will be found at (n_playersfound - 1).
	// The minimum number of players found will be 1.
	
	new ChosenPlayer = GetRandomInt(0, n_playersfound-1);	// Choose a random player between index 0 and the max index.
	
	if ( (GetConVarInt(cv_Debug) & DEBUGFLAG_INDICES) == DEBUGFLAG_INDICES )
	{
		LogMessage("Players found on team %d: %d. Chosen player index: %d (%N).", team, n_playersfound, playersfound[ChosenPlayer], playersfound[ChosenPlayer]);
	}
	
	return playersfound[ChosenPlayer];
}

/*	Changes a client's team without killing them.	*/
stock ChangeClientTeamPersistent(client, team)
{
	if ( client < 1 || client > MaxClients || !IsClientInGame(client) )
	{
		LogMessage("Persistent error: client %d did not pass checks.", client);
		return;
	}
	
	// If the player has chosen a team but not a class yet, ignore them.
	if ( IsClientInGame(client) && TF2_GetPlayerClass(client) == TFClass_Unknown ) return;
	
	if ( IsValidForPersistent(client) ) SetEntProp(client, Prop_Send, "m_lifeState", 2);
	ChangeClientTeam(client, team);
	//if ( IsValidForPersistent(client) )
	SetEntProp(client, Prop_Send, "m_lifeState", 0);
}
 
 /*	Returns true if m_lifeState should be changed for ChangeClientTeamPersistent.
	Seeing if this will stop infinite spawn time bugs.	*/
stock bool:IsValidForPersistent(client)
{
	if ( !IsFakeClient(client) )
	{
		if ( IsPlayerAlive(client) && !IsClientTimingOut(client) ) return true;
		else return false;
	}
	else
	{
		if ( IsPlayerAlive(client) ) return true;
		else return false;
	}
}

/*	Returns true if the client's current weapon is from the specified slot.	*/
stock bool:IsCurrentWeaponFromSlot(client, slot)
{
	if ( client < 1 || client > MaxClients || !IsClientInGame(client) || GetClientTeam(client) < TEAM_RED || GetClientTeam(client) > TEAM_BLUE ) return false;
	
	// Get the weapon index from the  slot.
	new slotweapon = GetPlayerWeaponSlot(client, slot);
	if ( !IsValidEntity(slotweapon) ) return false;
	
	// Get its classname.
	decl String:slotweapon_classname[65];
	GetEntityClassname(slotweapon, slotweapon_classname, sizeof(slotweapon_classname));
	
	// Get the classname of the current weapon.
	decl String:classname[65];
	GetClientWeapon(client, classname, sizeof(classname));
	
	// return true if the strings are equal.
	return StrEqual(slotweapon_classname, classname, false);
}

/*	Disables any objective-related map entities.	*/
stock DisableObjectives()
{
	new g_debug = GetConVarInt(cv_Debug);
	
	// Kill any control point triggers.
	new ent = -1;
	
	while ( (ent = FindEntityByClassname2(ent, "trigger_capture_area")) != -1 )
	{
		if ( (g_debug & DEBUGFLAG_OBJECTIVES) == DEBUGFLAG_OBJECTIVES )
		{
			LogMessage("Killing trigger_capture_area %d.", ent);
		}
		
		AcceptEntityInput(ent, "Kill");
	}
	
	// Disable and hide any control points.
	ent = -1;
	
	while ( (ent = FindEntityByClassname2(ent, "team_control_point")) != -1 )
	{
		if ( (g_debug & DEBUGFLAG_OBJECTIVES) == DEBUGFLAG_OBJECTIVES )
		{
			LogMessage("Disabling team_control_point %d.", ent);
		}
		
		AcceptEntityInput(ent, "HideModel");
		AcceptEntityInput(ent, "Disable");
	}
	
	// Kill any CTF flags.
	ent = -1;
	
	while ( (ent = FindEntityByClassname2(ent, "item_teamflag")) != -1 )
	{
		if ( (g_debug & DEBUGFLAG_OBJECTIVES) == DEBUGFLAG_OBJECTIVES )
		{
			LogMessage("Killing item_teamflag %d.", ent);
		}
		
		AcceptEntityInput(ent, "Kill");
	}
	
	// Kill any flag capture areas.
	// This will also kill the capture areas around payload carts.
	ent = -1;
	
	while ( (ent = FindEntityByClassname2(ent, "func_capturezone")) != -1 )
	{
		if ( (g_debug & DEBUGFLAG_OBJECTIVES) == DEBUGFLAG_OBJECTIVES )
		{
			LogMessage("Killing func_capturezone %d.", ent);
		}
		
		AcceptEntityInput(ent, "Kill");
	}
}

/*	Kills any buildings built by the specified player.
	Client is the player index to check.
	Flags is the types of building to check for.
	1 = Sentries
	2 = Dispensers
	4 = Teleporters	*/
stock KillBuildings(client, flags)
{
	if ( TF2_GetPlayerClass(client) != TFClass_Engineer ) return;
	
	// Sentries:
	if ( (flags & BUILDING_SENTRY) == BUILDING_SENTRY )
	{
		new n_SentryIndex = -1;
		while ( (n_SentryIndex = FindEntityByClassname2(n_SentryIndex, "obj_sentrygun")) != -1 )
		{
			if ( GetEntPropEnt(n_SentryIndex, Prop_Send, "m_hBuilder") == client )
			{
				SetVariantInt( GetEntProp(n_SentryIndex, Prop_Send, "m_iMaxHealth") + 1 );
				AcceptEntityInput(n_SentryIndex, "RemoveHealth");
				AcceptEntityInput(n_SentryIndex, "Kill");
			}
		}
	}
	
	// Dispensers:
	if ( (flags & BUILDING_DISPENSER) == BUILDING_DISPENSER )
	{
		new n_DispenserIndex = -1;
		while ( (n_DispenserIndex = FindEntityByClassname2(n_DispenserIndex, "obj_dispenser")) != -1 )
		{
			if ( GetEntPropEnt(n_DispenserIndex, Prop_Send, "m_hBuilder") == client )
			{
				SetVariantInt( GetEntProp(n_DispenserIndex, Prop_Send, "m_iMaxHealth") + 1 );
				AcceptEntityInput(n_DispenserIndex, "RemoveHealth");
				AcceptEntityInput(n_DispenserIndex, "Kill");
			}
		}
	}
	
	// Teleporters:
	if ( (flags & BUILDING_TELEPORTER) == BUILDING_TELEPORTER )
	{
		new n_TeleporterIndex = -1;
		while ( (n_TeleporterIndex = FindEntityByClassname2(n_TeleporterIndex, "obj_teleporter")) != -1 )
		{
			if ( GetEntPropEnt(n_TeleporterIndex, Prop_Send, "m_hBuilder") == client )
			{
				SetVariantInt( GetEntProp(n_TeleporterIndex, Prop_Send, "m_iMaxHealth") + 1 );
				AcceptEntityInput(n_TeleporterIndex, "RemoveHealth");
				AcceptEntityInput(n_TeleporterIndex, "Kill");
			}
		}
	}
}

/*	Sets the team of the buildings for the specified client.	*/
stock ModifyEngineerBuildings(client, team)
{
	if ( client < 1 || client > MaxClients || !IsClientInGame(client) || GetClientTeam(client) < TEAM_RED || TF2_GetPlayerClass(client) != TFClass_Engineer ) return;
	
	new i = -1;
	while ( (i = FindEntityByClassname2(i, "obj_sentrygun")) != -1 )
	{
		if ( GetEntPropEnt(i, Prop_Send, "m_hBuilder") == client )
		{
			SetEntProp(i, Prop_Send, "m_iTeamNum", team);
			SetEntProp(i, Prop_Send, "m_nSkin", team-2);	// Skin is 2 less than team number.
		}
	}
	
	i = -1;
	while ( (i = FindEntityByClassname2(i, "obj_dispenser")) != -1 )
	{
		if ( GetEntPropEnt(i, Prop_Send, "m_hBuilder") == client )
		{
			SetEntProp(i, Prop_Send, "m_iTeamNum", team);
			SetEntProp(i, Prop_Send, "m_nSkin", team-2);	// Skin is 2 less than team number.
		}
	}
	
	i = -1;
	while ( (i = FindEntityByClassname2(i, "obj_teleporter")) != -1 )
	{
		if ( GetEntPropEnt(i, Prop_Send, "m_hBuilder") == client )
		{
			SetEntProp(i, Prop_Send, "m_iTeamNum", team);
			SetEntProp(i, Prop_Send, "m_nSkin", team-2);	// Skin is 2 less than team number.
		}
	}
}

/*	Updates the target player with particle effects.	*/
stock UpdateTarget()
{
	static p_ParentIndex = -1;	// Entity index of the parent of this particle effect.
	static p_Index = -1;			// Index of the effect itself.
	
	new target = GetClientOfUserId(g_Target);	// Index of target.
	
	// If the target is not valid, kill the particle effect if it's alive.
	if ( g_Target < 1 || target < 1 )
	{
		if ( p_Index > MaxClients && IsValidEntity(p_Index) ) AcceptEntityInput(p_Index, "Kill");
		p_Index = -1;
		p_ParentIndex = -1;
	}
	// If the target's valid but the effect is not parented to the correct person, kill it.
	else if ( p_ParentIndex != target )
	{
		if ( p_Index > MaxClients && IsValidEntity(p_Index) ) AcceptEntityInput(p_Index, "Kill");
		p_Index = -1;
		p_ParentIndex = -1;
	}
	
	// Now, if the effect doesn't exist but it should, create it.
	if ( p_Index <= MaxClients || !IsValidEntity(p_Index) )
	{
		if ( target > 0 && target <= MaxClients && IsClientInGame(target) )
		{
			new effect = CreateEntityByName("info_particle_system");
			if ( effect < 1 )
			{
				p_Index = -1;
				p_ParentIndex = -1;
				return;
			}
			
			// Teleport the effect to the player.
			decl Float:pos[3];
			GetEntPropVector(target, Prop_Send, "m_vecOrigin", pos);
			pos[2] += PARTICLE_OFFSET;
			TeleportEntity(effect, pos, NULL_VECTOR, NULL_VECTOR);
			
			// Set the effect type.
			if ( GetClientTeam(target) == TEAM_BLUE ) DispatchKeyValue(effect, "effect_name", TARGET_BLUE);
			else DispatchKeyValue(effect, "effect_name", TARGET_RED);
			DispatchKeyValue(effect, "targetname", "target_effect");
			
			// Name the player and parent the effect to them.
			decl String:TargetName[33];
			Format(TargetName, sizeof(TargetName), "target_%d", g_Target);
			DispatchKeyValue(target, "targetname", TargetName);
			DispatchKeyValue(effect, "parentname", TargetName);
			
			//Spawn and activate the effect.
			DispatchSpawn(effect);
			ActivateEntity(effect);
			AcceptEntityInput(effect, "start");
			
			// Parent the effect via I/O.
			SetVariantString(TargetName);
			AcceptEntityInput(effect, "SetParent", effect, effect, 0);
			SetEntPropEnt(effect, Prop_Send, "m_hOwnerEntity", target);
			
			// Record the indices of the effect and the target.
			p_Index = effect;
			p_ParentIndex = target;
			
		}
		else
		{
			p_Index = -1;
			p_ParentIndex = -1;
		}
	}
	else
	{
		p_Index = -1;
		p_ParentIndex = -1;
	}
}

/*	Checks each client's score against the max score. If a score is greater than or equal to the max score, the round is won.	*/
stock CheckScoresAgainstMax()
{
	// Find the max score in the array.
	new MaxScore = -1;
	//new ClientOfMaxScore = 1;
	
	for ( new i = 0; i < MAXPLAYERS; i++ )
	{
		if ( g_Scores[i] > MaxScore )
		{
			MaxScore = g_Scores[i];
			//ClientOfMaxScore = i+1;
		}
	}
	
	// Now check if the max score is greater than or equal to the max score ConVar.
	if ( MaxScore >= GetConVarInt(cv_MaxScore) )
	{
		RoundWin(TEAM_RED);
	}
}

// ===== Timers =====

/*	Timer continually called every 0.5s to re-apply conditions to the assassin.	*/
public Action:TimerAssassinCondition(Handle:timer)
{
	if ( g_PluginState > 0 ) return Plugin_Handled;
	
	new g_Debug = GetConVarInt(cv_Debug);
	new client = GetClientOfUserId(g_Assassin);
	new target = GetClientOfUserId(g_Target);
	
	if ( client > 0 && client <= MaxClients && IsClientInGame(client) && IsPlayerAlive(client) )
	{
		// Check the player's class and apply effects depending on the class.
		switch ( TF2_GetPlayerClass(client) )
		{
			case TFClass_Scout:
			{
				if ( (g_Debug & DEBUGFLAG_CONDITION) == DEBUGFLAG_CONDITION )
				{
					LogMessage("Condition timer: Class is Scout.");
				}
				
				if ( IsCurrentWeaponFromSlot(client, 2) ) TF2_AddCondition(client, TFCond_HalloweenCritCandy, CONDITION_REFRESH+0.05);
				else TF2_AddCondition(client, TFCond_Buffed, CONDITION_REFRESH+0.05);	// Scout gets the Buff Banner effect(Crit-a-Cola loses its effect after a short while).
			}
			
			case TFClass_Soldier:
			{
				if ( (g_Debug & DEBUGFLAG_CONDITION) == DEBUGFLAG_CONDITION )
				{
					LogMessage("Condition timer: Class is Soldier.");
				}
				
				if ( IsCurrentWeaponFromSlot(client, 2) ) TF2_AddCondition(client, TFCond_HalloweenCritCandy, CONDITION_REFRESH+0.05);
				else TF2_AddCondition(client, TFCond_RegenBuffed, CONDITION_REFRESH+0.05);	// Soldier gets the Japanese banner's effect.
			}
			
			case TFClass_Pyro:
			{
				if ( (g_Debug & DEBUGFLAG_CONDITION) == DEBUGFLAG_CONDITION )
				{
					LogMessage("Condition timer: Class is Pyro.");
				}
				
				if ( IsCurrentWeaponFromSlot(client, 2) ) TF2_AddCondition(client, TFCond_HalloweenCritCandy, CONDITION_REFRESH+0.05);
				else TF2_AddCondition(client, TFCond_CritCola, CONDITION_REFRESH+0.05);	// Pyro gets the Crit-a-Cola effect.
			}
			
			case TFClass_DemoMan:
			{
				if ( (g_Debug & DEBUGFLAG_CONDITION) == DEBUGFLAG_CONDITION )
				{
					LogMessage("Condition timer: Class is Demoman.");
				}
				
				if ( IsCurrentWeaponFromSlot(client, 2) ) TF2_AddCondition(client, TFCond_HalloweenCritCandy, CONDITION_REFRESH+0.05);
				else TF2_AddCondition(client, TFCond_RegenBuffed, CONDITION_REFRESH+0.05);	// Demo gets the Japanese banner's effect.
			}
			
			case TFClass_Heavy:
			{
				if ( (g_Debug & DEBUGFLAG_CONDITION) == DEBUGFLAG_CONDITION )
				{
					LogMessage("Condition timer: Class is Heavy.");
				}
				
				// Heavy gets the whip speed effect.
				TF2_AddCondition(client, TFCond_SpeedBuffAlly, CONDITION_REFRESH+0.05);
				
				if ( IsCurrentWeaponFromSlot(client, 2) ) TF2_AddCondition(client, TFCond_HalloweenCritCandy, CONDITION_REFRESH+0.05);
			}
			
			case TFClass_Engineer:
			{
				if ( (g_Debug & DEBUGFLAG_CONDITION) == DEBUGFLAG_CONDITION )
				{
					LogMessage("Condition timer: Class is Engineer.");
				}
				
				if ( IsCurrentWeaponFromSlot(client, 2) ) TF2_AddCondition(client, TFCond_HalloweenCritCandy, CONDITION_REFRESH+0.05);
				else TF2_AddCondition(client, TFCond_RegenBuffed, CONDITION_REFRESH+0.05);	// Engi gets the Japanese banner's effect.
			}
			
			case TFClass_Medic:
			{
				if ( (g_Debug & DEBUGFLAG_CONDITION) == DEBUGFLAG_CONDITION )
				{
					LogMessage("Condition timer: Class is Medic.");
				}
				
				if ( IsCurrentWeaponFromSlot(client, 2) )
				{
					TF2_AddCondition(client, TFCond_HalloweenCritCandy, CONDITION_REFRESH+0.05);
				}
				else
				{
					// Medic gets Buff Banner and whip speed effect.
					TF2_AddCondition(client, TFCond_Buffed, CONDITION_REFRESH+0.05);
				}
				
				TF2_AddCondition(client, TFCond_SpeedBuffAlly, CONDITION_REFRESH+0.05);
			}
			
			case TFClass_Sniper:
			{
				if ( (g_Debug & DEBUGFLAG_CONDITION) == DEBUGFLAG_CONDITION )
				{
					LogMessage("Condition timer: Class is Sniper.");
				}
				
				if ( IsCurrentWeaponFromSlot(client, 2) ) TF2_AddCondition(client, TFCond_HalloweenCritCandy, CONDITION_REFRESH+0.05);
				else TF2_AddCondition(client, TFCond_Buffed, CONDITION_REFRESH+0.05);	// Sniper gets the Buff Banner effect.
			}
			
			case TFClass_Spy:
			{
				if ( (g_Debug & DEBUGFLAG_CONDITION) == DEBUGFLAG_CONDITION )
				{
					LogMessage("Condition timer: Class is Spy.");
				}
				
				// Spy gets Crit-a-Cola effect and whip speed effect, as long as he's not cloaked or disguised.
				if ( !TF2_IsPlayerInCondition(client, TFCond_Disguising) && !TF2_IsPlayerInCondition(client, TFCond_Disguised)
						&& !TF2_IsPlayerInCondition(client, TFCond_Cloaked) && !TF2_IsPlayerInCondition(client, TFCond_DeadRingered) )
				{
					if ( !IsCurrentWeaponFromSlot(client, 2) )	// We don't want any buffs on the Spy's knife since it already gets backstabs.
					{
						TF2_AddCondition(client, TFCond_CritCola, CONDITION_REFRESH+0.05);
					}
					
					TF2_AddCondition(client, TFCond_SpeedBuffAlly, CONDITION_REFRESH+0.05);
				}
			}
		}
	}
	
	if ( target > 0 && target <= MaxClients && IsClientInGame(target) && IsPlayerAlive(target) )
	{
		// Target melee check (because I CBA to make a whole new timer for the target when it's not needed):
		if ( IsCurrentWeaponFromSlot(target, 2) && TF2_GetPlayerClass(client) != TFClass_Spy )
		{
			TF2_AddCondition(target, TFCond_HalloweenCritCandy, CONDITION_REFRESH+0.05);
		}
	}
	
	return Plugin_Handled;
}

/*	Timer called once a second to update the HUD messages.	*/
public Action:TimerHUDRefresh(Handle:timer)
{
	UpdateHUDMessages(g_Assassin, g_Target);
	
	return Plugin_Continue;
}

/*	Timer called once a second to update the HUD info.	*/
public Action:TimerHUDInfoRefresh(Handle:timer)
{
	if ( (g_PluginState & STATE_NOT_IN_ROUND) != STATE_NOT_IN_ROUND ) UpdateHUDInfo(g_Scores);
	else ShowWinner(g_Scores);
	
	return Plugin_Continue;
}

/*	Updates the HUD for all clients concerning who is the assassin/target.	*/
stock UpdateHUDMessages(assassin_id, target_id)
{
	if ( g_PluginState > STATE_DISABLED ) return;	// If we're not enabled, return.
	
	new assassin = GetClientOfUserId(assassin_id);
	new target = GetClientOfUserId(target_id);
	
	new assassin_team, target_team;
	
	if ( assassin > 0 && assassin <= MaxClients && IsClientInGame(assassin) ) assassin_team = GetClientTeam(assassin);
	if ( target > 0 && target <= MaxClients && IsClientInGame(target) ) target_team = GetClientTeam(target);
	
	if ( hs_Assassin != INVALID_HANDLE )	// If our assassin synchroniser exists:
	{
		switch(assassin_team)
		{
			case TEAM_RED:
			{
				SetHudTextParams(0.05, 0.1,
									1.05,
									189,
									58,
									58,
									255,
									0,
									0.0,
									0.0,
									0.0);
			}
			
			case TEAM_BLUE:
			{
				SetHudTextParams(0.05, 0.1,
									1.05,
									0,
									38,
									255,
									255,
									0,
									0.0,
									0.0,
									0.0);
			}
			
			default:
			{
				SetHudTextParams(0.05, 0.1,
									1.05,
									255,
									255,
									255,
									255,
									0,
									0.0,
									0.0,
									0.0);
			}
		}
		
		if ( (g_PluginState & STATE_NOT_IN_ROUND) != STATE_NOT_IN_ROUND )	// If we're in a round:
		{
			
			// Display the text to all players.
			decl String:s_AssassinName[MAX_NAME_LENGTH + 1];
			s_AssassinName[0] = '\0';
			
			// Make sure our client is valid before we get their name.
			if ( assassin > 0 && assassin <= MaxClients && IsClientInGame(assassin) )
			{
				GetClientName(assassin, s_AssassinName, sizeof(s_AssassinName));
				
				for ( new i_assassin = 1; i_assassin <= MaxClients; i_assassin++ )	// Iterate through the client indices
				{
					if ( IsClientInGame(i_assassin) )	// If the client is connected:
					{
						ShowSyncHudText(i_assassin, hs_Assassin, "%T: %s", "as_assassin", i_assassin, s_AssassinName);
					}
				}
			}
			else
			{
				for ( new i_assassin = 1; i_assassin <= MaxClients; i_assassin++ )	// Iterate through the client indices
				{
					if ( IsClientInGame(i_assassin) )	// If the client is connected:
					{
						ShowSyncHudText(i_assassin, hs_Assassin, "%T: %T", "as_assassin", i_assassin, "as_none", i_assassin);
					}
				}
			}
		}
		else	// Otherwise:
		{
			// Clear HUD sync for all players
			ClearSyncHUDTextAll(hs_Assassin);
		}
	}
	
	if ( hs_Target != INVALID_HANDLE )	// If our target synchroniser exists:
	{
		switch(target_team)
		{
			case TEAM_RED:
			{
				SetHudTextParams(0.05, 0.13,
									1.05,
									189,
									58,
									58,
									255,
									0,
									0.0,
									0.0,
									0.0);
			}
			
			case TEAM_BLUE:
			{
				SetHudTextParams(0.05, 0.13,
									1.05,
									0,
									38,
									255,
									255,
									0,
									0.0,
									0.0,
									0.0);
			}
			
			default:
			{
				SetHudTextParams(0.05, 0.13,
									1.05,
									255,
									255,
									255,
									255,
									0,
									0.0,
									0.0,
									0.0);
			}
		}
		
		if ( (g_PluginState & STATE_NOT_IN_ROUND) != STATE_NOT_IN_ROUND )	// If we're in a round:
		{			
			// Display the text to all players.
			decl String:s_TargetName[MAX_NAME_LENGTH + 1];
			s_TargetName[0] = '\0';
			
			// Make sure our client is valid before we get their name.
			if ( target > 0 && target <= MaxClients && IsClientInGame(target) )
			{
				GetClientName(target, s_TargetName, sizeof(s_TargetName));
			
				for ( new i_target= 1; i_target <= MaxClients; i_target++ )	// Iterate through the client indices
				{
					if ( IsClientInGame(i_target) )	// If the client is connected:
					{
						ShowSyncHudText(i_target, hs_Target, "%T: %s", "as_target", i_target, s_TargetName);
					}
				}
			}
			else
			{
				for ( new i_target = 1; i_target <= MaxClients; i_target++ )	// Iterate through the client indices
				{
					if ( IsClientInGame(i_target) )	// If the client is connected:
					{
						ShowSyncHudText(i_target, hs_Target, "%T: %T", "as_target", i_target, "as_none", i_target);
					}
				}
			}
		}
		else	// Otherwise:
		{
			// Clear HUD sync for all players
			ClearSyncHUDTextAll(hs_Target);
		}
	}
}

/*	Clears the HUD text through the HUD synchroniser for all clients.
	Argument is the handle of the synchronisation object.*/
stock ClearSyncHUDTextAll(Handle:syncobj = INVALID_HANDLE)
{
	if ( syncobj == INVALID_HANDLE ) return;	// If our handle isn't valid, return.
	
	for ( new i = 1; i <= MaxClients; i++ )	// Iterate through the client indices
	{
		if ( IsClientInGame(i) )	// If the client is connected:
		{
			ClearSyncHud(i, syncobj);	// Clear their sync object.
		}
	}
}

/*	Updates the HUD display of scores.	*/
stock UpdateHUDInfo(scores[])
{
	if ( (g_PluginState & STATE_DISABLED) == STATE_DISABLED || (g_PluginState & STATE_NOT_IN_ROUND) == STATE_NOT_IN_ROUND || g_Assassin < 1 ) return;
	
	new ClientScores[MAXPLAYERS][2];
	
	for ( new i = 0; i < MAXPLAYERS; i++ )
	{
		ClientScores[i][0] = i+1;			// Column 0 is the client index.
		ClientScores[i][1] = scores[i];	// Column 1 is the client's score.
	}
	
	// Sort the 2D array.
	SortCustom2D(ClientScores, MAXPLAYERS, SortClientScores);
	
	// Display the scores.
	SetHudTextParams(0.05, 0.35,
									1.05,
									189,
									246,
									194,
									68,
									0,
									0.0,
									0.0,
									0.0);
	
	// HUD display format will be as follows:
	//
	// xxxx - ClientName1
	// yyyy - ClientName2
	// zzzz - ClientName3
	//
	// nnnn - YourNameHere
	
	decl String:ClientScore1[MAX_NAME_LENGTH+9];
	decl String:ClientScore2[MAX_NAME_LENGTH+9];
	decl String:ClientScore3[MAX_NAME_LENGTH+9];
	decl String:CurrentPlayer[MAX_NAME_LENGTH+9];
	
	// ClientScore1/2/3 will not change as we display the text to different clients.
	decl String:ClientName[MAX_NAME_LENGTH+1];
	
	if ( IsClientInGame(ClientScores[0][0]) ) GetClientName(ClientScores[0][0], ClientName, sizeof(ClientName));
	else ClientName = "N/A";
	Format(ClientScore1, sizeof(ClientScore1), "%d - %s", ClientScores[0][1], ClientName);
	
	if ( IsClientInGame(ClientScores[1][0]) ) GetClientName(ClientScores[1][0], ClientName, sizeof(ClientName));
	else ClientName = "N/A";
	Format(ClientScore2, sizeof(ClientScore2), "%d - %s", ClientScores[1][1], ClientName);
	
	if ( IsClientInGame(ClientScores[2][0]) ) GetClientName(ClientScores[2][0], ClientName, sizeof(ClientName));
	else ClientName = "N/A";
	Format(ClientScore3, sizeof(ClientScore3), "%d - %s", ClientScores[2][1], ClientName);
	
	for ( new j = 1; j <= MaxClients; j++ )
	{
		if ( IsClientInGame(j) )
		{
			GetClientName(j, ClientName, sizeof(ClientName));
			Format(CurrentPlayer, sizeof(CurrentPlayer), "%d - %s", scores[j-1], ClientName);
			
			ShowSyncHudText(j, hs_Info, "%s\n%s\n%s\n\n%s", ClientScore1, ClientScore2, ClientScore3, CurrentPlayer);
		}
	}
}

/*	Displays info about the winning player.	*/
stock ShowWinner(scores[])
{
	if ( (g_PluginState & STATE_DISABLED) == STATE_DISABLED || (GetTeamClientCount(TEAM_RED) + GetTeamClientCount(TEAM_BLUE)) < 2 ) return;
	
	new ClientScores[MAXPLAYERS][2];
	
	for ( new i = 0; i < MAXPLAYERS; i++ )
	{
		ClientScores[i][0] = i+1;			// Column 0 is the client index.
		ClientScores[i][1] = scores[i];	// Column 1 is the client's score.
	}
	
	// Sort the 2D array.
	SortCustom2D(ClientScores, MAXPLAYERS, SortClientScores);
	
	new client = ClientScores[0][0];
	new score = ClientScores[0][1];
	
	if ( score < 1 ) return;
	
	SetHudTextParams(-1.0, 0.13,
									1.05,
									189,
									246,
									194,
									68,
									0,
									0.0,
									0.0,
									0.0);
	
	decl String:ClientName[MAX_NAME_LENGTH+1];
	GetClientName(client, ClientName, sizeof(ClientName));
	
	for ( new j = 1; j <= MaxClients; j++ )
	{
		if ( IsClientInGame(j) )
		{
			ShowSyncHudText(j, hs_Info, "%T", "as_round_win", j, ClientName, score);
		}
	}
}

/*	Sorts the score array. Apparently this sorts via column 1.	*/
public SortClientScores(x[], y[], array[][], Handle:data)
{
    if (x[1] > y[1]) 
        return -1;
    else if (x[1] < y[1]) 
        return 1;    
    return 0;
}

/*	Outputs the assassin and target indices to the console.	*/
public Action:Cmd_ShowIndices(client, args)
{
	new assassin = GetClientOfUserId(g_Assassin);
	new target = GetClientOfUserId(g_Target);
	decl String:AssassinName[MAX_NAME_LENGTH+1], String:TargetName[MAX_NAME_LENGTH+1];
	
	if ( assassin < 1 || assassin > MaxClients ) AssassinName = "N/A";
	else GetClientName(assassin, AssassinName, sizeof(AssassinName));
	
	if ( target < 1 || target > MaxClients ) TargetName = "N/A";
	else GetClientName(target, TargetName, sizeof(TargetName));
	
	PrintToConsole(client, "Assassin ID: %d; Index: %d; Name: %s. Target ID: %d; Index: %d; Name: %s.", g_Assassin, assassin, AssassinName, g_Target, target, TargetName);
	
	return Plugin_Handled;
}

/*	Outputs scores to the console.	*/
public Action:Cmd_ShowScores(client, args)
{
	for ( new i = 0; i < MAXPLAYERS; i++ )
	{
		PrintToConsole(client, "Score for player index %d: %d", i, g_Scores[i]);
	}
	
	return Plugin_Handled;
}

/*	Outputs player info to the console.
	Used for debugging when players get stuck in limbo and don't respawn on a team.	*/
public Action:Cmd_Players(client, args)
{
	for ( new i = 0; i < MaxClients; i++ )
	{
		if ( IsClientInGame(i) ) PrintToConsole(client, "%d. %N - Team %d", i, i, GetClientTeam(i));
	}
	
	return Plugin_Handled;
}