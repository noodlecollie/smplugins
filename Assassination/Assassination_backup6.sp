/* --++==Assassination Game Mode, version 1.0==++--
Made by [X6] Herbius. File first created on Saturday 11th June at 8:45pm GMT,
after I learnt the evils of premature optimisation.

This plugin attempts to recreate the classic Assassination game mode from James
Bond 007: Nightfire for TF2. The setup is as follows:

-	One person on each team is designated either the "Assassin" or the "Target".
	On a new game, a Red player is chosen as the assassin and a Blu player as the
	target.
	
-	The assassin or the target are the only players who can gain their team points.
	Each team has a global point counter that is displayed in the HUD. The first team
	to reach the server-defined point limit wins the game.
	
-	To gain points, the assassin must eliminate the target, or vice-versa.
	
	* Each time	the assassin kills the target, he gains (at base) 5 points for his team.
	* Each time	the target kills the assassin, he gains (at base) 3	points for his team,
		and	subsequently becomes the new assassin. The new target is chosen from the
		players on the other team.
	* If another player kills the assassin, he becomes the new assassin	but no points
		are gained.
	* If the assassin kills	himself, a player from the other team becomes the assassin
		and a new target is	chosen at random from the late assassin's team.
	* If an enemy player kills the target, no points are gained and a new target is
		chosen.
	.
-	Depending on what weapon was used to kill the assassin or the victim, a points
	modifier is applied.
	
	* For example, if the assassin killed the target with a Pyro shotgun and the shotgun
		had a modifier of 1, 5 points would be awarded, (points x modifier) being (5 x 1).
	* If the assassin killed the target with a Level 3 sentry and the sentry had a modifier
		of 0.4, 2 points would be awarded (5 x 0.4 = 2).
	* If the assassin killed the target with a sniper rifle headshot and the modifier was
		1.3, 7	points would be awarded (5 x 1.3 = 6.5, rounded to 7).
	
	These modifiers are	in an attempt to balance weapons, as it's much easier to kill
	someone if you have	a level 3 sentry ready to massacre than if you're a Spy. It should
	allow for greater rewards for using classes such as Spy/Medic (who are difficult to use
	in heavy combat) and deter all the players from going Engineer just to allow for the
	most efficient way to kill the goal player.
	
-	Some other notable combat mechanics are: the assassin is granted mini-crits
	against enemy players; full crits have a point multiplier of 1.5 on top
	of the weapon multiplier; the target takes half damage from all players apart from
	the assassin; if the target is Ubercharged, players around him receive mini-crits.

If I've referred to the target as the "victim" anywhere in this description or in the
code itself, please forgive me. It's an idiosyncracy that's very hard for me to break. :P

--++==Map Setup==++--
Since the mod relies on a deathmatch playstyle (ie. no fixed spawn rooms to
prevent the victim/assassin from hiding), custom maps should be used. Spawn points
(info_player_teamspawn entities) should be placed around the map where players are
required to spawn. Maps should be built in duel_ format, where there is no objective
to capture, and should include a team_round_timer so that the plugin can hook in and
modify the time of each round according to the server operator's preferences.

FORSEEN BUG: I'm not 100% on whether TF2 checks for objects that are in the way of
the player spawn point before it spawns players, but I'm guessing that it wouldn't.
If a sentry is built on a player spawn point, it would be possible for the player to
spawn inside the sentry and become stuck; either I'd have to implement a !stuck
command or do something like the telefrag where a player kills anyone/thing they spawn
inside.

And now, on to the code...

I think comments are important. :3*/

#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <tf2_stocks>
#define DEBUG	1

/* FCVAR_ values for my own reference:

FCVAR_PROTECTED - Sensitive information (should not be exposed to clients or logs).
FCVAR_NOTIFY - Clients are notified of changes.
FCVAR_CHEAT - Can only be use if sv_cheats is 1.
FCVAR_REPLICATED - Setting is forced to clients.
FCVAR_PLUGIN - Custom plugin ConVar (should be used by default). */

