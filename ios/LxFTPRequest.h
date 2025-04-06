

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

@interface LxFTPRequest : NSObject

@property (nonatomic, copy) NSURL *serverURL;
@property (nonatomic, copy) NSURL *localFileURL;
@property (nonatomic, copy) NSString *username;
@property (nonatomic, copy) NSString *password;

@property (nonatomic, assign) NSInteger finishedSize;
@property (nonatomic, assign) NSInteger totalSize;
@property (nonatomic, assign) NSTimeInterval timeoutInterval;
@property (nonatomic, assign) NSInteger maxRetryCount;
@property (nonatomic, assign) BOOL isRunning;
@property (nonatomic, assign) BOOL isCancelled;

@property (nonatomic, copy) void (^progressAction)(NSInteger totalSize, NSInteger finishedSize, CGFloat finishedPercent);
@property (nonatomic, copy) void (^successAction)(Class resultClass, id result);
@property (nonatomic, copy) void (^failAction)(CFStreamErrorDomain errorDomain, NSInteger error, NSString *errorDescription);

/**
 *  Return whether the request started successful.
 */
- (BOOL)start;
- (void)stop;
- (void)cancel;
- (BOOL)isRequestRunning;
- (void)reset;

@end

@interface LxRenameFTPRequest : LxFTPRequest
@property (nonatomic, strong) NSURL *destinationURL;
@end

@interface LxFTPRequest (Create)

+ (LxFTPRequest *)resourceListRequest;
+ (LxFTPRequest *)downloadRequest;
+ (LxFTPRequest *)uploadRequest;
+ (LxFTPRequest *)createResourceRequest;
+ (LxFTPRequest *)destoryResourceRequest;
+ (LxFTPRequest *)makeDirectoryRequest;
+ (LxFTPRequest *)renameRequest;

- (instancetype)init __attribute__((unavailable("LxFTPRequest: Forbidden use!")));

@end

@interface NSString (ftp)

@property (nonatomic, readonly) BOOL isValidateFTPURLString;
@property (nonatomic, readonly) BOOL isValidateFileURLString;
- (NSString *)stringByDeletingScheme;
- (NSString *)stringDecorateWithUsername:(NSString *)username password:(NSString *)password;

@end
