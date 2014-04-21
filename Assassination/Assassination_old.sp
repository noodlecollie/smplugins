/* --++==Assassination Game Mode, version 1.0==++--
Made by [X6] Herbius. File first created on Thursday 9th June at 8:45pm GMT.
I should be revising Further Pure Mathematics at this point, but what the hell.

This plugin attempts to recreate the classic Assassination game mode from James
Bond 007: Nightfire for TF2. The setup is as follows:

-	One person on each team is designated either the "Assassin" or the "Target".
	On a new game, a Red player is chosen as the assassin and a Blu player as the
	target.
-	The assassin or the target are the only players who can gain their team points.
	Each team has a global point counter that is displayed in the HUD. The first team
	to reach the server-defined point limit wins the game.
-	To gain points, the assassin must eliminate the target, or vice-versa. Each time
	the assassin kills the target, he gains (at base) 5 points for his team and a new
	target is chosen. Each time	the victim kills the assassin, he gains (at base) 3
	points for his team, and	subsequently becomes the new assassin. The new target is
	chosen from the players on the other team. If another player kills the assassin,
	he becomes the new assassin but no points are gained. If the assassin kills
	himself, a player from the other team becomes the assassin and a new target is
	chosen at random. If another player kills the victim, a new victim is chosen and
	no points are gained.
-	Depending on what weapon was used to kill the assassin or the victim, a points
	modifier is applied. For example, if the assassin killed the target with a Pyro
	shotgun and the shotgun had a	modifier of 1, 5 points would be awarded, (points x
	modifier) being (5 x 1).	If the assassin killed the target with a Level 3 sentry
	and the sentry had a modifier of 0.4, 2 points would be awarded (5 x 0.4 = 2). If
	the assassin	killed the target with a sniper rifle headshot and the modifier was
	1.3, 7	points would be awarded (5 x 1.3 = 6.5, rounded to 7). These modifiers are
	in an attempt to balance weapons, as it's much easier to kill someone if you have
	a level 3 sentry ready to massacre than if you're a Spy. It should allow for
	greater rewards for using classes such as Spy/Medic (who are difficult to use in
	heavy combat) and deter all the players from going Engineer just to allow for the
	most efficient way to kill the goal player.
-	Some other notable combat mechanics are: the assassin is granted mini-crits
	against enemy players; full crits have a point multiplier of 1.5 on top
	of the weapon multiplier; the target takes half damage from all players apart from
	the assassin.

If I've referred to the target as the "victim" anywhere in this description or in the
code itself, please forgive me. It's a very strong habit of mine. :P

--++==Map Setup==++--
Since the mod relies on a deathmatch playstyle (ie. no fixed spawn rooms to
prevent the victim/assassin from hiding), custom maps should be used. Spawn points
(info_player_teamspawn entities) should be placed around the map where players are
required to spawn. Maps should be built in duel_ format, where there is no objective
to capture, and should include a team_round_timer so that the plugin can hook in and
modify the time of each round according to the server operator's preferences. Note
that, due to round restarts having to be executed through a game_round_win entity,
setting a round limit on the server is not recommended since the round restarts when
the player count goes above or below the threshold value may count towards the total
rounds played on a map.

FORSEEN BUG: I'm not 100% on whether TF2 checks for objects that are in the way of
the player spawn point before it spawns players, but I'm guessing that it wouldn't.
If a sentry is built on a player spawn point, it would be possible for the player to
spawn inside the sentry and become stuck; either I'd have to implement a !stuck
command or do something like the telefrag where a player kills anyone/thing they spawn
inside.

And now, on to the code...

I think comments are important. :3*/

#include <sourcemod>
#include <sdktools>
#define DEBUG 0

// FCVAR_ values for my own reference:

// FCVAR_PROTECTED - Sensitive information (should not be exposed to clients or logs).
// FCVAR_NOTIFY - Clients are notified of changes.
// FCVAR_CHEAT - Can only be use if sv_cheats is 1.
// FCVAR_REPLICATED - Setting is forced to clients.
// FCVAR_PLUGIN - Custom plugin ConVar (should be used by default).

// Plugin defines
#define PLUGIN_NAME			"Assassination (V1.0)"
#define PLUGIN_AUTHOR		"[X6] Herbius"
#define PLUGIN_DESCRIPTION	"Deathmatch; eliminate the target to gain points."
#define PLUGIN_VERSION		"1.0.0.0"
#define PLUGIN_URL			"http://change.this.url/"

#define RED_TEAM			"2"	// Team integers
#define BLUE_TEAM			"3"

new Handle:cvPluginVersion = INVALID_HANDLE;	// ConVar: [as_version]					Plugin version.
new Handle:cvBPKillAssassin = INVALID_HANDLE;	// ConVar: [as_points_kill_assassin]	The base amount of points awarded for KILLING the assassin.
new Handle:cvBPKillTarget = INVALID_HANDLE	;	// ConVar: [as_points_kill_target]		The base amount of points awarded for KILLING the target.
new Handle:cvPluginEnabled = INVALID_HANDLE;	// ConVar: [as_enabled]					Enables or disables the plugin. Changing this will restart the map.
new Handle:cvScoreLimit = INVALID_HANDLE;		// ConVar: [as_score_limit]				When a team reaches this score they win the game.

