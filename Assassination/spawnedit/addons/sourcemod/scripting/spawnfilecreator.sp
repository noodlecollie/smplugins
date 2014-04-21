/*	To do:
	- Fix the crouch detection.	*/
	
// Removal/spawn load noises not working.
// Change echo text in edit cfg.
// Cancelling the finish command has no effect.
// As soon as I entered edit mode the spawn file disappeared. Something's wrong.
// Crouch = 4

/*
	Recent changes:
	- Damage applied to players if they are killed by a respawning player is now telefrag.
		- This function requires SDKHooks. If SDKHooks is not available, the player will suicide as in the previous version.
	- Method for choosing a spawn point can now be one of four things: random, random queued, nearest point, furthest point.
		- Random is the same as before, where a point is chosen completely at random.
		- Random queued is a random succession of all the active spawn points. When the ene of the queue is reached, it is reset back to the start.
			Queues are re-generated at the beginning of each round or via the admin command "dmspawn_regenerate_spawn_queue".
		- Nearest/furthest spawn points are calculated by which point has the nearest/furthest average distance to players. Once a spawn point
			has been chosen, it is excluded when deciding on the next point.
		- The ConVar "dmspawn_mode" chooses which mode to use. 0 = Random, 1 = Random queued, 2 = Nearest, 3 = Furthest.
	- Changed admin command permission flags to ADMFLAG_CONFIG (one level above the previous) to better reflect their intended usage.
	- Added sounds for extra feedback on actions.
*/

#include <sourcemod>
#include <keyvalues>
#include <sdktools>
#include <sdkhooks>
#include <tf2>

#define DEBUG		0
#pragma semicolon	1

#define PLUGIN_NAME 		"Deathmatch Spawn File Creator"
#define PLUGIN_AUTHOR		"[X6] Herbius"
#define PLUGIN_DESCRIPTION	"Creates and handles custom deathmatch spawns for Team Fortress 2."
#define PLUGIN_VERSION		"1.1.0.1"

#define MAX_SPAWN_POINTS	64

// Teams
#define TEAM_INVALID	-1
#define TEAM_UNASSIGNED	0
#define TEAM_SPECTATOR	1
#define TEAM_RED		2
#define TEAM_BLUE		3

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
#define SOUND_FINISH_SPAWNS		"vo/sniper_positivevocalization04.wav"
#define SOUND_CANCEL_SPAWNS		"vo/sniper_jeers01.wav"

// Variable declarations:
new g_PluginState;						// Holds the flags for the global plugin state.

new Float:Angles[MAX_SPAWN_POINTS][3];
new Float:Position[MAX_SPAWN_POINTS][3];
new TeamNum[MAX_SPAWN_POINTS];
new SpawnModelIndex[MAX_SPAWN_POINTS] = {-1, ...};
new NumPoints;								// Records the total number of spawn points in the file.
new String:FilePath[128];
new bool:b_SpawnsLoaded;
new Timelimit;								// Holds the server's mp_timelimit value.
new GlobalClient = -1;						// Holds the value of the client who is editing.
new bool:b_IsCrouching;						// Whether or not the above client is crouching.
//new bool:SDKHooks_Exists;					// Set to true in OnPluginStart if SDKHooks is available.

// ConVars:
new Handle:cv_PluginEnabled = INVALID_HANDLE;	// Enables or disables the plugin. Changing this while in-game will restart the map.
new Handle:cv_Resupply = INVALID_HANDLE;		// If 0, resupply cabinets will be disabled at the start of the map.
new Handle:cv_SpawnRadius = INVALID_HANDLE;		// Radius around spawn point in which to destroy objects/kill clients.
new Handle:cv_TeamTriggers = INVALID_HANDLE;	// If 0, team filters for spawn doors will be disabled.
new Handle:cv_SpawnMode = INVALID_HANDLE;		// Spawn mode. 0 = Random spawns, 1 = Random spawn queue, 2 = Spawn near players, 3 = Spawn away from players.

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
	
	//SDKHooks_Exists = LibraryExists("sdkhooks");
	
	CreateConVar("dmspawn_version", PLUGIN_VERSION, "Plugin version.", FCVAR_PLUGIN | FCVAR_NOTIFY);
	cv_PluginEnabled  = CreateConVar("dmspawn_enabled",
												"1",
												"Enables or disables the plugin. Changing this while in-game will restart the map.",
												FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
												true,
												0.0,
												true,
												1.0);
	
	cv_Resupply  = CreateConVar("dmspawn_resupply_enabled",
												"0",
												"If 0, resupply cabinets will be disabled at the start of the map.",
												FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
												true,
												0.0,
												true,
												1.0);
	cv_SpawnRadius  = CreateConVar("dmspawn_spawn_radius",
												"64",
												"Radius around spawn point in which to destroy objects/kill clients.",
												FCVAR_PLUGIN | FCVAR_ARCHIVE,
												true,
												1.0,
												true,
												128.0);
												
	cv_TeamTriggers  = CreateConVar("dmspawn_team_filters_enabled",
												"0",
												"If 0, team filters for spawn doors will be disabled.",
												FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
												true,
												0.0,
												true,
												1.0);
	
	cv_SpawnMode  = CreateConVar("dmspawn_mode",
												"0",
												"Spawn mode. 0 = Random spawns, 1 = Random spawn queue.",
												FCVAR_PLUGIN | FCVAR_NOTIFY | FCVAR_ARCHIVE,
												true,
												0.0,
												true,
												1.0);
	
	HookConVarChange(cv_PluginEnabled,	CvarChange);
	HookConVarChange(cv_SpawnMode,		CvarChange);
	
	HookEventEx("teamplay_round_start",		Event_RoundStart,	EventHookMode_Post);
	HookEventEx("player_spawn",				Event_Spawn,		EventHookMode_Post);
	HookEventEx("player_team",				Event_TeamsChange,	EventHookMode_Post);
	
	RegAdminCmd("dmspawn_edit",						Command_Edit,		ADMFLAG_CONFIG, "Enables spawn edit mode.");
	RegAdminCmd("dmspawn_load",						Command_Load,		ADMFLAG_CONFIG,	"Loads the spawn points from the map spawn file.");
	RegAdminCmd("dmspawn_add",						Command_Add,		ADMFLAG_CONFIG,	"Adds a spawn point at the player's current position.");
	RegAdminCmd("dmspawn_remove",					Command_Remove,		ADMFLAG_CONFIG,	"Removes the spawn point the player is standing beside.");
	RegAdminCmd("dmspawn_finish",					Command_Finish,		ADMFLAG_CONFIG,	"Exports the current spawn points to the spawn file and exits edit mode.");
	RegAdminCmd("dmspawn_dump_all",					Command_DumpAll,	ADMFLAG_CONFIG, "Debugging command. Dumps all global variable values to the client's console.");
	RegAdminCmd("dmspawn_regenerate_spawn_queue",	Command_RegenQueue,	ADMFLAG_CONFIG, "Re-generates the random queue that decides where clients will spawn.");
	
	#if DEBUG == 1
	RegAdminCmd("dmspawn_find_spawns",	Command_FindSpawns,	ADMFLAG_CONFIG, "Finds and outputs any info_player_teamspawns.");
	#endif
	
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
	
	if ( convar == cv_SpawnMode ) SpawnModeChanged(GetConVarInt(cv_SpawnMode));
}

