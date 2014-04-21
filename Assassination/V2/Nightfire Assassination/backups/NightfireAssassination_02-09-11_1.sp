// Fourth re-write of the Assassination plugin.

/*
	Recent changes:
	- Re-structured the plugin to help fix assassin and target assignment issues.
*/

#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <tf2_stocks>
#include <keyvalues>

#define DEBUGFLAG_GENERAL		1	// General debugging.
#define DEBUGFLAG_INDICES		2	// Logging when the global indices change.
#define DEBUGFLAG_RANDOMPLAYER	4	// Logging when fetching a random player.
#define DEBUGFLAG_TEAMCHANGE	8	// Logging when a player changes team.
#define DEBUGFLAG_ASSASSINCOND	16	// Logging when the assassin condition timer is created or destroyed.
#define DEBUGFLAG_DEATH			32	// Logging when the assassin, target etc. die.

#define DEBUG				63

// Plugin defines
#define PLUGIN_NAME			"Nightfire: Assassination"
#define PLUGIN_AUTHOR		"[X6] Herbius"
#define PLUGIN_DESCRIPTION	"Team deathmatch; become the assassin to gain points."
#define PLUGIN_VERSION		"1.1.0.44"
#define PLUGIN_URL			"http://forums.alliedmods.net/showthread.php?p=1531506#post1531506"
// Note: I don't update this religiously on builds. :P There have been AT LEAST this many builds.

// Team integers
#define TEAM_INVALID		-1
#define TEAM_UNASSIGNED		0
#define TEAM_SPECTATOR		1
#define TEAM_RED			2
#define TEAM_BLUE			3

// State flags
#define STATE_DISABLED		2	// Plugin is disabled via ConVar.
#define STATE_NOT_IN_ROUND	1	// A round is not in progress. This flag is set on MapEnd, RoundWin or RoundStalemate and reset on RoundStart.

#define ICON_OFFSET		75.0

// Building type flags:
#define BUILDING_SENTRY		1
#define BUILDING_DISPENSER	2
#define BUILDING_TELEPORTER	4

// Cleanup modes
#define CLEANUP_ROUNDSTART	0
#define CLEANUP_ROUNDWIN	1
#define CLEANUP_MAPSTART	2
#define CLEANUP_MAPEND		3
#define CLEANUP_PLAYERSPAWN	4

// Sounds
#define SND_ASSASSIN_KILLED					"assassination/assassin_killed.mp3"					// Sound when the assassin is killed by a player.
#define SND_ASSASSIN_KILLED_BY_TARGET		"assassination/assassin_killed_by_target.mp3"		// Sound when the assassin is killed by the target.
#define SND_ASSASSIN_SCORE					"assassination/assassin_score.mp3"					// Sound when the assassin kills the target.
#define SND_TARGET_KILLED					"assassination/target_killed.mp3"					// Sound when the assassin kills the target.

// Particles
#define PARTICLE_PCF			"particles/assassination.pcf"
#define ASSASSIN_PARTICLE		"duel_red"
#define TARGET_PARTICLE			"particle_nemesis_red"

// Global variables
new g_PluginState;		// Holds the global state of the plugin.
new GlobalIndex[2];		// Index 0 is the assassin, 1 is the target.
new GlobalScore[4];		// 0/1 = Red/Blue total, 2/3 = Red/Blue current.
new DisconnectIndex;	// If a player disconnects, this will hold their indx for use in TeamsChange.

// ConVar handle declarations
new Handle:cv_PluginEnabled = INVALID_HANDLE;			// Enables or disables the plugin. Changing this while in-game will restart the map.
new Handle:cv_MaxScore = INVALID_HANDLE;				// When this score is reached, the round will end.

// Timer handle declarations
new Handle:timer_AssassinCondition = INVALID_HANDLE;	// Handle to our timer that refreshes the buffed state on the assassin. Created on MapStart/PluginStart and killed on MapEnd.
new Handle:timer_MedicHealBuff = INVALID_HANDLE;		// Handle to our timer to refresh the buffed state on assassin Medics' heal targets. Created same as above.
new Handle:timer_HUDMessageRefresh = INVALID_HANDLE;	// Handle to our HUD refresh timer.
new Handle:timer_HUDScoreRefresh = INVALID_HANDLE;