// Plugin defines
#define PLUGIN_NAME			"Assassination (V1.0)"
#define PLUGIN_AUTHOR		"[X6] Herbius"
#define PLUGIN_DESCRIPTION	"Deathmatch; eliminate the target to gain points."
#define PLUGIN_VERSION		"0.0.0.6"
#define PLUGIN_URL			"http://change.this.url/"

#define TEAM_INVALID		-1	// Team integers
#define TEAM_UNASSIGNED		0
#define TEAM_SPECTATOR		1
#define TEAM_RED			2
#define TEAM_BLUE			3

// Variable declarations
new n_WinIndex = -1;			// Index of our game_round_win
new bool:b_InRound;				// This flag is set if a round is in progress, and cleared at the end.
new n_AssassinIndex;		// Client index of the assassin player.
new n_TargetIndex;			// Client index of the target player
new bool:b_MapRestart;			// Set if we're waiting for a map restart.
new bool:b_TeamBelowMin = true;	// This flag is set if either team has less than 2 players.
new bool:b_StateChangePending;	// This flag is set if the enable/disable convar is waiting for a map restart.
new n_ScoreCounterBlu;			// Game mode-specific score counter for the Blue team.
new n_ScoreCounterRed;			// Game mode-specific score counter for the Red team.
new n_ScoreTotalBlu;			// Blu's overall score for this map.
new n_ScoreTotalRed;			// Red's overall score for this map.
new bool:b_RoundRestarting;		// If this is set, treat as if there were not enough players.

// ConVar handle declarations
new Handle:cv_PluginEnabled = INVALID_HANDLE;	// Enables or disables the plugin. Changing this while in-game will restart the map.
new Handle:cv_PluginVersion = INVALID_HANDLE;	// Plugin version.

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
	LogMessage("--++==Assassination Mode started. Version: %s==++--", PLUGIN_VERSION);
	LoadTranslations( "assassination_phrases" );
	
	// ConVar declarations:
	cv_PluginEnabled  = CreateConVar("as_enabled",	/*In-game name*/
												"1",	/*Default value*/
												"Enables or disables the plugin. Changing this while in-game will restart the map.",	/*Description*/
												FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,	/*Flags*/
												true,	/*Has a minimum*/
												0.0,	/*Minimum value, float*/
												true,	/*Has a maximum*/
												1.0);	/*Maximum value, float*/
												
	cv_PluginVersion  = CreateConVar("as_version",	
												PLUGIN_VERSION,
												"Plugin version.",	
												FCVAR_PLUGIN | FCVAR_REPLICATED | FCVAR_NOT_CONNECTED);
	
	// Hooks:
	HookEventEx("teamplay_round_start",		Event_RoundStart,	EventHookMode_Post);	// Check minimum players is met, do startup admin.
	HookEventEx("teamplay_round_win",		Event_RoundWin,		EventHookMode_Post);	// Show endround stats, etc.
	HookEventEx("player_team",				Event_TeamsChange,	EventHookMode_Post);	// Check team numbers.
	HookEventEx("player_death",				Event_PlayerDeath,	EventHookMode_Post);	// Handle assassin/target switching logic.
	
	HookConVarChange(cv_PluginEnabled,	CvarChange);	// CvarChange handles everything.
}

/* ==================== \/ Begin Event Hooks \/ ==================== */

/*	Called when the map loads.	*/
public OnMapStart()
{
	b_MapRestart = false; 	// Reset our state changed flag in case it's still set.
	b_InRound = false;		// If our InRound flag is still set to true for any reason, clear it.
	b_StateChangePending = false;
	
	// Clear all the things that should be cleared at the start of a map.
	ModifyGlobalIndex(0, 0);	// Reset both indices to 0.
	
	n_ScoreCounterBlu = 0;
	n_ScoreCounterRed = 0;
	n_ScoreTotalBlu = 0;
	n_ScoreTotalRed = 0
}

