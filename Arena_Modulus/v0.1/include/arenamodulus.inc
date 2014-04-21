// Arena Modulus include file

#if defined _arenamodulus_included
 #endinput
#endif
#define _arenamodulus_included

// Team integers
#define TEAM_INVALID		-1
#define TEAM_UNASSIGNED		0
#define TEAM_SPECTATOR		1
#define TEAM_RED			2
#define TEAM_BLUE			3

// Flags for possible states.
// Higher flags take priority over lower flags.
// These are used to control which functionality should be active.
// If no flags are active, the plugin is running normally.
// Flags can also be checked with inequalities.
#define STATE_NO_ACTIVITY				4	// Plugin has been loaded on an active server, don't do anything until a map change.
#define STATE_DISABLED					2	// Plugin is disabled via ConVar.
#define STATE_NOT_IN_ROUND				1	// Not currently in a round.

/*
	Flag usage:
	STATE_NO_ACTIVITY: Set on plugin start, if IsServerProcessing returns true. This means that if the plugin is loaded
		while a match is taking place, it will not activate. This flag is only (and always) reset OnMapStart, meaning that the
		plugin will begin functioning after a map change. If the plugin is loaded as the server starts, IsServerProcessing will
		return false and the flag will not be set. This flag prevents any plugin hooks at all from running.
	STATE_DISABLED: Set when the ConVar nfas_enabled is set to 0, and cleared when it is set to 1. This flag will also
		prevent any plugin hooks from running, apart from CvarChange.
*/

// Enum that holds the IDs of each mode.
// New modes must register their ID here.
enum en_Modes
{
	MODE_NONE = 0,
	MODE_LIGHT_STING,
	MODE_WETWORK,
	MODE_SENTRIES,
	MODE_TARGETS,
	MODE_BOSS_BATTLE,
	MODE_SHIELD_BASH,
	MODE_SANDVICH_BOMBS
};

// Properties for each mode.
// These link to the mode's phrase tag in the translations file.
new String:Mode_Name_Trans[en_Modes][65];			// Mode name. Maximum length is 64 characters. Translation max length 64 characters.
new String:Mode_Description_Trans[en_Modes][65];	// Mode description. Maximum length is 64 characters. Translation max length 128 characters.

Mode_Name_Trans[MODE_NONE] = "am_name_normal_round";
Mode_Description_Trans[MODE_NONE] = "am_desc_normal_round";

// Minimum number of players required for the mode to run. Index [ModeID][TEAM-2] is the team-specific count.
// If the team counts in-game are >= these values, the mode will run.
// If there is no miminum player count, set both values to 1.
// If there is a general minimum player count which is not team-specific, set the [ModeID][0] index to -1 and
// the [1] index to the total player count.
// If either team has 0 players, the mode will not be run regardless of these settings.

new Mode_MinimumPlayers[en_Modes][2];

new ModeQueue[en_Modes-1];		// Array that holds the queue of modes to play, - 1 to ignore MODE_NONE.