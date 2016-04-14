/**
 * For copyright & license, see LICENSE.
 */

#import "L4FileAppender.h"
#import "L4Layout.h"
#import "L4LogLog.h"
#import "L4Logging.h"

@interface L4FileAppender ()

- (void)_setFileName:(NSString *)theName;

@end

@implementation L4FileAppender

- (id) init
{
	return [self initWithLayout:nil fileName:nil append:NO];
}

- (id) initWithProperties:(L4Properties *) initProperties
{    
    self = [super initWithProperties:initProperties];

    if ( self != nil ) {
        // Support for appender.File in properties configuration file
        NSString *buf = [initProperties stringForKey:@"File"];
        if ( buf == nil ) {
            [L4LogLog error:@"Invalid filename; L4FileAppender properties require a file be specified."];
            [self release];
            return nil;
        }
        fileName = [[buf stringByExpandingTildeInPath] retain];
        // Backup fileName pattern.
        fileNamePattern = [fileName copy];

        // Support for appender.Append in properties configuration file
        append = YES;
        if ( [initProperties stringForKey:@"Append"] != nil ) {
            NSString *buf = [[initProperties stringForKey:@"Append"] lowercaseString];
            append = [buf isEqualToString:@"true"];
        }
		[self setupFile];
    }
    
    return self;
}

- (id) initWithLayout:(L4Layout *) aLayout fileName:(NSString *) aName
{
	return [self initWithLayout:aLayout fileName:aName append:NO];
}

- (id) initWithLayout:(L4Layout *) aLayout fileName:(NSString *) aName append:(BOOL) flag
{
    self = [super init];
	if (self != nil)
	{
		[self setLayout:aLayout];
		fileName = [[aName stringByExpandingTildeInPath] retain];
        // Backup fileName pattern.
        fileNamePattern = [fileName copy];
		append = flag;
		[self setupFile];
	}
	return self;
}

- (void)dealloc
{
	[fileName release];
	fileName = nil;
	
	[super dealloc];
}

#if TARGET_OS_IPHONE

- (void)_setFileName:(NSString *)theName
{
    if (fileName == theName) {
        return ;
    }
    [theName retain];
    [fileName release];
    fileName = theName;
}

/**
 
 Mod by Deheng.Xu @2013.1.28
 
 Change the path rules for iOS.
 Using relative path like below:
 
 log4cocoa.appender.A2.File=Documents/YourDir/YourFileName
 
 log4cocoa.appender.A2.File=Library/YourDir/YourFileName
 
 log4cocoa.appender.A2.File=tmp/YourDir/YourFileName
 
 //Doesn't support this path, will throw an exception by OS.
 log4cocoa.appender.A2.File=YourDir/YourFileName
 
 YourFileName rules in -[self parseTag:].
 

 */
