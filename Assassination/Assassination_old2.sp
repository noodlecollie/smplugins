/* --++==Assassination Game Mode, version 1.0==++--
Made by [X6] Herbius. File recreated on Saturday 11th June at 8:45pm GMT,
after I learnt the evils of premature optimisation.

I'd like to credit the following people, whose souce code has aided my little newbie programming hands
in coding some functions that would otherwise have given me terrible amounts of grief:

*	toazron1, whose donator recognition plugin demonstrated to me how to parent and move oriented sprites
		with the player. https://forums.alliedmods.net/showthread.php?t=122320
*	Dr. Eggman, whose Saxton Hale game mode helped me in killing Engineer sentries on player death and
		modifying player health. https://forums.alliedmods.net/showthread.php?t=146884

In relation to anyone using my code from this plugin: go for it, no need to give credit. It's only
instructions, after all.

----------

This plugin attempts to recreate the classic Assassination game mode from James
Bond 007: Nightfire for TF2. The setup is as follows:

-	One person on each team is designated either the "Assassin" or the "Target".
	On a new game, a Red player is chosen as the assassin and a Blu player as the
	target.
	
-	Each team has a global point counter that is displayed in the HUD. The first team
	to reach the server-defined point limit wins the game.
	
-	Points are gained when the a player from the same team as the assassin kills a player
	from the same team as the target, or when the assassin player kills the target player,
	or vice-versa.
	
	* Each time	the assassin kills the target, he gains (at base) 10 points for his team.
	* Each time	the target kills the assassin, he gains (at base) 7	points for his team,
		and	subsequently becomes the new assassin. The new target is chosen from the
		players on the other team.
	* If another player kills the assassin, he becomes the new assassin	but no points
		are gained.
	* If the assassin kills	himself, a player from the other team becomes the assassin
		and a new target is	chosen at random from the late assassin's team.
	* If an enemy player kills the target, points can be deducted and a new target is
		chosen.
	* If an ordinary player on the assassin's team kills an ordinary player on the target's
		team, one point is awarded.
	.
-	Depending on what weapon was used to kill the assassin or the target, a points
	modifier is applied.
	
	* For example, if the assassin killed the target with a Pyro shotgun and the shotgun
		had a modifier of 1, 10 points would be awarded, (points x modifier) being (10 x 1).
	* If the assassin killed the target with a Level 3 sentry and the sentry had a modifier
		of 0.4, 4 points would be awarded (10 x 0.4 = 4).
	* If the assassin killed the target with a sniper rifle and the modifier was
		1.35, 14 points would be awarded (10 x 1.35 = 13.5, rounded to 14).
	
	These modifiers are	in an attempt to balance weapons, as it's much easier to kill
	someone if you have	a level 3 sentry ready to massacre than if you're a Spy. It should
	allow for greater rewards for using classes such as Spy/Medic (who are difficult to use
	in heavy combat) and deter all the players from going Engineer just to allow for the
	most efficient way to kill the goal player.
	
-	Some other notable combat mechanics are: the assassin is granted mini-crits
	against enemy players, and the target takes half damage from all players apart from
	the assassin.

If I've referred to the target as the "victim" anywhere in this description or in the
code itself, please forgive me. It's an idiosyncracy that's very hard for me to break. :P

--++==Map Setup==++--
Since the mod relies on a deathmatch playstyle (ie. no fixed spawn rooms to
prevent the victim/assassin from hiding), custom maps should be used. Spawn points
(info_player_teamspawn entities) should be placed around the map where players are
required to spawn. Maps should have no objective to capture, and should include a
team_round_timer.

And now, on to the code...

I think comments are important. :3*/

// NOTE: If there's anything that still needs doing that I've forgotten about, it's flagged with a TODO comment.

/*	Notable bug: In build 0.0.0.22, when I first introduced the assassin/target sprites, a strange and hilarious bug sprang up
	where (seemingly random) players would constantly bounce off the ground if they jumped at all during the game. I think this
	had something to do with the sprite movement where it was moving the player insead, but I'm not entirely sure. I've since
	tweaked the code somewhat at random and the problem has disappeared, but I thought it was worth mentioning that I don't
	know exactly what I fixed.	*/

#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <tf2_stocks>
#include <keyvalues>
#define DEBUG	1

/* FCVAR_ values for my own reference:

FCVAR_PROTECTED - Sensitive information (should not be exposed to clients or logs).
FCVAR_NOTIFY - Clients are notified of changes.
FCVAR_CHEAT - Can only be use if sv_cheats is 1.
FCVAR_REPLICATED - Setting is forced to clients.
FCVAR_PLUGIN - Custom plugin ConVar (should be used by default). */

// Plugin defines
#define PLUGIN_NAME			"Assassination"
#define PLUGIN_AUTHOR		"[X6] Herbius"
#define PLUGIN_DESCRIPTION	"Deathmatch; become the assassin to gain points."
#define PLUGIN_VERSION		"0.0.0.33"	// Note: I don't update this religiously on builds. :P There have been AT LEAST this many builds.
#define PLUGIN_URL			"www.change.this.url/"

// Team integers
#define TEAM_INVALID		-1
#define TEAM_UNASSIGNED		0
#define TEAM_SPECTATOR		1
#define TEAM_RED			2
#define TEAM_BLUE			3

// Custom kill types
#define KILL_HEADSHOT		1
#define KILL_BACKSTAB		2

#define SND_ASSASSIN_KILLED					"assassination/assassin_killed.mp3"					// Sound when the assassin is killed by a player.
#define SND_PATH_ASSASSIN_KILLED			"sound/assassination/assassin_killed.mp3"
#define SND_ASSASSIN_KILLED_BY_TARGET		"assassination/assassin_killed_by_target.mp3"		// Sound when the assassin is killed by the target.
#define SND_PATH_ASSASSIN_KILLED_BY_TARGET	"sound/assassination/assassin_killed_by_target.mp3"
#define SND_ASSASSIN_SCORE					"assassination/assassin_score.mp3"					// Sound when the assassin kills the target.
#define SND_PATH_ASSASSIN_SCORE				"sound/assassination/assassin_score.mp3"

#define ASSASSIN_SPRITE_PATH	"materials/assassination/assassin_sprite"	// Path to the assassin sprite (excluding extension).
#define TARGET_SPRITE_PATH		"materials/assassination/target_sprite"		// Path to the target sprite (excluding extension).
#define ASSASSIN_SPRITE_Z_PATH	"materials/assassination/assassin_sprite_z"	// Path to the assassin sprite (excluding extension), ignoring Z-buffer.
#define TARGET_SPRITE_Z_PATH	"materials/assassination/target_sprite_z"	// Path to the target sprite (excluding extension), ignoring Z-buffer.
#define SPRITE_OFFSET			32											// Offset above the client's eye co-ords to display the sprite.

// Responses
/*#define RESPONSE_FALL_TO_DEATH				"assassination/assassin_fall_to_death.mp3"			// "I'd give that dive a three, actually."
#define RESPONSE_PATH_FALL_TO_DEATH			"sound/assassination/assassin_fall_to_death.mp3"
#define RESPONSE_ASSASSIN_STREAK1			"assassination/assassin_score_streak1.mp3"			// "I've seen this before..."
#define RESPONSE_PATH_ASSASSIN_STREAK1		"sound/assassination/assassin_score_streak1.mp3"
#define RESPONSE_ASSASSIN_STREAK2			"assassination/assassin_score_streak2.mp3"			// "You can take your offer to hell."
#define RESPONSE_PATH_ASSASSIN_STREAK2		"sound/assassination/assassin_score_streak2.mp3"
#define RESPONSE_ASSASSIN_STREAK3			"assassination/assassin_score_streak3.mp3"			// "Try rising from -those- ashes."
#define RESPONSE_PATH_ASSASSIN_STREAK3		"sound/assassination/assassin_score_streak3.mp3"*/

// Variable declarations
new n_WinIndex = -1;			// Index of the round win entity.
new bool:b_InRound;				// This flag is set if a round is in progress, and cleared at the end.
new n_AssassinIndex;			// Client index of the assassin player.
new n_TargetIndex;				// Client index of the target player
new bool:b_MapRestart;			// Set if we're waiting for a map restart.
new bool:b_TeamBelowMin = true;	// This flag is set if either team has less than 2 players.
new bool:b_StateChangePending;	// This flag is set if the enable/disable convar is waiting for a map restart.
new n_ScoreCounterBlu;			// Game mode-specific score counter for the Blue team.
new n_ScoreCounterRed;			// Game mode-specific score counter for the Red team.
new n_ScoreTotalBlu;			// Blu's overall score for this map.
new n_ScoreTotalRed;			// Red's overall score for this map.
new bool:b_RoundRestarting;		// If this is set, treat as if there were not enough players.
new n_AssassinSpriteCIndex;		// Holds the index of the player the assassin sprite is assigned to.
new n_TargetSpriteCIndex;		// Holds the index of the player the target sprite is assigned to.
new n_AssassinSpriteIndex;		// Entity index of the assassin sprite itself.
new n_TargetSpriteIndex;		// Entity index of the target sprite itself.
new gVelocityOffset;			// Offset at which to find the client's velocity vector.

// ConVar handle declarations
new Handle:cv_PluginEnabled = INVALID_HANDLE;			// Enables or disables the plugin. Changing this while in-game will restart the map.
new Handle:cv_PluginVersion = INVALID_HANDLE;			// Plugin version.
new Handle:cv_TargetLOS = INVALID_HANDLE;				// If possible, the new target will be chosen by prioritising players who have line-of-sight to the current assassin.
new Handle:cv_TargetTakeDamage = INVALID_HANDLE;		// If the target is hurt by an ordinary player, they will only take this fraction of the damage (between 0.1 and 1).
new Handle:cv_ColourTarget = INVALID_HANDLE;			// If 1, the target player will be tinted with their team's colour.
new Handle:cv_NoZSprites = INVALID_HANDLE;				// If 1, the assassin and target sprites will always be visible over world geometry.
new Handle:cv_SpawnProtection = INVALID_HANDLE;			// How long, in seconds, a player is protected from damage after they spawn.
//new Handle:cv_KillTargetNoAssassin = INVALID_HANDLE;	// If the target is killed by an ordinary player, this amount of points will be taken from the team's score.
new Handle:cv_KillAssassin = INVALID_HANDLE;			// The base amount of points the target gets for killing the assassin.
new Handle:cv_KillTarget = INVALID_HANDLE;				// The base amount of points the assassin gets for killing the target.
new Handle:cv_HeadshotMultiplier = INVALID_HANDLE;		// Score multiplier for headshots. Applied on top of the weapon modifier.
new Handle:cv_BackstabMultiplier = INVALID_HANDLE;		// Score multiplier for backstabs. Applied on top of the weapon modifier.
new Handle:cv_ReflectMultiplier = INVALID_HANDLE;		// Score multiplier for reflected projectiles. Applied on top of the weapon modifier.
new Handle:cv_SentryL1Multiplier = INVALID_HANDLE;		// Score multiplier for level 1 sentries.
new Handle:cv_SentryL2Multiplier = INVALID_HANDLE;		// Score multiplier for level 2 sentries.
new Handle:cv_SentryL3Multiplier = INVALID_HANDLE;		// Score multiplier for level 3 sentries.
new Handle:cv_TelefragMultiplier = INVALID_HANDLE;		// Score multiplier for telefrags.
new Handle:cv_MaxScore = INVALID_HANDLE;				// When this score is reached, the round will end.

