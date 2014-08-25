/**
 * plugininfo.inc - Defines plugin identification info.
 */

#include "pluginbuild"

#define PLUGIN_NAME             "TF: Biohazard"
#define PLUGIN_AUTHOR           "[X6] Herbius"
#define PLUGIN_DESCRIPTION      "Hold off the zombies to win the round!"
#define PLUGIN_URL              "https://forums.alliedmods.net/showthread.php?p=2127501"

#define PLUGIN_MAJOR            0
#define PLUGIN_MINOR            0
#define PLUGIN_REVISION         1
// PLUGIN_BUILD is included from above.

// REMOVE ME
#define PLUGIN_VERSION "0.0.0.0"

// Note that the build number for a given compile (smx) will be one less than the build number specified in pluginbuild.inc,
// because this is incremented -after- the compile has taken place.
public Plugin:myinfo = 
{
    name = PLUGIN_NAME,
    author = PLUGIN_AUTHOR,
    description = PLUGIN_DESCRIPTION,
    version = PLUGIN_VERSION,
    url = PLUGIN_URL
}