/*	Called when the map finished	*/
public OnMapEnd()
{
	b_InRound = false;
	
	ModifyGlobalIndex(0, 0);	// Reset both indices to 0.
}
/*	Called when a new round begins.	*/
public Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	if ( !GetConVarBool(cv_PluginEnabled) || b_MapRestart ) return;	// If we're disabled or locked, exit.
	
	b_InRound = true;	// Set our global state flag.
	b_RoundRestarting = false;
	
	//Reset the variables that need it.
	ResetStartOfRoundVars();
	
	if ( GetTeamClientCount(TEAM_RED) < 2 || GetTeamClientCount(TEAM_BLUE) < 2 )	// If we're in any condition with too few players:
	{
		PrintToChatAll("[AS] %t", "as_notenoughplayers");
		return;
	}
	
	// By this point we should have performed all checks to make sure it's valid to continue.
	// From here we will start assigning the assassin and the victim.
	
	ModifyGlobalIndex(RandomPlayerFromTeam(TEAM_RED), RandomPlayerFromTeam(TEAM_BLUE));	// Set both indices to random players.
	
	if ( n_AssassinIndex <= 0)	// If it failed:
	{
		LogMessage("[AS] Get random assassin from team %d (Red) failed (assassin index = %d).", TEAM_RED, n_AssassinIndex);
		PrintToChatAll("[AS] %t", "as_newassassinfailed");
		
		return;
	}
	
	if ( n_TargetIndex <= 0)	// If it failed:
	{
		LogMessage("[AS] Get random target from team %d (Blue) failed (target index = %d).", TEAM_BLUE, n_TargetIndex);
		PrintToChatAll("[AS] %t", "as_newtargetfailed");
		
		return;
	}
}

/*	Called when a round ends.	*/
public Event_RoundWin(Handle:event, const String:name[], bool:dontBroadcast)
{
	if ( !GetConVarBool(cv_PluginEnabled) ) return;	// If we're disabled, exit.
	
	b_InRound = false;	// Clear our global state flag. Needs to be done even if we're locked.
	
	n_AssassinIndex = 0;
	n_TargetIndex = 0;
	
	if ( b_MapRestart ) return;	// Now, if we're locked, exit.
}

/*	Checks which ConVar has changed and does the relevant things.	*/
public CvarChange( Handle:convar, const String:oldValue[], const String:newValue[] )
{
	// If the enabled/disabled convar has changed, run PluginStateChanged
	if ( convar == cv_PluginEnabled ) PluginEnabledStateChanged(GetConVarBool(cv_PluginEnabled));
}

