#if defined _ARENAROULETTE_INC
 #endinput
#endif

#define _ARENAROULETTE_INC

#pragma semicolon 1
#pragma newdecls required

enum ArenaRoulette_ForwardType
{
	ArenaRouletteFwdType_Invalid = 0,
	ArenaRouletteFwdType_CanSelectMode = 1,

	ArenaRouletteFwdType__Max__DoNotUse
};

typedef ArenaRouletteFwd_CanSelectMode = function bool ();

// Expects pairs of arguments. The first of each pair should be
// a ArenaRoulette_ForwardType value, and the second should be
// the function corresponding to this forward.
native bool ArenaRoulette_RegisterMode(any ...);
