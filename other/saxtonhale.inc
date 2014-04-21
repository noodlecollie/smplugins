#if defined _VSH_included
 #endinput
#endif
#define _VSH_included

/**
 *
 * @return true, if VSH Mode is enabled, or false if isn't.
 */
native bool:VSH_IsSaxtonHaleModeEnabled();

/**
 * Who is Saxton Hale Now?
 *
 * @return		    	Userid of Saxton Hale (-1 if Hale do not exists)
 */
native VSH_GetSaxtonHaleUserId();

/**
 * What is current team of Saxton Hale
 *
 * @return		    	Number of Saxton Hale's team
 */
native VSH_GetSaxtonHaleTeam();

/**
 * Who is this boss? Hale? Vagineer? HHH? CBS?
 *
 * @return		    	0 - Saxton Hale
 *						1 - Vagineer
 *						2 - HHH
 *						4 - CBS
 */
native VSH_GetSpecialRoundIndex();

/**
 * What is curret Health of Saxton Hale?
 *
 * @return		    	Health o Saxton Hale (or Special boss)
 */
native VSH_GetSaxtonHaleHealth();

/**
 * What is initial Health of Saxton Hale?
 *
 * @return		    	Max Health o Saxton Hale (or Special boss)
 */
native VSH_GetSaxtonHaleHealthMax();

/**
 * How many damage this clients deals to Hale?
 *
 * @param client 		Client index.
 * @return		    	Damage, dealed by this client.
 */
native VSH_GetClientDamage(client);

/**
 * Begins when Hale makes Brave Jump
 *
 * @return		    Plugin_Stop will prevent Jump;
 */
forward Action:VSH_OnDoJump();

/**
 * Begins when Hale makes Rage
 *
 * @param RageDist 	Distance of Boss' rage. Change it and return Plugin_Changed to change the distance.
 * @return		    Plugin_Stop will prevent Rage, Plugin_Changed to change the distance.
 */
forward Action:VSH_OnDoRage(&Float:RageDist);

/**
 * Begins when Hale makes Weighdown
 *
 * @return		    Plugin_Stop will prevent Weighdown;
 */
forward Action:VSH_OnDoWeighdown();

public SharedPlugin:__pl_SaxtonHale = 
{
	name = "saxtonhale",
	file = "saxtonhale.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public __pl_SaxtonHale_SetNTVOptional()
{
	MarkNativeAsOptional("VSH_IsSaxtonHaleModeEnabled");
	MarkNativeAsOptional("VSH_GetSaxtonHaleUserId");
	MarkNativeAsOptional("VSH_GetSaxtonHaleTeam");
	MarkNativeAsOptional("VSH_GetSpecialRoundIndex");
	MarkNativeAsOptional("VSH_GetSaxtonHaleHealth");
	MarkNativeAsOptional("VSH_GetSaxtonHaleHealthMax");
	MarkNativeAsOptional("VSH_GetClientDamage");
}
#endif

