/* =================================================
    StringExtra - X6Herbius, 11/02/2017
   ================================================= */

#if defined _STRINGEXTRA_INC
 #endinput
#endif
#define _STRINGEXTRA_INC

#pragma semicolon 1
#pragma newdecls required

#include <string>

enum StringCase
{
    StrEx_Lowercase,
    StrEx_Uppercase
};

public void StrEx_ToCase(char[] strDest, int nDestLength, const char[] strSource, StringCase nCase)
{
	strcopy(strDest, nDestLength, strSource);
	
	for ( int i = 0; i < nDestLength; ++i )
	{
		strDest[i] = nCase == StrEx_Uppercase ? CharToUpper(strDest[i]) : CharToLower(strDest[i]);
	}
}