/*	Called on map start.	*/
public OnMapStart()
{
	// Clear the NO_ACTIVITY flag.
	g_PluginState &= ~STATE_NO_ACTIVITY;
	
	b_SpawnsLoaded = false;
	
	// If disabled, return.
	if ( (g_PluginState & STATE_DISABLED) == STATE_DISABLED ) return;
	
	decl String:MapName[64];
	GetCurrentMap(MapName, sizeof(MapName));
	Format(FilePath, sizeof(FilePath), "scripts/dmspawn/%s_spawns.txt", MapName);
	
	#if DEBUG == 1
	LogMessage("File path for map: %s", FilePath);
	#endif
	
	// Get the info and stick it into our global variables.
	if ( !RetrieveSpawnInfo(FilePath) || NumPoints < 1) return;
}

public OnMapEnd()
{
	// Regardless of what state is set, clear the editing state flag.
	g_PluginState &= ~STATE_EDIT_MODE;
	b_SpawnsLoaded = false;
	
	ClearAllIndices();
	SpawnDistIndex(_, true);
	SpawnQueue(_, _, true);
}

/*	Called when a new round begins.	*/
public Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	g_PluginState &= ~STATE_NOT_IN_ROUND;
	
	if ( g_PluginState >= STATE_DISABLED ) return;
	
	if ( !GetConVarBool(cv_Resupply) )
	{
		// Find any func_regenerates that currently exist and disable them.
		new Resupply = -1;
		while ( (Resupply = FindEntityByClassname(Resupply, "func_regenerate")) != -1 )
		{
			AcceptEntityInput(Resupply, "Disable");
			#if DEBUG == 1
			LogMessage("Resupply locker at index %d disabled.", Resupply);
			#endif
		}
	}
	
	// Find any func_respawnrooms that currently exist and kill them.
	new n_Index = -1;
	while ( (n_Index = FindEntityByClassname(n_Index, "func_respawnroom")) != -1 )
	{
		AcceptEntityInput(n_Index, "Kill");
		#if DEBUG == 1
		LogMessage("Respawnroom at index %d removed.", n_Index);
		#endif
	}
	
	if ( !GetConVarBool(cv_TeamTriggers) )
	{
		// Find any func_respawnroomvisualisers that currently exist and kill them.
		n_Index = -1;
		while ( (n_Index = FindEntityByClassname(n_Index, "func_respawnroomvisualizer")) != -1 )
		{
			AcceptEntityInput(n_Index, "Kill");
			#if DEBUG == 1
			LogMessage("Respawn visualiser at index %d removed.", n_Index);
			#endif
		}
		
		// Find any filters that currently exist and nullify them.
		// NOTE: for the moment we'll kill it, maybe use AddOutput if it's convenient later.
		n_Index = -1;
		while ( (n_Index = FindEntityByClassname(n_Index, "filter_activator_tfteam")) != -1 )
		{
			AcceptEntityInput(n_Index, "Kill");
			#if DEBUG == 1
			LogMessage("Filter at index %d removed.", n_Index);
			#endif
		}
	}
	
	if ( g_PluginState >= STATE_EDIT_MODE ) return;
	
	if ( NumPoints > 0 )
	{
		switch (GetConVarInt(cv_SpawnMode))
		{
			case 1:	// If queued, re-generate the queue.
			{
				SpawnDistIndex(_, true);
				SpawnQueue(true, true);
			}
			
			default:	// Anything else, reset all in preparation.
			{
				SpawnQueue(_, _, true);
				SpawnDistIndex(_, true);
			}
		}
	}
}

/*	Called when a player changes team.	*/
public Event_TeamsChange(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	if ( client == GlobalClient )
	{
		// Execute the finish command.
		ClientCommand(client, "dmspawn_finish");
	}
}