/*Called when a player changes team.*/
public Event_TeamsChange(Handle:event, const String:name[], bool:dontBroadcast)
{
	// Welcome to hell.
	
	//	Turns out that the TeamChange event is fired before the player actually joins the team they've selected,
	// even if the event hook is post, so checking the team counts via GetTeamClientCount returns the team counts as they were
	// the instant before the player joined the other team instead of how the teams look after the player has joined.
	// See CheckMinTeams for more info on how that's handled.
	
	// TL;DR: Even though this event is set as Post, it acts like a Pre. If anyone knows why this is happening, PLEASE tell me.
	// As it is, we deal with things. Please don't touch this in any way or the Jenga tower will come tumbling down.
	
	if ( !GetConVarBool(cv_PluginEnabled) ) return;	// If we're not enabled, don't do anything.
	
	// Values to pass to the team checker:
	new tc_clientid = GetEventInt(event, "userid");
	new tc_clientindex = GetClientOfUserId(tc_clientid);
	new tc_newteamid = GetEventInt(event, "team");
	new tc_oldteamid = GetEventInt(event, "oldteam");
	new bool:tcb_disconnect = GetEventBool(event, "disconnect");
	
	if ( tc_clientindex == n_AssassinIndex )
	{
		n_AssassinIndex = 0;	// If the assassin is changing team, clear the index in preparation.
		new b_assassinchanging = true;
	}
	
	else if ( tc_clientindex == n_TargetIndex )
	{
		n_TargetIndex = 0;	// If the target is changing team, clear the index in preparation.
		new b_targetchanging = true;
	}
	
	// When the team numbers change for whatever reason, we want to check to see whether either is now below 2 players.
	switch (CheckMinTeams(tc_newteamid, tc_oldteamid, tcb_disconnect))	// If this returns 2 or 3, we're interested.
	{
		case 0:	// If any teams are below 2 players, exit.
		{
			return;
		}
		
		case 2:	// Both teams have just passed above the threshold.
		{
			PrintToChatAll("[AS] %t", "as_playersriseabovethreshold");	// Let us know.
			if ( b_MapRestart )
			{
				ServerCommand("mp_restartround 3");	// Restart the round if we're not restarting the map.
				b_RoundRestarting = true;
				// Note that mp_restartround 3 doesn't work in Waiting for Players time, but b_RoundRestarting gets reset
				// anyway when the new round starts after the wait.
			}
			
			return;
		}
		
		case 3:	// One team has just dropped below the threshold.
		{
			PrintToChatAll("[AS] %t", "as_playersdropbelowthreshold");	// Let us know.
			if ( b_MapRestart )
			{
				ServerCommand("mp_restartround 3");	// Restart the round if we're not restarting the map.
				b_RoundRestarting = true;
				// Note that mp_restartround 3 doesn't work in Waiting for Players time, but b_RoundRestarting gets reset
				// anyway when the new round starts after the wait.
			}
			
			return;
		}
	}
	
	// If we're here it means the plugin is enabled and there are enough players.
	// If the assassin or target return true here, it means it's safe to select a new player at random from their team.
	
	if ( b_assassinchanging )	// If the assassin was detected further up:
	{
		n_AssassinIndex = RandomPlayerFromTeam(tc_oldteamid, tc_clientindex);	// Choose a random player from the old team, ignoring the changing player.
		
		if ( n_AssassinIndex <= 0)	// If it failed:
		{
			LogMessage("[AS] Get random assassin on disconnect from team %d failed (assassin index = %d).", tc_oldteamid, n_AssassinIndex);
			PrintToChatAll("[AS] %t", "as_newassassinfailed");
			
			return;
		}
	}
	
	else if ( b_targetchanging )	// If the target was detected further up:
	{
		n_TargetIndex = RandomPlayerFromTeam(tc_oldteamid, tc_clientindex);	// Choose a random player from the old team, ignoring the changing player.
		
		if ( n_TargetIndex <= 0)	// If it failed:
		{
			LogMessage("[AS] Get random target on disconnect from team %d failed (target index = %d).", tc_oldteamid, n_TargetIndex);
			PrintToChatAll("[AS] %t", "as_newtargetfailed");
			
			return;
		}
	}
}

/*Called when a client disconnects.*/
public OnClientDisconnect(client)
{
	if ( n_AssassinIndex == client )	// If the client was the assassin:
	{
		n_AssassinIndex = 0;	// Clear the index.
		n_AssassinIndex = RandomPlayerFromTeam(GetClientTeam(client), client)	// Get a new client from the team, ignoring the client who's leaving.
		
		if ( n_AssassinIndex <= 0)	// If it failed:
		{
			LogMessage("[AS] Get random assassin on disconnect from team %d failed (assassin index = %d).", GetClientTeam(client), n_AssassinIndex);
			PrintToChatAll("[AS] %t", "as_newassassinfailed");
			
			return;
		}
	}
	else if ( n_TargetIndex == client )	// If the client was the target:
	{
		n_TargetIndex = 0;	// Clear the index.
		n_TargetIndex = RandomPlayerFromTeam(GetClientTeam(client), client)	// Get a new client from the team, ignoring the client who's leaving.
		
		if ( n_TargetIndex <= 0)	// If it failed:
		{
			LogMessage("[AS] Get random target on disconnect from team %d failed (target index = %d).", GetClientTeam(client), n_TargetIndex);
			PrintToChatAll("[AS] %t", "as_newtargetfailed");
			
			return;
		}
	}
}

