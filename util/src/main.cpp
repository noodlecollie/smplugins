#include <QCoreApplication>
#include <QString>
#include <QFile>
#include <iostream>
#include <QTextStream>
#include <QRegularExpression>
#include <QHash>

using namespace std;

#define PLUGIN_MAJOR    "PLUGIN_MAJOR"
#define PLUGIN_MINOR    "PLUGIN_MINOR"
#define PLUGIN_REVISION "PLUGIN_REVISION"
#define PLUGIN_BUILD    "PLUGIN_BUILD"
#define PLUGIN_VERSION  "PLUGIN_VERSION"

#if defined WIN32 || defined WIN64
#define ENDL "\r\n"
#else
#define ENDL "\n"
#endif

//#define VERBOSE

int main(int argc, char *argv[])
{
    QCoreApplication a(argc, argv);
    
    if ( argc < 2 )
    {
        cout << "Usage: spbuildinc <filename>" << endl;
        return 1;
    }
    
    QString filename = a.arguments().at(1);
    QFile fileIn(filename);
    if ( !fileIn.open(QIODevice::ReadOnly) )
    {
        cerr << "Could not open file " << filename.toStdString() << " for reading." << endl;
        return 1;
    }
    
    cout << "Reading from " << filename.toStdString() << endl;
    
    // We want to be writing:
    // PLUGIN_MAJOR
    // PLUGIN_MINOR
    // PLUGIN_REVISION
    // PLUGIN_BUILD
    // PLUGIN_VERSION = "<PLUGIN_MAJOR>.<PLUGIN_MINOR>.<PLUGIN_REVUSION>.<PLUGIN_BUILD>"
    
    QTextStream streamIn(&fileIn);
    typedef QHash<QString, QString> StringHash;
    StringHash stringTable;
    
    // Populate the defines string table;
    while ( !streamIn.atEnd() )
    {
        QString line = streamIn.readLine().trimmed();
        
        // Split the line by spaces.
        QStringList items = line.split(QRegularExpression("\\s+"), QString::SkipEmptyParts);
        
        // If we have too few items (we're expecting "define xxxx yyyy"), continue;
        if ( items.count() < 3 || items.at(0) != "#define" ) continue;
        
        // Item 1 will be the key and 2 will be the value (We're not catering for anything more complicated right now).
        stringTable.insert(items.at(1), items.at(2));
        
#ifdef VERBOSE
        cout << "Read line: " << line.toStdString() << endl;
        cout << "Elements: " << endl;
        for ( int i = 0; i < items.count(); i++ )
        {
            cout << "[" << i << "] " << items.at(i).toStdString() << endl;
        }
#endif
    }
    
    if ( !stringTable.contains(PLUGIN_BUILD) )
    {
        cerr << "Did not find a " << PLUGIN_BUILD << " entry in file." << endl;
    }
    
    // Find PLUGIN_BUILD and increment it.
    bool success = false;
    QString val = stringTable.value(PLUGIN_BUILD);
    int buildNo = val.toInt(&success);
    if ( !success )
    {
        cerr << "Could not convert " << PLUGIN_BUILD << " value of \"" << val.toStdString() << "\" to an integer." << endl;
    }
    
    buildNo++;
    stringTable.insert(PLUGIN_BUILD, QString("%0").arg(buildNo));
    
    // Generate a PLUGIN_VERSION string.
    QString maj = stringTable.value(PLUGIN_MAJOR, "0");
    QString min = stringTable.value(PLUGIN_MINOR, "0");
    QString rev = stringTable.value(PLUGIN_REVISION, "0");
    QString bld = stringTable.value(PLUGIN_BUILD, "0");
    QString verStr = "\"" + maj + "." + min + "." + rev + "." + bld + "\"";
    cout << "New " << PLUGIN_VERSION << " string: " << verStr.toStdString() << endl;
    stringTable.insert(PLUGIN_VERSION, verStr);
    
    // Write out to the file.
    QString filename_out = filename + ".bak";
    QFile fileOut(filename_out);
    if ( !fileOut.open(QIODevice::WriteOnly) )
    {
        cerr << "Could not open file " << filename_out.toStdString() << " for writing." << endl;
        fileIn.close();
        return 1;
    }
    
    QTextStream streamOut(&fileOut);
    
    // Can't reliably use an iterator because the hash is unordered...
    streamOut << "#define " << PLUGIN_MAJOR << " " << stringTable.value(PLUGIN_MAJOR) << ENDL;
    streamOut << "#define " << PLUGIN_MINOR << " " << stringTable.value(PLUGIN_MINOR) << ENDL;
    streamOut << "#define " << PLUGIN_REVISION << " " << stringTable.value(PLUGIN_REVISION) << ENDL;
    streamOut << "#define " << PLUGIN_BUILD << " " << stringTable.value(PLUGIN_BUILD) << ENDL;
    streamOut << "#define " << PLUGIN_VERSION << " " << verStr << ENDL;
    
    fileOut.close();
    
    fileIn.remove();
    fileOut.rename(filename);
    
    return 0;
}
