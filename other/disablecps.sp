#include <sourcemod>
#include <tf2items>
#include <tf2>
#include <tf2_stocks>
#include <sdktools>
#include <sdkhooks>

#pragma semicolon 1

public Plugin:myinfo = 
{
	name = "Arse",
	author = "Arse",
	description = "Arse",
	version = "Arse",
	url = "Arse"
}

public OnPluginStart()
{
	LogMessage("Arse");
	
	HookEventEx("teamplay_round_start",		Event_RoundStart,		EventHookMode_Pre);
	HookEventEx("teamplay_setup_finished",	Event_SetupFinished,	EventHookMode_Post);
}

public OnMapStart()
{
	CreateTimer(1.0, Timer_DoorRefresh, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	new i = -1;
	while ( (i = FindEntityByClassname(i, "func_regenerate")) != -1 )
	{
		AcceptEntityInput(i, "Kill");
	}
	
	i = -1;
	while ( (i = FindEntityByClassname(i, "team_control_point")) != -1 )
	{
		SetVariantInt(1);
		AcceptEntityInput(i, "SetLocked");
	}
	
	i = -1;
	while ( (i = FindEntityByClassname(i, "func_capturezone")) != -1 )
	{
		AcceptEntityInput(i, "Disable");
	}
	
	i = -1;
	while ( (i = FindEntityByClassname(i, "func_respawnroomvisualizer")) != -1 )
	{
		AcceptEntityInput(i, "Kill");
	}
	
	new timer = FindEntityByClassname(-1, "team_round_timer");
	if ( timer != -1 )
	{
		SetVariantInt(60);
		AcceptEntityInput(timer, "SetSetupTime");
	}
}

public Event_SetupFinished(Handle:event, const String:name[], bool:dontBroadcast)
{
	new timer = FindEntityByClassname(-1, "team_round_timer");
	
	if ( timer != -1 )
	{
		SetVariantInt(300);
		AcceptEntityInput(timer, "SetMaxTime");
		SetVariantInt(300);
		AcceptEntityInput(timer, "SetTime");
	}
}

public Action:Timer_DoorRefresh(Handle:ltimer, Handle:pack)
{
	new i = -1;
	
	while ( (i = FindEntityByClassname(i, "func_door")) != -1 )
	{
			AcceptEntityInput(i, "Unlock");
			AcceptEntityInput(i, "Open");
	}
}

// public Action:OnPlayerRunCmd(client, &buttons, &impulse, Float:vel[3], Float:angles[3], &weapon)
// {
// 	PrintToChatAll("%N's air dash state: %d", client, GetEntProp(client, Prop_Send, "m_iAirDash"));
// 	return Plugin_Continue;
// }