// Other handles
new Handle:timer_AssassinCondition = INVALID_HANDLE;	// Hande to our timer that refreshes the buffed state on the assassin.
new Handle:hs_Assassin = INVALID_HANDLE;				// Handle to our HUD synchroniser for displaying who is the assassin.
new Handle:hs_Target = INVALID_HANDLE;					// Handle to our HUD synchroniser for displaying who is the target.
new Handle:timer_HUDMessageRefresh = INVALID_HANDLE;	// Handle to our HUD refresh timer.

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
	LoadTranslations("assassination/assassination_phrases");
	
	// ConVar declarations.
	// Prefixed with "nfas" (Nightfire Assassination) to make them more unique.
	cv_PluginEnabled  = CreateConVar("nfas_enabled",	/*In-game name*/
												"1",	/*Default value*/
												"Enables or disables the plugin. Changing this while in-game will restart the map.",	/*Description*/
												FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,	/*Flags*/
												true,	/*Has a minimum*/
												0.0,	/*Minimum value, float*/
												true,	/*Has a maximum*/
												1.0);	/*Maximum value, float*/
	
	cv_PluginVersion  = CreateConVar("nfas_version",	
												PLUGIN_VERSION,
												"Plugin version.",	
												FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_REPLICATED | FCVAR_NOT_CONNECTED);
												
	cv_TargetLOS  = CreateConVar("nfas_target_los_priority",
												"0",
												"If possible, the new target will be chosen by prioritising players who have line-of-sight to the current assassin.",
												FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
												true,
												0.0,
												true,
												1.0);
	
	cv_TargetTakeDamage  = CreateConVar("nfas_target_damage_modifier",
												"0.5",
												"If the target is hurt by an ordinary player, they will only take this fraction of the damage (between 0.1 and 1).",
												FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
												true,
												0.1,
												true,
												1.0);
	
	cv_ColourTarget  = CreateConVar("nfas_target_colour",
												"0",
												"If 1, the target player will be tinted with their team's colour.",
												FCVAR_PLUGIN | FCVAR_ARCHIVE,
												true,
												0.0,
												true,
												1.0);
	
	cv_NoZSprites  = CreateConVar("nfas_sprites_no_zbuffer",
												"0",
												"If 1, the assassin and target sprites will always be visible over world geometry.",
												FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
												true,
												0.0,
												true,
												1.0);
	
	cv_SpawnProtection  = CreateConVar("nfas_spawn_protection_length",
												"3.0",
												"How long, in seconds, a player is protected from damage after they spawn.",
												FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
												true,
												0.0,
												true,
												10.0);
	
	/*cv_KillTargetNoAssassin  = CreateConVar("nfas_target_point_deduction",
												"0",
												"If the target is killed by an ordinary player, this amount of points will be taken from the team's score.",
												FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
												true,
												0.0);*/
	
	cv_KillTarget  = CreateConVar("nfas_kill_target_score",
												"10",
												"The base amount of points the assassin gets for killing the target.",
												FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
												true,
												0.0);
	
	cv_KillAssassin  = CreateConVar("nfas_kill_assassin_score",
												"7",
												"The base amount of points the target gets for killing the assassin.",
												FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
												true,
												0.0);
	
	cv_HeadshotMultiplier  = CreateConVar("nfas_headshot_multiplier",
												"2.0",
												"Score multiplier for headshots. Applied on top of the weapon modifier.",
												FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
												true,
												0.0);
	
	cv_BackstabMultiplier  = CreateConVar("nfas_backstab_multiplier",
												"3.0",
												"Score multiplier for backstabs. Applied on top of the weapon modifier.",
												FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
												true,
												0.0);
	
	cv_ReflectMultiplier  = CreateConVar("nfas_reflect_multiplier",
												"2.0",
												"Score multiplier for reflected projectiles. Applied on top of the weapon modifier.",
												FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
												true,
												0.0);
	
	cv_SentryL1Multiplier  = CreateConVar("nfas_sentry_level1_multiplier",
												"2.0",
												"Score multiplier for level 1 sentries.",
												FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
												true,
												0.0);
	
	cv_SentryL2Multiplier  = CreateConVar("nfas_sentry_level2_multiplier",
												"1.0",
												"Score multiplier for level 2 sentries.",
												FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
												true,
												0.0);
	
	cv_SentryL3Multiplier  = CreateConVar("nfas_sentry_level3_multiplier",
												"0.5",
												"Score multiplier for level 3 sentries.",
												FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
												true,
												0.0);
	
	cv_TelefragMultiplier  = CreateConVar("nfas_telefrag_multiplier",
												"4.0",
												"Score multiplier for telefrags.",
												FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
												true,
												0.0);
	
	cv_MaxScore  = CreateConVar("nfas_score_max",
												"100",
												"When this score is reached, the round will end.",
												FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
												true,
												0.0);
	
	// Hooks:
	HookEventEx("teamplay_round_start",		Event_RoundStart,	EventHookMode_Post);	// Check minimum players is met, do startup admin.
	HookEventEx("teamplay_round_win",		Event_RoundWin,		EventHookMode_Post);	// Show endround stats, etc.
	HookEventEx("player_team",				Event_TeamsChange,	EventHookMode_Post);	// Check team numbers.
	HookEventEx("player_death",				Event_PlayerDeath,	EventHookMode_Post);	// Handle assassin/target switching logic.
	HookEventEx("player_hurt",				Event_PlayerHurt,	EventHookMode_Post);	// Modify target's health.
	HookEventEx("player_spawn",				Event_PlayerSpawn,	EventHookMode_Post);	// Create sprites if we need to.
	
	HookConVarChange(cv_PluginEnabled,	CvarChange);	// CvarChange handles everything.
	
	#if DEBUG == 1
	RegConsoleCmd("nfas_checkindices",	Command_CheckIndices,	"Outputs the assassin and target indices.");
	RegConsoleCmd("nfas_testmessage",	Command_TestMessage,	"Displays a test message at the specified position.");
	RegConsoleCmd("nfas_testkvparse",	Command_TestKVParse,	"Tests the KeyValues parsing system.");
	#endif
	
	gVelocityOffset = FindSendPropInfo("CBasePlayer", "m_vecVelocity[0]");
	
	// Parse the weaponmodifiers file
	WeaponModifiers(false);	// "False" switch
	
	ModifyGlobalIndex(0, 0);	// Reset both indices to 0.
	ModifyGlobalIndex(1, 0);
	
	n_ScoreCounterBlu = 0;
	n_ScoreCounterRed = 0;
	n_ScoreTotalBlu = 0;
	n_ScoreTotalRed = 0;
	
	n_AssassinSpriteCIndex = 0;
	n_TargetSpriteCIndex = 0;
	
	if ( IsServerProcessing() )
	{
		if ( GetTeamClientCount(TEAM_RED) >= 2 && GetTeamClientCount(TEAM_BLUE) >= 2 ) b_TeamBelowMin = false;
		else b_TeamBelowMin = true;
	}
	
}

/* ==================== \/ Begin Event Hooks \/ ==================== */

/*	Called when the map loads.	*/
public OnMapStart()
{
	// Files to download:
	//AddFileToDownloadsTable("translations/assassination/assassination_phrases.txt");	// Do we need this?
	AddFileToDownloadsTable(SND_PATH_ASSASSIN_KILLED);
	AddFileToDownloadsTable(SND_PATH_ASSASSIN_KILLED_BY_TARGET);
	AddFileToDownloadsTable(SND_PATH_ASSASSIN_SCORE);
	
	// Precache:
	PrecacheSound(SND_ASSASSIN_KILLED, true);
	PrecacheSound(SND_ASSASSIN_KILLED_BY_TARGET, true);
	PrecacheSound(SND_ASSASSIN_SCORE, true);
	
	// Precache sprites by adding extensions
	decl String:spriteprecache[128];
	
	Format( spriteprecache, sizeof(spriteprecache), "%s.vmt", ASSASSIN_SPRITE_PATH);
	AddFileToDownloadsTable(spriteprecache);
	PrecacheGeneric(spriteprecache, true);
	
	Format( spriteprecache, sizeof(spriteprecache), "%s.vtf", ASSASSIN_SPRITE_PATH);
	AddFileToDownloadsTable(spriteprecache);
	PrecacheGeneric(spriteprecache, true);
	
	Format( spriteprecache, sizeof(spriteprecache), "%s.vmt", TARGET_SPRITE_PATH);
	AddFileToDownloadsTable(spriteprecache);
	PrecacheGeneric(spriteprecache, true);
	
	Format( spriteprecache, sizeof(spriteprecache), "%s.vtf", TARGET_SPRITE_PATH);
	AddFileToDownloadsTable(spriteprecache);
	PrecacheGeneric(spriteprecache, true);
	
	b_MapRestart = false; 	// Reset our state changed flag in case it's still set.
	b_InRound = false;		// If our InRound flag is still set to true for any reason, clear it.
	b_StateChangePending = false;
	
	// Clear all the things that should be cleared at the start of a map.
	ModifyGlobalIndex(0, 0);	// Reset both indices to 0.
	ModifyGlobalIndex(1, 0);
	
	n_ScoreCounterBlu = 0;
	n_ScoreCounterRed = 0;
	n_ScoreTotalBlu = 0;
	n_ScoreTotalRed = 0;
	
	n_AssassinSpriteCIndex = 0;
	n_TargetSpriteCIndex = 0;
	
	if ( GetTeamClientCount(TEAM_RED) >= 2 && GetTeamClientCount(TEAM_BLUE) >= 2 ) b_TeamBelowMin = false;
	else b_TeamBelowMin = true;
	
	if ( !GetConVarBool(cv_PluginEnabled) ) return;	// After this point, only do things if we're enabled.
	
	// When the map starts, we create a timer that automatically updates once a second.
	// This will redraw the HUD mesages (which each last for a second).
	hs_Assassin = CreateHudSynchronizer();
	hs_Target = CreateHudSynchronizer();
	
	if ( hs_Assassin != INVALID_HANDLE && hs_Target != INVALID_HANDLE )	// If the above was successful:
	{
		UpdateHUDMessages();	// Update the HUD
		timer_HUDMessageRefresh = CreateTimer(1.0, TimerHUDRefresh, _, TIMER_REPEAT);	// Set up the timer to next update the HUD.
	}
}

