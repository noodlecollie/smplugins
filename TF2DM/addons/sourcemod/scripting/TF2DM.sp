/*
  _______ ______ ___    _____  __  __ 
 |__   __|  ____|__ \  |  __ \|  \/  |
    | |  | |__     ) | | |  | | \  / |
    | |  |  __|   / /  | |  | | |\/| |
    | |  | |     / /_  | |__| | |  | |
    |_|  |_|    |____| |_____/|_|  |_|

    A deathmatch game mode for TF2.
    Created by [X6] Herbius on 05/11/12 at 14:02.
*/

/* Reference:
enum
{
	TFWeaponSlot_Primary,
	TFWeaponSlot_Secondary,
	TFWeaponSlot_Melee,
	TFWeaponSlot_Grenade,
	TFWeaponSlot_Building,
	TFWeaponSlot_PDA,
	TFWeaponSlot_Item1,
	TFWeaponSlot_Item2	
};

enum TFClassType
{
	TFClass_Unknown = 0,
	TFClass_Scout,
	TFClass_Sniper,
	TFClass_Soldier,
	TFClass_DemoMan,
	TFClass_Medic,
	TFClass_Heavy,
	TFClass_Pyro,
	TFClass_Spy,
	TFClass_Engineer
};

enum TFTeam
{
	TFTeam_Unassigned = 0,
	TFTeam_Spectator = 1,
	TFTeam_Red = 2,
	TFTeam_Blue = 3	
};
*/

#include <sourcemod>
#include <TF2DM>

#pragma semicolon 1

#define PLUGIN_NAME			"Team Fortress 2: Deathmatch"
#define PLUGIN_AUTHOR		"[X6] Herbius"
#define PLUGIN_DESCRIPTION	"Deathmatch-style gameplay with weapon pickups and power-ups."
#define PLUGIN_VERSION		"1.0.0.0"
#define PLUGIN_URL			"http://x6herbius.com/"

// Debug defines
#define DEBUG_ITEMPARSE	1	// Debugging parsing items_game.txt

// State flags
// Control what aspects of the plugin will run.
#define STATE_DISABLED	1	// Plugin is disabled via convar. No gameplay-modifying activity will occur.

// Weapon data defines
#define MAX_WEAPONS		2048
#define MAX_PREFABS		128

// ConVars
new Handle:cv_PluginEnabled = INVALID_HANDLE;	// Enables or disables the plugin.
new Handle:cv_Debug = INVALID_HANDLE;			// Enables or disables debugging using debug flags.

// Weapon data
new g_IDRedirect[MAX_WEAPONS] = {-1, ...};		// Holds the index at which the weapon's data can be found.

// Global variables
bool:exSDKHooks = false;	// True if SDKHooks exists.

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
	// Begin initialisation.
	LogMessage("=== %s v%s ===", PLUGIN_NAME, PLUGIN_VERSION);
	
	// Check for libraries.
	exSDKHooks = LibraryExists("sdkhooks");
	
	if ( !exSDKHooks ) SetFailState("TF2DM could not find SDKHooks, plugin will not run.");
	
	LoadTranslations("TF2DM/TF2DM_phrases");
	LoadTranslations("common.phrases");
	AutoExecConfig(true, "TF2DM", "sourcemod/TF2DM");
	
	// Plugin version convar
	CreateConVar("tf2dm_version", PLUGIN_VERSION, "Plugin version.", FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_DONTRECORD);
	
	// ConVars
	cv_PluginEnabled  = CreateConVar("tf2dm_enabled",
										"1",
										"Enables or disables the plugin.",
										FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
										true,
										0.0,
										true,
										1.0);
	
	cv_Debug  = CreateConVar("tf2dm_debug",
										"0",
										"Enables or disables debugging using debug flags.",
										FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_DONTRECORD,
										true,
										0.0);
}

/*	Checks which ConVar has changed and performs the relevant actions.	*/
public CvarChange( Handle:convar, const String:oldValue[], const String:newValue[])
{
	if ( convar == cv_PluginEnabled ) PluginEnabledStateChanged(GetConVarBool(cv_PluginEnabled));
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
	}
	else
	{
		// If we're already disabled, do nothing.
		if ( g_PluginState & STATE_DISABLED == STATE_DISABLED ) return;
		
		g_PluginState |= STATE_DISABLED;	// Set the disabled flag.
	}
}

/*	If dependant libraries are unloaded, stop the plugin.	*/
public OnLibraryRemoved(const String:name[])
{
	// SDKHooks
	if ( StrEqual(name, "sdkhooks") )
	{
		// Clean everything up.
		Cleanup(EndAll);
		SetFailState("TF2DM detected SDKHooks unloading, plugin will not continue.");
	}
}

/*	Keeps cleanup tasks together.	*/
stock Cleanup(CleanupState:mode)
{
	switch (mode)
	{
		case CLEANUP_ROUNDSTART:	// Called even if plugin is disabled, so don't put anything important here.
		{
			
		}
		
		case CLEANUP_ROUNDEND:
		{
			
		}
		
		case CLEANUP_FIRSTSTART:
		{
			
		}
		
		case CLEANUP_ENDALL:	// Called when the plugin is unloaded or is disabled.
		{
			
		}
		
		case CLEANUP_MAPSTART:
		{
			
		}
		
		case CLEANUP_MAPEND:
		{
			
		}
	}
}

/*	Parses items_game.txt and loads weapon information. This should probably be considered expensive.	*/
stock bool:ParseItemFile()
{
	// Create a keyvalues handle.
	new Handle:KV = CreateKeyValues("items_game");
	
	// Open the file.
	if ( !FileToKeyValues(KV, "scripts/items/items_game.txt") )
	{
		LogError("items_game.txt unable to be located for parsing!");
		CloseHandle(KV);
		return false;
	}
	
	// Go to the first sub-key.
	if ( !KvGotoFirstSubKey(KV) )
	{
		LogError("items_game.txt does not contain any sub-keys!");
		CloseHandle(KV);
		return false;
	}
	
	// Search this sub-key.
	do
	{
		// Get its name.
		decl String:skName[128];
		KvGetSectionName(KV, skName, sizeof(skName))
		
		if ( cv_Debug & DEBUG_ITEMPARSE ) LogMessage("Sub-key: %s", skName);
		
		// ========== Prefabs ==========
		if ( StrEqual(skName, "prefabs") )
		{
			// Weapons can be based off prefabs, which means that when a weapon entry comes around
			// we may not be able to get the class information directly from it.
			// We will need to record each prefab which references a class in order to use it to
			// determine future weapon class restrictions.
			// Weapon prefabs include:
			// "craft_class"	"weapon"
			
			// Go to the first prefab sub-key.
			if ( KvGotoFirstSubKey(KV) )
			{
				do
				{
					// Get its name.
					decl String:pskName[128];
					KvGetSectionName(KV, pskName, sizeof(pskName))
					
					if ( cv_Debug & DEBUG_ITEMPARSE ) LogMessage("Prefab sub-key: %s", pskName);
				}
				while ( KvGotoNextKey(KV) );
			}
		}
		// =============================
	}
	while ( KvGotoNextKey(KV) );
	
	CloseHandle(KV)
	return true;
}