/*	Called when a player dies.
	This is where we look at who died and swap around the assassin/target appropriately.	*/
public Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	// If there are too few players, exit. This will save us from going through all the unnecessary stuff below.
	if ( !GetConVarBool(cv_PluginEnabled) || GetTeamClientCount(TEAM_RED) < 2 || GetTeamClientCount(TEAM_BLUE) < 2 ) return;	// If we're not enabled, don't do anything.
	
	new pd_ClientID = GetEventInt(event, "userid");
	new pd_ClientIndex = GetClientOfUserId(pd_ClientID);		// Index of the player who died.
	new pd_AttackerID = GetEventInt(event, "attacker");
	new pd_AttackerIndex = GetClientOfUserId(pd_AttackerID);	// Index of the player who killed them.
	new pd_WeaponID = GetEventInt(event, "weaponid");			// ID of weapon used (for modifying points later).
	
	// Firstly, let's deal with if the assassin has died.
	if ( pd_ClientIndex = n_AssassinIndex )
	{
		// If the killer was a PLAYER from the opposite team:
		if ( IsClientConnected(pd_AttackerIndex) && GetClientTeam(pd_ClientIndex) != GetClientTeam(pd_AttackerIndex) )
		{
			// Clear the indices.
			n_AssassinIndex = 0;
			n_TargetIndex = 0;
			
			// Make the killer player the assassin.
			n_AssassinIndex = pd_AttackerIndex;
			
			// Assign the target to a random player on the late assassin's team.
			// Note that the late assassin is not excluded, so he could become the target.
			n_TargetIndex = RandomPlayerFromTeam(GetClientTeam(pd_ClientIndex))
			
			if ( n_TargetIndex <= 0)	// If it failed:
			{
				LogMessage("[AS] Get random target on death from team %d failed (target index = %d).", GetClientTeam(pd_ClientIndex), n_TargetIndex);
				PrintToChatAll("[AS] %t", "as_newtargetfailed");
				
				return;
			}
		}
		// If the killer wasn't a player, or was a player from the same team, or it was suicide:
		else if ( !IsClientConnected(pd_AttackerIndex) || pd_AttackerIndex > MaxClients || pd_AttackerIndex < 1 || GetClientTeam(pd_ClientIndex) == GetClientTeam(pd_AttackerIndex) || pd_ClientIndex = pd_AttackerIndex )
		{
			// Clear both indices.
			n_AssassinIndex = 0;
			n_TargetIndex = 0;
			
			// Assign the assassin to be someone from the opposite team to the late assassin.
			switch (GetClientTeam(pd_ClientIndex))
			{
				case TEAM_RED:
				{
					n_AssassinIndex = RandomPlayerFromTeam(TEAM_BLUE);
					
					if ( n_AssassinIndex <= 0)	// If it failed:
					{
						LogMessage("[AS] Get random assassin on death from team %d failed (assassin index = %d).", TEAM_BLUE, n_AssassinIndex);
						PrintToChatAll("[AS] %t", "as_newassassinfailed");
						
						return;
					}
				}
				
				case TEAM_BLUE:
				{
					n_AssassinIndex = RandomPlayerFromTeam(TEAM_RED);
					
					if ( n_AssassinIndex <= 0)	// If it failed:
					{
						LogMessage("[AS] Get random assassin on death from team %d failed (assassin index = %d).", TEAM_RED, n_AssassinIndex);
						PrintToChatAll("[AS] %t", "as_newassassinfailed");
						
						return;
					}
				}
			}
			
			// Assign the target to be someone from the late assassin's team.
			n_TargetIndex = RandomPlayerFromTeam(GetClientTeam(pd_ClientIndex));
			
			if ( n_TargetIndex <= 0)	// If it failed:
			{
				LogMessage("[AS] Get random target on death from team %d failed (target index = %d).", GetClientTeam(pd_ClientIndex), n_TargetIndex);
				PrintToChatAll("[AS] %t", "as_newtargetfailed");
				
				return;
			}
		}
	}
	
	// Now, if the target has died.
	if ( pd_ClientIndex = n_TargetIndex )
	{
		// If the killer wasn't a player OR if it was suicide:
		if ( !IsClientConnected(pd_AttackerIndex) || pd_AttackerIndex > MaxClients || pd_AttackerIndex < 1 || pd_ClientIndex = pd_AttackerIndex )
		{
			// Clear the target index.
			n_TargetIndex = 0;
			
			// Choose another random player from the same team, excluding the late target.
			n_TargetIndex = RandomPlayerFromTeam(GetClientTeam(pd_ClientIndex), pd_ClientIndex);
			
			if ( n_TargetIndex <= 0)	// If it failed:
			{
				LogMessage("[AS] Get random target on death from team %d failed (target index = %d).", GetClientTeam(pd_ClientIndex), n_TargetIndex);
				PrintToChatAll("[AS] %t", "as_newtargetfailed");
				
				return;
			}
		}
		// If the killer was an enemy player:
		else if ( IsClientConnected(pd_AttackerIndex) && GetClientTeam(pd_ClientIndex) != GetClientTeam(pd_AttackerIndex) )
		{
			// Clear the target index.
			n_TargetIndex = 0;
			
			// Choose a new target from the same team.
			n_TargetIndex = RandomPlayerFromTeam(GetClientTeam(pd_ClientIndex));
			
			if ( n_TargetIndex <= 0)	// If it failed:
			{
				LogMessage("[AS] Get random target on death from team %d failed (target index = %d).", GetClientTeam(pd_ClientIndex), n_TargetIndex);
				PrintToChatAll("[AS] %t", "as_newtargetfailed");
				
				return;
			}
		}
	}
}