- (void)setupFile
{
	NSFileManager*	fileManager = nil;
    
//    NSString *dir = nil;
//    NSRange searchRange = NSMakeRange(NSNotFound, 0);
//    if ((searchRange = [fileName rangeOfString:@"Documents"]).location == 0) {
//        NSArray * result = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
//        dir = [result lastObject];
//    }else if ((searchRange = [fileName rangeOfString:@"Library"]).location == 0) {
//        NSArray * result = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
//        dir = [result lastObject];
//    }else if ((searchRange = [fileName rangeOfString:@"tmp"]).location == 0) {
//        dir = NSTemporaryDirectory();
//    }else {
//        NSArray * result = NSSearchPathForDirectoriesInDomains(NSApplicationDirectory, NSUserDomainMask, YES);
//        dir = [result lastObject];
//    }
//    
//    [fileName autorelease];
//    
//    //Scrab tag only for subclass.
////    if (self.class != [L4FileAppender class] && [self isKindOfClass:[L4FileAppender class]]) {
//        NSRange foundRange = NSMakeRange(NSNotFound, 0);
//        NSString *regexStr = @"<[(a-z)|(A-Z)|(0-9)|(: _)]{0,}>";
//        NSString *replace = nil;
//        do {
//            foundRange = [fileName rangeOfString:regexStr options:NSRegularExpressionSearch];
//            printf("->%s\n", CharFromString(NSStringFromRange(foundRange)));
//            if (foundRange.length) {
//                replace = [self parseTag:[fileName substringWithRange:foundRange]];
//                if (!replace) {
//                    continue;
//                }
//                [self _setFileName:[fileName stringByReplacingCharactersInRange:foundRange withString:replace]];
//            }
//        } while (foundRange.length);
////    }
//    
//    [self _setFileName:[NSString stringWithFormat:@"%@%@", dir, [fileName substringFromIndex:searchRange.length]]];
    
    [self _setFileName:[self updateFileName]];
    
    printf("New log file name:%s\n", CharFromString(fileName));
    
	@synchronized(self) {
        if (fileName == nil || [fileName length] <= 0) {
            [self closeFile];
            [fileName release];
            fileName = nil;
            [self setFileHandle:nil];
        } else {
            
            fileManager = [NSFileManager defaultManager];
            
            NSMutableArray *components = [[fileName componentsSeparatedByString:@"/"] mutableCopy];
            [components removeLastObject];
            NSString *logDir = [components componentsJoinedByString:@"/"];
            
            
            if (![fileManager fileExistsAtPath:logDir]) {
                if (![fileManager createDirectoryAtPath:logDir withIntermediateDirectories:YES attributes:nil error:nil]) {
                    [NSException raise:@"DirectoryNotFoundException" format:@"Could not create a directory at %@", logDir];
                }
            }
            
            // if file doesn't exist, try to create the file
            if (![fileManager fileExistsAtPath:fileName]) {
                // if the we cannot create the file, raise a FileNotFoundException
                if (![fileManager createFileAtPath:fileName contents:nil attributes:nil]) {
                    [NSException raise:@"FileNotFoundException" format:@"Couldn't create a file at %@", fileName];
                }
            }
            
            // if we had a previous file name, close it and release the file handle
            if (fileName != nil) {
                [self closeFile];
            }
            
            // open a file handle to the file
            [self setFileHandle:[NSFileHandle fileHandleForWritingAtPath:fileName]];
            
            // check the append option
            if (append) {
                [fileHandle seekToEndOfFile];
            } else {
                [fileHandle truncateFileAtOffset:0];
            }
        }
    }
}

/**

 YourFileName rule:
 <date:format>, Replace date time string with current place by 'format' style.
 <version>, Replace app build version with current place.
 <bundleIdentifier>,    Replace app bundle identifier with current place.

 */
- (NSString *)parseTag:(NSString *)fileTag inName:(NSString *)aName
{
    NSString *foundedTag = nil;
    
    if ([fileTag rangeOfString:@"<date:"].location == 0) {
        ///---------------------------Add date string to file name dynamicly.
        NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
        TRY_BEGIN
        foundedTag = fileTag;
        NSString *format = [foundedTag substringWithRange:NSMakeRange(@"<date:".length, foundedTag.length - 1 - @"<date:".length)];
        [formatter setDateFormat:format];
        //printf("found:%s   %s\n", CharFromString(foundedTag), CharFromString(format));
        TRY_CATCH
        
        return [formatter stringFromDate:[NSDate date]];
    }else if ([fileTag rangeOfString:@"<version>"].location == 0) {
        ///--------------------------Add app version automically.
        NSString *versionRegex = @"<version>";
        NSRange verTagRange = [aName rangeOfString:versionRegex options:NSRegularExpressionSearch];
        if (verTagRange.location != NSNotFound) {
            return [[[NSBundle mainBundle] infoDictionary] valueForKey:@"CFBundleVersion"];
        }
    }else if ([fileTag rangeOfString:@"<bundleIdentifier>"].location == 0) {
        ///--------------------------Add Bundle identifier.
        NSString *bundleIdRegex = @"<bundleIdentifier>";
        NSRange bundleIdRange = [aName rangeOfString:bundleIdRegex options:NSRegularExpressionSearch];
        if (bundleIdRange.location != NSNotFound) {
            return [[[NSBundle mainBundle] infoDictionary] valueForKey:@"CFBundleIdentifier"];
        }
    }
    
    return nil;
}

#else