new Bool:b_PluginEnabled = true;	// If the plugin is enabled, this flag is true. It's mainly to save us from calling
									// GetConVarInt every single time.
#ifdef 0
new Bool:b_FewPlayers = true;		// If the number of players on the server is less than 4, this flag should be true.
											// This is checked at the same time as b_PluginEnabled but is different, since we're
											// only lying dormant and not completely disabled.
#endif
new n_WinIndex = -1;				// Global variable storing the entity index of the custom-created game_round_win.
new n_RedCounter = 0;				// Red score counter.
new n_BlueCounter = 0;				// Blue score counter.
new n_AssassinIndex = 0;			// Client index of the assassin.
new n_TargetIndex = 0;				// Client index of the target.
new Bool:b_InRound = false;			// Is true if a new round has started, false if it hasn't or the round has been won.

 
public Plugin:myinfo =
{
	// This section should take care of itself nicely now.
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = PLUGIN_URL
};
 
public OnPluginStart()
{
	LogMessage("--++==Assassination Mode started. Version: %s==++--", PLUGIN_VERSION);

	// Load translation files here.
	LoadTranslations( assassination_phrases );
	
	//ConVars:
	cvBPKillAssassin = CreateConVar("as_points_kill_assassin",									/*ConVar in-game name (always as_ prefix)*/
												"5",											/*Default 5*/
												"Base amount of points awarded for killing the assassin. Actual value is determined by weapons; see documentation.",	/*Description*/
												FCVAR_PLUGIN | FCVAR_NOTIFY,					/*Flags*/
												true,											/*Has minimum*/
												1.0);											/*Minimum 1 base point*/
	
	cvBPKillTarget = 	CreateConVar("as_points_kill_target",	
												"3",
												"Base amount of points awarded for killing the target. Actual value is determined by weapons; see documentation.",	
												FCVAR_PLUGIN | FCVAR_NOTIFY,
												true,
												1.0);

	cvPluginVersion  = CreateConVar("as_version",	
												PLUGIN_VERSION,
												"Plugin version.",	
												FCVAR_PLUGIN | FCVAR_REPLICATED);

	cvPluginEnabled  = CreateConVar("as_enabled",	
												"1",
												"Enables or disables the plugin. Changing this will restart the map.",	
												FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
												true,
												0.0,
												true,
												1.0);
	
	cvScoreLimit  = CreateConVar("as_score_limit",	
												"50",
												"When a team reaches this score they win the game.",	
												FCVAR_PLUGIN | FCVAR_NOTIFY,
												true,
												1.0);

	/* Hooks that we need:
	* Player spawn - fire the "destroy what I'm standing in" function.
	* Player death - obviously needed for finding out whether the assassin or target has died and for awarding points
	* Game frame - needed for displaying the assassin/target sprite.
	* When any base damage convars are changed - update the relevant variables in code.
	* Player connect - if we were under the minimum player amount but are now not, respawn everyone.
	* Player hurt - modify the amount of damage the target takes from enemy players.
	* Round start - check that there are enough players, do setup admin.
	* Round win - overlay endround stats, reset variables, etc.*/

	HookEventEx("player_spawn",				event_player_spawn,	EventHookMode_Post);		// Post since we need the new spawn co-ords
	HookEventEx("player_death",				event_player_death,	EventHookMode_Post);		// Post because we're adding to, not overriding
	HookEventEx("player_hurt", 				event_hurt,			EventHookMode_Pre);			// Pre because we need to jump in and change target received damage
	HookEventEx("teamplay_round_start",		event_round_start,	EventHookMode_PostNoCopy);	// Post because we're not overriding anything, NoCopy because we don't need anything from the event
	HookEventEx("teamplay_round_win",		event_round_win,	EventHookMode_Post);		// Post because we're not overriding anything
	
	HookConVarChange(cvBPKillAssassin,	CvarChange);	// CvarChange will check which ConVar has changed and do stuff accordingly.
	HookConVarChange(cvBPKillTarget,	CvarChange);
	HookConVarChange(cvPluginEnabled,	CvarChange);
	// OnClientConnected, OnGameFrame are managed without a hook.
}