/*	Called when the map finishes.	*/
public OnMapEnd()
{
	b_InRound = false;
	
	ModifyGlobalIndex(0, 0);	// Reset both indices to 0.
	ModifyGlobalIndex(1, 0);
	
	if ( !GetConVarBool(cv_PluginEnabled) ) return;
	
	if ( hs_Assassin != INVALID_HANDLE ) CloseHandle(hs_Assassin);	// If the assassin hud snyc isn't invalid, close it.
	if ( hs_Target != INVALID_HANDLE ) CloseHandle(hs_Target);		// If the target hud snyc isn't invalid, close it.
}
/*	Called when a new round begins.	*/
public Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	if ( !GetConVarBool(cv_PluginEnabled) || b_MapRestart ) return;	// If we're disabled or locked, exit.
	
	b_InRound = true;	// Set our global state flag.
	b_RoundRestarting = false;
	
	//Reset the variables that need it.
	ResetStartOfRoundVars();
	
	// NOTE: TEMPHACK
	CreateTimer(3.0, TimerAsTrCheck);
	
	if ( GetTeamClientCount(TEAM_RED) < 2 || GetTeamClientCount(TEAM_BLUE) < 2 )	// If we're in any condition with too few players:
	{
		PrintToChatAll("[AS] %t", "as_notenoughplayers");
		LogMessage ("[AS] Not enough players.");
		return;
	}
	
	// By this point we should have performed all checks to make sure it's valid to continue.
	// From here we will start assigning the assassin and the victim.
	
	ModifyGlobalIndex(0, RandomPlayerFromTeam(TEAM_RED));
	ModifyGlobalIndex(1, RandomPlayerFromTeam(TEAM_BLUE));	// Set both indices to random players.
	
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
	b_InRound = false;	// Clear our global state flag. Needs to be done even if we're locked.
	
	ModifyGlobalIndex(0, 0);	// Set assassin index to 0.
	ModifyGlobalIndex(1, 0);	// Set target index to 0.
	
	if ( !GetConVarBool(cv_PluginEnabled) || b_MapRestart ) return;	// If we're disabled or locked, exit.
	
	n_ScoreTotalBlu += n_ScoreCounterBlu;
	n_ScoreTotalRed += n_ScoreCounterRed;
	
	// NOTE: Send a message to the HUD stating the total scores for this map.
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
	new tc_clientindex = GetClientOfUserId(GetEventInt(event, "userid"));
	new tc_newteamid = GetEventInt(event, "team");
	new tc_oldteamid = GetEventInt(event, "oldteam");
	new bool:tcb_disconnect = GetEventBool(event, "disconnect");
	
	new bool:b_assassinchanging;	// Will be true if the assassin is changing team.
	new bool:b_targetchanging;	// Will be true if the target is changing.
	
	if ( tc_clientindex == n_AssassinIndex )
	{
		b_assassinchanging = true;
	}
	else if ( tc_clientindex == n_TargetIndex )
	{
		b_targetchanging = true;
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
			if ( !b_MapRestart )
			{
				ServerCommand("mp_restartround 3");	// Restart the round if we're not restarting the map.
				b_RoundRestarting = true;
			}
			
			return;
		}
		
		case 3:	// One team has just dropped below the threshold.
		{
			PrintToChatAll("[AS] %t", "as_playersdropbelowthreshold");	// Let us know.
			if ( !b_MapRestart )
			{
				ServerCommand("mp_restartround 3");	// Restart the round if we're not restarting the map.
				b_RoundRestarting = true;
			}
			
			return;
		}
	}
	
	// If we're here it means the plugin is enabled and there are enough players.
	// If the assassin or target return true here, it means it's safe to select a new player at random from their team.
	
	if ( b_assassinchanging )	// If the assassin was detected further up:
	{
		ModifyGlobalIndex(0, RandomPlayerFromTeam(tc_oldteamid, tc_clientindex));	// Choose a random player from the old team, ignoring the changing player.
		
		if ( n_AssassinIndex <= 0)	// If it failed:
		{
			LogMessage("[AS] Get random assassin on disconnect from team %d failed (assassin index = %d).", tc_oldteamid, n_AssassinIndex);
			PrintToChatAll("[AS] %t", "as_newassassinfailed");
			
			return;
		}
	}
	else if ( b_targetchanging )	// If the target was detected further up:
	{
		ModifyGlobalIndex(1, RandomPlayerFromTeam(tc_oldteamid, tc_clientindex));	// Choose a random player from the old team, ignoring the changing player.
		
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
	if ( client == n_AssassinIndex )	// If the client was the assassin:
	{
		if ( GetTeamClientCount(TEAM_RED) >= 2 && GetTeamClientCount(TEAM_BLUE) >= 2 )
		{
			ModifyGlobalIndex(0, RandomPlayerFromTeam(GetClientTeam(client), client));	// Get a new client from the team, ignoring the client who's leaving.
			
			if ( n_AssassinIndex <= 0)	// If it failed:
			{
				LogMessage("[AS] Get random assassin on disconnect from team %d failed (assassin index = %d).", GetClientTeam(client), n_AssassinIndex);
				PrintToChatAll("[AS] %t", "as_newassassinfailed");
				
				return;
			}
		}
		else
		{
			ModifyGlobalIndex(0, 0);	// Reset indices 
		}
	}
	else if ( client == n_TargetIndex )	// If the client was the target:
	{
		if ( GetTeamClientCount(TEAM_RED) >= 2 && GetTeamClientCount(TEAM_BLUE) >= 2 )
		{
			ModifyGlobalIndex(1, RandomPlayerFromTeam(GetClientTeam(client), client));	// Get a new client from the team, ignoring the client who's leaving.
			
			if ( n_TargetIndex <= 0)	// If it failed:
			{
				LogMessage("[AS] Get random target on disconnect from team %d failed (target index = %d).", GetClientTeam(client), n_TargetIndex);
				PrintToChatAll("[AS] %t", "as_newtargetfailed");
				
				return;
			}
		}
		else
		{
			ModifyGlobalIndex(1, 0);	// Reset indices 
		}
	}
}

/*	Called when a player dies.
	This is where we look at who died and swap around the assassin/target appropriately.
	We also give points and play sounds.	*/
public Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	// If there are too few players, we're disabled or it's the end of a round, exit. This will save us from going through all the unnecessary stuff below.
	if ( !GetConVarBool(cv_PluginEnabled) || GetTeamClientCount(TEAM_RED) < 2 || GetTeamClientCount(TEAM_BLUE) < 2 || !b_InRound || b_MapRestart || b_RoundRestarting ) return;
	
	new pd_ClientID = GetEventInt(event, "userid");
	new pd_AttackerID = GetEventInt(event, "attacker");
	new pd_AssisterID = GetEventInt(event, "assister");
	
	new pd_ClientIndex = GetClientOfUserId(pd_ClientID);		// Index of the player who died.
	new pd_AttackerIndex = GetClientOfUserId(pd_AttackerID);	// Index of the player who killed them.
	new pd_AssisterIndex = GetClientOfUserId(pd_AssisterID);	// Index of the assister.
	new pd_ClientTeam;											// Team of client.
	new pd_AttackerTeam;										// Team of attacker.
	new pd_AssisterTeam;										// Team of assister.
	new pd_WeaponID = GetEventInt(event, "weaponid");			// ID of weapon used (for modifying points later).
	//new pd_DamageBits = GetEventInt(event, "damagebits");		// Damage type
	new pd_EntIndex = GetEventInt(event, "inflictor_entindex");	// Entindex of sentry
	new pd_CustomKill = GetEventInt(event, "customkill");		// Custom kill value
	new pd_DeathFlags = GetEventInt(event, "death_flags");		// Death flags
	new b_AssassinTeam;											// True if the attacker is on the same team as the assassin.
	
	if ( pd_ClientIndex > 0 && pd_ClientIndex <= MaxClients )
	{
		pd_ClientTeam = GetClientTeam(pd_ClientIndex);
	}
	
	if ( pd_AttackerIndex > 0 && pd_AttackerIndex <= MaxClients )
	{
		pd_AttackerTeam = GetClientTeam(pd_AttackerIndex);
		if ( pd_AttackerTeam == GetClientTeam(n_AssassinIndex) ) b_AssassinTeam = true;
	}
	
	if ( pd_AssisterIndex > 0 && pd_AssisterIndex <= MaxClients )
	{
		pd_AssisterTeam = GetClientTeam(pd_AssisterIndex);
	}
	
	// Firstly, let's deal with if the assassin has died.
	// NOTE: Checking whether the player is alive always returns true here - same situation as player_teamchange?
	// Screw you, code.
	if ( pd_ClientIndex == n_AssassinIndex /*&& (pd_DeathFlags & 32)*/ )	// How do you check if the bitflags do NOT contain 32?
	{
		// If the killer was a PLAYER from the opposite team:
		if ( IsClientConnected(pd_AttackerIndex) && pd_ClientTeam != pd_AttackerTeam )
		{
			// Add to the target's team's score count.
			// Here we want to set up a temporary variable which will hold the number of points to add.
			// At the end of all the calculations, the team's score counter will be incremented by this variable's value.
			
			new Float:pfl_AssassinDeath;	// Temporary score variable
			
			if ( pd_AttackerIndex == n_TargetIndex )	// If the killer was the target:
			{
				EmitSoundToAll(SND_ASSASSIN_KILLED_BY_TARGET, _, SNDCHAN_STATIC, SNDLEVEL_TRAFFIC, SND_NOFLAGS, SNDVOL_NORMAL, 100, pd_AttackerIndex, _, NULL_VECTOR, false, 0.0);	// Play target killed assassin
				//LogMessage("Sound played: assassin killed by target.");
				
				pfl_AssassinDeath = (GetConVarFloat(cv_KillAssassin) * WeaponModifiers(true, pd_WeaponID));
				
				if ( pd_EntIndex != 0 && IsValidEntity(pd_EntIndex) )
				{
					decl String:a_sentryname[64];
					GetEdictClassname(pd_EntIndex, a_sentryname, sizeof(a_sentryname));
					if ( StrEqual(a_sentryname, "obj_sentrygun", false) )
					{
						switch (GetEntPropEnt(pd_EntIndex, Prop_Send, "m_iUpgradeLevel"))
						{
							case 1:
							{
								pfl_AssassinDeath = (pfl_AssassinDeath * GetConVarFloat(cv_SentryL1Multiplier));
							}
							
							case 2:
							{
								pfl_AssassinDeath = (pfl_AssassinDeath * GetConVarFloat(cv_SentryL2Multiplier));
							}
							
							case 3:
							{
								pfl_AssassinDeath = (pfl_AssassinDeath * GetConVarFloat(cv_SentryL3Multiplier));
							}
						}
					}
				}
				
				switch (pd_CustomKill)
				{
					case KILL_HEADSHOT:
					{
						pfl_AssassinDeath = (pfl_AssassinDeath * GetConVarFloat(cv_HeadshotMultiplier));
					}
					
					case KILL_BACKSTAB:
					{
						pfl_AssassinDeath = (pfl_AssassinDeath * GetConVarFloat(cv_BackstabMultiplier));
					}
				}
				
				// NOTE: Still to be dealt with: reflect projectiles, telefrags
			}
			else
			{
				EmitSoundToAll(SND_ASSASSIN_KILLED, _, SNDCHAN_STATIC, SNDLEVEL_TRAFFIC, SND_NOFLAGS, SNDVOL_NORMAL, 100, pd_AttackerIndex, _, NULL_VECTOR, false, 0.0);	// Play assassin killed
				//LogMessage("Sound played: assassin killed.");
				
				switch(pd_AttackerTeam)	// Check the killer's team.
				{
					case TEAM_RED:
					{
						n_ScoreCounterRed += RoundFloat(pfl_AssassinDeath);
						#if DEBUG == 1
							PrintToChatAll("Red counter: %d Increment: %d", n_ScoreCounterRed, RoundFloat(pfl_AssassinDeath));
						#endif
						// NOTE: Send off a timer refresh here for our HUD display.
					}
					
					case TEAM_BLUE:
					{
						n_ScoreCounterBlu += RoundFloat(pfl_AssassinDeath);
						#if DEBUG == 1
							PrintToChatAll("Blue counter: %d Increment: %d", n_ScoreCounterBlu, RoundFloat(pfl_AssassinDeath));
						#endif
						// NOTE: Send off a timer refresh here for our HUD display.
					}
				}
			}
			
			// Make the killer player the assassin.
			ModifyGlobalIndex(0, pd_AttackerIndex);
			
			// Assign the target to a random player on the late assassin's team.
			// Note that the late assassin is not excluded, so he could become the target.
			ModifyGlobalIndex(1, RandomPlayerFromTeam(pd_ClientTeam));
			
			if ( n_TargetIndex <= 0)	// If it failed:
			{
				LogMessage("[AS] Get random target on death from team %d failed (target index = %d).", pd_ClientTeam, n_TargetIndex);
				PrintToChatAll("[AS] %t", "as_newtargetfailed");
				
				return;
			}
			
			// Check if we scored anything (attacker = target only) and update the score variables.
			if ( pfl_AssassinDeath > 0.0 )
			{
				switch(pd_AttackerTeam)	// Check the killer's team.
				{
					case TEAM_RED:
					{
						n_ScoreCounterRed += RoundFloat(pfl_AssassinDeath);
						#if DEBUG == 1
							PrintToChatAll("Red counter: %d Increment: %d (%f)", n_ScoreCounterRed, RoundFloat(pfl_AssassinDeath), pfl_AssassinDeath);
						#endif
						// NOTE: Send off a timer refresh here for our HUD display.
					}
					
					case TEAM_BLUE:
					{
						n_ScoreCounterBlu += RoundFloat(pfl_AssassinDeath);
						#if DEBUG == 1
							PrintToChatAll("Blue counter: %d Increment: %d (%f)", n_ScoreCounterBlu, RoundFloat(pfl_AssassinDeath), pfl_AssassinDeath);
						#endif
						// NOTE: Send off a timer refresh here for our HUD display.
					}
				}
			}
		}
		// If the killer wasn't a player, or was a player from the same team, or it was suicide:
		else if ( pd_AttackerIndex > MaxClients || pd_AttackerIndex < 1 || !IsClientConnected(pd_AttackerIndex) || pd_ClientTeam == pd_AttackerTeam || pd_ClientIndex == pd_AttackerIndex )
		{		
			// Assign the assassin to be someone from the opposite team to the late assassin.
			switch (pd_ClientTeam)
			{
				case TEAM_RED:
				{
					ModifyGlobalIndex(0, RandomPlayerFromTeam(TEAM_BLUE));
					
					if ( n_AssassinIndex <= 0)	// If it failed:
					{
						LogMessage("[AS] Get random assassin on death from team %d failed (assassin index = %d).", TEAM_BLUE, n_AssassinIndex);
						PrintToChatAll("[AS] %t", "as_newassassinfailed");
						
						return;
					}
				}
				
				case TEAM_BLUE:
				{
					ModifyGlobalIndex(0, RandomPlayerFromTeam(TEAM_RED));
					
					if ( n_AssassinIndex <= 0)	// If it failed:
					{
						LogMessage("[AS] Get random assassin on death from team %d failed (assassin index = %d).", TEAM_RED, n_AssassinIndex);
						PrintToChatAll("[AS] %t", "as_newassassinfailed");
						
						return;
					}
				}
			}
			
			// Assign the target to be someone from the late assassin's team.
			ModifyGlobalIndex(1, RandomPlayerFromTeam(pd_ClientTeam));
			
			if ( n_TargetIndex <= 0)	// If it failed:
			{
				LogMessage("[AS] Get random target on death from team %d failed (target index = %d).", pd_ClientTeam, n_TargetIndex);
				PrintToChatAll("[AS] %t", "as_newtargetfailed");
				
				return;
			}
		}
	}
	// Now, if the target has died instead:
	else if ( pd_ClientIndex == n_TargetIndex /*&& !GetEventBool(event, "feign_death")*/ )	// DR checking messed up again
	{
		// If the killer wasn't a player, or was a player from the same team, or it was suicide:
		if ( pd_AttackerIndex > MaxClients || pd_AttackerIndex < 1 || !IsClientConnected(pd_AttackerIndex) || pd_ClientIndex == pd_AttackerIndex || pd_ClientTeam == pd_AttackerTeam )
		{		
			// Choose another random player from the same team, excluding the late target.
			ModifyGlobalIndex(1, RandomPlayerFromTeam(pd_ClientTeam, pd_ClientIndex));
			
			if ( n_TargetIndex <= 0)	// If it failed:
			{
				LogMessage("[AS] Get random target on death from team %d failed (target index = %d).", pd_ClientTeam, n_TargetIndex);
				PrintToChatAll("[AS] %t", "as_newtargetfailed");
				
				return;
			}
		}
		// If the killer was an enemy player:
		else if ( IsClientConnected(pd_AttackerIndex) && pd_ClientTeam != pd_AttackerTeam )
		{
			new Float:pfl_TargetDeath;
			
			if ( pd_AttackerIndex == n_AssassinIndex )	// If the killer was the assassin:
			{
				EmitSoundToAll(SND_ASSASSIN_SCORE, _, SNDCHAN_STATIC, SNDLEVEL_TRAFFIC, SND_NOFLAGS, SNDVOL_NORMAL, 100, pd_AttackerIndex, _, NULL_VECTOR, false, 0.0);	// Play assassin killed target
				//LogMessage("Sound played: target killed by assassin.");
				
				pfl_TargetDeath = (GetConVarFloat(cv_KillTarget) * WeaponModifiers(true, pd_WeaponID));
				
				if ( pd_EntIndex != 0 && IsValidEntity(pd_EntIndex) )
				{
					decl String:t1_sentryname[64];
					GetEdictClassname(pd_EntIndex, t1_sentryname, sizeof(t1_sentryname));
					if ( StrEqual(t1_sentryname, "obj_sentrygun", false) )
					{
						switch (GetEntPropEnt(pd_EntIndex, Prop_Send, "m_iUpgradeLevel"))
						{
							case 1:
							{
								pfl_TargetDeath = (pfl_TargetDeath * GetConVarFloat(cv_SentryL1Multiplier));
							}
							
							case 2:
							{
								pfl_TargetDeath = (pfl_TargetDeath * GetConVarFloat(cv_SentryL2Multiplier));
							}
							
							case 3:
							{
								pfl_TargetDeath = (pfl_TargetDeath * GetConVarFloat(cv_SentryL3Multiplier));
							}
						}
					}
				}
				
				switch (pd_CustomKill)
				{
					case KILL_HEADSHOT:
					{
						pfl_TargetDeath = (pfl_TargetDeath * GetConVarFloat(cv_HeadshotMultiplier));
					}
					
					case KILL_BACKSTAB:
					{
						pfl_TargetDeath = (pfl_TargetDeath * GetConVarFloat(cv_BackstabMultiplier));
					}
				}
				
				// NOTE: Still to be dealt with: reflect projectiles, telefrags
			}
			// TODO: Check if the Medic's heal target is the attacker?
			else if ( pd_AssisterIndex == n_AssassinIndex && pd_AssisterTeam != pd_ClientTeam && TF2_GetPlayerClass(pd_AssisterIndex) == TFClass_Medic )	// Or if the assister was an enemy Medic who was the assassin:
			{
				EmitSoundToAll(SND_ASSASSIN_SCORE, _, SNDCHAN_STATIC, SNDLEVEL_TRAFFIC, SND_NOFLAGS, SNDVOL_NORMAL, 100, pd_AttackerIndex, _, NULL_VECTOR, false, 0.0);	// Play assassin killed target
				//LogMessage("Sound played: target killed by assassin.");
				
				pfl_TargetDeath = (GetConVarFloat(cv_KillTarget) * WeaponModifiers(true, pd_WeaponID));
				
				if ( pd_EntIndex != 0 && IsValidEntity(pd_EntIndex) )
				{
					decl String:t1_sentryname[64];
					GetEdictClassname(pd_EntIndex, t1_sentryname, sizeof(t1_sentryname));
					if ( StrEqual(t1_sentryname, "obj_sentrygun", false) )
					{
						switch (GetEntPropEnt(pd_EntIndex, Prop_Send, "m_iUpgradeLevel"))
						{
							case 1:
							{
								pfl_TargetDeath = (pfl_TargetDeath * GetConVarFloat(cv_SentryL1Multiplier));
							}
							
							case 2:
							{
								pfl_TargetDeath = (pfl_TargetDeath * GetConVarFloat(cv_SentryL2Multiplier));
							}
							
							case 3:
							{
								pfl_TargetDeath = (pfl_TargetDeath * GetConVarFloat(cv_SentryL3Multiplier));
							}
						}
					}
				}
				
				switch (pd_CustomKill)
				{
					case KILL_HEADSHOT:
					{
						pfl_TargetDeath = (pfl_TargetDeath * GetConVarFloat(cv_HeadshotMultiplier));
					}
					
					case KILL_BACKSTAB:
					{
						pfl_TargetDeath = (pfl_TargetDeath * GetConVarFloat(cv_BackstabMultiplier));
					}
				}
			}
			else if ( b_AssassinTeam )	// If the killer was on the same team as the assassin:
			{
				switch (pd_AttackerTeam)
				{
					case TEAM_RED:
					{
						n_ScoreCounterRed ++;
						#if DEBUG == 1
							PrintToChatAll("Red counter: %d", n_ScoreCounterRed);
						#endif
					}
					
					case TEAM_BLUE:
					{
						n_ScoreCounterBlu ++;
						#if DEBUG == 1
							PrintToChatAll("Blue counter: %d", n_ScoreCounterBlu);
						#endif
					}
				}
			}
			
			// Choose a new target from the same team.
			
			if ( GetConVarBool(cv_TargetLOS) )	// If we want the new target to have LOS to the assassin:
			{
				if ( pd_AttackerIndex == n_AssassinIndex  ) ModifyGlobalIndex(1, RandomPlayerFromTeam(pd_ClientTeam, _, pd_AttackerIndex));
				// Don't bother with Medic complications like above.
			}
			else
			{
				ModifyGlobalIndex(1, RandomPlayerFromTeam(pd_ClientTeam));	// If we don't want LOS, go as normal.
			}
			
			if ( n_TargetIndex <= 0)	// If it failed:
			{
				LogMessage("[AS] Get random target on death from team %d failed (target index = %d).", pd_ClientTeam, n_TargetIndex);
				PrintToChatAll("[AS] %t", "as_newtargetfailed");
				
				return;
			}
			
			// Check if we scored anything and update the score variables.
			if ( pfl_TargetDeath > 0.0 )
			{
				switch(pd_AttackerTeam)	// Check the killer's team.
				{
					case TEAM_RED:
					{
						n_ScoreCounterRed += RoundFloat(pfl_TargetDeath);
						#if DEBUG == 1
							PrintToChatAll("Red counter: %d Increment: %d", n_ScoreCounterRed, RoundFloat(pfl_TargetDeath));
						#endif
						// NOTE: Send off a timer refresh here for our HUD display.
					}
					
					case TEAM_BLUE:
					{
						n_ScoreCounterBlu += RoundFloat(pfl_TargetDeath);
						#if DEBUG == 1
							PrintToChatAll("Blue counter: %d Increment: %d", n_ScoreCounterBlu, RoundFloat(pfl_TargetDeath));
						#endif
						// NOTE: Send off a timer refresh here for our HUD display.
					}
				}
			}
		}
	}
	else	// If it's not the assassin or the target:
	{
		if ( b_AssassinTeam && pd_AttackerTeam != pd_ClientTeam )	// If the attacker's team is the same team as the assassin and it's not a team kill:
		{
			switch (pd_AttackerTeam)
			{
				case TEAM_RED:
				{
					n_ScoreCounterRed ++;
					#if DEBUG == 1
						PrintToChatAll("Red counter: %d", n_ScoreCounterRed);
					#endif
				}
				
				case TEAM_BLUE:
				{
					n_ScoreCounterBlu ++;
					#if DEBUG == 1
						PrintToChatAll("Blue counter: %d", n_ScoreCounterBlu);
					#endif
				}
			}
		}
	}
	
	// If, for any reason, the assassin and target are still on the same team here, swap the target's team.
	// This SHOULDN'T happen (in theory) but I was having some problems. I think they were related to checking
	// feign death, but if not this should fix anyway.
	
	if ( GetClientTeam(n_AssassinIndex) == GetClientTeam(n_TargetIndex) )
	{
		switch (GetClientTeam(n_TargetIndex))
		{
			case TEAM_RED:
			{
				if ( GetConVarBool(cv_TargetLOS) ) ModifyGlobalIndex(1, RandomPlayerFromTeam(TEAM_BLUE, _, n_AssassinIndex));
				else ModifyGlobalIndex(1, RandomPlayerFromTeam(TEAM_BLUE));
				
				if ( n_TargetIndex <= 0)	// If it failed:
				{
					LogMessage("[AS] Get random target on death from team %d failed (target index = %d).", TEAM_BLUE, n_TargetIndex);
					PrintToChatAll("[AS] %t", "as_newtargetfailed");
					
					return;
				}
			}
			
			case TEAM_BLUE:
			{
				if ( GetConVarBool(cv_TargetLOS) ) ModifyGlobalIndex(1, RandomPlayerFromTeam(TEAM_RED, _, n_AssassinIndex));
				else ModifyGlobalIndex(1, RandomPlayerFromTeam(TEAM_RED));
				
				if ( n_TargetIndex <= 0)	// If it failed:
				{
					LogMessage("[AS] Get random target on death from team %d failed (target index = %d).", TEAM_RED, n_TargetIndex);
					PrintToChatAll("[AS] %t", "as_newtargetfailed");
					
					return;
				}
			}
		}
	}
	
	if ( TF2_GetPlayerClass(pd_ClientIndex) == TFClass_Engineer )	// If the player who died was an Engineer:
	{
		// Kill the Engineer's sentry if he has one.
		
		new n_SentryIndex = -1;
		while ( (n_SentryIndex = FindEntityByClassname(n_SentryIndex, "obj_sentrygun")) != -1 )
		{
			if ( IsValidEntity(n_SentryIndex) && GetEntPropEnt(n_SentryIndex, Prop_Send, "m_hBuilder") == pd_ClientIndex )
			{
				SetVariantInt( GetEntProp(n_SentryIndex, Prop_Send, "m_iMaxHealth") + 1 );
				AcceptEntityInput(n_SentryIndex, "RemoveHealth");
				AcceptEntityInput(n_SentryIndex, "Kill");
			}
		}
	}
	
	// After everything else is done, check to see if either of the score counters is now above the max:
	new n_MaxScore = GetConVarInt(cv_MaxScore);
	
	if ( n_ScoreCounterBlu >= n_MaxScore && n_ScoreCounterRed >= n_MaxScore )	// If both just crossed the max (unlikely):
	{
		ServerCommand("mp_stalemate_enable 0");
		RoundWin();	// Win the round as a draw.
	}
	else if ( n_ScoreCounterRed >= n_MaxScore )	// Red has won:
	{
		RoundWin(TEAM_RED);
	}
	else if ( n_ScoreCounterBlu >= n_MaxScore )	// Blue has won:
	{
		RoundWin(TEAM_BLUE);
	}
}

