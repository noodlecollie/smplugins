================================================================================
                          SourcePawn Compiler GUI
                              Author: FaTony
             Version: 1.0.0.9 (Release Candidate 4. 30 Jan 2011)
================================================================================


TABLE OF CONTENTS
 1. SYSTEM REQUIREMENTS
 2. MAIN WINDOW
 3. OPTIONS WINDOW
 4. COMMAND LINE ARGUMENTS
 5. NOTES
 6. KNOWN ISSUES
 7. TROUBLESHOOTING
 8. LICENSE


1. SYSTEM REQUIREMENTS
This application requires Microsoft Visual C++ 2010 Redistributable Package (x86).
It can be downloaded at:
http://www.microsoft.com/downloads/en/details.aspx?familyid=A7B7A05E-6DE6-4D3A-A423-37BF0912DB84
Automatic plugin reloading feature requires Auto Plugin Reload extension. It can
be downloaded at http://forums.alliedmods.net/showthread.php?t=142475


2. MAIN WINDOW
Main window is the first thing you'll see when you start an application. It
consists of "Plugin name" field, Plugin index box, 3 fields for file paths (each
with corresponding "Browse..." button), New plugin, Copy plugin, Delete plugin,
Save plugins, Move plugin up, Move plugin down, "Compile" and "Options..."
buttons and output box.

Plugin name (optional)
You can type a short name of your plugin in order to easily find it. You can
select different plugins from the dropdown list.

Plugin index box
Shows the index of the current plugin. It is used with -plugin command line
argument.

Source file
You must specify a path to the source file of your plugin (.sp file) to be
compiled. The application will check if it exists before compilation.

Intermediate file (optional)
If you don't want compiler to use the default path for the compiled file (.smx
file), you need to specify this parameter. Normally, you would like it to be
somewhere near the source file. The value of this parameter in not checked by
the application before compilation, but the existence of the file is checked
after compilation if the final file parameter was set.

Final file (optional)
This is normally a plugins directory of the server, where the plugins get
executed. This parameter is used only if intermediate file parameter is set and
compilation was successful.

New plugin button
Creates an empty plugin to compile.

Copy plugin button
Copies the current plugin and pastes it in the new slot at the end of the list.

Delete plugin button
Deletes current plugin or resets all fields if there is only one.

Save plugin button
Saves all plugins into the settings.ini file.

Move plugin up button
Moves current plugin one position up in the list effectively decreasing it's
index by one. You can't do this to the first plugin in the list.

Move plugin down button
Moves current plugin one position down in the list effectively increasing it's
index by one. You can't do this to the last plugin in the list.

Compile button
Starts the compilation process. If all paths are set and compilation was
successful, it'll try to copy intermediate file to it's final location. If that
was successful and "Reload plugin on server" checkbox was set, it also will try
to reload the plugin on the server.

Options button
Opens options window.

Output box
Shows compilation progress and all errors.


3. OPTIONS WINDOW
Options window is the window you'll see when you press "Options..." button in
the main window. If consists of 2 fields for paths, timeout box, reload check
box, server port box, "OK" and "Cancel" buttons.

Path to executable
Path to the compiler executable.

Include files directory (optional)
If you want to use non-default path to the include files, you must specify this
parameter.

Executable timeout
Timeout in seconds to wait before forcing compiler executable to terminate.

Reload plugin on server
Tick this option if you want application to automatically reload plugins on the
server.

Server port (optional)
The port to send reload requests to.

OK button
Remembers all options.

Cancel button
Discards changes.


4. COMMAND LINE ARGUMENTS
Arguments can be in any order. There can be any number of the same arguments.

-last
This argument tells the application to compile the last used plugin.

-plugin 0-255
This argument tells the application to compile the specified plugin by it's
index. Passing number 255 equals -last.


5. NOTES
This application stores it's configuration in the settings.ini in it's working
directory. Settings are autoloaded at the application start. When the
application terminates, it firstly deletes settings.ini file and then saves all
settings in the newly created one. You can manually save configuration using
Save plugins button at any time.
This application can have 255 plugin configurations at most. Valid configuration
indexes are from 0 to 254 inclusive.
There can be only one instance of the application running at a time. If the user
starts the second instance of the application, it will first detect if another
instance is already running. If true, it will bring original window to top and
if it'll also detect valid command line arguments, it will pass them to the
first instance.
If there are no other instances running and valid command line arguments have
been detected, this application will start in the console mode and will
automatically execute all commands. In this mode it can be easily embedded into
another application such as an IDE.
If you enable reloading on server, this application will try to send a request
to the server. In order to reload plugins, you need to install Auto Plugin
Reload extension on the server. Do not use ports below 1024 because it may
conflict with other applications. You can only reload plugins on the same
machine. It was done deliberately as a security measure.


6. KNOWN ISSUES
Problem: Application fails to load with error saying that some dll in not found.
Solution: Please download and install Microsoft Visual C++ 2010 Redistributable
Package (x86). Link can be found in the System Requirements section.

Problem: Unable to reload plugins. Application says that server has timed out.
Solution: Ensure that Auto Plugin Reload is correctly installed on the server.
For more information please see Auto Plugin Reload ReadMe.txt and SourceMod
documentation. Ensure that your firewall allows you to access the server port.


7. TROUBLESHOOTING
If you encounter any non-documented issue, please post detailed description of
how to reproduce it at http://forums.alliedmods.net/showthread.php?t=142475

8. LICENSE
Application binary file and this document is in public domain.