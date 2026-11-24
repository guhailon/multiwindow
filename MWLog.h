// MWLog.h — ONE shared diagnostic logger for the MultiWindow app and the
// MWFloat tweak (1.0.2, logging only, no behavior change).
//
// Every line goes to NSLog with tag MWLOG and is appended to
// /var/mobile/Library/Logs/MultiWindow.log with a timestamp, so Lee can
// pull a single file and we can see both the app path and the tweak path.
//
// Header-only (static inline) so neither Makefile needs a new .m entry:
// the app imports it as "MWLog.h", the tweak as "../MWLog.h".
// Usage: MWLog(@"DASV", @"init self=%@ content=%@", NSStringFromCGRect(...), ...);
#import <Foundation/Foundation.h>
#import <stdarg.h>

static inline void MWLog(NSString *tag, NSString *fmt, ...) NS_FORMAT_FUNCTION(2, 3);
static inline void MWLog(NSString *tag, NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    NSString *line = [NSString stringWithFormat:@"MWLOG [%@] %@", tag, msg];
    NSLog(@"%@", line);
    static NSObject *mwLogLock = nil;
    static NSDateFormatter *mwLogDF = nil;
    static dispatch_once_t mwLogOnce = 0;
    dispatch_once(&mwLogOnce, ^{
        mwLogLock = [NSObject new];
        mwLogDF = [[NSDateFormatter alloc] init];
        mwLogDF.dateFormat = @"MM-dd HH:mm:ss.SSS";
        mwLogDF.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    });
    @synchronized (mwLogLock) {
        @try {
            NSString *ts = [mwLogDF stringFromDate:[NSDate date]];
            NSString *fileLine = [NSString stringWithFormat:@"%@ %@\n", ts, line];
            NSString *path = @"/var/mobile/Library/Logs/MultiWindow.log";
            NSFileManager *fm = [NSFileManager defaultManager];
            if (![fm fileExistsAtPath:path]) {
                [fileLine writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:nil];
            } else {
                NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
                if (fh) {
                    [fh seekToEndOfFile];
                    [fh writeData:[fileLine dataUsingEncoding:NSUTF8StringEncoding]];
                    [fh closeFile];
                }
            }
        } @catch (NSException *e) { (void)e; }
    }
}
