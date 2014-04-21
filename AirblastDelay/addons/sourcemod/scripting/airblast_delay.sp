#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

#pragma semicolon 1

#define PLUGIN_NAME 		"Airblast delay"
#define PLUGIN_AUTHOR		"[X6] Herbius"
#define PLUGIN_DESCRIPTION	"Allows modification of the delay between Pyro airblasts."
#define PLUGIN_VERSION		"1.0.0.0"
#define PLUGIN_URL			"http://x6herbius.com"

#define COMPILE_DEBUG 0

public Plugin:myinfo = 
{
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = PLUGIN_URL
}

// The property on a flamethrower entity that contains the next seconary attack time is m_flNextSecondaryAttack.
// Hopefully we can modify this when we need to.
// On weapon prethink, we should check to see whether next secondary attack has changed since our last check.
// If it has, we have alt-fired. If we have alt-fired, apply the delay delta to the recorded time and cache this.

// Cvars:
new Handle:cv_PluginEnabled = INVALID_HANDLE;
new Handle:cv_Delay = INVALID_HANDLE;

// Data table:
#define MAX_ENTRIES 64 // Old value: MAXCLIENTS+1
new Float:flClientFlamethrower[MAX_ENTRIES] = {0.0, ...};	// Table of next secondary fire times for flamethrowers.

new entityIndices[MAX_ENTRIES] = {-1, ...};					// Records which entities have been SDKHook'd.
new registeredIndices = 0;

new Handle:timer_Check = INVALID_HANDLE;

public OnPluginStart()
{
	LogMessage("===== Airblast delay plugin active =====");

	// Perhaps the prefix "abdl" is unfortunate...
	cv_PluginEnabled  = CreateConVar("abdl_enabled",
										"1",
										"Enables or disables the plugin.",
										FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
										true,
										0.0,
										true,
										1.0);

	cv_Delay  = CreateConVar("abdl_delay",
										"0.0",
										"The amount of extra delay to apply to airblasting, in seconds. Can be negative.",
										FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE);
}

public OnMapStart()
{
	ClearFloatTable();
	ClearEntityRegister();

	// Create the check timer.
	timer_Check = CreateTimer(0.1, Timer_CheckWeapons, _, TIMER_REPEAT);
}

public OnMapEnd()
{
	ClearFloatTable();
	ClearEntityRegister();

	// Kill the timer if it exists.
	if ( timer_Check != INVALID_HANDLE )
	{
		KillTimer(timer_Check);
		timer_Check = INVALID_HANDLE;
	}
}

public Flamethrower_PreThink(entity)
{
	if ( entity <= MaxClients ) return;
	if ( !GetConVarBool(cv_PluginEnabled) ) return;	// Don't continue if we're disabled.

	//#if COMPILE_DEBUG != 0
	//PrintToChatAll("Think for %d", entity);
	//#endif

	// Find the entry for this weapon in the tables. If it does not exist, don't go any further.
	new index = FindRegisteredEntity(entity);
	if ( index < 0 ) return;

	// Get the next secondary attack time.
	new Float:nextAttack = GetEntPropFloat(entity, Prop_Send, "m_flNextSecondaryAttack");

	if ( nextAttack == flClientFlamethrower[index] ) return;	// Value is the same as the one we have stored - return.

	#if COMPILE_DEBUG != 0
	PrintToChatAll("Flamethrower %d's next attack2 value %f differs to stored value of %f", entity, nextAttack, flClientFlamethrower[index]);
	#endif

	// If this is different to the stored time then it must have been updated by the game, implying that the player
	// has alt-fired. Update the time with our delta.
	new Float:delta = GetConVarFloat(cv_Delay);
	nextAttack += delta;
	if ( nextAttack < 0.0 ) nextAttack = 0.0;

	SetEntPropFloat(entity, Prop_Send, "m_flNextSecondaryAttack", nextAttack);
	flClientFlamethrower[index] = nextAttack;
}

public OnEntityCreated(entity, const String:classname[])
{
	// If this is a flamethrower, hook it.
	if ( strcmp(classname, "tf_weapon_flamethrower") == 0 )
	{
		#if COMPILE_DEBUG != 0
		PrintToChatAll("Hooking flamethrower entity %d.", entity);
		#endif

		// Previously we SDKHooked but this doesn't seem to work for PreThink, so trying something else...
		// if ( RegisterEntity(entity) )
		// {
		// 	new bool:success = SDKHookEx(entity, SDKHook_PreThink, Flamethrower_PreThink);

		// 	#if COMPILE_DEBUG != 0
		// 	PrintToChatAll("Hook success: %d", success);
		// 	#endif
		// }

		new bool:success = RegisterEntity(entity);

		#if COMPILE_DEBUG != 0
		PrintToChatAll("Register success: %d", success);	
		#endif
	}
}

public OnEntityDestroyed(entity)
{
	// If the entity is registered as hooked, unhook it.
	new i = FindRegisteredEntity(entity);
	if ( i >= 0 )
	{
		#if COMPILE_DEBUG != 0
		PrintToChatAll("Unhooking flamethrower entity %d", entity);
		#endif

		//SDKUnhook(entity, SDKHook_PreThink, Flamethrower_PreThink);
		RemoveIndex(i);
	}
}

stock bool:RegisterEntity(ent)
{
	if ( registeredIndices >= MAX_ENTRIES ) return false;

	entityIndices[registeredIndices] = ent;
	registeredIndices++;
	return true;
}

stock FindRegisteredEntity(const ent)
{
	for ( new i = 0; i < registeredIndices; i++ )
	{
		if ( entityIndices[i] == ent ) return i;
	}

	return -1;
}

stock RemoveIndex(index)
{
	if ( index < 0 || index >= MAX_ENTRIES ) return -1;

	new ret = entityIndices[index];
	for ( new i = index; i < registeredIndices-1; i++ )
	{
		entityIndices[i] = entityIndices[i+1];
	}

	entityIndices[registeredIndices] = -1;
	registeredIndices--;

	return ret;
}

stock UnregisterEntity(ent)
{
	if ( (new index = FindRegisteredEntity(ent)) >= 0 ) RemoveIndex(index);
}

stock ClearEntityRegister()
{
	for ( new i = 0; i < MAX_ENTRIES; i++ )
	{
		entityIndices[i] = -1;
	}

	registeredIndices = 0;
}

stock ClearFloatTable()
{
	for ( new i = 0; i < MAX_ENTRIES; i++ )
	{
		flClientFlamethrower[i] = 0.0;
	}
}

public Action:Timer_CheckWeapons(Handle:timer)
{
	if ( registeredIndices < 1 ) return Plugin_Continue;

	for ( new i = 0; i < registeredIndices; i++ )
	{
		Flamethrower_PreThink(entityIndices[i]);
	}

	return Plugin_Continue;
}