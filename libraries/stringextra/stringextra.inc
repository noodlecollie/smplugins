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

/**
 * Converts a string to the given case.
 * The destination string is expected to be at least as long as the source string.
 *
 * @param strDest       Output buffer.
 * @param nDestLength   Length of the output buffer.
 * @param strSource     Source string.
 * @param nCase         Case to convert to.
 *
 * @noreturn
 */
public void StrEx_ToCase(char[] strDest, int nDestLength, const char[] strSource, StringCase nCase)
{
    strcopy(strDest, nDestLength, strSource);
    int nSourceLength = strlen(strSource);
    int nMinLength = nDestLength < nSourceLength ? nDestLength : nSourceLength;
    
    if ( nCase == StrEx_Uppercase )
    {
        for ( int i = 0; i < nMinLength; ++i )
        {
            strDest[i] = CharToUpper(strDest[i]);
        }
    }
    else
    {
        for ( int i = 0; i < nMinLength; ++i )
        {
            strDest[i] = CharToLower(strDest[i]);
        }
    }
}