/*	Called when a player spawns.	*/
public Event_Spawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	if ( g_PluginState > 0 ) return;
	
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	// Choose a random spawn index to teleport the client to.
	if ( NumPoints > 0 && client > 0 && client <= MaxClients && IsClientInGame(client) )
	{
		new i;	// This is the index number.
		
		switch (GetConVarInt(cv_SpawnMode))
		{
			case 1:	// Queued mode.
			{
				i = SpawnQueue();
			}
			
			case 2:	// Near mode.
			{
				i = SpawnDistIndex(true);
				
				// If something went wrong, try a random number instead.
				if ( i < 0 ) i = GetRandomInt(0, (NumPoints - 1));
			}
			
			case 3:	// Far mode.
			{
				i = SpawnDistIndex(false);
				
				// If something went wrong, try a random number instead.
				if ( i < 0 ) i = GetRandomInt(0, (NumPoints - 1));
			}
			
			default:	// Random mode
			{
				i = GetRandomInt(0, (NumPoints - 1));
			}
		}
		
		if ( i < 0 )
		{
			LogError("ERROR: Unable to choose a spawn index. (i = %d)", i);
			return;
		}
		
		// Firstly, check to see if there is any client or building within the specified radius of the spawn point.
		new Float:SpawnRadius = GetConVarFloat(cv_SpawnRadius);
		
		for ( new ClientSearch = 1; ClientSearch <= MaxClients; ClientSearch++ )
		{
			if ( IsClientInGame(ClientSearch) )
			{
				new Float:ClOrigin[3];
				GetClientAbsOrigin(ClientSearch, ClOrigin);
				
				// If the client is near enough:
				if ( GetVectorDistance(ClOrigin, Position[i]) <= SpawnRadius && GetClientTeam(ClientSearch) != GetClientTeam(client) )
				{
					/*if ( SDKHooks_Exists )
					{
						SDKHooks_TakeDamage(ClientSearch, client, client, 1000.0, 1, 0, NULL_VECTOR, Position[i]);	// Telefrag them.
					}
					else
					{*/
						ForcePlayerSuicide(ClientSearch);
					//}
				}
			}
		}
		
		new BuildingSearch = -1;
		while ( (BuildingSearch = FindEntityByClassname(BuildingSearch, "obj_sentrygun")) != -1 )
		{
			new Float:EntOrigin[3], BuildingTeam;
			GetEntPropVector(BuildingSearch, Prop_Send, "m_vecOrigin", EntOrigin);
			BuildingTeam = GetEntProp(BuildingSearch, Prop_Send, "m_iTeamNum");
			
			// If the building is near enough:
			if ( GetVectorDistance(EntOrigin, Position[i]) <= SpawnRadius && BuildingTeam != GetClientTeam(client) )
			{
				// Set up a trace to see if anything is in the way.
				/*TR_TraceRay(Position[i],*/			/*Start at the spawn point*/
								/*EntOrigin,*/			/*End at the entity*/
								/*MASK_PLAYERSOLID,*/	/*Anything that blocks the player*/
								/*RayType_EndPoint);*/	/*The ray goes between two points*/
				
				/*if ( !TR_DidHit(INVALID_HANDLE) )	// If nothing was hit along the way:
				{*/
					SetVariantInt( GetEntProp(BuildingSearch, Prop_Send, "m_iMaxHealth") + 1 );
					AcceptEntityInput(BuildingSearch, "RemoveHealth");
					AcceptEntityInput(BuildingSearch, "Kill");
				/*} */
			}
		}
		
		BuildingSearch = -1;
		while ( (BuildingSearch = FindEntityByClassname(BuildingSearch, "obj_dispenser")) != -1 )
		{
			new Float:EntOrigin[3], BuildingTeam;
			GetEntPropVector(BuildingSearch, Prop_Send, "m_vecOrigin", EntOrigin);
			BuildingTeam = GetEntProp(BuildingSearch, Prop_Send, "m_iTeamNum");
			
			// If the building is near enough:
			if ( GetVectorDistance(EntOrigin, Position[i]) <= SpawnRadius && BuildingTeam != GetClientTeam(client) )
			{
				// Set up a trace to see if anything is in the way.
				/*TR_TraceRay(Position[i],*/			/*Start at the spawn point*/
								/*EntOrigin,*/			/*End at the entity*/
								/*MASK_PLAYERSOLID,*/	/*Anything that blocks the player*/
								/*RayType_EndPoint);*/	/*The ray goes between two points*/
				
				/*if ( !TR_DidHit(INVALID_HANDLE) )	// If nothing was hit along the way:
				{*/
					SetVariantInt( GetEntProp(BuildingSearch, Prop_Send, "m_iMaxHealth") + 1 );
					AcceptEntityInput(BuildingSearch, "RemoveHealth");
					AcceptEntityInput(BuildingSearch, "Kill");
				/*} */
			}
		}
		
		BuildingSearch = -1;
		while ( (BuildingSearch = FindEntityByClassname(BuildingSearch, "obj_teleporter")) != -1 )
		{
			new Float:EntOrigin[3], BuildingTeam;
			GetEntPropVector(BuildingSearch, Prop_Send, "m_vecOrigin", EntOrigin);
			BuildingTeam = GetEntProp(BuildingSearch, Prop_Send, "m_iTeamNum");
			
			// If the building is near enough:
			if ( GetVectorDistance(EntOrigin, Position[i]) <= SpawnRadius && BuildingTeam != GetClientTeam(client) )
			{
				// Set up a trace to see if anything is in the way.
				/*TR_TraceRay(Position[i],*/			/*Start at the spawn point*/
								/*EntOrigin,*/			/*End at the entity*/
								/*MASK_PLAYERSOLID,*/	/*Anything that blocks the player*/
								/*RayType_EndPoint);*/	/*The ray goes between two points*/
				
				/*if ( !TR_DidHit(INVALID_HANDLE) )	// If nothing was hit along the way:
				{*/
					SetVariantInt( GetEntProp(BuildingSearch, Prop_Send, "m_iMaxHealth") + 1 );
					AcceptEntityInput(BuildingSearch, "RemoveHealth");
					AcceptEntityInput(BuildingSearch, "Kill");
				/*} */
			}
		}
		
		TeleportEntity(client, Position[i], Angles[i], NULL_VECTOR);
		
		#if DEBUG == 1
		LogMessage("Player %N was teleported to %f %f %f, angles %f %f %f", client, Position[i][0], Position[i][1], Position[i][2], Angles[i][0], Angles[i][1], Angles[i][2]);
		#endif
	}
	else LogError("WARNING: NumPoints likely < 1.");
}

/*	Run when checking player movement buttons.	*/
public Action:OnPlayerRunCmd(client, &buttons, &impulse, Float:vel[3], Float:angles[3], &weapon)
{
	if ( (g_PluginState & STATE_EDIT_MODE) != STATE_EDIT_MODE ) return;
	
	// If the client is crouching, set the global crouching bool.
	if ( client == GlobalClient && (buttons & FL_DUCKING) == FL_DUCKING ) b_IsCrouching = true;
	else b_IsCrouching = false;
	
	#if DEBUG == 1
	LogMessage("PlayerRunCmd: Player %d, GlobalClient %d, buttons %d, crouching: %d", client, GlobalClient, buttons, b_IsCrouching);
	#endif
}

/*	=========== End Event Hook Functions ===========	*/

/*	========== Begin Custom Functions ==========	*/

