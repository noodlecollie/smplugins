// Arena Modulus include file

#if defined _arenamodulus_included
 #endinput
#endif
#define _arenamodulus_included

// ================================
// =========== Natives ============
// ================================

/*
 * Registers a mode into the handler.
 *
 * @param	String:ModeName		Name of the mode. Should be translated into LANG_SERVER before being passed. Max length 64 characters.
 * @param	String:ModeDesc		Description of the mode. Should be translated into LANG_SERVER before being passed. Max length 128 characters.
 * @param	MinPlayersRed		Minimum number of players that must be on the Red team for this mode to activate.
 * @param	MinPlayersBlue		Minimum number of players that must be on the Blue team for this mode to activate.
 * @return		    			ID of the mode as registered in the handler, or -1 if unable to be registered.
 */
native ArenaMod_RegisterMode(String:ModeName[], String:ModeDesc[], MinPlayersRed, MinPlayersBlue);

/*
 * Cancels the current mode in progress.
 *
 * @param	modeID				ID of the mode calling the function.
 * @return		    			No return.
 */
native ArenaMod_CancelCurrentRound(String:ModeName[], String:ModeDesc[], MinPlayersRed, MinPlayersBlue);

// ================================
// =========== Forwards ===========
// ================================

/*
 * Broadcasts a search for modes. Modes that use this function must call ArenaMod_RegisterMode to register their presence.
 *
 * @return						No return.
 */
forward ArenaMod_SearchForModes();

/*
 * Called once a mode has been chosen on RoundStart.
 *
 * @param	modeID				ID of the chosen mode. Modes should check this ID against theirs and activate if it matches.
 * @return						No return.
 */
forward ArenaMod_RoundStart();
 
/*
 * Called when a round is ended.
 *
 * @param	modeID				ID of the chosen mode. The mode with this ID should clean up all the resources it is using in preparation for the next round.
 * @param	winning_team		Team who won the round; 0 on stalemate.
 * @return						No return.
 */
forward ArenaMod_RoundEnd();
 
/*
 * Called when the map ends. All modes should respond to this forward by clearing up all of their resources.
 *
 * @return						No return.
 */
forward ArenaMod_MapEnd();
 
public SharedPlugin:__pl_ArenaModulus = 
{
	name = "ArenaModulus",
	file = "ArenaModulus.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public __pl_ArenaModulus_SetNTVOptional()
{
	MarkNativeAsOptional("ArenaMod_RegisterMode");
	MarkNativeAsOptional("ArenaMod_CancelCurrentRound");
}
#endif