/*	Called when a player is hurt.
	Here we check to see how much damage was done (to play responses), or modify target's health.	*/
public Event_PlayerHurt(Handle:event, const String:name[], bool:dontBroadcast)
{
	new ph_ClientID = GetEventInt(event, "userid");
	new ph_AttackerID = GetEventInt(event, "attacker");
	new ph_ClientIndex = GetClientOfUserId(ph_ClientID);		// Index of the client who was hurt.
	new ph_AttackerIndex = GetClientOfUserId(ph_AttackerID);	// Index of the client who fired the shot.
	new ph_ClientHealth = GetEventInt(event, "health");			// How much health the injured player now has.
	new ph_ClientDamage = GetEventInt(event, "damageamount");	// The amount of damage the injured player took.
	
	// The target was hit by someone who wasn't the assassin.
	// If the damage taken was from an ordinary player, and it didn't kill them, give the target back half of the damage done
	// (rounded down).
	if ( ph_ClientIndex == n_TargetIndex && ph_AttackerIndex > 0 && ph_AttackerIndex <= MaxClients && ph_AttackerIndex != n_AssassinIndex && ph_ClientHealth > 0  )
	{
		new Float:f_healthtoset = float(ph_ClientHealth) + (float(ph_ClientDamage) * (1.0 - GetConVarFloat(cv_TargetTakeDamage)));
		SetEntProp(ph_ClientIndex, Prop_Data, "m_iHealth", RoundToFloor(f_healthtoset));
		
		// Immediately mark the health value as changed.
		ChangeEdictState(ph_ClientIndex, GetEntSendPropOffs(ph_ClientIndex, "m_iHealth"));
	}	
}

/*	Called when a player spawns.	*/
public Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	new ps_ClientIndex = GetClientOfUserId(GetEventInt(event, "userid"));
	
	if ( n_AssassinSpriteCIndex <= 0 && ps_ClientIndex == n_AssassinIndex )	// If the CIndex is 0 and the respawned player is the assassin:
	{
		CreateSprite(ps_ClientIndex, false);
	}
	
	if ( n_TargetSpriteCIndex <= 0 && ps_ClientIndex == n_TargetIndex )	// If the CIndex is 0 and the respawned player is the target:
	{
		CreateSprite(ps_ClientIndex, true);
	}
	
	// Set up spawn protection.
	// Until/unless I can come up with a better solution, the player will have an Ubercharge applied.
	
	if ( GetConVarFloat(cv_SpawnProtection) > 0.0 ) TF2_AddCondition(ps_ClientIndex, TFCond_Ubercharged, GetConVarFloat(cv_SpawnProtection));
}

/*	Called on every frame. Should be WELL-OPTIMISED.	*/
public OnGameFrame()
{	
	// Here we want to manage sprite movement.
	// If a sprite doesn't exist, skip the process.
	
	if ( n_AssassinSpriteIndex > MaxClients && IsValidEntity(n_AssassinSpriteIndex) && n_AssassinIndex > 0 && n_AssassinIndex <= MaxClients && IsClientInGame(n_AssassinIndex) )
	{
		new Float:v_asOrigin[3], Float:v_asVelocity[3];
		
		GetClientEyePosition(n_AssassinIndex, v_asOrigin);
		v_asOrigin[2] += SPRITE_OFFSET;
		GetEntDataVector(n_AssassinIndex, gVelocityOffset, v_asVelocity);
		TeleportEntity(n_AssassinSpriteIndex, v_asOrigin, NULL_VECTOR, v_asVelocity);
	}
	
	if ( n_TargetSpriteIndex > MaxClients && IsValidEntity(n_TargetSpriteIndex) && n_TargetIndex > 0 && n_TargetIndex <= MaxClients && IsClientInGame(n_TargetIndex) )
	{
		new Float:v_trOrigin[3], Float:v_trVelocity[3];
		
		GetClientEyePosition(n_TargetIndex, v_trOrigin);
		v_trOrigin[2] += SPRITE_OFFSET;
		GetEntDataVector(n_TargetIndex, gVelocityOffset, v_trVelocity);
		TeleportEntity(n_TargetSpriteIndex, v_trOrigin, NULL_VECTOR, v_trVelocity);
	}
}

/* ==================== /\ End Event Hooks /\ ==================== */

/* ==================== \/ Begin Custom Functions \/ ==================== */

/*	Restarts the round through the use of game_round_win entities. 0 = none, 2 = red, 3 = blu.
	Passing true as the second parameter forces a map reset.	*/
stock RoundWin(n_team = 0, b_resetmap = 0)	// Defaults: team = none, reset map = no
{	
	new n_gamerules;
	if ( (n_gamerules = FindEntityByClassname(-1, "tf_gamerules")) == -1 ) return;
	AcceptEntityInput(n_gamerules, "SetStalemateOnTimelimit 0");
	if ( n_WinIndex != -1 && IsValidEntity(n_WinIndex) ) AcceptEntityInput(n_WinIndex, "Kill");
	
	n_WinIndex = CreateEntityByName("game_round_win");
	if ( n_WinIndex == -1 ) return;	
	
	#if DEBUG == 1
	DispatchKeyValue(n_WinIndex, "targetname", "nfas_round_win");	// Give us a targetname for debugging purposes.
	#endif
	
	switch (n_team)
	{
		case TEAM_RED:	// Red is team ID 2
		{
			DispatchKeyValue(n_WinIndex, "TeamNum", "2");
		}
		case TEAM_BLUE:	// Blue is team ID 3
		{
			DispatchKeyValue(n_WinIndex, "TeamNum", "3");
		}
		default:	// If the team number isn't Red or Blu, set our team to none.
		{
			DispatchKeyValue(n_WinIndex, "TeamNum", "0");
		}
	}
	
	if ( b_resetmap )	// If we want to reset the map:
	{
		DispatchKeyValue(n_WinIndex, "force_map_reset", "1");	// Make sure the keyvalue is 1 (yes)
	}
	else	// Otherwise:
	{
		DispatchKeyValue(n_WinIndex, "force_map_reset", "0");	// Make sure the keyvalue is 0 (no)
	}
	
	DispatchSpawn(n_WinIndex);	// Spawn it.	
	AcceptEntityInput(n_WinIndex, "RoundWin");
	return;
}