// Hud syncs
new Handle:hs_Assassin = INVALID_HANDLE;				// Handle to our HUD synchroniser for displaying who is the assassin.
new Handle:hs_Target = INVALID_HANDLE;					// Handle to our HUD synchroniser for displaying who is the target.
new Handle:hs_Score = INVALID_HANDLE;					// Handle to our HUD synchroniser for displaying scores.

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
	LogMessage("--++==Assassination Mode started. Version: %s==++--", PLUGIN_VERSION);	
	LoadTranslations("assassination/assassination_phrases");
	AutoExecConfig(true, "assassination", "sourcemod/assassination");
	
	// ConVar declarations.
	// Prefixed with "nfas" (Nightfire Assassination) to make them more unique.
	CreateConVar("nfas_version", PLUGIN_VERSION, "Plugin version.", FCVAR_PLUGIN | FCVAR_NOTIFY);
	
	cv_PluginEnabled  = CreateConVar("nfas_enabled",
												"1",
												"Enables or disables the plugin. Changing this while in-game will restart the map.",
												FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
												true,
												0.0,
												true,
												1.0);
	
	cv_MaxScore  = CreateConVar("nfas_score_max",
												"100",
												"When this score is reached, the round will end.",
												FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
												true,
												1.0);
	
	// Hooks:
	HookConVarChange(cv_PluginEnabled,	CvarChange);
	
	HookEventEx("teamplay_round_start",		Event_RoundStart,		EventHookMode_Post);
	HookEventEx("teamplay_round_win",		Event_RoundWin,			EventHookMode_Post);
	HookEventEx("teamplay_round_stalemate",	Event_RoundStalemate,	EventHookMode_Post);
	HookEventEx("player_spawn",				Event_PlayerSpawn,		EventHookMode_Post);
	HookEventEx("player_team",				Event_TeamsChange,		EventHookMode_Post);
	HookEventEx("player_disconnect",		Event_Disconnect,		EventHookMode_Post);
	HookEventEx("player_death",				Event_PlayerDeath,		EventHookMode_Post);
	
	RegConsoleCmd("nfas_checkindices", Cmd_CheckIndices, "Outputs the global indices to the client's console.");
	
	// Only continue on from this point if the round is already being played.
	if ( !IsServerProcessing() ) return;
	
	// End the current round.
	RoundWin(TEAM_UNASSIGNED);
	
	if ( timer_AssassinCondition == INVALID_HANDLE )
	{
		timer_AssassinCondition = CreateTimer(0.5, TimerAssassinCondition, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
		
		#if (DEBUG & DEBUGFLAG_ASSASSINCOND) == DEBUGFLAG_ASSASSINCOND
		LogMessage("Assassin cond timer created on plugin start.");
		#endif
	}
	#if (DEBUG & DEBUGFLAG_ASSASSINCOND) == DEBUGFLAG_ASSASSINCOND
	else
	{
		LogMessage("Assassin cond timer is not INVALID_HANDLE on plugin start. This is probably a weird error!");
	}
	#endif
	
	if ( timer_MedicHealBuff == INVALID_HANDLE )
	{
		timer_MedicHealBuff = CreateTimer(0.25, TimerMedicHealBuff, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}
	
	if ( hs_Assassin == INVALID_HANDLE )
	{
		hs_Assassin = CreateHudSynchronizer();
	}
	
	if ( hs_Target == INVALID_HANDLE )
	{
		hs_Target = CreateHudSynchronizer();
	}
	
	if ( hs_Score == INVALID_HANDLE )
	{
		hs_Score = CreateHudSynchronizer();
	}
	
	if ( hs_Assassin != INVALID_HANDLE && hs_Target != INVALID_HANDLE )	// If the above was successful:
	{
		UpdateHUDMessages(GlobalIndex[0], GlobalIndex[1]);	// Update the HUD
		timer_HUDMessageRefresh = CreateTimer(1.0, TimerHUDRefresh, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);	// Set up the timer to next update the HUD.
	}
	
	if ( hs_Score != INVALID_HANDLE )	// If the above was successful:
	{
		UpdateHUDScore(GlobalScore[0], GlobalScore[1], GlobalScore[2], GlobalScore[3]);	// Update the HUD
		timer_HUDScoreRefresh = CreateTimer(1.0, TimerHUDScoreRefresh, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);	// Set up the timer to next update the HUD.
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
	
	// Get the current map name
	decl String:mapname[64];
	GetCurrentMap(mapname, sizeof(mapname));
	LogMessage("[AS] Plugin state changed. Restarting map (%s)...", mapname);
	
	// Restart the map	
	ForceChangeLevel(mapname, "Nightfire Assassinaion enabled state changed, requires map restart.");
}

// ================================
// ============ Hooks =============
// ================================

public OnMapStart()
{
	// Set the NOT_IN_ROUND flag.
	g_PluginState |= STATE_NOT_IN_ROUND;
	
	Cleanup(CLEANUP_MAPSTART);
	
	// Start precaching here.
	// Files to download:
	decl String:SoundBuffer[128];
	
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
	
	if ( (g_PluginState & STATE_DISABLED) == STATE_DISABLED ) return;
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
	
	if ( (g_PluginState & STATE_DISABLED) == STATE_DISABLED ) return;
	
	AssignBestIndices();
}

/*	Called when a round is won.	*/
public Event_RoundWin(Handle:event, const String:name[], bool:dontBroadcast)
{
	// Set the NOT_IN_ROUND flag.
	g_PluginState |= STATE_NOT_IN_ROUND;
	
	Cleanup(CLEANUP_ROUNDWIN);
	
	if ( (g_PluginState & STATE_DISABLED) == STATE_DISABLED ) return;
}

/*	Called when a round is drawn.	*/
public Event_RoundStalemate(Handle:event, const String:name[], bool:dontBroadcast)
{
	// Set the NOT_IN_ROUND flag.
	g_PluginState |= STATE_NOT_IN_ROUND;
	
	Cleanup(CLEANUP_ROUNDWIN);
	
	if ( (g_PluginState & STATE_DISABLED) == STATE_DISABLED ) return;
}

/*	Called when a player spawns.	*/
public Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (	(g_PluginState & STATE_DISABLED)		== STATE_DISABLED		||
			(g_PluginState & STATE_NOT_IN_ROUND)	== STATE_NOT_IN_ROUND  )
	{
		Cleanup(CLEANUP_PLAYERSPAWN);
		
		#if (DEBUG & DEBUGFLAG_INDICES) == DEBUGFLAG_INDICES
		LogMessage("Spawn: Reset indices to 0; plugin disabled or not in round.");
		#endif
		
		return;
	}
	
	AssignBestIndices();
}

/*	Called when a player disconnects.
	This is called BEFORE TeamsChange below.*/
public Event_Disconnect(Handle:event, const String:name[], bool:dontBroadcast)
{
	DisconnectIndex = GetClientOfUserId(GetEventInt(event, "userid"));
}

/*	Called when a player changes team.	*/
public Event_TeamsChange(Handle:event, const String:name[], bool:dontBroadcast)
{
	
	// Player spawn will deal with assigning the assassin or target.
	// Here we need to check whether the player who is changing team is the assassin or target.
	
	new tc_ClientIndex = GetClientOfUserId(GetEventInt(event, "userid"));
	new tc_NewTeamID = GetEventInt(event, "team");
	new tc_OldTeamID = GetEventInt(event, "oldteam");
	
	new tc_RedTeamCount = GetTeamClientCount(TEAM_RED);		// These will give us the team counts BEFORE the client has switched.
	new tc_BlueTeamCount = GetTeamClientCount(TEAM_BLUE);
	
	// Since the team change event is ALWAYS called like a pre (thanks, Valve), we need to build up a picture of what
	// the teams will look like after the switch.
	
	if ( GetEventBool(event, "disconnect") ) 	// If the team change happened because the client was disconnecting:
	{
		// Note that, if disconnect == true, the userid will point to the index 0.
		// We fix this here.
		tc_ClientIndex = DisconnectIndex;	// This is retrieved from player_disconnect, which is fired before player_team.
		DisconnectIndex = 0;
		
		#if (DEBUG & DEBUGFLAG_TEAMCHANGE) == DEBUGFLAG_TEAMCHANGE
		LogMessage("TC: Player %d is disconnecting.", tc_ClientIndex);
		#endif
		
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
		#if (DEBUG & DEBUGFLAG_TEAMCHANGE) == DEBUGFLAG_TEAMCHANGE
		LogMessage("TC: Player %N is not disconnecting.", tc_ClientIndex);
		#endif
		
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
	
	if ( tc_ClientIndex > 0 && tc_ClientIndex == GlobalIndex[1] )	// If the client was the target:
	{
		#if (DEBUG & DEBUGFLAG_TEAMCHANGE) == DEBUGFLAG_TEAMCHANGE
		LogMessage("TC: Player %d is the target.", tc_ClientIndex);
		#endif
		
		// If there will not be enough players on a team after the change, set both indices to 0.
		if ( tc_RedTeamCount < 1 || tc_BlueTeamCount < 1 )
		{
			GlobalIndex[0] = 0;
			GlobalIndex[1] = 0;
			
			#if (DEBUG & DEBUGFLAG_TEAMCHANGE) == DEBUGFLAG_TEAMCHANGE
			LogMessage("TC: All indices set to 0.", tc_ClientIndex);
			#endif
		}
		else	// Otherwise, the team counts are acceptable.
		{
			if ( GlobalIndex[0] != 0 && IsClientConnected(GlobalIndex[0]) )	// If the assassin is valid, choose the other team.
			{
				new AssassinTeam = GetClientTeam(GlobalIndex[0]);
				
				switch (AssassinTeam)
				{
					case TEAM_RED:
					{
						GlobalIndex[1] = RandomPlayerFromTeam(TEAM_BLUE, tc_ClientIndex);	// Ignore the changing client since they will still be on the team at this point.
						
						#if (DEBUG & DEBUGFLAG_TEAMCHANGE) == DEBUGFLAG_TEAMCHANGE
						LogMessage("TC: Target is %N", GlobalIndex[1]);
						#endif
					}
					
					case TEAM_BLUE:
					{
						GlobalIndex[1] = RandomPlayerFromTeam(TEAM_RED, tc_ClientIndex);
						
						#if (DEBUG & DEBUGFLAG_TEAMCHANGE) == DEBUGFLAG_TEAMCHANGE
						LogMessage("TC: Target is %N", GlobalIndex[1]);
						#endif
					}
				}
			}
			else	// If the assassin isn't valid, choose at random.
			{
				new RandomTeam = GetRandomInt(TEAM_RED, TEAM_BLUE);
				GlobalIndex[1] = RandomPlayerFromTeam(RandomTeam, tc_ClientIndex);
				
				#if (DEBUG & DEBUGFLAG_TEAMCHANGE) == DEBUGFLAG_TEAMCHANGE
				LogMessage("TC: Target is %N", GlobalIndex[1]);
				#endif
			}
		}
	}
	else if ( tc_ClientIndex > 0 && tc_ClientIndex == GlobalIndex[0] )	// If the client was the assassin:
	{
		#if (DEBUG & DEBUGFLAG_TEAMCHANGE) == DEBUGFLAG_TEAMCHANGE
		LogMessage("TC: Player %d is the assassin.", tc_ClientIndex);
		#endif
		
		// If there will not be enough players on a team after the change, set both indices to 0.
		if ( tc_RedTeamCount < 1 || tc_BlueTeamCount < 1 )
		{
			GlobalIndex[0] = 0;
			GlobalIndex[1] = 0;
			
			#if (DEBUG & DEBUGFLAG_TEAMCHANGE) == DEBUGFLAG_TEAMCHANGE
			LogMessage("TC: All indices set to 0.", tc_ClientIndex);
			#endif
		}
		else	// Otherwise, the team counts are acceptable.
		{
			if ( GlobalIndex[1] != 0 && IsClientConnected(GlobalIndex[1]) )	// If the target is valid, choose the other team.
			{
				new TargetTeam = GetClientTeam(GlobalIndex[1]);
				
				switch (TargetTeam)
				{
					case TEAM_RED:
					{
						GlobalIndex[0] = RandomPlayerFromTeam(TEAM_BLUE, tc_ClientIndex);
						
						#if (DEBUG & DEBUGFLAG_TEAMCHANGE) == DEBUGFLAG_TEAMCHANGE
						LogMessage("TC: Assassin is %N", GlobalIndex[1]);
						#endif
					}
					
					case TEAM_BLUE:
					{
						GlobalIndex[0] = RandomPlayerFromTeam(TEAM_RED, tc_ClientIndex);
						
						#if (DEBUG & DEBUGFLAG_TEAMCHANGE) == DEBUGFLAG_TEAMCHANGE
						LogMessage("TC: Assassin is %N", GlobalIndex[1]);
						#endif
					}
				}
			}
			else	// If the target isn't valid, choose at random.
			{
				new RandomTeam = GetRandomInt(TEAM_RED, TEAM_BLUE);
				GlobalIndex[0] = RandomPlayerFromTeam(RandomTeam, tc_ClientIndex);
				
				#if (DEBUG & DEBUGFLAG_TEAMCHANGE) == DEBUGFLAG_TEAMCHANGE
				LogMessage("TC: Assassin is %N", GlobalIndex[1]);
				#endif
			}
		}
	}
}

/*	Called when a player changes team.	*/
public Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	// We need a robust system for managing what happens when a player dies.
	// OnAssassinDeath will manage when the assassin dies,
	// OnTargetDeath will manage when the target dies, and
	// OnAssassinEnemyDeath will manage when a player on the opposite team to the assassin dies.
	// Each handler function will act differently depending on how many people are on each team
	// and which indices are currently valid.
	
	// If there are ANY abnormal states, don't go through all the crap below.
	if ( g_PluginState > 0 ) return;
	
	decl DeathEvents[11];
	
	DeathEvents[0] = GetEventInt(event, "userid");					// This is the user ID of the player who died.
	DeathEvents[1] = GetEventInt(event, "victim_entindex");			// ???
	DeathEvents[2] = GetEventInt(event, "inflictor_entindex");		// Entindex of the inflictor. This could be a weapon, sentry, projectile, etc.
	DeathEvents[3] = GetEventInt(event, "attacker");				// User ID of the attacker.
	DeathEvents[4] = GetEventInt(event, "weaponid");				// Weapon ID the attacker used.
	DeathEvents[5] = GetEventInt(event, "damagebits");				// Bitflags of the damage dealt.
	DeathEvents[6] = GetEventInt(event, "customkill");				// Custom kill value (headshot, etc.).
	DeathEvents[7] = GetEventInt(event, "assister");				// User ID of the assister.
	DeathEvents[8] = GetEventInt(event, "stun_flags");				// Bitflags of the user's stunned state before death.
	DeathEvents[9] = GetEventInt(event, "death_flags");				// Bitflags describing the type of death.
	DeathEvents[10] = GetEventInt(event, "playerpenetratecount");	// ??? To do with new penetration weapons?
	
	decl String:Weapon[32], String:WeaponLogClassname[32];
	GetEventString(event, "weapon", Weapon, sizeof(Weapon));										// Weapon name.
	GetEventString(event, "weapon_logclassname", WeaponLogClassname, sizeof(WeaponLogClassname));	// Weapon that should be printed to the log.
	
	new bool:SilentKill = GetEventBool(event, "silent_kill");
	
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if ( client < 1 ) return;
	
	// The assassin has died.
	if ( client == GlobalIndex[0] )
	{
		OnAssassinDeath(DeathEvents, sizeof(DeathEvents), Weapon, WeaponLogClassname, SilentKill);
	}
	
	// The target has died.
	else if ( client == GlobalIndex[1] )
	{
		OnTargetDeath(DeathEvents, sizeof(DeathEvents), Weapon, WeaponLogClassname, SilentKill);
	}
	
	// A player on the opposite team to the assassin has died.
	else if ( GlobalIndex[0] > 0 && IsClientConnected(GlobalIndex[0]) )
	{
		if ( GetClientTeam(client) == TEAM_RED && GetClientTeam(GlobalIndex[0]) == TEAM_BLUE )
		{
			OnAssassinEnemyDeath(DeathEvents, sizeof(DeathEvents), Weapon, WeaponLogClassname, SilentKill);
		}
		else if ( GetClientTeam(client) == TEAM_BLUE && GetClientTeam(GlobalIndex[0]) == TEAM_RED )
		{
			OnAssassinEnemyDeath(DeathEvents, sizeof(DeathEvents), Weapon, WeaponLogClassname, SilentKill);
		}
	}
}

/*	Called when the assassin dies.	*/
stock OnAssassinDeath(EventArray[], size, String:Weapon[], String:WeaponLogClassname[], bool:SilentKill)
{
	#if (DEBUG & DEBUGFLAG_DEATH) == DEBUGFLAG_DEATH
	LogMessage("Assassin %N has died:", GetClientOfUserId(EventArray[0]));
	#endif
}

/*	Called when the target dies.	*/
stock OnTargetDeath(EventArray[], size, String:Weapon[], String:WeaponLogClassname[], bool:SilentKill)
{
	#if (DEBUG & DEBUGFLAG_DEATH) == DEBUGFLAG_DEATH
	LogMessage("Target %N has died:", GetClientOfUserId(EventArray[0]));
	#endif
}

/*	Called when someone on the opposite team to the assassin dies.	*/
stock OnAssassinEnemyDeath(EventArray[], size, String:Weapon[], String:WeaponLogClassname[], bool:SilentKill)
{
	#if (DEBUG & DEBUGFLAG_DEATH) == DEBUGFLAG_DEATH
	LogMessage("Assassin enemy %N has died:", GetClientOfUserId(EventArray[0]));
	#endif
}

/*	Returns a random player from the chosen team, or 0 on error.
	If exclude is specified, the client with this indx will be excluded from the search.	*/
stock RandomPlayerFromTeam(team, exclude = 0)
{
	if ( team < 0 ) return 0;	// Make sure our team input value is valid.
	
	new playersfound[MaxClients];
	new n_playersfound = 0;
	
	// Check each client index.
	for (new i = 1; i <= MaxClients; i++)
	{
		if ( IsClientConnected(i) && i != exclude )	// If the client we've chosen is in the game and not excluded:
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
	
	#if (DEBUG & DEBUGFLAG_INDICES) == DEBUGFLAG_INDICES
	LogMessage("Players found on team %d: %d. Chosen player index: %d (%N).", team, n_playersfound, playersfound[ChosenPlayer], playersfound[ChosenPlayer]);
	#endif
	
	return playersfound[ChosenPlayer];
}

/*	Runs checks and assigns indices if they are needed.	*/
AssignBestIndices()
{
	// Check the number of players on the Red and Blue teams.
	new RedTeamCount = GetTeamClientCount(TEAM_RED);
	new BlueTeamCount = GetTeamClientCount(TEAM_BLUE);
	
	// If either team has no players, reset the indices to 0.
	// We don't need to be playing any sounds or dealing with score here.
	if ( RedTeamCount < 1 || BlueTeamCount < 1 )
	{
		#if (DEBUG & DEBUGFLAG_INDICES) == DEBUGFLAG_INDICES
		LogMessage("ABI: Red or Blue has 0 players. Red: %d. Blue: %d", RedTeamCount, BlueTeamCount);
		#endif
		
		GlobalIndex[0] = 0;
		GlobalIndex[1] = 0;
		
		#if (DEBUG & DEBUGFLAG_INDICES) == DEBUGFLAG_INDICES
		LogMessage("ABI: Reset indices to 0.");
		#endif
	}
	else	// Both teams have a count of 1 or greater.
	{
		
		if ( GlobalIndex[0] == 0 || !IsClientConnected(GlobalIndex[0]) )	// If the assassin is not a valid player, re-assign.
		{
			#if (DEBUG & DEBUGFLAG_INDICES) == DEBUGFLAG_INDICES
			LogMessage("ABI: Assassin index %d is not connected.", GlobalIndex[0]);
			#endif
			
			if ( GlobalIndex[1] != 0 && IsClientConnected(GlobalIndex[1]) )	// If the target is valid, choose the other team.
			{
				#if (DEBUG & DEBUGFLAG_INDICES) == DEBUGFLAG_INDICES
				LogMessage("ABI: Target %d is valid.", GlobalIndex[1]);
				#endif
				
				new TargetTeam = GetClientTeam(GlobalIndex[1]);
				
				switch (TargetTeam)
				{
					case TEAM_RED:
					{
						GlobalIndex[0] = RandomPlayerFromTeam(TEAM_BLUE);
						
						#if (DEBUG & DEBUGFLAG_INDICES) == DEBUGFLAG_INDICES
						LogMessage("ABI: Assassin is %N", GlobalIndex[0]);
						#endif
					}
					
					case TEAM_BLUE:
					{
						GlobalIndex[0] = RandomPlayerFromTeam(TEAM_RED);
						
						#if (DEBUG & DEBUGFLAG_INDICES) == DEBUGFLAG_INDICES
						LogMessage("ABI: Assassin is %N", GlobalIndex[0]);
						#endif
					}
				}
			}
			else	// If the target isn't valid, choose at random.
			{
				#if (DEBUG & DEBUGFLAG_INDICES) == DEBUGFLAG_INDICES
				LogMessage("ABI: Target %d is not valid.", GlobalIndex[1]);
				#endif
				
				new RandomTeam = GetRandomInt(TEAM_RED, TEAM_BLUE);
				GlobalIndex[0] = RandomPlayerFromTeam(RandomTeam);
				
				#if (DEBUG & DEBUGFLAG_INDICES) == DEBUGFLAG_INDICES
				LogMessage("ABI: Assassin is %N", GlobalIndex[0]);
				#endif
			}
		}
		
		// If the assassin is valid, leave them.
		
		if ( GlobalIndex[1] == 0 || !IsClientConnected(GlobalIndex[1]) )	// If the target is not a valid player, re-assign.
		{
			#if (DEBUG & DEBUGFLAG_INDICES) == DEBUGFLAG_INDICES
			LogMessage("ABI: Target index %d is not connected.", GlobalIndex[1]);
			#endif
			
			if ( GlobalIndex[0] != 0 && IsClientConnected(GlobalIndex[0]) )	// If the assassin is valid, choose the other team.
			{
				#if (DEBUG & DEBUGFLAG_INDICES) == DEBUGFLAG_INDICES
				LogMessage("ABI: Assassin %d is valid", GlobalIndex[0]);
				#endif
				
				new AssassinTeam = GetClientTeam(GlobalIndex[0]);
				
				switch (AssassinTeam)
				{
					case TEAM_RED:
					{
						GlobalIndex[1] = RandomPlayerFromTeam(TEAM_BLUE);
						
						#if (DEBUG & DEBUGFLAG_INDICES) == DEBUGFLAG_INDICES
						LogMessage("ABI: Target is %N", GlobalIndex[1]);
						#endif
					}
					
					case TEAM_BLUE:
					{
						GlobalIndex[1] = RandomPlayerFromTeam(TEAM_RED);
						
						#if (DEBUG & DEBUGFLAG_INDICES) == DEBUGFLAG_INDICES
						LogMessage("ABI: Target is %N", GlobalIndex[1]);
						#endif
					}
				}
			}
			else	// If the target isn't valid, choose at random.
			{
				#if (DEBUG & DEBUGFLAG_INDICES) == DEBUGFLAG_INDICES
				LogMessage("ABI: Assassin %d is not valid", GlobalIndex[0]);
				#endif
				
				new RandomTeam = GetRandomInt(TEAM_RED, TEAM_BLUE);
				GlobalIndex[0] = RandomPlayerFromTeam(RandomTeam);
				
				#if (DEBUG & DEBUGFLAG_INDICES) == DEBUGFLAG_INDICES
				LogMessage("ABI: Target is %N", GlobalIndex[1]);
				#endif
			}
		}
		
		// If the target is valid, leave them.
		
		// If the assassin and the target are on the same team, re-assign the target.
		if ( GlobalIndex[0] > 0 && GlobalIndex[1] > 0 && IsClientConnected(GlobalIndex[0]) && IsClientConnected(GlobalIndex[1]) && GetClientTeam(GlobalIndex[0]) == GetClientTeam(GlobalIndex[1]) )
		{
			switch (GetClientTeam(GlobalIndex[0]))
			{
				case TEAM_RED:
				{
					GlobalIndex[1] = RandomPlayerFromTeam(TEAM_BLUE);
				}
				
				case TEAM_BLUE:
				{
					GlobalIndex[1] = RandomPlayerFromTeam(TEAM_RED);
				}
				
				default:	// This shouldn't happen, but just in case:
				{
					GlobalIndex[0] = RandomPlayerFromTeam(TEAM_RED);
					GlobalIndex[1] = RandomPlayerFromTeam(TEAM_BLUE);
				}
			}
		}
	}
}

/*	Wins the round for the specified team.	*/
stock RoundWin(n_team = 0)
{	
	static n_WinIndex = -1;
	
	if ( n_WinIndex != -1 && IsValidEntity(n_WinIndex) ) AcceptEntityInput(n_WinIndex, "Kill");
	
	n_WinIndex = CreateEntityByName("game_round_win");
	if ( n_WinIndex == -1 ) return;	
	
	#if DEBUG == 1
	DispatchKeyValue(n_WinIndex, "targetname", "nfas_round_win");	// Give us a targetname for debugging purposes.
	#endif
	
	decl String:Team[4];
	
	switch (n_team)
	{
		case TEAM_RED:	// Red is team ID 2
		{
			Format(Team, sizeof(Team), "2");
		}
		case TEAM_BLUE:	// Blue is team ID 3
		{
			Format(Team, sizeof(Team), "3");
		}
		default:	// If the team number isn't Red or Blu, set our team to none.
		{
			Format(Team, sizeof(Team), "0");
		}
	}
	
	DispatchKeyValue(n_WinIndex, "TeamNum", Team);
	DispatchKeyValue(n_WinIndex, "force_map_reset", "0");
	
	DispatchSpawn(n_WinIndex);	// Spawn it.	
	AcceptEntityInput(n_WinIndex, "RoundWin");
	return;
}

stock Cleanup(mode = 0)
{
	/*On RoundStart:
	* 	Reset normal score counters.
	* On RoundWin:
	* 	Reset assassin and target indices to 0.
	* On MapStart:
	* 	Reset assassin and target indices to 0.
	* 	Reset normal score counters to 0.
	* 	Reset total score counters to 0.
	* On MapEnd:
	* 	Reset assassin and target indices to 0.
	* 	Reset normal score counters to 0.
	* 	Reset total score counters to 0.
	*	Reset spawn edit flag.
	*	Reset spawn edit client.
	*	Kill any menus.
	* 	Kill any timers.
	* 	Kill any HUD sync objects.
	* On PlayerSpawn:
	*	Reset indices (only called if we're not in a round or the mode is disabled).*/
	
	switch (mode)
	{
		case CLEANUP_ROUNDSTART:	// RoundStart
		{
			GlobalScore[TEAM_RED] = 0;
			GlobalScore[TEAM_BLUE] = 0;
		}
		
		case CLEANUP_ROUNDWIN:	// RoundWin:
		{
			GlobalIndex[0] = 0;
			GlobalIndex[1] = 0;
		}
		
		case CLEANUP_MAPSTART:	// MapStart
		{
			GlobalIndex[0] = 0;
			GlobalIndex[1] = 0;
			
			GlobalScore[TEAM_RED-2] = 0;
			GlobalScore[TEAM_BLUE-2] = 0;
			GlobalScore[TEAM_RED] = 0;
			GlobalScore[TEAM_BLUE] = 0;
			
			// We only want to do these bits if we're enabled.
			if ( (g_PluginState & STATE_DISABLED) != STATE_DISABLED )
			{
				if ( timer_AssassinCondition == INVALID_HANDLE )
				{
					timer_AssassinCondition = CreateTimer(0.5, TimerAssassinCondition, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
				}
				
				if ( timer_MedicHealBuff == INVALID_HANDLE )
				{
					timer_MedicHealBuff = CreateTimer(0.25, TimerMedicHealBuff, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
				}
				
				if ( hs_Assassin == INVALID_HANDLE )
				{
					hs_Assassin = CreateHudSynchronizer();
				}
				
				if ( hs_Target == INVALID_HANDLE )
				{
					hs_Target = CreateHudSynchronizer();
				}
				
				if ( hs_Score == INVALID_HANDLE )
				{
					hs_Score = CreateHudSynchronizer();
				}
				
				if ( hs_Assassin != INVALID_HANDLE && hs_Target != INVALID_HANDLE )	// If the above was successful:
				{
					UpdateHUDMessages(GlobalIndex[0], GlobalIndex[1]);	// Update the HUD
					timer_HUDMessageRefresh = CreateTimer(1.0, TimerHUDRefresh, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);	// Set up the timer to next update the HUD.
				}
				
				if ( hs_Score != INVALID_HANDLE )	// If the above was successful:
				{
					UpdateHUDScore(GlobalScore[0], GlobalScore[1], GlobalScore[2], GlobalScore[3]);	// Update the HUD
					timer_HUDScoreRefresh = CreateTimer(1.0, TimerHUDScoreRefresh, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);	// Set up the timer to next update the HUD.
				}
			}
		}
		
		case CLEANUP_MAPEND:	// MapEnd
		{
			GlobalIndex[0] = 0;
			GlobalIndex[1] = 0;
			
			GlobalScore[TEAM_RED-2] = 0;
			GlobalScore[TEAM_BLUE-2] = 0;
			GlobalScore[TEAM_RED] = 0;
			GlobalScore[TEAM_BLUE] = 0;
			
			if ( timer_AssassinCondition != INVALID_HANDLE )
			{
				KillTimer(timer_AssassinCondition);
				timer_AssassinCondition = INVALID_HANDLE;
			}
			
			if ( timer_MedicHealBuff != INVALID_HANDLE )
			{
				KillTimer(timer_MedicHealBuff);
				timer_MedicHealBuff = INVALID_HANDLE;
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
			
			if ( hs_Score != INVALID_HANDLE )
			{
				CloseHandle(hs_Score);
				hs_Score = INVALID_HANDLE;
			}
			
			if ( timer_HUDMessageRefresh != INVALID_HANDLE )
			{
				KillTimer(timer_HUDMessageRefresh);
				timer_HUDMessageRefresh = INVALID_HANDLE;
			}
			
			if ( timer_HUDScoreRefresh != INVALID_HANDLE )
			{
				KillTimer(timer_HUDScoreRefresh);
				timer_HUDScoreRefresh = INVALID_HANDLE;
			}
		}
		
		case CLEANUP_PLAYERSPAWN:	// PlayerSpawn
		{
			GlobalIndex[0] = 0;
			GlobalIndex[1] = 0;
		}
	}
	
	return;
}

/*	Checks the team scores against the max score ConVar.
	If either team is over the max, the round is won for that team.
	If both teams are over, the round is ended as a draw.*/
stock CheckScoresAgainstMax()
{
	if ( GlobalScore[TEAM_RED] >= GetConVarInt(cv_MaxScore) && GlobalScore[TEAM_BLUE] >= GetConVarInt(cv_MaxScore) )
	{
		RoundWin();
	}
	else if ( GlobalScore[TEAM_RED] >= GetConVarInt(cv_MaxScore) )
	{
		RoundWin(TEAM_RED);
	}
	else if ( GlobalScore[TEAM_RED] >= GetConVarInt(cv_MaxScore) )
	{
		RoundWin(TEAM_BLUE);
	}
}

// Timers:

/*	Timer continually called every 0.5s to re-apply the buffed condition on the assassin.
	This is to allow the assassin to stay buffed if another soldier on the team activates their buff banner,
	as this would otherwise disable the assassin buff condition when it finishes.
	Since the assassin index is always changed if something happens to the client who is the assassin,
	hopefully it's safe to use in this timer.	*/
public Action:TimerAssassinCondition(Handle:timer)
{
	if ( g_PluginState > 0 ) return Plugin_Handled;
	
	// If the assassin index is valid, reset the condition on the assassin.
	if ( GlobalIndex[0] > 0 && IsClientConnected(GlobalIndex[0]) && IsPlayerAlive(GlobalIndex[0]) )
	{
		TF2_AddCondition(GlobalIndex[0], TFCond_Buffed, 0.55);
	}
	
	return Plugin_Handled;
}

/*	Timer continually called every 0.25 seconds to re-apply the buffed condition on the assassin's heal target, if the
	assassin is a Medic.	*/
public Action:TimerMedicHealBuff(Handle:timer)
{
	// If there are any abnormal states, exit.
	if ( g_PluginState > 0 ) return Plugin_Handled;
	
	// If the assassin index is valid:
	if ( GlobalIndex[0] > 0 && IsClientConnected(GlobalIndex[0]) && IsPlayerAlive(GlobalIndex[0]) )
	{
		// If the assassin is a Medic:
		if ( TF2_GetPlayerClass(GlobalIndex[0]) == TFClass_Medic )
		{
			decl String:CurrentWeapon[32];
			CurrentWeapon[0] = '\0';
			GetClientWeapon(GlobalIndex[0], CurrentWeapon, sizeof(CurrentWeapon));
			
			// If the current weapon is a medigun and it's healing:
			if ( StrContains(CurrentWeapon, "tf_weapon_medigun", false) != -1 && GetEntProp(GetPlayerWeaponSlot(GlobalIndex[0], 1), Prop_Send, "m_bHealing") == 1 )
			{
				// Look through all the players and apply the buffed condition to the player who matches the Medic's heal target.
				for ( new i = 1; i <= MaxClients; i++ )
				{
					if ( IsClientInGame(i) && IsPlayerAlive(i) && GetEntPropEnt(GetPlayerWeaponSlot(GlobalIndex[0], 1), Prop_Send, "m_hHealingTarget") == i )
					{
						TF2_AddCondition(i, TFCond_Buffed, 0.3);
					}
				}
			}
		}
	}
	
	return Plugin_Handled;
}

/*	Timer called once a second to update the HUD messages.	*/
public Action:TimerHUDRefresh(Handle:timer)
{
	UpdateHUDMessages(GlobalIndex[0], GlobalIndex[1]);
	
	return Plugin_Continue;
}

public Action:TimerHUDScoreRefresh(Handle:timer)
{
	UpdateHUDScore(GlobalScore[0], GlobalScore[1], GlobalScore[2], GlobalScore[3]);
	
	return Plugin_Continue;
}

// HUD Message functions:

/*	Updates the HUD for all clients concerning who is the assassin/target.	*/
stock UpdateHUDMessages(assassin, target)
{
	if ( g_PluginState > STATE_DISABLED ) return;	// If we're not enabled, return.
	
	new assassin_team;
	new target_team;
	
	if ( assassin > 0 && IsClientConnected(assassin) ) assassin_team = GetClientTeam(assassin);
	if ( target > 0 && IsClientConnected(target) ) target_team = GetClientTeam(target);
	
	if ( hs_Assassin != INVALID_HANDLE )	// If our assassin synchroniser exists:
	{
		switch(assassin_team)
		{
			case TEAM_RED:
			{
				SetHudTextParams(0.05, 0.1,
									1.0,
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
									1.0,
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
									1.0,
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
									1.0,
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
									1.0,
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
									1.0,
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

stock UpdateHUDScore(red_total, blue_total, red, blue)
{
	if ( g_PluginState > STATE_DISABLED ) return;	// If we're not enabled, return.
	
	new MaxScore = GetConVarInt(cv_MaxScore);
	
	if ( hs_Score != INVALID_HANDLE )
	{
		SetHudTextParams(-1.0, 0.8,
									1.0,
									255,
									255,
									255,
									255,
									0,
									0.0,
									0.0,
									0.0);
	}
	
	if ( (g_PluginState & STATE_NOT_IN_ROUND) != STATE_NOT_IN_ROUND )
	{
		if ( hs_Score != INVALID_HANDLE )
		{
			// Display the scores to all players.

			for ( new i_target= 1; i_target <= MaxClients; i_target++ )	// Iterate through the client indices
			{
				if ( IsClientInGame(i_target) )	// If the client is connected:
				{
					ShowSyncHudText(i_target, hs_Score, "%t %d | %t %d | %t %d", "as_red", red, "as_blue", blue, "as_playingto", MaxScore);
				}
			}
		}
	}
	else	// Otherwise, hide any text.
	{
		if ( hs_Score != INVALID_HANDLE )
		{
			// Clear HUD sync for all players
			ClearSyncHUDTextAll(hs_Score);
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

// User commands are below:

/*	Displays the global indices to a client via the console.	*/
public Action:Cmd_CheckIndices(client, args)
{
	if ( GlobalIndex[0] == 0 || !IsClientConnected(GlobalIndex[0]) ) PrintToConsole(client, "Asassin index %d is invalid.", GlobalIndex[0]);
	else PrintToConsole(client, "Asassin index: %d (%N)", GlobalIndex[0], GlobalIndex[0]);
	
	if ( GlobalIndex[1] == 0 || !IsClientConnected(GlobalIndex[1]) ) PrintToConsole(client, "Target index %d is invalid.", GlobalIndex[1]);
	else PrintToConsole(client, "Target index: %d (%N)", GlobalIndex[1], GlobalIndex[1]);
	
	return Plugin_Handled;
}