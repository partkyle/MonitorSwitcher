//
//  ddcctl.m
//  query and control monitors through their on-wire data channels and OSD microcontrollers
//  http://en.wikipedia.org/wiki/Display_Data_Channel#DDC.2FCI
//  http://en.wikipedia.org/wiki/Monitor_Control_Command_Set
//
//  Copyright Joey Korkames 2016 http://github.com/kfix
//  Licensed under GPLv3, full text at http://www.gnu.org/licenses/gpl-3.0.txt

//  Now using argv[] instead of user-defaults to handle commandline arguments.
//  Added optional use of an external app 'OSDisplay' to have a BezelUI like OSD.
//  Have fun! Marc (Saman-VDR) 2016

#ifndef DDCCTL_M
#define DDCCTL_M

#ifdef DEBUG
#define MyLog NSLog
#else
#define MyLog(...) (void)printf("%s\n",[[NSString stringWithFormat:__VA_ARGS__] UTF8String])
#endif

#import <Foundation/Foundation.h>
#import <AppKit/NSScreen.h>
#import "DDC.h"
#import "ddcctl.h"

#ifdef BLACKLIST
NSUserDefaults *defaults;
int blacklistedDeviceWithNumber;
#endif
#ifdef OSD
bool useOsd;
#endif

extern io_service_t CGDisplayIOServicePort(CGDirectDisplayID display) __attribute__((weak_import));

NSString *EDIDString(char *string)
{
    NSString *temp = [[NSString alloc] initWithBytes:string length:13 encoding:NSASCIIStringEncoding];
    return ([temp rangeOfString:@"\n"].location != NSNotFound) ? [[temp componentsSeparatedByString:@"\n"] objectAtIndex:0] : temp;
}

NSString *getDisplayDeviceLocation(CGDirectDisplayID cdisplay)
{
    // FIXME: scraping prefs files is vulnerable to use of stale data?
    // TODO: try shelling `system_profiler SPDisplaysDataType -xml` to get "_spdisplays_displayPath" keys
    //    this seems to use private routines in:
    //      /System/Library/SystemProfiler/SPDisplaysReporter.spreporter/Contents/MacOS/SPDisplaysReporter

    // get the WindowServer's table of DisplayIds -> IODisplays
    NSString *wsPrefs = @"/Library/Preferences/com.apple.windowserver.plist";
    NSDictionary *wsDict = [NSDictionary dictionaryWithContentsOfFile:wsPrefs];
    if (!wsDict)
    {
        MyLog(@"E: Failed to parse WindowServer's preferences! (%@)", wsPrefs);
        return NULL;
    }

    NSArray *wsDisplaySets = [wsDict valueForKey:@"DisplayAnyUserSets"];
    if (!wsDisplaySets)
    {
        MyLog(@"E: Failed to get 'DisplayAnyUserSets' key from WindowServer's preferences! (%@)", wsPrefs);
        return NULL;
    }

    // $ PlistBuddy -c "Print DisplayAnyUserSets:0:0:IODisplayLocation" -c "Print DisplayAnyUserSets:0:0:DisplayID" /Library/Preferences/com.apple.windowserver.plist
    // > IOService:/AppleACPIPlatformExpert/PCI0@0/AppleACPIPCI/PEG0@1/IOPP/GFX0@0/ATY,Longavi@0/AMDFramebufferVIB
    // > 69733382
    for (NSArray *displaySet in wsDisplaySets) {
        for (NSDictionary *display in displaySet) {
            if ([[display valueForKey:@"DisplayID"] integerValue] == cdisplay) {
                return [display valueForKey:@"IODisplayLocation"]; // kIODisplayLocationKey
            }
        }
    }

    MyLog(@"E: Failed to find display in WindowServer's preferences! (%@)", wsPrefs);
    return NULL;
}

/* Get current value for control from display */
uint getControl(CGDirectDisplayID cdisplay, uint control_id)
{
    struct DDCReadCommand command;
    command.control_id = control_id;
    command.max_value = 0;
    command.current_value = 0;
    MyLog(@"D: querying VCP control: #%u =?", command.control_id);

    if (!DDCRead(cdisplay, &command)) {
        MyLog(@"E: DDC send command failed!");
        MyLog(@"E: VCP control #%u (0x%02hhx) = current: %u, max: %u", command.control_id, command.control_id, command.current_value, command.max_value);
    } else {
        MyLog(@"I: VCP control #%u (0x%02hhx) = current: %u, max: %u", command.control_id, command.control_id, command.current_value, command.max_value);
    }
    return command.current_value;
}

/* Set new value for control from display */
void setControl(io_service_t framebuffer, uint control_id, uint new_value)
{
    struct DDCWriteCommand command;
    command.control_id = control_id;
    command.new_value = new_value;

    MyLog(@"D: setting VCP control frambuffer(%u) #%u => %u", framebuffer, command.control_id, command.new_value);
    if (!DDCWrite(framebuffer, &command)){
        MyLog(@"E: Failed to send DDC command!");
    }
#ifdef OSD
    if (useOsd) {
        NSString *OSDisplay = @"/Applications/OSDisplay.app/Contents/MacOS/OSDisplay";
        switch (control_id) {
            case 16:
                [NSTask launchedTaskWithLaunchPath:OSDisplay
                                         arguments:[NSArray arrayWithObjects:
                                                    @"-l", [NSString stringWithFormat:@"%u", new_value],
                                                    @"-i", @"brightness", nil]];
                break;

            case 18:
                [NSTask launchedTaskWithLaunchPath:OSDisplay
                                         arguments:[NSArray arrayWithObjects:
                                                    @"-l", [NSString stringWithFormat:@"%u", new_value],
                                                    @"-i", @"contrast", nil]];
                break;

            default:
                break;
        }
    }
#endif
}

/* Get current value to Set relative value for control from display */
void getSetControl(io_service_t framebuffer, uint control_id, NSString *new_value, NSString *operator)
{
    struct DDCReadCommand command;
    command.control_id = control_id;
    command.max_value = 0;
    command.current_value = 0;

    // read
    MyLog(@"D: querying VCP control: #%u =?", command.control_id);

    if (!DDCRead(framebuffer, &command)) {
        MyLog(@"E: DDC send command failed!");
        MyLog(@"E: VCP control #%u (0x%02hhx) = current: %u, max: %u", command.control_id, command.control_id, command.current_value, command.max_value);
    } else {
        MyLog(@"I: VCP control #%u (0x%02hhx) = current: %u, max: %u", command.control_id, command.control_id, command.current_value, command.max_value);
    }

    // calculate
    NSString *formula = [NSString stringWithFormat:@"%u %@ %@", command.current_value, operator, new_value];
    NSExpression *exp = [NSExpression expressionWithFormat:formula];
    NSNumber *set_value = [exp expressionValueWithObject:nil context:nil];

    // validate and write
    int clamped_value = MIN(MAX(set_value.intValue, 0), command.max_value);
    MyLog(@"D: relative setting: %@ = %d (clamped to 0, %d)", formula, clamped_value, command.max_value);
    setControl(framebuffer, control_id, (uint) clamped_value);
}

#endif