/*	Chooses a random player from the specified team.
	If a second argument is specified, exclude the player with this index.
	If the third argument is non-zero, the function will try to return a random player who have line of sight to
	the player of this index. If there are none, it will return a random player as normal.
	Returns the client index of the player, or 0 if not found. */
stock RandomPlayerFromTeam(team, exclude = 0, los_index = 0)
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
	
	// First, do our stuff but don't return yet. If we do LOS checks later and come up blank, this value will be returned instead.
	
	// Return a random index from the array, less than or equal to the number of players we found. -1 to allow for the 0 array index.
	new n = GetRandomInt(0, n_playersfound-1);
	
	#if DEBUG == 1
	decl String:clientname[MAX_NAME_LENGTH + 1];
	clientname[0] = '\0';
	GetClientName(playersfound[n], clientname, sizeof(clientname));
	LogMessage("RPFT: Players found: %d Index chosen: %d in array, %d (%s)", n_playersfound, n, playersfound[n], clientname);
	#endif
	
	if ( los_index < 1 || los_index > MaxClients || !IsClientConnected(los_index) )	// If the LOS index is invalid:
	{		
		return playersfound[n];
	}
	
	// Now we want to iterate through each of the players in our found index and check to see if they have line of sight to
	// the player of the index specified in los_index.
	// We know that if we have got this far the player in los_index definitely exists, so we don't need to do more checks.
	// The process below will never add los_index to the array, since we don't trace to ourself.
	
	// I'd like to note that this method is crude in that it checks for a traceline from the queried player to the specified
	// player via checking to see whether the line between their two eye positions is blocked. This may disallow the choosing
	// of a player even if they can see the rest of the body of the target player.
	
	new los_playersfound[n_playersfound];	// Array to hold the indices of who we find
	new n_los_playersfound;					// The number of people we found
	new Float:eyepos_los_index[3];
	new Float:eyepos_los_i[3];
	GetClientEyePosition(los_index, eyepos_los_index);
	
	for ( new los_i = 0; los_i < n_playersfound; los_i++ )	// Starts at 0 instead of 1 since we're now going through an array
	{
		// First, make sure we're not tracing to ourself.
		if ( los_i != los_index )
		{		
			// Run a traceline measuring from the eye position of the player at los_i to the eye position of the player at los_index.
			GetClientEyePosition(los_i, eyepos_los_i);
			
			TR_TraceRayFilter(eyepos_los_i,				/*Start at the eyepos of the current queried player*/
								eyepos_los_index,		/*End at the eyepos of the specified player*/
								MASK_VISIBLE,			/*Anything that blocks player LOS*/
								RayType_EndPoint,		/*The ray goes between two points*/
								TraceRayDontHitSelf,	/*Function to make sure we don't hit ourself*/
								los_i);					/*The index of ourself to pass to the function*/
			
			// Now, work out if anything blocked the trace.
			// Only add the queried player to the array if nothing was hit.
			if ( !TR_DidHit(INVALID_HANDLE) )	// If there was nothing hit:
			{
				los_playersfound[n_los_playersfound] = los_i;	// Add the client index to the array.
				n_los_playersfound++;							// Increment our "players found" count and loop back.
			}
		}
	}
	
	// By now we will have a new array of players. If we didn't find anyone, return a random index from the players we found back
	// in the first loop.
	
	if ( n_los_playersfound >= 1 )	// If we found people:
	{
		// Return a random index from the array, less than or equal to the number of players we found. -1 to allow for the 0 array index.
		new los_n = GetRandomInt(0, n_los_playersfound-1);
		
		#if DEBUG == 1
		decl String:los_clientname[MAX_NAME_LENGTH + 1];
		los_clientname[0] = '\0';
		GetClientName(los_playersfound[los_n], los_clientname, sizeof(los_clientname));
		LogMessage("RPFT (LOS): Players found: %d Index chosen: %d in array, %d (%s)", n_los_playersfound, los_n, los_playersfound[los_n], los_clientname);
		#endif
		
		return playersfound[los_n];
	}
	else	// If we found no-one:
	{
		return playersfound[n];
	}
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
	ModifyGlobalIndex(0, 0);
	ModifyGlobalIndex(1, 0);
}

/*	Changes the assassin/target indices and updates the relevant dependant systems.
	First argument is which index to change (0 = assassin, 1 = target).
	Second argument is the value to assign.
	
	ANY changes to n_AssassinIndex or n_TargetIndex should be performed through this function.*/
stock ModifyGlobalIndex(index, value)
{
	if ( index == 0 )	// If the index is 0 (assassin):
	{
		// Clear the buff condition on the previous assassin, if there was one.
		if ( n_AssassinIndex > 0 && n_AssassinIndex <= MaxClients && IsClientConnected(n_AssassinIndex) )
		{
			TF2_RemoveCondition(n_AssassinIndex, TFCond_Buffed);
			
			if ( timer_AssassinCondition != INVALID_HANDLE )
			{
				KillTimer(timer_AssassinCondition);	// Kill the timer if there is one.
				timer_AssassinCondition = INVALID_HANDLE;	// Set our handle back to invalid (this doesn't happen automatically, it seems).
			}
		}
		
		n_AssassinIndex = value;
		
		// If the index isn't 0 and the client is valid, set the buff condition on the new assassin.
		if ( n_AssassinIndex > 0 && n_AssassinIndex <= MaxClients && IsClientConnected(n_AssassinIndex) )
		{
			if ( IsPlayerAlive(n_AssassinIndex) )	// If the player's alive, set the buff.
			{
				TF2_AddCondition(n_AssassinIndex, TFCond_Buffed, 0.5);
			}
			
			// We still want to set the timer, even if the player isn't alive.
			timer_AssassinCondition = CreateTimer(0.5, TimerAssassinCondition, _, TIMER_REPEAT);
		}
	}
	else if (index == 1)	// If the index is 1 (target):
	{
		// Reset the render mode on the target player
		if ( n_TargetIndex > 0 && n_TargetIndex <= MaxClients )	// If they're valid:
		{
			SetEntityRenderColor(n_TargetIndex, 255, 255, 255, 255);	// (Assuming we can set render colour using just a client index) (Assuming one can simply RENDER COLOUR MORDOR)
		}
		
		n_TargetIndex = value;	// Assign the new target
		
		// Set the render mode on the target player
		if ( n_TargetIndex > 0 && n_TargetIndex <= MaxClients && GetConVarBool(cv_ColourTarget) )	// If they're valid and we should be colouring the target:
		{
			switch (GetClientTeam(n_TargetIndex))
			{
				case TEAM_RED:
				{
					SetEntityRenderColor(n_TargetIndex, 255, 58, 84, 255);
				}
				
				case TEAM_BLUE:
				{
					SetEntityRenderColor(n_TargetIndex, 50, 98, 255, 255);
				}
			}
		}
	}
	
	#if DEBUG == 1
	new String:debugassassin[MAX_NAME_LENGTH + 1];
	new String:debugtarget[MAX_NAME_LENGTH + 1];
	GetClientName(n_AssassinIndex, debugassassin, sizeof(debugassassin));
	GetClientName(n_TargetIndex, debugtarget, sizeof(debugtarget));
	LogMessage("[AS] Assassin: %s Target: %s", debugassassin, debugtarget);
	#endif
	
	// Update any systems that should update when an index changes.
	
	if ( timer_HUDMessageRefresh != INVALID_HANDLE )	// If the HUD message timer is still alive:
	{
		KillTimer(timer_HUDMessageRefresh);			// Kill the timer.
		timer_HUDMessageRefresh = INVALID_HANDLE;	// Reset the handle to invalid.
	}
	
	UpdateHUDMessages();
	timer_HUDMessageRefresh = CreateTimer(1.0, TimerHUDRefresh, _, TIMER_REPEAT);	// Set up the new timer.
	
	// Assign sprites
	SpriteAdmin();
}

#if DEBUG == 1
/*	Debug command to print the current client and target to the chat.	*/
public Action:Command_CheckIndices(client, args)
{	
	if ( !GetConVarBool(cv_PluginEnabled) ) return Plugin_Handled;	// If we're not enabled, don't do anything.
	// However, we still want to run this if we have too few players, since it will just return 0.
	
	if ( n_AssassinIndex > 0 )
	{
		new String:s_assassinname[MAX_NAME_LENGTH + 1];
		GetClientName(n_AssassinIndex, s_assassinname, sizeof(s_assassinname));
		PrintToChatAll("Assassin: %d (%s).", n_AssassinIndex, s_assassinname);
	}
	else
	{
		PrintToChatAll("No assassin assigned.");
	}
	
	if ( n_TargetIndex > 0 )
	{
		new String:s_targetname[MAX_NAME_LENGTH + 1];
		GetClientName(n_TargetIndex, s_targetname, sizeof(s_targetname));
		PrintToChatAll("Target: %d (%s).", n_TargetIndex, s_targetname);
	}
	else
	{
		PrintToChatAll("No target assigned.");
	}
	
	return Plugin_Handled;
}

/*	Debug command to print a long string of text at the specified point on the HUD.
	Used to check where to display the current assassin and target.*/
public Action:Command_TestMessage(client, args)
{
	new String:arg1[32], String:arg2[32];
	new Float:x = -1.0, Float:y = -1.0;	// Initialise our x and y vars to centre of screen.
	
	if (args >= 1 && GetCmdArg(1, arg1, sizeof(arg1)) && GetCmdArg(2, arg2, sizeof(arg2)))
	{
		x = StringToFloat(arg1);	// Convert the arguments to our x and y values.
		y = StringToFloat(arg2);
		
		if ( x > 1 )	x = 1.0;	// If the variables are out of range, clamp them.
		if ( x < 0 )	x = -1.0;
		if ( y > 1 )	y = 1.0;
		if ( y < 0 )	y = -1.0;
	}
	
	// Now draw our text.
	SetHudTextParams(x, y, 5.0, 255, 255, 255, 255, 0, 0.0, 0.2, 0.2);
	ShowHudText(client, -1, "Assassin: [X6] Border Than a Collie");
	
	return Plugin_Handled;
}

public Action:Command_TestKVParse(client, args)
{
	new String:arg1[32];
	
	if (args >= 1 && GetCmdArg(1, arg1, sizeof(arg1)) )
	{
		PrintToChatAll( "Weapon ID: %d, Modifier returned: %f", StringToInt(arg1), WeaponModifiers(true, StringToInt(arg1)) );
	}
}
#endif

/*	Timer continually called every 0.5s to re-apply the buffed condition on the assassin.
	This is to allow the assassin to stay buffed if another soldier on the team activates their buff banner,
	as this would otherwise disable the assassin buff condition when it finishes.
	Since the assassin index is always changed if something happens to the client who is the assassin,
	hopefully it's safe to use in this timer.	*/
public Action:TimerAssassinCondition(Handle:timer)
{
	// If the assassin index is valid, reset the condition on the assassin.
	if ( n_AssassinIndex > 0 && n_AssassinIndex <= MaxClients && IsClientConnected(n_AssassinIndex) && IsPlayerAlive(n_AssassinIndex) )
	{
		TF2_AddCondition(n_AssassinIndex, TFCond_Buffed, 0.5);
	}
	
	return Plugin_Handled;
}