/*	Zeroes out all global indices.	*/
ClearAllIndices()
{
	NumPoints = 0;
	
	for ( new i = 0; i < MAX_SPAWN_POINTS; i++ )
	{
		Angles[i][0] = 0.0;
		Angles[i][1] = 0.0;
		Angles[i][2] = 0.0;
		
		Position[i][0] = 0.0;
		Position[i][1] = 0.0;
		Position[i][2] = 0.0;
		
		TeamNum[i] = 0;
		SpawnModelIndex[i] = -1;
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

/*	Called when the mode ConVar is changed.	*/
SpawnModeChanged(mode)
{
	switch (mode)
	{
		case 1:	// Queued mode.
		{
			// If the mode is 1, we want to re-generate the spawn queue immediately.
			// Clearing the queue will only happen if it's already been generated,
			// so it's safe to call from other cases.
			SpawnQueue(true, true);
		}
		
		default:	// Anything else, clear all out.
		{
			SpawnDistIndex(_, true);
			SpawnQueue(_, _, true);
		}
	}
}

/*	Parses the spawn info file and puts the values into the global variables.
	Returns true on success, false on failure.	*/
bool:RetrieveSpawnInfo(String:s_FilePath[])
{	
	new Handle:kv = CreateKeyValues("spawns");
	
	if ( kv == INVALID_HANDLE )
	{
		LogMessage("%t", "dms_keyvalues_handle_invalid");
		return false;
	}
	
	if ( !FileToKeyValues(kv, s_FilePath) )
	{
		LogMessage("%t", "dms_no_spawns_found");
		return false;
	}
	
	NumPoints = 0;
	
	if ( !KvGotoFirstSubKey(kv) )	// If there are no sub-keys:
		{
			LogMessage("[DMS] No first key found.");
		}
	else	// If there are sub-keys:
	{
		new Float:vAngles[3];
		new Float:vPosition[3];
		new Team;
		new SwitchNum = TEAM_RED;
		
		do
		{
			KvGetVector(kv, "angles", vAngles);
			Team = KvGetNum(kv, "TeamNum", SwitchNum);
			KvGetVector(kv, "position", vPosition);
			
			if ( (Team == TEAM_RED || Team == TEAM_BLUE) && NumPoints < MAX_SPAWN_POINTS )	// If the spawn formatting is valid:
			{
				// Put the data into the global variables.
				TeamNum[NumPoints] = Team;
				Angles[NumPoints] = vAngles;
				Position[NumPoints] = vPosition;
				
				#if DEBUG == 1
				LogMessage("Spawn point %d: team %d, pos %f %f %f, ang %f %f %f", NumPoints, TeamNum[NumPoints],
							Position[NumPoints][0], Position[NumPoints][1], Position[NumPoints][2],
							Angles[NumPoints][0], Angles[NumPoints][1], Angles[NumPoints][2]);
				#endif
				
				NumPoints++;
			}
			
			vAngles[0] = 0.0;
			vAngles[1] = 0.0;
			vAngles[2] = 0.0;
			vPosition[0] = 0.0;
			vPosition[1] = 0.0;
			vPosition[2] = 0.0;
			Team = 0;
			
			if ( SwitchNum == TEAM_RED ) SwitchNum = TEAM_BLUE;
			else SwitchNum = TEAM_RED;
			
		} while ( KvGotoNextKey(kv) );	// Increment NumPoints while the next key exists.
	}
	
	// Now all data is held in the global arrays.
	CloseHandle(kv);
	kv = INVALID_HANDLE;
	
	LogMessage("[DMS] Number of spawns in file: %d", NumPoints);
	
	return true;
}

/*	Creates a model for the spawn point at the specified array index.
	Remember that the index is one less than the actual spawn ID.	*/
MakeSpawnModel(array_index)
{
	new Model = CreateEntityByName("prop_dynamic");
	
	if ( Model > MaxClients )
	{
		DispatchKeyValue(Model, "disablereceiveshadows", "0");
		DispatchKeyValue(Model, "rendermode", "0");
		DispatchKeyValue(Model, "renderfx", "0");
		DispatchKeyValue(Model, "DefaultAnim", "ragdollspawn");
		DispatchKeyValue(Model, "maxdxlevel", "0");
		DispatchKeyValue(Model, "spawnflags", "0");
		DispatchKeyValue(Model, "mindxlevel", "0");
		DispatchKeyValue(Model, "pressuredelay", "0");
		DispatchKeyValue(Model, "disableshadows", "0");
		DispatchKeyValue(Model, "ExplodeDamage", "0");
		DispatchKeyValue(Model, "StartDisabled", "0");
		DispatchKeyValue(Model, "PerformanceMode", "0");
		DispatchKeyValue(Model, "ExplodeRadius", "0");
		DispatchKeyValue(Model, "fademaxdist", "1200");
		DispatchKeyValue(Model, "bodygroup", "0");
		DispatchKeyValue(Model, "fademindist", "1000");
		DispatchKeyValue(Model, "fadescale", "1");
		DispatchKeyValue(Model, "MaxAnimTime", "10");
		DispatchKeyValue(Model, "MinAnimTime", "5");
		DispatchKeyValue(Model, "model", "models/player/sniper.mdl");
		DispatchKeyValue(Model, "solid", "0");
		DispatchKeyValue(Model, "RandomAnimation", "0");
		DispatchKeyValue(Model, "renderamt", "255");
		DispatchKeyValue(Model, "rendercolor", "255 255 255");
		
		if ( TeamNum[array_index] == TEAM_RED )
		{
			DispatchKeyValue(Model, "skin", "0");
		}
		else
		{
			DispatchKeyValue(Model, "skin", "1");
		}
		
		decl String:Targetname[13];
		Format(Targetname, sizeof(Targetname), "spawnmodel%d", (array_index + 1));
		DispatchKeyValue(Model, "targetname", Targetname);
		
		/*new String:ID[4];
		IntToString((array_index + 1), ID, sizeof(ID));
		DispatchKeyValue(Model, "linkedtospawnid", ID);*/
		
		if ( DispatchSpawn(Model) ) return Model;
	}
	
	return -1;
}

/*	Manages the spawn queue and returns the index of the current spawn to use, or -1 on error.
	Passing true as the first parameter re-generates the spawn queue first, according to NumPoints.
	If noreturn = true, the index to use is not incremented.
	If clearall = true, the queue is cleared out and all other parameters are ignored.	*/
SpawnQueue(bool:mode = false, bool:noreturn = false, bool:clearall = false)
{
	static Queue[MAX_SPAWN_POINTS] = {-1, ...};
	static bool:Generated = false;
	static IndexToUse = -1;
	
	if ( clearall )
	{
		if ( Generated )
		{
			for ( new i = 0; i < MAX_SPAWN_POINTS; i++ )
			{
				Queue[i] = -1;
			}
		}
		
		IndexToUse = -1;
		Generated = false;
		
		return -1;
	}
	
	if ( NumPoints < 1 ) return -1;
	
	if ( mode )
	{
		
		Generated = GenerateSpawnQueue(Queue, sizeof(Queue));
		IndexToUse = NumPoints;	// This will then mean that the next index (when it is incremented) will be 0.
	}
	
	if ( !Generated ) return -1;
	
	if ( !noreturn )
	{
		// Increment the queue index, then return the spawn index from the queue.
		// At this point, IndexToUse will be the value previously returned.
		if ( IndexToUse >= (NumPoints-1) ) IndexToUse = 0;
		else IndexToUse++;
	}
	
	return Queue[IndexToUse];
}

/*	Generates a new queue and places it in the specified array.
	Returns true on success, false on failure.	*/
bool:GenerateSpawnQueue(Queue[], maxlength)
{
	if ( NumPoints < 1 ) return false;

	decl SpawnMirror[NumPoints];
	new TotalIndices = NumPoints;
	
	// We will need to make a note of the total number of spawns and put the indices into the mirror array.
	// We will then take a random number between 0 and the total count (-1) and copy this number into the first index of the queue array.
	// After this we will knock the value out of the mirror array, shift all the other values down and reduce our total count.
	// The process will be repeated with a new random number between 1 and the new total count (-1), until the list is depleted.
	
	// Apparently we can't do this on declaration (FFFUUU-), so it has to happen here.
	for ( new i = 0; i < NumPoints; i++ )
	{
		SpawnMirror[i] = i;
	}
	
	for ( new i = 0; TotalIndices > 0; i++ )
	{
		new Pass = GetRandomInt(0, (TotalIndices - 1));
		
		// Stick the value in the queue.
		if ( (i+1) <= maxlength ) Queue[i] = SpawnMirror[Pass];
		
		// Shift the rest of the array down.
		for ( new shift = (Pass + 1); shift < TotalIndices; shift++ )
		{
			// Each time, shift will point to the information in the next index on.
			// Move this information to the index (shift - 1).
			SpawnMirror[shift-1] = SpawnMirror[shift];
		}
		
		SpawnMirror[TotalIndices-1] = -1;
		TotalIndices--;	// Decrement the total indices count.
		
	}
	
	return true;
}

/*	Returns the index of the spawn to use, depending on the parameters, or -1 on error.
	If mode = true, the nearest spawn will be returned.
	If mode = false, the furthest spawn will be returned.
	The chosen spawn index will be noted for testing exclusion next time.
	If reset = true, the excluded spawn will be reset and no calculation will take place.
	I'd imagine, due to for-loop Inception, this might end up being quite expensive and so should only be
	called when needed.	*/
SpawnDistIndex(bool:mode = true, bool:reset = false)
{
	static Exclude = -1;
	
	new Float:MaxDist = 0.0;
	new Float:MinDist = 0.0;
	new MaxDistSpawn = -1;
	new MinDistSpawn = -1;
	
	if ( reset )
	{
		Exclude = -1;
		return -1;
	}
	
	// Look through each spawn.
	for ( new i = 0; i < NumPoints; i++ )
	{
		if ( i != Exclude )
		{
			new Float:Distance;
			
			// Check each client (on Red or Blue) and find the distance to them.
			for ( new client = 1; client <= MaxClients; client++ )
			{
				if ( IsClientInGame(client) && IsPlayerAlive(client) && (GetClientTeam(client) == TEAM_RED || GetClientTeam(client) == TEAM_BLUE) )
				{
					new Float:vClientOrigin[3];
					GetClientAbsOrigin(client, vClientOrigin);
					
					Distance += GetVectorDistance(Position[i], vClientOrigin);
					
					#if DEBUG == 1
					LogMessage("Spawn %d distance to client %d is %f (total %f).", i, client, GetVectorDistance(Position[i], vClientOrigin), Distance);
					#endif
				}
			}
			
			// Now that all the distances have been added up, see if this spawn is nearer/further than what we already know of so far.
			if ( !mode )
			{
				#if DEBUG == 1
				LogMessage("Mode is false, furthest spawn.");
				#endif
				
				if ( Distance > MaxDist )
				{
					MaxDist = Distance;
					MaxDistSpawn = i;
					Exclude = i;
					
					#if DEBUG == 1
					LogMessage("Greatest spawn distance: %d with distance %f (exclude now %d).", MaxDistSpawn, MaxDist, Exclude);
					#endif
				}
				#if DEBUG == 1
				else
				{
					LogMessage("Distance (%f) is not greater than MaxDist (%f).", Distance, MaxDist);
				}
				#endif
			}
			else
			{
				#if DEBUG == 1
				LogMessage("Mode is true, nearest spawn.");
				#endif
				
				if ( Distance < MinDist || MinDist <= 0.0)
				{
					#if DEBUG == 1
					LogMessage("MinDist = %f.", MinDist);
					#endif
					
					MinDist = Distance;
					MinDistSpawn = i;
					Exclude = i;
					
					#if DEBUG == 1
					LogMessage("Smallest spawn distance: %d with distance %f (exclude now %d).", MinDistSpawn, MaxDist, Exclude);
					#endif
				}
				#if DEBUG == 1
				else
				{
					LogMessage("Distance (%f) is not less than MaxDist (%f).", Distance, MaxDist);
				}
				#endif
			}
		}
	}
	
	if ( mode ) return MinDistSpawn;
	else return MaxDistSpawn;
}

/*	=========== End Custom Functions ===========	*/

/*	========== Begin Commands ==========	*/

/*	Enters edit mode.	*/
public Action:Command_Edit(client, args)
{
	if ( (g_PluginState & STATE_NO_ACTIVITY) == STATE_NO_ACTIVITY || (g_PluginState & STATE_NOT_IN_ROUND) == STATE_NOT_IN_ROUND ) return Plugin_Handled;
	
	if ( IsClientInGame(client) && GetClientTeam(client) < TEAM_RED )
	{
		ShowActivity2(client, "[DMS]", "%t", "dms_team_not_valid");
		return Plugin_Handled;
	}
	
	if ( IsClientInGame(client) && !IsPlayerAlive(client) )
	{
		ShowActivity2(client, "[DMS]", "%t", "dms_player_not_alive");
		return Plugin_Handled;
	}
	
	if ( (g_PluginState & STATE_EDIT_MODE) == STATE_EDIT_MODE )
	{
		ShowActivity2(client, "[DMS]", "%t %N.", "dms_edit_mode_already_enabled", GlobalClient);
		return Plugin_Handled;
	}
	
	g_PluginState |= STATE_EDIT_MODE;
	g_PluginState |= STATE_NOT_IN_ROUND;
	
	// Store the current mp_timelimit value.
	new Handle:cvTimelimit = FindConVar("mp_timelimit");
	Timelimit = GetConVarInt(cvTimelimit);
	
	// Pause the timer.
	new RoundTimer = FindEntityByClassname(-1, "team_round_timer");
	if ( RoundTimer != -1 )
	{
		AcceptEntityInput(RoundTimer, "Pause");
		AcceptEntityInput(RoundTimer, "Disable");
	}
	
	ServerCommand("mp_timelimit 0");
	ServerCommand("mp_restartround 3");
	
	GlobalClient = client;
	
	EmitSoundToClient(client, SOUND_EDIT_MODE);
	
	return Plugin_Handled;
}

/*	Loads spawn points from the map spawn file.	*/
public Action:Command_Load(client, args)
{
	if ( (g_PluginState & STATE_NO_ACTIVITY) == STATE_NO_ACTIVITY ) return Plugin_Handled;
	
	if ( (g_PluginState & STATE_EDIT_MODE != STATE_EDIT_MODE) || (g_PluginState & STATE_NOT_IN_ROUND == STATE_NOT_IN_ROUND) )
	{
		PrintToChat(client, "%t", "dms_not_in_edit_mode");
		return Plugin_Handled;
	}
	
	if ( client != GlobalClient )
	{
		ShowActivity2(client, "[DMS]", "%t %N.", "dms_edit_mode_already_enabled", GlobalClient);
		return Plugin_Handled;
	}
	
	if ( IsClientInGame(client) && GetClientTeam(client) < TEAM_RED )
	{
		ShowActivity2(client, "[DMS]", "%t", "dms_team_not_valid");
		return Plugin_Handled;
	}
	
	if ( IsClientInGame(client) && !IsPlayerAlive(client) )
	{
		ShowActivity2(client, "[DMS]", "%t", "dms_player_not_alive");
		return Plugin_Handled;
	}
	
	if ( !RetrieveSpawnInfo(FilePath) )
	{
		decl String:CurrentMapName[64];
		GetCurrentMap(CurrentMapName, sizeof(CurrentMapName));
		PrintToChat(client, "%t %s.", "dms_no_spawns_found", CurrentMapName);
		b_SpawnsLoaded = true;
		EmitSoundToClient(client, SOUND_LOAD_SPAWNS);
		return Plugin_Handled;
	}
	
	// Spawns have been loaded; go through each one and create a model at the co-ordinates.
	
	for ( new i = 0; i < NumPoints; i++ )
	{
		new Model = MakeSpawnModel(i);
		SpawnModelIndex[i] = Model;
		
		if ( Model > MaxClients )
		{
			TeleportEntity(Model, Position[i], Angles[i], NULL_VECTOR);
			
			// taunt02 or taunt06 work well.
			new RandomTaunt = GetRandomInt(0, 1);
			if ( RandomTaunt < 1 ) SetVariantString("taunt02");
			else SetVariantString("taunt06");
			
			AcceptEntityInput(Model, "SetAnimation");
		}
	}
	
	b_SpawnsLoaded = true;
	
	EmitSoundToClient(client, SOUND_LOAD_SPAWNS);
	
	return Plugin_Handled;
}

/*	Adds a new spawn point where the client is standing.	*/
public Action:Command_Add(client, args)
{
	if ( (g_PluginState & STATE_NO_ACTIVITY) == STATE_NO_ACTIVITY ) return Plugin_Handled;
	
	if ( (g_PluginState & STATE_EDIT_MODE != STATE_EDIT_MODE) || (g_PluginState & STATE_NOT_IN_ROUND == STATE_NOT_IN_ROUND) )
	{
		ShowActivity2(client, "[DMS]", "%t", "dms_not_in_edit_mode");
		return Plugin_Handled;
	}
	
	if ( client != GlobalClient )
	{
		ShowActivity2(client, "[DMS]", "%t %N.", "dms_edit_mode_already_enabled", GlobalClient);
		return Plugin_Handled;
	}
	
	if ( IsClientInGame(client) && GetClientTeam(client) < TEAM_RED )
	{
		ShowActivity2(client, "[DMS]", "%t", "dms_team_not_valid");
		return Plugin_Handled;
	}
	
	if ( IsClientInGame(client) && !IsPlayerAlive(client) )
	{
		ShowActivity2(client, "[DMS]", "%t", "dms_player_not_alive");
		return Plugin_Handled;
	}
	
	if ( !b_SpawnsLoaded )
	{
		ShowActivity2(client, "[DMS]", "%t", "dms_no_spawns_loaded");
		return Plugin_Handled;
	}
	
	if ( client <= 0 || client > MaxClients || !IsClientInGame(client) )
	{
		return Plugin_Handled;
	}
	
	if ( b_IsCrouching )
	{
		ShowActivity2(client, "[DMS]", "%t", "dms_crouching");
		return Plugin_Handled;
	}
	
	// Spawns are loaded, get the client's current position and angles.
	new Float:ClientPos[3], Float:ClientAng[3];
	
	GetClientAbsOrigin(client, ClientPos);
	GetClientAbsAngles(client, ClientAng);
	
	// We want to ignore pitch and roll for the spawn point, so reset these.
	ClientAng[0] = 0.0;
	ClientAng[2] = 0.0;
	
	// Add in the new info for the spawn point.	
	if ( NumPoints >= MAX_SPAWN_POINTS )
	{
		ShowActivity2(client, "[DMS]", "%t", "dms_max_spawns");
		return Plugin_Handled;
	}
	
	new String:Buffer[8];
	GetCmdArg(1, Buffer, sizeof(Buffer));
	
	if ( StrEqual(Buffer, "red", false) )
	{
		TeamNum[NumPoints] = TEAM_RED;
	}
	else
	{
		TeamNum[NumPoints] = TEAM_BLUE;
	}
	
	Angles[NumPoints] = ClientAng;
	Position[NumPoints] = ClientPos;
	
	new nModelIndex = MakeSpawnModel(NumPoints);
	if ( nModelIndex > MaxClients )
	{
		SpawnModelIndex[NumPoints] = nModelIndex;
		TeleportEntity(nModelIndex, Position[NumPoints], Angles[NumPoints], NULL_VECTOR);
		
		// taunt02 or taunt06 work well.
		new RandomTaunt = GetRandomInt(0, 1);
		if ( RandomTaunt < 1 ) SetVariantString("taunt02");
		else SetVariantString("taunt06");
		
		AcceptEntityInput(nModelIndex, "SetAnimation");
	}
	
	ShowActivity2(client, "[DMS]", "%t", "dms_spawn_created", (NumPoints + 1), TeamNum[NumPoints]);
	
	NumPoints++;
	
	new sound = GetRandomInt(1, 4);
	
	switch (sound)
	{
		case 1:
		{
			EmitSoundToClient(client, SOUND_ADD_SPAWN_01);
		}
		
		case 2:
		{
			EmitSoundToClient(client, SOUND_ADD_SPAWN_02);
		}
		
		case 3:
		{
			EmitSoundToClient(client, SOUND_ADD_SPAWN_03);
		}
		
		default:
		{
			EmitSoundToClient(client, SOUND_ADD_SPAWN_04);
		}
	}
	
	return Plugin_Handled;
}

/*	Removes the spawn point the client is nearest.	*/
public Action:Command_Remove(client, args)
{
	if ( (g_PluginState & STATE_NO_ACTIVITY) == STATE_NO_ACTIVITY ) return Plugin_Handled;
	
	if ( (g_PluginState & STATE_EDIT_MODE != STATE_EDIT_MODE) || (g_PluginState & STATE_NOT_IN_ROUND == STATE_NOT_IN_ROUND) )
	{
		ShowActivity2(client, "[DMS]", "%t", "dms_not_in_edit_mode");
		return Plugin_Handled;
	}
	
	if ( client != GlobalClient )
	{
		ShowActivity2(client, "[DMS]", "%t %N.", "dms_edit_mode_already_enabled", GlobalClient);
		return Plugin_Handled;
	}
	
	if ( IsClientInGame(client) && GetClientTeam(client) < TEAM_RED )
	{
		ShowActivity2(client, "[DMS]", "%t", "dms_team_not_valid");
		return Plugin_Handled;
	}
	
	if ( IsClientInGame(client) && !IsPlayerAlive(client) )
	{
		ShowActivity2(client, "[DMS]", "%t", "dms_player_not_alive");
		return Plugin_Handled;
	}
	
	if ( !b_SpawnsLoaded )
	{
		ShowActivity2(client, "[DMS]", "%t", "dms_no_spawns_loaded");
		return Plugin_Handled;
	}
	
	if ( client <= 0 || client > MaxClients || !IsClientInGame(client) || !IsClientInGame(client) )
	{
		return Plugin_Handled;
	}
	
	if ( GetCmdArgs() > 0 )
	{
		new String:ArgBuffer[16];
		GetCmdArg(1, ArgBuffer, sizeof(ArgBuffer));
		
		// If the command argument is "all", get rid of everything.
		if ( StrEqual(ArgBuffer, "all", false) )
		{
			for ( new i = 0; i < NumPoints; i++ )
			{
				if ( IsValidEntity(SpawnModelIndex[i]) ) AcceptEntityInput(SpawnModelIndex[i], "Kill");
				// if ( IsValidEntity(Index[i]) ) AcceptEntityInput(Index[i], "Kill");
				
				Angles[i][0] = 0.0;
				Angles[i][1] = 0.0;
				Angles[i][2] = 0.0;
				
				Position[i][0] = 0.0;
				Position[i][1] = 0.0;
				Position[i][2] = 0.0;
				
				TeamNum[i] = 0;
				// Index[i] = -1;
				SpawnModelIndex[i] = 0;
			}
			
			NumPoints = 0;
			
			new sound = GetRandomInt(1, 4);
			switch (sound)
			{
				case 1:
				{
					EmitSoundToClient(client, SOUND_REMOVE_SPAWN_01);
				}
				
				case 2:
				{
					EmitSoundToClient(client, SOUND_REMOVE_SPAWN_02);
				}
				
				case 3:
				{
					EmitSoundToClient(client, SOUND_REMOVE_SPAWN_03);
				}
				
				default:
				{
					EmitSoundToClient(client, SOUND_REMOVE_SPAWN_04);
				}
			}
			
			ShowActivity2(client, "[DMS]", "dms_all_spawns_removed");
			return Plugin_Handled;
		}
	}
	
	// Look through all the model indices
	new SpawnIndex = -1;
	for ( new i = 0; i < NumPoints; i++ )
	{
		if ( IsValidEntity(SpawnModelIndex[i]) )
		{
			new Float:ModelPos[3], Float:ClientPos[3];
			GetEntPropVector(SpawnModelIndex[i], Prop_Send, "m_vecOrigin", ModelPos);
			GetClientAbsOrigin(client, ClientPos);
			
			if ( GetVectorDistance(ModelPos, ClientPos) <= 64.0 )
			{
				SpawnIndex = i;
				break;
			}
		}
	}
	
	if ( SpawnIndex == -1 )
	{
		LogMessage("No nearby spawn points.");
		ShowActivity2(client, "[DMS]", "%t", "dms_no_remove_target");
		return Plugin_Handled;
	}
	
	AcceptEntityInput(SpawnModelIndex[SpawnIndex], "Kill");
	// if ( IsValidEntity(Index[SpawnIndex]) ) AcceptEntityInput(Index[SpawnIndex], "Kill");
	
	// Shift all the information down in the arrays.
	for ( new shift = (SpawnIndex + 1); shift < NumPoints; shift++ )
	{
		// Each time, shift will point to the information in the next index on.
		// Move this information to the index (shift - 1).
		Angles[shift-1][0] = Angles[shift][0];
		Angles[shift-1][1] = Angles[shift][1];
		Angles[shift-1][2] = Angles[shift][2];
		
		Position[shift-1][0] = Position[shift-1][0];
		Position[shift-1][1] = Position[shift-1][1];
		Position[shift-1][2] = Position[shift-1][2];
		
		TeamNum[shift-1] = TeamNum[shift];
		SpawnModelIndex[shift-1] = SpawnModelIndex[shift];
	}
	
	// We're at the last index which is now redundant.
	// Remove all the information at this index.
	Angles[NumPoints-1][0] = 0.0;
	Angles[NumPoints-1][1] = 0.0;
	Angles[NumPoints-1][2] = 0.0;
	
	Position[NumPoints-1][0] = 0.0;
	Position[NumPoints-1][1] = 0.0;
	Position[NumPoints-1][2] = 0.0;
	
	TeamNum[NumPoints-1] = 0;
	// Index[NumPoints-1] = -1;
	SpawnModelIndex[NumPoints-1] = -1;
	
	NumPoints--;	// Decrement NumPoints now we've lost a spawn.
	
	new sound = GetRandomInt(1, 4);
	switch (sound)
	{
		case 1:
		{
			EmitSoundToClient(client, SOUND_REMOVE_SPAWN_01);
		}
		
		case 2:
		{
			EmitSoundToClient(client, SOUND_REMOVE_SPAWN_02);
		}
		
		case 3:
		{
			EmitSoundToClient(client, SOUND_REMOVE_SPAWN_03);
		}
		
		default:
		{
			EmitSoundToClient(client, SOUND_REMOVE_SPAWN_04);
		}
	}
	
	ShowActivity2(client, "[DMS]", "%t", "dms_spawn_removed", (SpawnIndex + 1));
	return Plugin_Handled;
}

/*	Exports the current spawn points to the map file.
	Passing "cancel" ignores saving the points to the file.	*/
public Action:Command_Finish(client, args)
{
	if ( (g_PluginState & STATE_NO_ACTIVITY) == STATE_NO_ACTIVITY ) return Plugin_Handled;
	
	if ( (g_PluginState & STATE_EDIT_MODE != STATE_EDIT_MODE) || (g_PluginState & STATE_NOT_IN_ROUND == STATE_NOT_IN_ROUND) )
	{
		ShowActivity2(client, "[DMS]", "%t", "dms_not_in_edit_mode");
		return Plugin_Handled;
	}
	
	if ( client != GlobalClient )
	{
		ShowActivity2(client, "[DMS]", "%t %N.", "dms_edit_mode_already_enabled", GlobalClient);
		return Plugin_Handled;
	}
	
	/*if ( IsClientInGame(client) && GetClientTeam(client) < TEAM_RED )
	{
		ShowActivity2(client, "[DMS]", "%t", "dms_team_not_valid");
		return Plugin_Handled;
	}*/
	
	/*if ( IsClientInGame(client) && !IsPlayerAlive(client) )
	{
		ShowActivity2(client, "[DMS]", "%t", "dms_player_not_alive");
		return Plugin_Handled;
	}*/
	
	if ( !b_SpawnsLoaded )
	{
		ShowActivity2(client, "[DMS]", "%t", "dms_no_spawns_loaded");
	}
	
	new String:ArgBuffer[16];
	
	if ( GetCmdArgs() > 0 ) GetCmdArg(1, ArgBuffer, sizeof(ArgBuffer));
	
	new bool:b_Cancel;
	if ( StrEqual(ArgBuffer, "cancel", false) ) b_Cancel = true;
	
	if ( !b_Cancel && b_SpawnsLoaded )
	{
		new Handle:kv = CreateKeyValues("spawns");
		
		if ( kv != INVALID_HANDLE )
		{		
			// Add to the keyvalues tree.
			for ( new i = 0; i < NumPoints; i++ )
			{
				decl String:Buffer[64];
				IntToString(i, Buffer, sizeof(Buffer));
				KvJumpToKey(kv, Buffer, true);			// This will create the new section named as whatever number i currently is.
				
				new Float:KvVector[3];
				KvVector[0] = Angles[i][0];
				KvVector[1] = Angles[i][1];
				KvVector[2] = Angles[i][2];
				KvSetVector(kv, "angles", KvVector);	// This will create a new vector with this value.
				
				new KvTeamNum = TeamNum[i];
				KvSetNum(kv, "TeamNum", KvTeamNum);		// And so on.
				
				KvVector[0] = Position[i][0];
				KvVector[1] = Position[i][1];
				KvVector[2] = Position[i][2];
				KvSetVector(kv, "position", KvVector);
				
				// That's all for this section, return back.
				KvGoBack(kv);
			}
			
			#if DEBUG == 1
			LogMessage("File path to write to: %s", FilePath);
			#endif
			
			KeyValuesToFile(kv, FilePath);
			CloseHandle(kv);
			
			#if DEBUG == 1
			LogMessage("File written, handle closed.");
			#endif
			
			ShowActivity2(client, "[DMS]", "%t", "dms_kv_savedtofile", FilePath);
		}
		else
		{
			ShowActivity2(client, "[DMS]", "%t", "dms_kv_notsaved");
		}
	}
	
	// Get rid of all of our spawn models.
	for ( new i = 0; i < NumPoints; i++ )
	{
		if ( IsValidEntity(SpawnModelIndex[i]) )
		{
			AcceptEntityInput(SpawnModelIndex[i], "Kill");
			#if DEBUG == 1
			LogMessage("Spawn model %d removed.", SpawnModelIndex[i]);
			#endif
			SpawnModelIndex[i] = -1;
		}
	}
	
	g_PluginState &= ~STATE_EDIT_MODE;
	g_PluginState |= STATE_NOT_IN_ROUND;
	
	ServerCommand("mp_timelimit %d", Timelimit);
	
	new RoundTimer = FindEntityByClassname(-1, "team_round_timer");
	if ( RoundTimer != -1 )
	{
		AcceptEntityInput(RoundTimer, "Enable");
		AcceptEntityInput(RoundTimer, "Resume");
	}
	
	ServerCommand("mp_restartround 3");
	
	GlobalClient = -1;
	
	// NOTE: If the client has created new spawns but cancels, the spawns stick around.
	// For the moment we'll restart the map when coming out of edit mode, but there could be a better solution.
	
	decl String:CurrentMapName[64];
	GetCurrentMap(CurrentMapName, sizeof(CurrentMapName));
	
	ServerCommand("changelevel", CurrentMapName);
	
	return Plugin_Handled;
}

/*	Dumps all info from global variables to the client's console.	*/
public Action:Command_DumpAll(client, args)
{
	if ( (g_PluginState & STATE_NO_ACTIVITY) == STATE_NO_ACTIVITY ) return Plugin_Handled;
	
	PrintToConsole(client, "Numpoints: %d", NumPoints);
	
	for ( new i = 0; i < MAX_SPAWN_POINTS; i++ )
	{
		PrintToConsole(client, "Info at index %d:", i);
		
		PrintToConsole(client, "Position %f %f %f, Angles %f %f %f", Position[i][0], Position[i][1], Position[i][2], Angles[i][0], Angles[i][1], Angles[i][2]);
		PrintToConsole(client, "TeamNum: %d, SpawnModelIndex: %d", TeamNum[i], /*Index[i],*/ SpawnModelIndex[i]);
	}
	
	PrintToConsole(client, "Dump finished.");
	
	return Plugin_Handled;
}

/*	Regenerates the spawn queue.	*/
public Action:Command_RegenQueue(client, args)
{
	if ( (g_PluginState & STATE_NO_ACTIVITY) == STATE_NO_ACTIVITY ) return Plugin_Handled;
	
	if ( (g_PluginState & STATE_EDIT_MODE == STATE_EDIT_MODE) )
	{
		ShowActivity2(client, "[DMS]", "%t", "dms_no_regen_in_edit_mode");
		return Plugin_Handled;
	}
	
	if ( GetConVarInt(cv_SpawnMode) != 1 )
	{
		ShowActivity2(client, "[DMS]", "%t", "dms_not_in_queued_mode");
		return Plugin_Handled;
	}
	
	new Success = SpawnQueue(true, true);
	
	if ( Success < 0 ) ShowActivity2(client, "[DMS]", "%t", "dms_queue_regen_failed");
	else ShowActivity2(client, "[DMS]", "%t %d", "dms_queue_regen_succeeded", Success);
	
	return Plugin_Handled;
}

#if DEBUG == 1
public Action:Command_FindSpawns(client, args)
{
	if ( (g_PluginState & STATE_NO_ACTIVITY) == STATE_NO_ACTIVITY ) return Plugin_Handled;
	
	new Ent = -1;
	
	while ( (Ent = FindEntityByClassname(Ent, "info_player_teamspawn")) != -1 )
	{
		LogMessage("Spawn found at index %d", Ent);
		/*new Float:Pos[3], Float:Ang[3];
		Ang[1] = -90.0;
		GetEntPropVector(Ent, Prop_Send, "m_vecOrigin", Pos);
		TE_SetupSparks(Pos, Ang, 1, 1);*/
	}
	
	return Plugin_Handled;
}
#endif

/*	=========== End Commands ===========	*/