- (void)setupFile
{
	NSFileManager*	fileManager = nil;

	@synchronized(self) {
        if (fileName == nil || [fileName length] <= 0) {
            [self closeFile];
            [fileName release];
            fileName = nil;
            [self setFileHandle:nil];
        } else {
        
            fileManager = [NSFileManager defaultManager];
        
            // if file doesn't exist, try to create the file
            if (![fileManager fileExistsAtPath:fileName]) {
                // if the we cannot create the file, raise a FileNotFoundException
                if (![fileManager createFileAtPath:fileName contents:nil attributes:nil]) {
                    [NSException raise:@"FileNotFoundException" format:@"Couldn't create a file at %@", fileName];
                }
            }
        
            // if we had a previous file name, close it and release the file handle
            if (fileName != nil) {
               [self closeFile];
            }
        
            // open a file handle to the file
            [self setFileHandle:[NSFileHandle fileHandleForWritingAtPath:fileName]];
        
            // check the append option
            if (append) {
                [fileHandle seekToEndOfFile];
            } else {
                [fileHandle truncateFileAtOffset:0];
            }
        }
    }
}

#endif

- (NSString *) fileName
{
	return fileName;
}

- (NSString *)fileNamePattern
{
    return fileNamePattern;
}

- (NSString *)updateFileName
{
    NSString *_loadNewFileName = [[self fileNamePattern] copy];
    return _loadNewFileName;
    NSString *dir = nil;
    NSRange searchRange = NSMakeRange(NSNotFound, 0);
    
    if ((searchRange = [_loadNewFileName rangeOfString:@"Documents"]).location != NSNotFound) {
        NSArray * result = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        dir = [result lastObject];
    }else if ((searchRange = [_loadNewFileName rangeOfString:@"Library"]).location != NSNotFound) {
        NSArray * result = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
        dir = [result lastObject];
    }else if ((searchRange = [_loadNewFileName rangeOfString:@"tmp"]).location != NSNotFound) {
        dir = NSTemporaryDirectory();
    }else {
        NSArray * result = NSSearchPathForDirectoriesInDomains(NSApplicationDirectory, NSUserDomainMask, YES);
        dir = [result lastObject];
    }
    
    //Scrab tag only for subclass.
//    if (self.class != [L4FileAppender class] && [self isKindOfClass:[L4FileAppender class]]) {
    NSRange foundRange = NSMakeRange(NSNotFound, 0);
    NSString *regexStr = @"<[(a-z)|(A-Z)|(0-9)|(: _)]{0,}>";
    NSString *replace = nil;
    NSString *_tmp = nil;
    do {
        foundRange = [_loadNewFileName rangeOfString:regexStr options:NSRegularExpressionSearch];
        if (foundRange.length) {
            printf("%s %d", __FUNCTION__, __LINE__);
            replace = [self parseTag:[_loadNewFileName substringWithRange:foundRange] inName:_loadNewFileName];
            printf("%s\n", CharFromString(replace));
            if (!replace) {
                continue;
            }
            
            NSString *_tmp = [_loadNewFileName stringByReplacingCharactersInRange:foundRange withString:replace];
            printf("%s %d %s", __FUNCTION__, __LINE__, CharFromString(_tmp));
            if (!_loadNewFileName || ![_loadNewFileName isEqualToString:_tmp]) {
                [_loadNewFileName release];
                _loadNewFileName = [_tmp retain];
                _tmp = nil;
            }
        }
    } while (foundRange.length);
//    }
    
    _tmp = [[NSString stringWithFormat:@"%@%@", dir, [_loadNewFileName substringFromIndex:searchRange.length]] retain];
    [_loadNewFileName release];
    _loadNewFileName = _tmp;
    
    printf("New log file name:%s\n", CharFromString(_loadNewFileName));
    return [_loadNewFileName autorelease];
}

- (BOOL) append
{
	return append;
}

/* ********************************************************************* */
#pragma mark Protected methods
/* ********************************************************************* */
- (void) closeFile
{
    @synchronized(self) {
        [fileHandle closeFile];
        
        // Deallocate the file handle because trying to read from or write to a closed file raises exceptions.  Sending messages to nil objects are no-ops.
        [fileHandle release];
        fileHandle = nil;
    }
}
@end