/*	Updates the HUD for all clients concerning who is the assassin/target.
	This is called every time ModifyGlobalIndex() is called.	*/
stock UpdateHUDMessages()
{
	if ( !GetConVarBool(cv_PluginEnabled) ) return;	// If we're not enabled, return.
	
	new assassin_team;
	new target_team;
	
	if ( n_AssassinIndex > 0 && n_AssassinIndex <= MaxClients && IsClientConnected(n_AssassinIndex) ) assassin_team = GetClientTeam(n_AssassinIndex);
	if ( n_TargetIndex > 0 && n_TargetIndex <= MaxClients && IsClientConnected(n_TargetIndex) ) target_team = GetClientTeam(n_TargetIndex);
	
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
		
		if ( n_AssassinIndex > 0 && b_InRound )	// If we should display text:
		{
			
			// Display the text to all players.
			decl String:s_AssassinName[MAX_NAME_LENGTH + 1];
			s_AssassinName[0] = '\0';
			
			// Make sure our client is valid before we get their name.
			if ( n_AssassinIndex > 1 && n_AssassinIndex <= MaxClients )
			{
				if ( IsClientInGame(n_AssassinIndex) ) GetClientName(n_AssassinIndex, s_AssassinName, sizeof(s_AssassinName));
			}
			
			for ( new i_assassin = 1; i_assassin <= MaxClients; i_assassin++ )	// Iterate through the client indices
			{
				if ( IsClientInGame(i_assassin) )	// If the client is connected:
				{
					ShowSyncHudText(i_assassin, hs_Assassin, "%t %s", "as_assassin_is", s_AssassinName);
				}
			}
		}
		else	// Otherwise, hide any text.
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
		
		if ( n_TargetIndex > 0 && b_InRound )	// If we should display text:
		{			
			// Display the text to all players.
			decl String:s_TargetName[MAX_NAME_LENGTH + 1];
			s_TargetName[0] = '\0';
			
			// Make sure our client is valid before we get their name.
			if ( n_TargetIndex > 1 && n_TargetIndex <= MaxClients )
			{
				if ( IsClientInGame(n_TargetIndex) ) GetClientName(n_TargetIndex, s_TargetName, sizeof(s_TargetName));
			}
			
			for ( new i_target= 1; i_target <= MaxClients; i_target++ )	// Iterate through the client indices
			{
				if ( IsClientInGame(i_target) )	// If the client is connected:
				{
					ShowSyncHudText(i_target, hs_Target, "%t %s", "as_target_is", s_TargetName);
				}
			}
		}
		else	// Otherwise, hide any text.
		{			
			// Clear HUD sync for all players
			ClearSyncHUDTextAll(hs_Target);
		}
	}
}

/*	Timer called once a second to update the HUD messages.
	If ModifyClientIndex is called, it will close this timer if it's running, execute the impending UpdateHUDMessages
	and then set up the timer again.	*/