/* ==================== /\ End Event Hooks /\ ==================== */

/* ==================== \/ Begin Custom Functions \/ ==================== */

/*	DEPRECATED! Use ServerCommand(mp_restartround x) instead.
	Note that the above will leave the gates open, but this -shouldn't- affect us.
	Restarts the round through the use of game_round_win entities. 0 = none, 2 = red, 3 = blu.
	Passing true as the second parameter forces a map reset.
	Returns 1 on success or an error code on failure:
	0	=	game_round_win was unable to be created.	*/
stock RestartRound(n_team = 0, b_resetmap = 0)	// Defaults: team = none, reset map = no
{
	if ( n_WinIndex == -1 )	// If we haven't already created our own game_round_win:
	{
		// Create us one; if it failed, return 0.
		if ( n_WinIndex = CreateEntityByName("game_round_win") == -1 ) return 0;	
		
		DispatchSpawn(n_WinIndex);	// Spawn it.

		#if DEBUG == 1
		AcceptEntityInput(n_WinIndex, "AddOutput targetname as_round_win");	// Give us a targetname for debugging purposes.
		#endif
	}

	// By this point we know we have our game_round_win and it's at index n_WinIndex.
	// The next thing we want to do is to set the team value to what's given to us.

	// AcceptEntityInput(n_WinIndex, "SetTeam %d", n_team);
	// I'm not sure we can use this, since n_team may be mistaken for a parameter, so I'm going to use a switch
	// which will also allow us to handle input values that would be invalid.
	
	switch (n_team)
	{
		case TEAM_RED:	// Red is team ID 2
		{
			AcceptEntityInput(n_WinIndex, "SetTeam 2");
		}
		case TEAM_BLUE:	// Blue is team ID 3
		{
			AcceptEntityInput(n_WinIndex, "SetTeam 3");
		}
		default:	// If the team number isn't Red or Blu, set our team to none.
		{
			AcceptEntityInput(n_WinIndex, "SetTeam 0");
		}
	}

	if ( b_resetmap )	// If we want to reset the map:
	{
		AcceptEntityInput(n_WinIndex, "AddOutput force_map_reset 1");	// Make sure the keyvalue is 1 (yes)
	}
	else	// Otherwise:
	{
		AcceptEntityInput(n_WinIndex, "AddOutput force_map_reset 0");	// Make sure the keyvalue is 0 (no)
	}

	// Now we want to tell the game_round_win to restart the game
	AcceptEntityInput(n_WinIndex, "RoundWin");
	LogMessage("[AS] RestartRound(%d, %d) executed. Round restarting...", n_team, b_resetmap);

	return 1;
}

