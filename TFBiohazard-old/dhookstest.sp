#include <sourcemod>
#include <dhooks>

new Handle:test = INVALID_HANDLE;
new ofDmgForce, ofDmgPos, ofReportedPos, ofInflictor, ofAttacker, ofWeapon, ofDmg, ofMaxDmg, ofBaseDmg, ofDmgBits, ofDmgCustom, ofDmgStats,
	ofAmmoType, ofDmgOtherPlayers, ofPenetrateCount;

public Plugin:myinfo = 
{
	name = "DHooks Test",
	author = "Me",
	description = "DHooks test",
	version = "1.0.0.0",
	url = "http://dummy.com"
}

public OnPluginStart()
{
	new Handle:gamedata = LoadGameConfigFile("tfbiohazard.offsets"); 
	if ( gamedata == INVALID_HANDLE ) SetFailState("Offset gamedata file not found."); 
    
	new offset = GameConfGetOffset(gamedata, "OnTakeDamage_Alive"); 
	test = DHookCreate(offset, HookType_Entity, ReturnType_Int, ThisPointer_CBaseEntity, OnTakeDamage_Alive); 
	DHookAddParam(test, HookParamType_ObjectPtr);
	
	ofDmgForce = GameConfGetOffset(gamedata, "m_vecDamageForce");
	ofDmgPos = GameConfGetOffset(gamedata, "m_vecDamagePosition");
	ofReportedPos = GameConfGetOffset(gamedata, "m_vecReportedPosition");
	ofInflictor = GameConfGetOffset(gamedata, "m_hInflictor");
	ofAttacker = GameConfGetOffset(gamedata, "m_hAttacker");
	ofWeapon = GameConfGetOffset(gamedata, "m_hWeapon");
	ofDmg = GameConfGetOffset(gamedata, "m_flDamage");
	ofMaxDmg = GameConfGetOffset(gamedata, "m_flMaxDamage");
	ofBaseDmg = GameConfGetOffset(gamedata, "m_flBaseDamage");
	ofDmgBits = GameConfGetOffset(gamedata, "m_bitsDamageType");
	ofDmgCustom = GameConfGetOffset(gamedata, "m_iDamageCustom");
	ofDmgStats = GameConfGetOffset(gamedata, "m_iDamageStats");
	ofAmmoType = GameConfGetOffset(gamedata, "m_iAmmoType");
	ofDmgOtherPlayers = GameConfGetOffset(gamedata, "m_iDamagedOtherPlayers");
	ofPenetrateCount = GameConfGetOffset(gamedata, "m_iPlayerPenetrateCount");
	
	CloseHandle(gamedata);
}

public OnClientPutInServer(client)
{
	DHookEntity(test, false, client); 
}

public MRESReturn:OnTakeDamage_Alive(this, Handle:hReturn, Handle:hParams) 
{
	// Damage is reported as a float, in-game appears to be rounded to the nearest integer.
	LogMessage("DHooksHacks = Victim %i, Attacker %i, Inflictor %i, Damage %f", this, DHookGetParamObjectPtrVar(hParams, 1, ofAttacker, ObjectValueType_Ehandle),
				DHookGetParamObjectPtrVar(hParams, 1, ofInflictor, ObjectValueType_Ehandle), DHookGetParamObjectPtrVar(hParams, 1, ofDmg, ObjectValueType_Float));
}