#ifdef 0
// At the start of the round, set everything up.
public event_round_start(Handle:event, const String:name[], bool:dontBroadcast)
{
	// Set our InRound flag to true.
	b_InRound = true;
	
	// Check if we're enabled or not.
	// if ( !b_PluginEnabled ) return Plugin_Continue;
	
	// Firstly we need to reset the team counters.
	// ManualResetScoreCounters();

	// Next, choose two players at random from both teams.
	if ( !n_AssassinIndex = RandomPlayerFromTeam(RED_TEAM) ) LogMessage("Random player unable to be chosen as assassin from Red team.");
	else LogMessage("New assassin is at client index %d", n_AssassinIndex);

	if ( !n_TargetIndex = RandomPlayerFromTeam(BLUE_TEAM) ) LogMessage( "Random player unable to be chosen as target from Blue team.");
	else LogMessage("New target is at client index %d", n_TargetIndex);
	
	// Now that the assassin and target are chosen, update all our systems that depend on them.
	// ManualUpdateScoreDisplay();
	// ManualUpdateAssassinDisplay();
	// ManualUpdateTargetDisplay();
	// ManualUpdateAssassinIcon();
	// ManualUpdateTargetIcon();
	// ManualUpdateAssassinSprite();
	// ManualUpdateTargetSprite();
}
#endif

// ----------
// Checks which ConVar has changed and does the relevant things.
// ----------
public CvarChange( Handle:convar, const String:oldValue[], const String:newValue[] )
{
	// If the enabled/disabled convar has changed, run PluginStateChanged
	if ( convar == cvPluginEnabled ) PluginEnabledStateChanged(GetConVarBool(cvPluginEnabled))
}

#ifdef 0
// Called when a client connects to the server. Paired with the below.
public OnClientConnected(client)
{
	// Todo
}
#endif

#ifdef 0
// Called when a client disconnects. Paired with the above.
public OnClientDisconnect(client)
{
	// Todo
}
#endif

// ----------
// Restarts the round through the use of game_round_win entities. 0 = neutral, 2 = red, 3 = blu.
// Passing true as the second parameter forces a map reset.
// Returns 1 on success or an error code on failure:
// 0	=	game_round_win was unable to be created.
// ----------
stock RestartRound(n_team = 0, b_resetmap = 0)	// Defaults: team = none, reset map = no
{
	// Here we want to ignore any game_round_win entities there are already and create one of our own.
	// This will then have its index assigned to a global variable and can be activated when needed,
	// and the team values can be changed via inputs (thanks Valve, thought I was going to have to use
	// AddOutput there ;) ).

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
		case 2:	// Red is team ID 2
		{
			AcceptEntityInput(n_WinIndex, "SetTeam 2");
		}
		case 3:	// Blu is team ID 3
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
	LogMessage("RestartRound(%d, %d) executed. Round restarting...", n_team, b_resetmap);

	return 1;	// We're done!
}

#ifdef 0
// ----------
// Resets the core features of the plugin in the following order:
// - Kills the assassin sprite
// - Kills the target sprite
// - Clears the assassin index (-1)
// - Clears the victim index (-1)
// - Resets the team score counters to 0
// ----------
stock ASResetCore()
{
	// Todo
}
#endif

#ifdef 0
// ----------
// Makes the player at the given client index the new assassin.
// ----------
stock MakeAssassin(client)
{
	// Todo
}
#endif

#ifdef 0
// ----------
// Makes the player at the given client index the new target.
// ----------
stock MakeTarget(client)
{
	// Todo
}
#endif

// ----------
// Sets the enabled/disabled state of the plugin and restarts the map.
// Passing 1 enables, 0 disables.
// Returns 0 if we're already in the state that's been passed.
// ----------
stock PluginEnabledStateChanged(Bool:b_state)
{
	// If the passed argument is the same as our current state, return 0.
	if ( b_state == b_PluginEnabled ) return 0;
	
	// Otherwise, change b_PluginEnabled to reflect the ConVar value.
	b_PluginEnabled = b_state;
	
	// Get the current map name
	decl String:mapname[64];
	GetCurrentMap(mapname, sizeof(mapname));
	
	// Restart the map
	ServerCommand( "changelevel %s", mapname)
}

// ----------
// Chooses a random player from the specified team.
// Returns the client index of the player, or 0 if not found.
// ----------
stock RandomPlayerFromTeam(team)
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
		
		if ( GetClientTeam(i) == team && IsClientInGame(i) )	// If the client we've chosen is on the right team and in the game:
		{
			playersfound[n_playersfound] = i;	// Put our client index (i) into the array.
			n_playersfound++;					// Increment our "players found" count and loop back.
		}
	}
	
	if ( n_playersfound < 1 ) return 0;	// If we didn't find any players, return 0.
	
	// By this point we will have the number of players found stored in n_playersfound, and their indices in playersfound[].
	// The max index will be found at (n_playersfound - 1).
	// The minimum number of players found will be 1.
	
	return playersfound[GetRandomInt(1, n_playersfound)-1];	// Return a random index from the array, less than or equal to the
															// number of players we found. -1 to allow for the 0 array index.
}

/*
--++==Post Notes==++--
I'm sticking stuff here that I think of as I go along but which isn't relevant to the code section
I'm currently writing.

- When the assassin/target changes, instead of killing the env_sprite make it teleport to the player
	it's needed for? Would it be better to do this or just kill/respawn the sprite? If the former, the
	sprites would obviously need to be killed off at the end of the round, in which case we'd need to
	hook into End Round as well.
*/