public Action:TimerHUDRefresh(Handle:timer)
{
	UpdateHUDMessages();
	
	return Plugin_Continue;
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

/*	Trace function to exclude tracelines from hitting the player they emerge from.	*/
public bool:TraceRayDontHitSelf(entity, mask, any:data)
{
 	if(entity == data) // Check if the TraceRay hit the player.
 	{
 		return false; // Don't let the entity be hit.
 	}
 
 	return true; // It didn't hit itself.
}

/*	Called on ModifyGlobalIndex to deal with the display of sprites above the assassin and target.	*/
stock SpriteAdmin()
{
	// If n_Assassin/TargetSpriteCIndex are between 1 and MaxClients inclusive, we know the sprite is assigned to a player
	// of this index. When the index is set to zero, we know the sprite doesn't exist.
	
	// If the assassin/target CIndex is non-zero but isn't the same as the global assassin/target, we know that the sprite is
	// assigned to a player it should no longer be (ie. the assassin/target has changed) and so should be killed. After the
	// sprite is killed, the CIndex is set to zero.
	
	// Then, when deciding whether to create a new sprite, if the CIndex is zero but the assassin/target index is between 1 and
	// MaxClients inclusive (and the assassin/target is alive) then a new sprite should be created. If the assassin/target is
	// not alive, a check will be performed on respawn to see if the sprite should be created.
	
	// If the assassin sprite is no longer assigned to the assassin:
	if ( n_AssassinSpriteCIndex > 0 && n_AssassinSpriteCIndex != n_AssassinIndex )
	{
		if ( n_AssassinSpriteIndex > MaxClients && IsValidEntity(n_AssassinSpriteIndex) )	// If the sprite entity exists
		{
			AcceptEntityInput(n_AssassinSpriteIndex, "Kill");	// Kill the sprite.
			n_AssassinSpriteIndex = 0;							// Set its entindex to 0.
			n_AssassinSpriteCIndex = 0;							// Set the currently assigned player index to 0.
		}
	}
	
	// If the target sprite is no longer assigned to the target:
	if ( n_TargetSpriteCIndex > 0 && n_TargetSpriteCIndex != n_TargetIndex )
	{
		if ( n_TargetSpriteIndex > MaxClients && IsValidEntity(n_TargetSpriteIndex) )	// If the sprite entity exists
		{
			AcceptEntityInput(n_TargetSpriteIndex, "Kill");	// Kill the sprite.
			n_TargetSpriteIndex = 0;						// Reset its entindex to 0.
			n_TargetSpriteCIndex = 0;						// Reset the currently assigned player index to 0.
		}
	}
	
	// Now decide whether we should create a new sprite.
	
	if ( n_AssassinSpriteCIndex <= 0 && n_AssassinIndex > 0 && n_AssassinIndex <= MaxClients && IsPlayerAlive(n_AssassinIndex) )	// If the CIndex is 0 but the assassin index is valid:
	{
		CreateSprite(n_AssassinIndex, false);	// false = assassin
	}
	
	if ( n_TargetSpriteCIndex <= 0 && n_TargetIndex > 0 && n_TargetIndex <= MaxClients && IsPlayerAlive(n_TargetIndex) )	// If the CIndex is 0 but the target index is valid:
	{
		CreateSprite(n_TargetIndex, true);	// true = target
	}
}

/*	Creates a sprite above the head of the specified player.
	Second argument specifies the sprite type (false = assassin, true = target).	*/
stock CreateSprite(client, bool:type)
{
	if ( IsPlayerAlive(client) )	// If the player is alive:
	{
		// Name the client for parenting purposes.
		// Here we use a UserID since these are much more likely to be unique than a client index.
		new String:s_ClientTargetname[64]; 
		Format(s_ClientTargetname, sizeof(s_ClientTargetname), "client%i", GetClientUserId(client));
		DispatchKeyValue(client, "targetname", s_ClientTargetname);
		
		new Float:v_ClientOrigin[3];
		GetClientAbsOrigin(client, v_ClientOrigin);
		v_ClientOrigin[2] += SPRITE_OFFSET;	// Set our Z (vertical) offset.
		
		// Create the sprite.
		new sprite = CreateEntityByName("env_sprite_oriented");
		
		if ( sprite )	// If creation succeeded:
		{
			decl String:spritepath[128];
			
			if ( !type )	// If type is 0 (assassin):
			{
				if ( GetConVarBool(cv_NoZSprites) )
				{
					Format(spritepath, sizeof(spritepath), "%s.vmt", ASSASSIN_SPRITE_Z_PATH);
				}
				else
				{
					Format(spritepath, sizeof(spritepath), "%s.vmt", ASSASSIN_SPRITE_PATH);
				}
			}
			else	// If type is 1 (target):
			{
				if ( GetConVarBool(cv_NoZSprites) )
				{
					Format(spritepath, sizeof(spritepath), "%s.vmt", TARGET_SPRITE_Z_PATH);
				}
				else
				{
					Format(spritepath, sizeof(spritepath), "%s.vmt", TARGET_SPRITE_PATH);
				}
			}
			
			DispatchKeyValue(sprite, "model", spritepath);
			DispatchKeyValue(sprite, "classname", "env_sprite_oriented");
			DispatchKeyValue(sprite, "spawnflags", "1");
			DispatchKeyValue(sprite, "scale", "0.1");
			DispatchKeyValue(sprite, "rendermode", "1");
			DispatchKeyValue(sprite, "rendercolor", "255 255 255");
			
			if ( !type ) DispatchKeyValue(sprite, "targetname", "assassin_sprite");	// Assassin sprite name
			else DispatchKeyValue(sprite, "targetname", "target_sprite");			// Target sprite name
			
			DispatchKeyValue(sprite, "parentname", s_ClientTargetname);
			DispatchSpawn(sprite);
			
			TeleportEntity(sprite, v_ClientOrigin, NULL_VECTOR, NULL_VECTOR);	// Place our sprite at the player.
			
			if ( !type )	// If assassin:
			{
				n_AssassinSpriteIndex = sprite;		// Set our global sprite index var to the index of the new sprite.
				n_AssassinSpriteCIndex = client;	// Record the player the sprite is now assigned to.
			}
			else	// If target:
			{
				n_TargetSpriteIndex = sprite;		// Set our global sprite index var to the index of the new sprite.
				n_TargetSpriteCIndex = client;		// Record the player the sprite is now assigned to.
			}
		}
	}
}

/*	Handles reading and writing weapon score modifier data.
	If read = false, the weapons modifier file will be parsed and the info put into the two static arrays. This should
	only be done once OnPluginStart since it's quite an intensive operation. Returns 1.0 on success, 0.0 on failure.
	If read = true, the weapon ID specified will be checked against the arrays and the score modifier value returned. If no modifier
	value was specified in the file, 1.0 will be returned (no change in the score).
	Note that this function should be called SPARINGLY. Make sure that read-false is only called OnPluginStart and read-true only
	called when the assassin kills the target (or vice-versa), as these are the only times we'll need to be checking weapon
	modifiers.	*/
stock Float:WeaponModifiers(bool:read = true, n_WeaponID = -1)
{
	/*	-- The process of applying weapon modifiers --
	* 
	* This was quite a system to devise, so it needs some explanation (also for my own reference).
	* 
	* I wanted to minimise the need to update this part of the plugin every single time Valve updated TF2 with new weapons and
	* items. In an ideal scenario, the player_death event could pass any weapon ID to the scoring function (ie. any integer
	* whatsoever) and it would be handled: if there was an entry in the configuration file that matched the weapon ID, the
	* specified score modifier would be applied, and if not it would be ignored (treated as 1). Looping through the file
	* on each and every kill was not an option, due to the intensity of the KeyValues operations, so I decided the best way
	* to deal with the file would be to load it when the plugin started and store the values in an array.
	* 
	* However, the problem arose as to what size the array should be. With potentially hundreds of different weapons the array
	* would need to be fairly large, and if I just hardcoded a top limit (of, say, 512 indices) then this would need to be
	* changed if Valve ever breached that amount of weapons (unlikely but, considering the way things are going, probably
	* possible). It would also be a tremendous waste of array indices if the server operator only had a handful of weapon
	* modifiers set, as the plugin would end up dimensioning an array of several hundred indices when only 10 were used.
	* 
	* Furthermore, there was a problem with decl'ing this type of array. I wanted the weapon ID to be handed straight over to
	* the array, so the modifier value for a weapon would be at the array index [weaponID - 1], but if the array was declared
	* using decl then it was possible for a weapon that wasn't specified in the KeyValues file to be passed over and the plugin
	* would attempt to access a garbage index. Finally, using a dynamic array also seemed to be out of the question since
	* dynamic arrays could only exist at local scope and the weapon modifier array needed to be persistent.
	* 
	* The system I have eventually chosen is to have two local-static dynamic arrays, WeaponID[] and WeaponModifier[]. When
	* a weapon ID is passed to the function, the indices of WeaponID are cycled through first and the values checked against
	* the given ID. When a match is found, the corresponding index number in WeaponModifier will contain the correct weapon
	* modifier float for the given weapon. Because the arrays are dynamic, they will only use the number of indices required
	* (the number of entries in the KeyValues file). This way, I can keep the size of the array down and (hopefully) never
	* need to manually update it when the game updates.	*/
	
	static Handle:WeaponID = INVALID_HANDLE;		// Dynamic aray to hold weapon IDs.
	static Handle:WeaponModifier = INVALID_HANDLE;	// Dynamic array to hold weapon score modifiers.
	static n_SubKeys;								// Holds the number of sub-keys we have.
	static bool:FileRead;							// After the KeyValues file has been read this flag is set to true, allowing reading from the arrays.
	
	if ( !read )	// If we're parsing:
	{
		/*	The KeyValues file is found at scripts/assassination/weaponmodifiers.txt
		* 	Format of the file should be as follows:
		* 
		* 	"weapons"
		* 	{
		* 		"[integersubkey]"
		* 		{
		* 			"weaponid"	"[weaponID]"
		* 			"modifier"	"[modifierfloat]"
		* 		}
		* 	}
		* 
		* 	[integersubkey] - An integer to group together the weapon ID and modifier. It's recommended to use integers increasing from 0. This value is not stored by the code.
		* 	[weaponID] 		- The ID of the weapon the modifier is tied to. This ID comes from TF2 Content GCF: tf/scripts/items/items_game.txt.
		* 	[modifierfloat]	- The points modifier for the weapon. This can be anything >= 0. If less than 0, the value will be treated as 0.
		* 					If the value is not formatted as a float (ie. not something like "2.0"), the function will return an error and treat the value as 1.
		*/
		
		if ( FileRead )	// If we've already read the file:
		{
			LogMessage("[AS] KeyValues file attempting to be re-parsed, which is not allowed.");			
			return 0.0;
		}
		
		new Handle:KV = CreateKeyValues("weapons");	// "weapons" is our root node.
		
		// Assuming the file path is from the tf directory?
		if ( !FileToKeyValues(KV, "scripts/assassination/weaponmodifiers.txt") )	// If the operation failed:
		{
			LogMessage("[AS] FileToKeyValues failed for scripts/assassination/weaponmodifiers.txt");
			return 0.0;
		}
		
		// If we've got this far, the file exists and is open.
		// We now need to check how many sub-keys are in the file and dimension our dynamic arrays accordingly.
		
		if ( !KvGotoFirstSubKey(KV) )	// If there are no sub-keys:
		{
			LogMessage("[AS] No first sub-key found in KeyValues file.");
		}
		else	// If there are sub-keys:
		{
			do
			{
				n_SubKeys++;
				
				#if DEBUG == 1
					LogMessage("Sub-key count: %d", n_SubKeys);
				#endif
			} while ( KvGotoNextKey(KV) );	// Increment n_SubKeys while the next key exists.
		}
		
		LogMessage("[AS] Number of sub-keys (weapon IDs) in file: %d", n_SubKeys);
		
		// At this point the number of keys we have (the number of weapon IDs in the file) will be held in n_SubKeys.
		// This will include if the same weapon ID occurs twice. When checking through the arrays later on, this should
		// mean that the first value matching the weapon ID will be returned, thus rendering the later instamces useless.
		
		if ( n_SubKeys <= 0 )	// If no sub-keys were found
		{
			// Dimension our arrays to hold no useful data.
			// This will mean that if the arrays are checked, the weapon ID will not match the values and will be ignored.
			
			WeaponID = CreateArray(1, 1);
			SetArrayCell(WeaponID, 0, -2);
			WeaponModifier = CreateArray(1, 1);
			SetArrayCell(WeaponModifier, 0, 1);
		}
		else	// If n_SubKeys > 0:
		{
			// Dimension our arrays to hold the number of values we found.
			if ( WeaponID == INVALID_HANDLE ) WeaponID = CreateArray(1, n_SubKeys);
			if ( WeaponModifier == INVALID_HANDLE ) WeaponModifier = CreateArray(1, n_SubKeys);
			
			// Go through the KeyValues file again and input the weapon IDs and modifier values into the arrays.
			KvRewind(KV);
			KvGotoFirstSubKey(KV);
			
			for ( new i = 1; i <= n_SubKeys; i++ )
			{
				SetArrayCell(WeaponID, i-1, KvGetNum(KV, "weaponid", -2));	// Put the weapon ID into the array.
				if ( GetArrayCell(WeaponID, i-1) < 0 ) SetArrayCell(WeaponID, i-1, -2);	// If the weapon ID is less than 0, set to an invalid index.
				
				#if DEBUG == 1
					LogMessage("Weapon ID key %d put into WeaponID[%d]", GetArrayCell(WeaponID, i-1), i-1);
				#endif
				
				SetArrayCell(WeaponModifier, i-1, KvGetFloat(KV, "modifier", 1.0));				
				if ( GetArrayCell(WeaponModifier, i-1) < 0.0 ) SetArrayCell(WeaponModifier, i-1, 0.0);	// If the modifier is less than 0, set to zero.
				
				#if DEBUG == 1
					LogMessage("Weapon modifier value %f put into WeaponModifier[%d]", GetArrayCell(WeaponModifier, i-1), i-1);
				#endif
				
				if ( i < n_SubKeys ) KvGotoNextKey(KV);	// If we're not on the last key, go to the next one.
			}
		}
		
		// Now all of the weapon IDs and modifiers have been put into their relevant arrays.
		// n_SubKeys holds the total number of weapon IDs (and n_SubKeys - 1 consequently the number of array indices we should
		// check).
		
		CloseHandle(KV);	// Close the KeyValues structure.
		FileRead = true;	// File has been parsed.
		return 1.0;			// We're finished.
	}
	else
	{
		if ( FileRead )	// As long as we've already read the file:
		{
			// If we didn't have any weapon IDs, return 1 (no modifier).
			if ( n_SubKeys <= 0 )
			{
				#if DEBUG == 1
					LogMessage("No. of sub-keys = 0. Return: 1.0");
				#endif
				return 1.0;
			}
			
			// If either array is invalid, return 1.0.
			if ( WeaponID == INVALID_HANDLE || WeaponModifier == INVALID_HANDLE )
			{
				#if DEBUG == 1
					LogMessage("WeaponID or WeaponModifier array is invalid. Return: 1.0");
				#endif
				return 1.0;
			}
			
			// If the passed weapon ID is < -1, reset to -1 so we don't accidentally get a match in the ID array.
			if ( n_WeaponID < -1 ) n_WeaponID = -1;
			
			// Now check through the Weapon ID array and see if the passed weapon ID can be found.
			for ( new j; j <= n_SubKeys; j++ )
			{
				// If the weapon IDs match, return the corresponding modifier.
				if ( GetArrayCell(WeaponID, j-1) == n_WeaponID )
				{
					#if DEBUG == 1
						LogMessage("Match: weapon ID %d matches array index %d of value %d", n_WeaponID, j-1, GetArrayCell(WeaponModifier, j-1));
					#endif
					return GetArrayCell(WeaponModifier, j-1);
				}
			}
			
			// If there were no matches, return 1.0.
			#if DEBUG == 1
				LogMessage("No match found for weapon ID %d, return: 1.0", n_WeaponID);
			#endif
			return 1.0;
			
			
		}
		else
		{
			#if DEBUG == 1
				LogMessage("Check ID called before file has been parsed. Return: 1.0");
			#endif
			return 1.0;	// Otherwise, return 1 (no modifier).
		}
	}
}

public Action:TimerAsTrCheck(Handle:timer)
{
	if ( GetTeamClientCount(TEAM_RED) >= 2 && GetTeamClientCount(TEAM_BLUE) >= 2 )
	{
		if ( n_AssassinIndex <= 0 ) ModifyGlobalIndex(0, RandomPlayerFromTeam(TEAM_RED));
		if ( n_TargetIndex <= 0 ) ModifyGlobalIndex(1, RandomPlayerFromTeam(TEAM_BLUE));
	}
}

/* ==================== /\ End Custom Functions /\ ==================== */

/*	If you've made it this far, I congratulate you. I'll just leave this here.
*
*	                     _
*						/ \
*				        |__\__   _
*						/^^^^^-_//
*				 _     /^^^^^^^^.¬.
*               | --__/^^^^^^^^^\^_.
*               |     (^^^^^^^|\ \.`
*               :    / /_-_.^^\__\\
*                \   /;//  \^^/ \ \.
*              , '_ | |,    \|,. \ |
*             ///" -> (|/--. /_|  ||
*            //  /---,`||__|  &/  \|
*          \.!" "  -_\ ( Y&¬ / \. ||
*           \        :~          \|`
*         ,-"     __  :       .---|
*        ,"/%T|  /%|\.\\      i&&/
*        c//,|\  ,"\ \ J\.       |
*        ,"//|:^ / \(:.H##\_  `-/
*        | "t~\:_;--\ (|\__ -\_/\
*        |j||(#   (# (|| \ -L__Y/
*      . /AY|        ||"  |#|.##/|
*      -¬ ( | __     |V   :###\j_\.
*     /   ,\\ \/     /"    :###\/#x
*    | ,_=__;\      /i;\    \###\#\\
*    :/"     \\,_ ,/|//:.    -,##\#\
*             ¬\-/"|%,-\;\   :C###_#.
*             ,,A   |:"##:-\. |###\..
*           ,//|[_--"-/-_####su####\-
*          ,"" ,\__/ //-\.#########j.|\
*          |(   -   //   |#\########\|:.
*          Y       ,/    |##\########L/X
*         /|       ;"    ,##\#########\,
*         " |      |     /###\#########\
*        /,--_.    |    ;####\##########|
*        ">/ ,\.__-"    |#####\#########|
*       / _--T-(:~;|    "######\########|
*       "/ " (~.)~/    /#######j.#######j
*      /"    (~\~;_    ;########\#######|
*      |   (~\~\/"~\  ,|######## \######|
*      \   \~,/~/~/ \ /|##########\_###,
*      \   \/ \~~;|   (|####,_/###_ ---"
*       ---/   \~|(  ,"|#_-~####_-
*          |    \~(  / |#####_/"~~~\
*         /      :-_/  |_---"~~~~~~~|
* 
* </twokindsfanart>
*/