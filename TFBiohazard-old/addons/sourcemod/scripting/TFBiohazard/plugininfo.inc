/**
 * plugininfo.inc - Defines plugin identification info.
 */

#include "pluginbuild"

#define PLUGIN_NAME             "TF: Biohazard"
#define PLUGIN_AUTHOR           "[X6] Herbius"
#define PLUGIN_DESCRIPTION      "Hold off the zombies to win the round!"
#define PLUGIN_URL              "https://forums.alliedmods.net/showthread.php?p=2127501"

public Plugin:myinfo = 
{
    name = PLUGIN_NAME,
    author = PLUGIN_AUTHOR,
    description = PLUGIN_DESCRIPTION,
    version = PLUGIN_VERSION,
    url = PLUGIN_URL
}