/*	Chooses a random player from the specified team.
	If a second parameter is specified, exclude the player with this index.
	Returns the client index of the player, or 0 if not found. */
stock RandomPlayerFromTeam(team, exclude = 0)
{
	// The first thing we need to do is iterate through all indices between 1 and MAX_CLIENTS inclusive.
	// Each time we come across a player, put their client index in an array. At the end, note down the
	// number of players we found.
	// Choose a random client index from the ones we collected and return that value.
	// If the total number of players we found was 0, or the team was invalid, return 0.
	
	if ( team < 0 ) return 0;	// Make sure our team input value is valid.
	
	new playersfound[MaxClients];
	new n_playersfound = 0;
	
	for (new i = 1; i <= MaxClients; i++)
	{
		
		if ( IsClientConnected(i) && i != exclude )	// If the client we've chosen is in the game and not excluded:
		{
			if ( GetClientTeam(i) == team /*&& !IsFakeClient(i)*/ )	// If they're on the right team:
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
	
	// Return a random index from the array, less than or equal to the number of players we found. -1 to allow for the 0 array index.
	new n = GetRandomInt(0, n_playersfound-1);
	#if DEBUG == 1
	decl String:clientname[MAX_NAME_LENGTH];
	clientname[0] = '\0';
	GetClientName(playersfound[n], clientname, sizeof(clientname));
	LogMessage("RPFT: Players found: %d Index chosen: %d in array, %d (%s)", n_playersfound, n, playersfound[n], clientname);
	#endif
	return playersfound[n];
}


/*	Sets the enabled/disabled state of the plugin and restarts the map.
	Passing 1 enables, 0 disables.	*/
stock PluginEnabledStateChanged(bool:b_state)
{	
	// If we're already locked (if the ConVar has been spam-changed), ignore.
	if ( b_StateChangePending ) return;
	
	b_MapRestart = true;	// Lock the rest of the plugin until we've reloaded.
	b_StateChangePending = true;
	
	PrintToChatAll("[AS] %t", "as_pluginstatechanged");
	
	// Get the current map name
	decl String:mapname[64];
	GetCurrentMap(mapname, sizeof(mapname));
	
	LogMessage("[AS] Plugin state changed. Restarting map (%s)...", mapname);
	
	// Restart the map
	ServerCommand( "changelevel %s", mapname);
	
	// Restart the map DON'T KNOW IF THIS WORKS
	//ServerCommand( "mp_restartgame 3" )
}

/*	Checks the team numbers to ensure that the minimum number of players is met on both teams.
	Parameters are the client's new team, old team and whether they disconnected, collected from the player_team event..
	Returns a number depending on a combination of factors.
	Consider the following table:
	
	T = b_TeamBelowMin, R = Red team, B = Blue team.
	T(1): One or both teams were below the min. T(0): Both teams were above the min.
	R/B(1): Team count >= min (above threshold). R/B(0): Team count < min (below threshold).
	up: A team was below the threshold but both are now above. Returns 2.
	down: Both teams were above the threshold but one is now below. Returns 3.
	high: Both teams were, and still are, above the threshold. Returns 1.
	low: One or both teams were, and still are, below the threshold. Returns 0.
	
	T R B Rslt | Rtrn
	-----------------
	0 0 0 down |  3
	0 0 1 down |  3
	0 1 0 down |  3
	0 1 1 high |  1
	1 0 0 low  |  0
	1 0 1 low  |  0
	1 1 0 low  |  0
	1 1 1 up   |  2
*/
stock CheckMinTeams(n_newteam, n_oldteam, bool:b_disconnect)
{	
	new n_redteamcount = GetTeamClientCount(TEAM_RED);		// Red team count BEFORE the team change.
	new n_blueteamcount = GetTeamClientCount(TEAM_BLUE);	// Blue team count BEFORE the team change.
	
	// HACKAROUND HERE: Turns out that the TeamChange event is fired before the player actually joins the team they've selected,
	// even if the event hook is post, so checking the team counts via GetTeamClientCount returns the team counts as they were
	// the instant before the player joined the other team instead of how the teams look after the player has joined.
	// To counteract this we'll need to do a bit of prediction and look at the player's current team and their target team
	// (or whether they're disconnecting).
	
	if ( b_disconnect )	// Firstly, check if the client has disconnected.
	{
		// If disconnected, this means the team he was on will lose a player and the other teams will stay the same.
		switch (n_oldteam)	// Find out which team the client left.
		{
			case TEAM_RED:
			{
				n_redteamcount--;	// Decrement our counter for the team.
			}
			
			case TEAM_BLUE:
			{
				n_blueteamcount--;	// Decrement our counter for the team.
			}
			
			// If the old team was spectator, we're not counting spec players so don't do anything.
		}
	}
	else	// If the client hasn't disconnected, this means they're changing teams.
	{
		// The client's old team will lose a player and their new team will gain a player.
		switch (n_oldteam)
		{
			case TEAM_RED:
			{
				n_redteamcount--;	// Decrement the old team's counter.
			}
			
			case TEAM_BLUE:
			{
				n_blueteamcount--;	// Decrement the old team's counter.
			}
			
			// If the old team was spectator, we're not counting spec players so don't do anything.
		}
		
		switch (n_newteam)
		{
			case TEAM_RED:
			{
				n_redteamcount++;	// Increment the new team's counter.
			}
			
			case TEAM_BLUE:
			{
				n_blueteamcount++;	// Increment the new team's counter.
			}
			
			// If the new team was spectator, we're not counting spec players so don't do anything.
		}
	}
	
	// By this point, the correct team values for AFTER the client's switch has occurred (what we want) will be held in
	// n_redteamcounter and n_blueteamcounter. We can check these values against our thresholds.
	
	if ( b_TeamBelowMin )	// If a team was below the threshold:
	{
		if ( n_redteamcount >= 2 && n_blueteamcount >= 2 )	// But now both are above:
		{
			b_TeamBelowMin = false;	// Let us know both teams are in the clear.
			return 2;
		}
		else	// One or both teams are still under.
		{
			return 0;
		}
	}
	else	// If no team was below the threshold:
	{
		if ( n_redteamcount < 2 || n_blueteamcount < 2 )	// But one now is:
		{
			b_TeamBelowMin = true;	// Let us know not all teams are in the clear.
			return 3;
		}
		else	// Both teams are still over.
		{
			return 1;
		}
	}
}

/*	Resets the relevant variables and values.
	These include:
	- Team score counters
	- Assassin and target indices	*/
stock ResetStartOfRoundVars()
{
	// Reset score counters
	n_ScoreCounterBlu = 0;
	n_ScoreCounterRed = 0;
	
	// Reset our assassin and target indices
	n_AssassinIndex = 0;
	n_TargetIndex = 0;
}

/*	Changes the assassin/target indices and updates the relevant dependant systems.
	First argument is the value to assign to n_AssassinIndex.
	Second argument is the value to assign to n_TargetIndex.
	If either of the values are less than 0 or omitted, the index is left the same.
	
	ANY changes to n_AssassinIndex or n_TargetIndex should be performed through this function.*/
stock ModifyGlobalIndex(assassinvalue = -1, targetvalue = -1)
{
	if ( assassinvalue >= 0 )	// As long as the assassin parameter is 0 or more, set the variable.
	{
		n_AssassinIndex = assassinvalue;
	}
	
	if ( targetvalue >= 0 )	// As long as the target parameter is 0 or more, set the variable.
	{
		n_TargetIndex = assassinvalue;
	}
	
	// Update any systems that should update when an index changes.
	// UpdateDependantSystems();
}

/* ==================== /\ End Custom Functions /\ ==================== */